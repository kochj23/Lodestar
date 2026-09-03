import Foundation

/// Talks to the local Nova Gateway so answers come back with Nova's persona (and,
/// when the gateway is wired to it, her memory). Nova's API is a single-query POST
/// rather than a streaming chat, so we fold the message list into one prompt and
/// yield the reply as a single chunk. Path/response-key are configurable because
/// gateway routes evolve.
final class NovaGatewayProvider: InferenceProvider, @unchecked Sendable {
    let id: String
    let capabilities: Set<Capability> = [.text]
    private let base: String
    private let path: String
    private let responseKey: String
    private let requestFormat: String     // "message" (/api/chat) | "query" (/api/ai/query)
    private let preferredBackend: String?  // pin a Nova backend (keeps content off cloud)
    private let taskType: String?
    private let token: String?
    private let egress: EgressGuard

    init(id: String, base: String, path: String, responseKey: String,
         requestFormat: String = "message", preferredBackend: String? = nil,
         taskType: String? = nil, token: String? = nil, egress: EgressGuard) {
        self.id = id
        self.base = base.hasSuffix("/") ? String(base.dropLast()) : base
        self.path = path.hasPrefix("/") ? path : "/" + path
        self.responseKey = responseKey
        self.requestFormat = requestFormat
        self.preferredBackend = preferredBackend
        self.taskType = taskType
        self.token = token
        self.egress = egress
    }

    func chat(_ req: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prompt = req.messages
                        .map { "\($0.role.rawValue): \($0.text)" }
                        .joined(separator: "\n")
                    guard let url = URL(string: base + path) else {
                        throw ProviderError.notConfigured("bad Nova base/path for \(id)")
                    }
                    // Build the body the running gateway understands, and always pass
                    // the load-balancer hints — servers that don't use a field ignore it.
                    let body = Self.makeBody(prompt: prompt, requestFormat: requestFormat,
                                             preferredBackend: preferredBackend, taskType: taskType)
                    var urlReq = URLRequest(url: url)
                    urlReq.httpMethod = "POST"
                    urlReq.timeoutInterval = 120
                    urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token { urlReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    urlReq.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (data, resp) = try await egress.data(for: urlReq)
                    if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                        throw ProviderError.http(http.statusCode, "from Nova gateway")
                    }
                    let text: String
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let answer = (obj[responseKey] as? String) ?? (obj["text"] as? String) {
                        text = answer
                    } else {
                        text = String(decoding: data, as: UTF8.self)
                    }
                    continuation.yield(ChatChunk(textDelta: text))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Pure body builder — kept static so the request shape is unit-testable.
    static func makeBody(prompt: String, requestFormat: String,
                         preferredBackend: String?, taskType: String?) -> [String: Any] {
        var body: [String: Any] = [:]
        if requestFormat == "query" {
            body["query"] = prompt
            body["stream"] = false
            if let taskType { body["task_type"] = taskType }
        } else {
            body["message"] = prompt
        }
        if let preferredBackend { body["preferred_backend"] = preferredBackend }
        return body
    }
}
