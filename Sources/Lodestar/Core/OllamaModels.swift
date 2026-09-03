import Foundation

/// Resolves configured model names against what's actually installed in Ollama, so a
/// config that names a model you don't have doesn't silently fail. Runs once at startup.
enum ModelResolver {
    private static let visionHints = ["vision", "vl", "llava", "moondream", "bakllava"]
    private static let skipHints   = ["embed", "arctic", "nomic"]

    static func resolve(_ config: Config) -> Config {
        var c = config
        for (id, pc) in c.providers where pc.kind == "openai" && pc.baseUrl.contains("11434") {
            guard let installed = installedModels(pc.baseUrl), !installed.isEmpty else { continue }
            var p = pc
            if let t = p.text, !installed.contains(t) {
                let picked = pickText(installed)
                Log.warn("provider \(id): text model '\(t)' not installed → using '\(picked ?? "none")'")
                p.text = picked
            } else if p.text == nil {
                p.text = pickText(installed)
            }
            if let v = p.vision, !installed.contains(v) {
                let picked = pickVision(installed)
                Log.warn("provider \(id): vision model '\(v)' not installed → using '\(picked ?? "none (vision off)")'")
                p.vision = picked
            }
            c.providers[id] = p
        }
        return c
    }

    static func pickVision(_ models: [String]) -> String? {
        models.first { m in visionHints.contains { m.lowercased().contains($0) } }
    }

    static func pickText(_ models: [String]) -> String? {
        models.first { m in
            let l = m.lowercased()
            return !visionHints.contains(where: { l.contains($0) })
                && !skipHints.contains(where: { l.contains($0) })
        }
    }

    /// Synchronous GET of Ollama's /api/tags (loopback, short timeout). Returns nil if
    /// Ollama isn't reachable — in which case we leave the config untouched.
    static func installedModels(_ baseUrl: String) -> [String]? {
        guard var comps = URLComponents(string: baseUrl) else { return nil }
        comps.path = "/api/tags"
        comps.query = nil
        guard let url = comps.url else { return nil }

        var result: [String]?
        let sem = DispatchSemaphore(value: 0)
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["models"] as? [[String: Any]] else { return }
            result = arr.compactMap { $0["name"] as? String }
        }.resume()
        _ = sem.wait(timeout: .now() + 4)
        return result
    }
}
