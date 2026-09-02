import AppKit

// Menu-bar accessory app — no dock icon. Everything is wired in AppController.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = MainActor.assumeIsolated { AppController() }
MainActor.assumeIsolated { controller.start() }

app.run()
