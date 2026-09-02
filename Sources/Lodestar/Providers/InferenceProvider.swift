import Foundation

/// What a backend can do. A provider advertises its set; the router honours it.
enum Capability: String, Sendable, Codable {
    case text, vision, tools, streaming
}

/// A screenshot (or any image) attached to a message for vision models.
struct Attachment: Sendable {
    var pngData: Data
}

struct Message: Sendable {
    enum Role: String, Sendable { case system, user, assistant }
    var role: Role
    var text: String
    var images: [Attachment]

    init(_ role: Role, _ text: String, images: [Attachment] = []) {
        self.role = role; self.text = text; self.images = images
    }
}

struct ChatRequest: Sendable {
    var messages: [Message]
    var model: String?
    var temperature: Double
    var stream: Bool

    init(messages: [Message], model: String? = nil, temperature: Double = 0.4, stream: Bool = true) {
        self.messages = messages; self.model = model
        self.temperature = temperature; self.stream = stream
    }
}

struct ChatChunk: Sendable {
    var textDelta: String
}

enum ProviderError: Error, CustomStringConvertible {
    case badResponse(String)
    case notConfigured(String)
    case http(Int, String)

    var description: String {
        switch self {
        case .badResponse(let s): return "bad response: \(s)"
        case .notConfigured(let s): return "not configured: \(s)"
        case .http(let c, let s): return "HTTP \(c): \(s)"
        }
    }
}

/// The single seam that makes "any local engine, including Nova" real.
/// Text, vision, and (later) tools all flow through this; adapters differ only
/// in how they speak to their local endpoint.
protocol InferenceProvider: Sendable {
    var id: String { get }
    var capabilities: Set<Capability> { get }
    func chat(_ req: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
}
