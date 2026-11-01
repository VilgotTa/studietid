import Cocoa

// Samma adress och token som i index.html. STUDIETID_API_URL kan åsidosätta adressen, t.ex. vid test.
let apiURL = ProcessInfo.processInfo.environment["STUDIETID_API_URL"]
    ?? "https://script.google.com/macros/s/AKfycbyk5eGIeF5fCQwM666EG_rTQjG-hkcep5hUbL7iwn2tEIgBJxfC4C4J4PXYNF8ZdOX6yQ/exec"
let apiToken = "Superstudent"
let pollIntervalRunning: TimeInterval = 10
let pollIntervalIdle: TimeInterval = 30

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

// Hämtar pågående pass från Apps Script. Vid nätfel eller felsvar behålls senast kända läge.
func poll() {
    guard var comps = URLComponents(string: apiURL) else { return }
    comps.queryItems = [
        URLQueryItem(name: "action", value: "getState"),
        URLQueryItem(name: "token", value: apiToken),
    ]
    guard let url = comps.url else { return }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15

    URLSession.shared.dataTask(with: request) { data, _, _ in
        var state: (start: Double?, course: String)? = nil
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["categories"] != nil {
            if let running = json["running"] as? [String: Any], let start = running["start"] as? Double {
                state = (start, String((running["course"] as? String ?? "").prefix(80)))
            } else {
                state = (nil, "")
            }
        }
        DispatchQueue.main.async {
            if let state = state {
                startMs = state.start
                course = state.course
                refresh()
            }
            // Oftare under ett pågående pass, glesare annars.
            let delay = startMs != nil ? pollIntervalRunning : pollIntervalIdle
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { poll() }
        }
    }.resume()
}

refresh()
poll()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in refresh() }
NSApplication.shared.run()
