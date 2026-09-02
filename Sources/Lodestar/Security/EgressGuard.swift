import Foundation

/// The single outbound chokepoint. Every network request in the app goes through
/// here, and any host not on the allow-list is refused. This is how "local-only"
/// is *enforced* rather than merely promised: there is no other code path to the
/// network, and the default allow-list is loopback only.
final class EgressGuard: @unchecked Sendable {
    private let allowed: Set<String>

    init(allowlist: [String]) {
        // Loopback is always permitted; everything else must be named explicitly.
        var set = Set(allowlist.map { $0.lowercased() })
        set.insert("127.0.0.1"); set.insert("::1"); set.insert("localhost")
        self.allowed = set
    }

    struct Blocked: Error, CustomStringConvertible {
        let host: String
        var description: String { "egress blocked: '\(host)' is not on the allow-list (local-only)" }
    }

    func check(_ url: URL?) throws {
        guard let host = url?.host?.lowercased() else { throw Blocked(host: "<none>") }
        guard allowed.contains(host) else { throw Blocked(host: host) }
    }

    /// Retried (2–3 attempts, backoff) after the allow-list check. Retries only on
    /// transport errors and 5xx — never on a 4xx (that won't get better).
    func data(for req: URLRequest) async throws -> (Data, URLResponse) {
        try check(req.url)
        return try await Retry.run { _ in
            let (d, r) = try await URLSession.shared.data(for: req)
            if let http = r as? HTTPURLResponse, http.statusCode >= 500 {
                throw ProviderError.http(http.statusCode, "server error")
            }
            return (d, r)
        }
    }

    /// Streaming: retry only the initial connection (can't resume a partial stream).
    func bytes(for req: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try check(req.url)
        return try await Retry.run { _ in
            try await URLSession.shared.bytes(for: req)
        }
    }

    var summary: String { allowed.sorted().joined(separator: ", ") }
}
