import AppKit

/// A transparent, click-through window covering all displays that draws a halo on
/// the resolved target. Multi-monitor works because the window spans the union of
/// every screen and we draw in global coordinates.
@MainActor
final class PointerOverlay {
    private var window: NSWindow?
    private let view = HaloView()

    func point(atAX axRect: CGRect, duration: TimeInterval = 3) {
        let primaryH = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        let cocoa = Self.axToCocoa(axRect, primaryHeight: primaryH)
        let win = window ?? makeWindow()
        window = win
        view.target = cocoa
        view.needsDisplay = true
        win.orderFrontRegardless()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self.hide()
        }
    }

    func hide() { window?.orderOut(nil) }

    private func makeWindow() -> NSWindow {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let w = NSWindow(contentRect: union, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .screenSaver
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        view.frame = CGRect(origin: .zero, size: union.size)
        view.originOffset = union.origin
        w.contentView = view
        return w
    }

    /// AX rect (top-left origin, y down, relative to primary display top) → Cocoa
    /// global rect (bottom-left origin, y up). Pure + injectable height so it's unit
    /// testable without a display.
    nonisolated static func axToCocoa(_ ax: CGRect, primaryHeight: CGFloat) -> CGRect {
        let y = primaryHeight - ax.origin.y - ax.size.height
        return CGRect(x: ax.origin.x, y: y, width: ax.size.width, height: ax.size.height)
    }
}

final class HaloView: NSView {
    var target: CGRect = .zero
    var originOffset: CGPoint = .zero   // window spans the union; convert global → view coords

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard target != .zero else { return }
        let r = CGRect(x: target.origin.x - originOffset.x,
                       y: target.origin.y - originOffset.y,
                       width: target.width, height: target.height).insetBy(dx: -5, dy: -5)
        let path = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
        NSColor.systemYellow.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.systemYellow.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}
