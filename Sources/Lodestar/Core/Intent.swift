import Foundation

/// The model speaks intent, not coordinates. It may answer in plain prose, or wrap
/// a small action in a ```lodestar {…}``` fence:
///
///   ```lodestar
///   { "say": "Top-right — click Export.", "point": "the Export button" }
///   ```
///
/// We keep the *pointing* local: `point` is a natural-language target that the
/// Targeter resolves against the on-screen Accessibility tree. That's what keeps
/// pointing working no matter how small the local model is.
struct AssistantIntent {
    var say: String
    var pointTarget: String?

    static func parse(_ raw: String) -> AssistantIntent {
        if let fence = raw.range(of: "```lodestar"),
           let close = raw.range(of: "```", range: fence.upperBound..<raw.endIndex) {
            let jsonStr = String(raw[fence.upperBound..<close.lowerBound])
            if let d = jsonStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                let outside = raw.replacingCharacters(in: fence.lowerBound..<close.upperBound, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let say = (obj["say"] as? String) ?? (outside.isEmpty ? "" : outside)
                return AssistantIntent(say: say, pointTarget: obj["point"] as? String)
            }
        }
        return AssistantIntent(say: raw.trimmingCharacters(in: .whitespacesAndNewlines), pointTarget: nil)
    }

    /// System prompt that teaches a model the (optional) action fence.
    static let systemPrompt = """
    You are Lodestar, a concise on-screen assistant that lives at the user's mouse cursor \
    on macOS. You are given a short description of what is on their screen and, optionally, \
    a screenshot. Answer briefly and practically. If the user is asking where something is \
    or how to do a step, you MAY append a single fenced block:
    ```lodestar
    { "say": "<one short spoken sentence>", "point": "<the exact on-screen control to point at>" }
    ```
    Only include "point" when there is a concrete, visible control to indicate. Never invent \
    UI that isn't described. Keep spoken answers to one or two sentences.
    """
}
