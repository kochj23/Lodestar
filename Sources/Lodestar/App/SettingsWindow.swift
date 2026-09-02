import AppKit
import SwiftUI

/// Owns the Settings window. `onSave` hands a new Config back to the app, which applies
/// it live and writes it to disk.
@MainActor
final class SettingsController {
    private var window: NSWindow?
    var onSave: ((Config) -> Void)?

    func show(config: Config) {
        let model = SettingsModel(config: config)
        model.onSave = { [weak self] cfg in
            self?.onSave?(cfg)
            self?.window?.close()
        }
        model.onCancel = { [weak self] in self?.window?.close() }

        let host = NSHostingView(rootView: SettingsView(model: model))
        let w = window ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Lodestar Settings"
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.center()
        window = w

        NSApp.activate(ignoringOtherApps: true)   // accessory app needs this to focus a window
        w.makeKeyAndOrderFront(nil)
    }
}
