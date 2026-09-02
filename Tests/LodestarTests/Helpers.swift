import Foundation
@testable import Lodestar

/// Yields a canned response — lets us test the answer→intent→point pipeline with no
/// network and no real model.
final class StubProvider: InferenceProvider, @unchecked Sendable {
    let id: String
    let capabilities: Set<Capability> = [.text]
    let canned: String
    init(id: String, canned: String) { self.id = id; self.canned = canned }

    func chat(_ req: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        let text = canned
        return AsyncThrowingStream { c in
            c.yield(ChatChunk(textDelta: text))
            c.finish()
        }
    }
}

/// Always errors — for exercising error paths.
final class FailingProvider: InferenceProvider, @unchecked Sendable {
    let id = "failing"
    let capabilities: Set<Capability> = [.text]
    func chat(_ req: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { c in c.finish(throwing: ProviderError.badResponse("boom")) }
    }
}
