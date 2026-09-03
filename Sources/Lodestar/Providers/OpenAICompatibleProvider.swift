import Foundation

/// One adapter, many engines: Ollama, LM Studio, llama.cpp `server`, vLLM, and
/// `mlx_lm.server` all speak the OpenAI Chat Completions shape (vision included
/// via base64 image_url). Configure a base URL + model names and you're done.
final class OpenAICompatibleProvider: InferenceProvider, @unchecked Sendable {
    let id: String
    let capabilities: Set<Capability>
    private let base: String            // includes /v1, no trailing slash
    private let textModel: String?
    private let visionModel: String?
    private let token: String?
    private let egress: EgressGuard

    init(id: String, base: String, textModel: String?, visionModel: String?,
         token: String? = nil, egress: EgressGuard) {
        self.id = id
        self.base = base.hasSuffix("/") ? String(base.dropLast()) : base
        self.textModel = textModel
        self.visionModel = visionModel
        self.token = token
        self.egress = egress
        var caps: Set<Capability> = [.text, .streaming]
        if visionModel != nil { caps.insert(.vision) }
        self.capabilities = caps
    }

    func chat(_ req: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let hasImages = req.messages.contains { !$0.images.isEmpty }
                    let model = req.model ?? (hasImages ? (visionModel ?? textModel) : textModel)
                    guard let model else { throw ProviderError.notConfigured("no model for \(id)") }
                    guard let url = URL(string: base + "/chat/completions") else {
                        throw ProviderError.notConfigured("bad base URL for \(id)")
                    }
                    var urlReq = URLRequest(url: url)
                    urlReq.httpMethod = "POST"
                    urlReq.timeoutInterval = 120   // never hang forever on a slow/missing model
                    urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token { urlReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    urlReq.httpBody = try Self.makeBody(model: model, req: req)

                    let (bytes, resp) = try await egress.bytes(for: urlReq)
                    if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                        throw ProviderError.http(http.statusCode, "from \(id)")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(ChatChunk(textDelta: content))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func makeBody(model: String, req: ChatRequest) throws -> Data {
        var msgs: [[String: Any]] = []
        for m in req.messages {
            if m.images.isEmpty {
                msgs.append(["role": m.role.rawValue, "content": m.text])
            } else {
                var content: [[String: Any]] = [["type": "text", "text": m.text]]
                for img in m.images {
                    let b64 = img.pngData.base64EncodedString()
                    content.append(["type": "image_url",
                                    "image_url": ["url": "data:image/png;base64,\(b64)"]])
                }
                msgs.append(["role": m.role.rawValue, "content": content])
            }
        }
        let json: [String: Any] = [
            "model": model, "messages": msgs,
            "temperature": req.temperature, "stream": req.stream,
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }
}
