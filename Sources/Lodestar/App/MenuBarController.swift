import AppKit

/// The menu-bar presence: quick actions, a visible statement of *where data can go*
/// (the egress allow-list), the privacy pause, and config access.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var pauseItem: NSMenuItem?

    var onAskScreen: (() -> Void)?
    var onTogglePause: (() -> Void)?
    private(set) var paused = false

    func install(providerIDs: [String], egressSummary: String) {
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "cursorarrow.rays",
                                accessibilityDescription: "Lodestar")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Lodestar — local AI at your cursor", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let ask = NSMenuItem(title: "Ask about screen",
                             action: #selector(askTapped), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)

        let pause = NSMenuItem(title: "Privacy pause (stop all capture)",
                               action: #selector(pauseTapped), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

        menu.addItem(.separator())
        menu.addItem(withTitle: "Providers: \(providerIDs.joined(separator: ", "))",
                     action: nil, keyEquivalent: "")
        let egress = NSMenuItem(title: "Egress → \(egressSummary)", action: nil, keyEquivalent: "")
        egress.toolTip = "The only hosts this app may contact. Everything else is blocked."
        menu.addItem(egress)

        let prefs = NSMenuItem(title: "Open config…", action: #selector(openConfig), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lodestar", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func askTapped() { onAskScreen?() }

    @objc private func pauseTapped() {
        paused.toggle()
        pauseItem?.state = paused ? .on : .off
        onTogglePause?()
    }

    @objc private func openConfig() { NSWorkspace.shared.open(Config.path) }

    @objc private func quitTapped() { NSApp.terminate(nil) }
}
