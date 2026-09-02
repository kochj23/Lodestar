import Foundation

/// What the model gets each turn: frontmost app, selected text, a compact list of
/// on-screen controls (from Accessibility), and optionally a screenshot. Built in
/// memory per turn and discarded afterwards.
struct ContextBundle {
    var appName: String
    var selection: String?
    var axSummary: String
    var screenshot: Data?
    var elements: [AXElement]
}

enum ContextFuser {
    static func build(includeScreenshot: Bool) async -> ContextBundle {
        let (app, sel, els) = Accessibility.snapshot()
        let summary = els.prefix(60)
            .map { "- [\($0.role.replacingOccurrences(of: "AX", with: ""))] \($0.label)" }
            .joined(separator: "\n")
        let shot = includeScreenshot ? await ScreenCapture.captureMainDisplay() : nil
        return ContextBundle(appName: app, selection: sel, axSummary: summary,
                             screenshot: shot, elements: els)
    }

    static func promptText(_ b: ContextBundle) -> String {
        var s = "Frontmost app: \(b.appName)\n"
        if let sel = b.selection, !sel.isEmpty {
            s += "Selected text: \(sel.prefix(600))\n"
        }
        if !b.axSummary.isEmpty {
            s += "Visible controls (name them exactly if you point):\n\(b.axSummary)\n"
        }
        return s
    }
}
