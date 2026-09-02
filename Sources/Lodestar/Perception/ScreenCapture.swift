import Foundation
import AppKit
import ScreenCaptureKit

/// Screenshot of the main display, downscaled, as PNG — only captured when a vision
/// model will actually use it. Held in memory and handed straight to the provider;
/// never written to disk (capture_retention = none).
enum ScreenCapture {
    static func captureMainDisplay(maxWidth: CGFloat = 1280) async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                    ?? content.displays.first else {
                Log.warn("no displays available to capture")
                return nil
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            let scale = min(1.0, maxWidth / CGFloat(display.width))
            cfg.width = Int(CGFloat(display.width) * scale)
            cfg.height = Int(CGFloat(display.height) * scale)
            cfg.showsCursor = true
            let cg = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: cfg)
            let rep = NSBitmapImageRep(cgImage: cg)
            return rep.representation(using: .png, properties: [:])
        } catch {
            Log.warn("screen capture failed (Screen Recording permission?): \(error)")
            return nil
        }
    }
}
