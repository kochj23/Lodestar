import XCTest
@testable import Lodestar

/// Category 7/7 — Frame: smoke tests. The core object graph assembles and the app's
/// invariants hold without launching the UI/run loop.
final class FrameTests: XCTestCase {

    func testCoreObjectGraphAssembles() {
        let cfg = Config.default
        let egress = EgressGuard(allowlist: cfg.security.egressAllowlist)
        let registry = ProviderRegistry(config: cfg, egress: egress)
        XCTAssertFalse(registry.ids.isEmpty, "should build at least one provider")
    }

    func testInvariants() {
        XCTAssertFalse(AssistantIntent.systemPrompt.isEmpty)
        XCTAssertTrue(Config.path.path.contains("lodestar"))
        XCTAssertFalse(EgressGuard(allowlist: []).summary.isEmpty)   // loopback always present
    }

    func testTTSConstructs() {
        // Constructing the default speech backend must not throw/crash.
        _ = AVSpeechTTS()
        _ = NullSTT()
    }
}
