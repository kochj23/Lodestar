import XCTest
@testable import Lodestar

/// Category 5/7 — Integration: components working together (registry ↔ config,
/// provider ↔ egress guard).
final class IntegrationTests: XCTestCase {

    func testRegistryBuildsAndRoutesFromConfig() {
        let egress = EgressGuard(allowlist: Config.default.security.egressAllowlist)
        let reg = ProviderRegistry(config: .default, egress: egress)
        XCTAssertTrue(reg.ids.contains("ollama"))
        XCTAssertTrue(reg.ids.contains("nova"))
        XCTAssertNotNil(reg.route(.default))
        XCTAssertTrue(reg.route(.vision)?.capabilities.contains(.vision) ?? false,
                      "vision route should resolve to a vision-capable provider")
    }

    func testProviderRefusesToLeaveTheAllowList() async {
        let egress = EgressGuard(allowlist: [])   // loopback only
        let p = OpenAICompatibleProvider(
            id: "x", base: "http://evil.example.com/v1",
            textModel: "m", visionModel: nil, egress: egress)
        do {
            for try await _ in p.chat(ChatRequest(messages: [Message(.user, "hi")])) {}
            XCTFail("provider should have been blocked by the egress guard")
        } catch {
            XCTAssertTrue("\(error)".contains("egress blocked"), "unexpected error: \(error)")
        }
    }

    func testUnknownProviderKindIsSkippedNotFatal() {
        var cfg = Config.default
        cfg.providers["weird"] = .init(kind: "does-not-exist", baseUrl: "http://127.0.0.1:1",
                                       text: nil, vision: nil, path: nil, responseKey: nil, useMemory: nil)
        let reg = ProviderRegistry(config: cfg, egress: EgressGuard(allowlist: []))
        XCTAssertFalse(reg.ids.contains("weird"))
        XCTAssertFalse(reg.ids.isEmpty)   // the valid ones still load
    }
}
