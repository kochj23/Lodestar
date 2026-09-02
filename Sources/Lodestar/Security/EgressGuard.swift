import Foundation

/// The single outbound chokepoint. Every network request in the app passes through
/// here; anything that isn't loopback, a private-LAN address, or an explicitly named
/// host is refused. The policy is "local network only" — the app itself never talks to
/// the public internet — while still letting you reach Nova, Ollama, etc. on your LAN.
///
/// Note the boundary: this governs where *Lodestar* connects. If you route through the
/// Nova gateway and Nova's balancer chooses a cloud backend (e.g. openrouter), that hop
/// is Nova's, not Lodestar's — pin a local `preferred_backend` to keep screen content on
/// your network.
final class EgressGuard: @unchecked Sendable {
    private let allowed: Set<String>
    private let allowPrivateNetwork: Bool

    /// - allowlist: extra named hosts to permit (e.g. `ollama.digitalnoise.net`).
    /// - allowPrivateNetwork: permit any RFC1918 / link-local / `.local` address
    ///   without naming it. Default true = "local network only". False = loopback +
    ///   allow-list only ("strictly local").
    init(allowlist: [String], allowPrivateNetwork: Bool = true) {
        var set = Set(allowlist.map { $0.lowercased() })
        set.insert("127.0.0.1"); set.insert("::1"); set.insert("localhost")
        self.allowed = set
        self.allowPrivateNetwork = allowPrivateNetwork
    }

    struct Blocked: Error, CustomStringConvertible {
        let host: String
        var description: String {
            "egress blocked: '\(host)' is not loopback, a private-LAN address, or allow-listed"
        }
    }

    func check(_ url: URL?) throws {
        guard let host = url?.host?.lowercased() else { throw Blocked(host: "<none>") }
        if allowed.contains(host) { return }
        if allowPrivateNetwork, Self.isPrivateOrLocal(host) { return }
        throw Blocked(host: host)
    }

    /// True for loopback, RFC1918 private ranges, link-local, and mDNS `.local` names —
    /// i.e. things that can't route off your network. String-only (no DNS lookup).
    static func isPrivateOrLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host == "::1" { return true }
        if host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") { return true } // IPv6 link-local / ULA
        let p = host.split(separator: ".").map(String.init)
        if p.count == 4, p.allSatisfy({ Int($0) != nil }), let a = Int(p[0]), let b = Int(p[1]) {
            if a == 127 { return true }                       // loopback
            if a == 10 { return true }                        // 10.0.0.0/8
            if a == 192, b == 168 { return true }             // 192.168.0.0/16
            if a == 172, (16...31).contains(b) { return true } // 172.16.0.0/12
            if a == 169, b == 254 { return true }             // link-local
        }
        return false
    }

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

    func bytes(for req: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try check(req.url)
        return try await Retry.run { _ in
            try await URLSession.shared.bytes(for: req)
        }
    }

    var summary: String {
        var parts = allowPrivateNetwork ? ["loopback+private-LAN"] : ["loopback"]
        let named = allowed.subtracting(["127.0.0.1", "::1", "localhost"]).sorted()
        parts.append(contentsOf: named)
        return parts.joined(separator: ", ")
    }
}
