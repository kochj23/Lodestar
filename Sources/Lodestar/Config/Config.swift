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
            "nova": .init(kind: "nova-gateway", baseUrl: "http://127.0.0.1:18792",
                          text: nil, vision: nil,
                          path: "/api/ai/query", responseKey: "response", useMemory: true),
            "ollama": .init(kind: "openai", baseUrl: "http://127.0.0.1:11434/v1",
                            text: "llama3.1:8b", vision: "llama3.2-vision:11b",
                            path: nil, responseKey: nil, useMemory: nil),
            "mlx": .init(kind: "openai", baseUrl: "http://127.0.0.1:8080/v1",
                         text: "qwen2.5-7b-instruct", vision: nil,
                         path: nil, responseKey: nil, useMemory: nil),
        ],
        routing: .init(default: "ollama", quick: "mlx", vision: "ollama"),
        speech: .init(stt: "none", sttModel: "large-v3-turbo", tts: "avspeech"),
        security: .init(
            egressAllowlist: ["127.0.0.1", "::1",
                              "memory-server.digitalnoise.net", "ollama.digitalnoise.net"],
            redactSecureFields: true, captureRetention: "none"),
        tools: .init(notes: true, calendar: true, shortcuts: true, files: false)
    )
}
