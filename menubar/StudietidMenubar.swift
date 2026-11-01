import Cocoa
import Network

let port: NWEndpoint.Port = 8765

var startMs: Double? = nil
var course = ""

NSApplication.shared.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

let courseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
let menu = NSMenu()
menu.addItem(courseItem)
menu.addItem(.separator())
menu.addItem(NSMenuItem(title: "Avsluta", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu

func format(_ total: Int) -> String {
    String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
}

func refresh() {
    if let start = startMs {
        let secs = max(0, Int((Date().timeIntervalSince1970 * 1000 - start) / 1000))
        statusItem.button?.title = "⏱ " + format(secs)
        courseItem.title = course.isEmpty ? "Pågående pass" : course
    } else {
        statusItem.button?.title = "⏱ Inte aktiv"
        courseItem.title = "Inget pågående pass"
    }
}

// Webbappens filer serveras från repo-mappen (en nivå över binären), eller från mappen som anges som första argument.
let webRoot: URL = {
    if CommandLine.arguments.count > 1 { return URL(fileURLWithPath: CommandLine.arguments[1]) }
    let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    return exe.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
}()

let webFiles: [String: (name: String, type: String)] = [
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/manifest.json": ("manifest.json", "application/manifest+json"),
    "/icon-192.png": ("icon-192.png", "image/png"),
    "/icon-512.png": ("icon-512.png", "image/png"),
]

struct Reply {
    var status = 200
    var type = "text/plain"
    var body = Data()
}

func route(_ request: String) -> Reply {
    let parts = request.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2, let comps = URLComponents(string: "http://localhost" + parts[1]) else {
        return Reply(status: 400)
    }
    switch comps.path {
    case "/start":
        let items = comps.queryItems ?? []
        if let s = items.first(where: { $0.name == "start" })?.value, let ms = Double(s) {
            startMs = ms
            course = String((items.first(where: { $0.name == "course" })?.value ?? "").prefix(80))
        }
        refresh()
        return Reply()
    case "/stop":
        startMs = nil
        course = ""
        refresh()
        return Reply()
    default:
        if let file = webFiles[comps.path],
           let data = try? Data(contentsOf: webRoot.appendingPathComponent(file.name)) {
            return Reply(status: 200, type: file.type, body: data)
        }
        return Reply(status: 404)
    }
}

func handle(_ conn: NWConnection) {
    conn.start(queue: .main)
    conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
        var reply = Reply(status: 400)
        if let data = data, let request = String(data: data, encoding: .utf8) {
            reply = route(request)
        }
        let head = "HTTP/1.1 \(reply.status) \(reply.status == 200 ? "OK" : "Error")\r\nContent-Type: \(reply.type)\r\nCache-Control: no-cache\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Private-Network: true\r\nContent-Length: \(reply.body.count)\r\nConnection: close\r\n\r\n"
        var out = head.data(using: .utf8)!
        out.append(reply.body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}

let params = NWParameters.tcp
params.requiredInterfaceType = .loopback
params.allowLocalEndpointReuse = true

do {
    let listener = try NWListener(using: params, on: port)
    listener.newConnectionHandler = handle
    listener.stateUpdateHandler = { state in
        if case .failed(let error) = state {
            fputs("Kunde inte lyssna på port \(port): \(error). Körs appen redan?\n", stderr)
            exit(1)
        }
    }
    listener.start(queue: .main)
} catch {
    fputs("Kunde inte starta: \(error)\n", stderr)
    exit(1)
}

refresh()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in refresh() }
NSApplication.shared.run()
