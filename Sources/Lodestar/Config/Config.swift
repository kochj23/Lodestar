import Foundation

/// User configuration, JSON at ~/.config/lodestar/config.json. Human-editable.
/// A sensible local-only default is written on first launch.
struct Config: Codable {
    var hotkey: Hotkey
    var providers: [String: ProviderConfig]
    var routing: Routing
    var speech: Speech
    var security: Security
    var tools: Tools

    struct Hotkey: Codable {
        var invoke: String   // e.g. "ctrl+opt+space"
        var pause: String    // privacy pause
    }

    struct ProviderConfig: Codable {
        var kind: String            // "openai" | "nova-gateway"
        var baseUrl: String
        var text: String?           // text model id
        var vision: String?         // vision model id
        var path: String?           // nova-gateway request path
        var responseKey: String?    // nova-gateway JSON key holding the answer
        var useMemory: Bool?        // nova-gateway memory recall/remember
        // Nova load-balancer controls:
        var requestFormat: String?  // "message" (/api/chat) | "query" (/api/ai/query)
        var preferredBackend: String? // force a Nova backend, e.g. "ollama"/"mlx"/"llamacpp" (keeps it off cloud)
        var taskType: String?       // Nova routing hint, e.g. "auto"/"chat"/"code"
    }

    struct Routing: Codable {
        var `default`: String
        var quick: String
        var vision: String
    }

    struct Speech: Codable {
        var stt: String
        var sttModel: String
        var tts: String
    }

    struct Security: Codable {
        var egressAllowlist: [String]
        var redactSecureFields: Bool
        var captureRetention: String   // "none"
        var allowPrivateNetwork: Bool? // true = "local network only"; false = loopback + allow-list only
    }

    struct Tools: Codable {
        var notes: Bool
        var calendar: Bool
        var shortcuts: Bool
        var files: Bool
    }

    // MARK: - Load / default

    static var path: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/lodestar/config.json")
    }

    /// Write the current config back to disk (used by the Settings window).
    func save() throws {
        let url = Config.path
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url)
    }

    static func loadOrCreate() -> Config {
        let url = path
        if let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            if let cfg = try? dec.decode(Config.self, from: data) { return cfg }
            Log.warn("config at \(url.path) is unreadable — using defaults (not overwriting)")
            return .default
        }
        let cfg = Config.default
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.keyEncodingStrategy = .convertToSnakeCase
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(cfg).write(to: url)
            Log.info("wrote default config to \(url.path)")
        } catch {
            Log.warn("could not write default config: \(error)")
        }
        return cfg
    }

    static let `default` = Config(
        hotkey: .init(invoke: "ctrl+opt+space", pause: "ctrl+opt+."),
        providers: [
            // Nova gateway = the built-in load balancer (health-checks ollama/mlx/
            // llamacpp/openrouter). "message" format → POST /api/chat {message}.
            // Set preferredBackend to a local backend to keep on-screen text off cloud.
            // preferredBackend pinned to a local backend by default: keeps on-screen
            // text off the cloud (openrouter). Set it null to let the balancer route
            // freely across all backends, including cloud.
            "nova": .init(kind: "nova-gateway", baseUrl: "http://127.0.0.1:18792",
                          text: nil, vision: nil,
                          path: "/api/chat", responseKey: "response", useMemory: true,
                          requestFormat: "message", preferredBackend: "ollama", taskType: "auto"),
            "ollama": .init(kind: "openai", baseUrl: "http://127.0.0.1:11434/v1",
                            text: "llama3.1:8b", vision: "llama3.2-vision:11b",
                            path: nil, responseKey: nil, useMemory: nil,
                            requestFormat: nil, preferredBackend: nil, taskType: nil),
            "mlx": .init(kind: "openai", baseUrl: "http://127.0.0.1:8080/v1",
                         text: "qwen2.5-7b-instruct", vision: nil,
                         path: nil, responseKey: nil, useMemory: nil,
                         requestFormat: nil, preferredBackend: nil, taskType: nil),
        ],
        // Text → Nova (persona + memory) via its balancer, PINNED to a local backend so
        // nothing reaches the *web* (openrouter). The LAN is fine — that's the boundary.
        // Screenshots → local Ollama vision, which has no web path at all.
        routing: .init(default: "nova", quick: "mlx", vision: "ollama"),
        speech: .init(stt: "none", sttModel: "large-v3-turbo", tts: "avspeech"),
        security: .init(
            egressAllowlist: ["memory-server.digitalnoise.net", "ollama.digitalnoise.net"],
            redactSecureFields: true, captureRetention: "none",
            allowPrivateNetwork: true),
        tools: .init(notes: true, calendar: true, shortcuts: true, files: false)
    )
}
