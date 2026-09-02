import Foundation

/// Turns the model's natural-language target ("the Export button") into an actual
/// on-screen rect by matching against the Accessibility tree. This is entirely
/// local, so pointing works no matter which (or how small) the model is. A vision
/// grounding fallback slots in here for canvas apps where AX is thin.
enum Targeter {
    static func resolve(_ phrase: String, in elements: [AXElement]) -> CGRect? {
        let q = tokens(phrase)
        guard !q.isEmpty else { return nil }
        var best: (score: Double, rect: CGRect)?
        for e in elements {
            let s = score(q, tokens(e.label))
            if s > 0, best == nil || s > best!.score {
                best = (s, e.frame)
            }
        }
        if let b = best, b.score >= 0.34 { return b.rect }
        return nil
    }

    /// Generic UI filler the model tends to add ("click the Export *button*"). These
    /// describe the kind of control, not which one, so they only add noise to matching.
    private static let stopwords: Set<String> = [
        "the", "a", "an", "click", "tap", "press", "on", "to", "in",
        "button", "icon", "menu", "item", "field", "tab", "option", "control", "link",
    ]

    private static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopwords.contains($0) })
    }

    private static func score(_ q: Set<String>, _ t: Set<String>) -> Double {
        guard !t.isEmpty else { return 0 }
        let inter = q.intersection(t).count
        guard inter > 0 else { return 0 }
        return Double(inter) / Double(q.count)   // fraction of the query matched
    }
}
