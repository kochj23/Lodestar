import Foundation
import AppKit
import ApplicationServices

/// A control the model can be told to point at: role, best label, and on-screen
/// frame (AX coordinates — origin top-left of the primary display, y increasing
/// downward). The Targeter matches phrases against these; the overlay draws on them.
struct AXElement {
    var role: String
    var label: String
    var frame: CGRect
}

/// Structured, exact UI reading via the Accessibility API — this is what makes
/// pointing reliable and cheap (no vision-model call needed for most apps).
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Pop the system Accessibility prompt (adds the app to the list + offers to open
    /// System Settings). Without this grant the global hotkey can't see key presses.
    static func promptForTrust() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func snapshot() -> (appName: String, selection: String?, elements: [AXElement]) {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let sys = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(
                sys, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let appRef = focusedApp else {
            return (appName, nil, [])
        }
        let app = appRef as! AXUIElement

        var selection: String?
        var focused: AnyObject?
        if AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let f = focused {
            selection = string(f as! AXUIElement, kAXSelectedTextAttribute)
        }

        var elements: [AXElement] = []
        var window: AnyObject?
        if AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let w = window {
            collect(w as! AXUIElement, into: &elements, depth: 0, maxDepth: 5, budget: 500)
        }
        return (appName, selection, elements)
    }

    private static func collect(_ el: AXUIElement, into out: inout [AXElement],
                                depth: Int, maxDepth: Int, budget: Int) {
        if out.count >= budget || depth > maxDepth { return }
        let role = string(el, kAXRoleAttribute) ?? ""
        let label = string(el, kAXTitleAttribute)
            ?? string(el, kAXDescriptionAttribute)
            ?? string(el, kAXValueAttribute) ?? ""
        if !label.isEmpty, let frame = frame(of: el), frame.width > 1, frame.height > 1 {
            out.append(AXElement(role: role, label: label, frame: frame))
        }
        var children: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
           let arr = children as? [AXUIElement] {
            for c in arr { collect(c, into: &out, depth: depth + 1, maxDepth: maxDepth, budget: budget) }
        }
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func frame(of el: AXUIElement) -> CGRect? {
        var posV: AnyObject?
        var sizeV: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posV) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeV) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posV as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}
