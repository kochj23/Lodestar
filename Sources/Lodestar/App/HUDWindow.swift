import AppKit
import SwiftUI

/// Owns the floating panel that hosts the HUD next to the cursor.
@MainActor
final class HUDController {
    let model = HUDModel()
    private var panel: NSPanel?

    func showAtCursor() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(x: mouse.x + 16, y: mouse.y - 240)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX + 8), f.maxX - 388)
            origin.y = min(max(origin.y, f.minY + 8), f.maxY - 40)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: HUDView(model: model))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.worksWhenModal = true
        return panel
    }
}
