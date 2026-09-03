import AppKit

// Headless test/CLI mode: `Lodestar ask "<question>" [provider]` — runs the real
// pipeline and prints the answer, then exits. No GUI.
if CLI.run(Array(CommandLine.arguments.dropFirst())) {
    exit(0)
}

// Menu-bar accessory app — no dock icon. Everything is wired in AppController.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = MainActor.assumeIsolated { AppController() }
MainActor.assumeIsolated { controller.start() }

app.run()
