import AppKit

/// Global hotkey via NSEvent monitors (needs the Accessibility grant to see keys
/// while other apps are frontmost). Default: Control+Option+Space.
final class HotkeyManager {
    struct Combo {
        var mods: NSEvent.ModifierFlags
        var key: String   // "space" or a single character
    }

    private let invoke: Combo
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var onInvoke: (() -> Void)?

    init(invoke spec: String) {
        self.invoke = HotkeyManager.parse(spec)
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e)
            return e
        }
    }

    /// Remove the monitors so the manager can be replaced (e.g. after a hotkey change).
    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }

    private func handle(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods == invoke.mods else { return }
        let matched = invoke.key == "space"
            ? (e.keyCode == 49)
            : ((e.charactersIgnoringModifiers ?? "").lowercased() == invoke.key)
        if matched { onInvoke?() }
    }

    static func parse(_ spec: String) -> Combo {
        var mods: NSEvent.ModifierFlags = []
        var key = "space"
        for part in spec.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command":       mods.insert(.command)
            case "opt", "option", "alt": mods.insert(.option)
            case "ctrl", "control":      mods.insert(.control)
            case "shift":                mods.insert(.shift)
            default:                     key = part
            }
        }
        return Combo(mods: mods, key: key)
    }
}
