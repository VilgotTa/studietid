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

func route(_ request: String) {
    let parts = request.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2, let comps = URLComponents(string: "http://localhost" + parts[1]) else { return }
    switch comps.path {
    case "/start":
        let items = comps.queryItems ?? []
        if let s = items.first(where: { $0.name == "start" })?.value, let ms = Double(s) {
            startMs = ms
            course = String((items.first(where: { $0.name == "course" })?.value ?? "").prefix(80))
        }
    case "/stop":
        startMs = nil
        course = ""
    default:
        break
    }
    refresh()
}

func handle(_ conn: NWConnection) {
    conn.start(queue: .main)
    conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
        if let data = data, let request = String(data: data, encoding: .utf8) {
            route(request)
        }
        let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Private-Network: true\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
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
