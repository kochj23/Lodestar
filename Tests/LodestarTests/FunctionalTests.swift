import XCTest
import CoreGraphics
@testable import Lodestar

/// Category 6/7 — Functional: end-to-end behavior from the caller's perspective.
/// The golden path here is "model answer → intent → resolved on-screen target".
final class FunctionalTests: XCTestCase {

    func testGoldenPath_answerBecomesAPointedTarget() async throws {
        let canned = "Top-right.\n```lodestar\n{\"say\":\"Click Export.\",\"point\":\"Export button\"}\n```"
        let provider = StubProvider(id: "stub", canned: canned)

        var full = ""
        for try await chunk in provider.chat(ChatRequest(messages: [Message(.user, "where's export?")])) {
            full += chunk.textDelta
        }
        let intent = AssistantIntent.parse(full)
        XCTAssertEqual(intent.say, "Click Export.")

        let elements = [
            AXElement(role: "AXButton", label: "Export", frame: CGRect(x: 900, y: 20, width: 80, height: 28)),
            AXElement(role: "AXButton", label: "Cancel", frame: CGRect(x: 800, y: 20, width: 80, height: 28)),
        ]
        let rect = Targeter.resolve(intent.pointTarget ?? "", in: elements)
        XCTAssertEqual(rect?.origin.x, 900, "should resolve to the Export button, not Cancel")
    }

    func testErrorPath_providerFailureSurfacesAsThrow() async {
        let provider = FailingProvider()
        do {
            for try await _ in provider.chat(ChatRequest(messages: [Message(.user, "x")])) {}
            XCTFail("failing provider should throw")
        } catch {
            XCTAssertTrue("\(error)".contains("boom"))
        }
    }

    func testPlainAnswer_noPointWhenNoTarget() async throws {
        let provider = StubProvider(id: "stub", canned: "It's already saved — nothing to do.")
        var full = ""
        for try await c in provider.chat(ChatRequest(messages: [Message(.user, "?")])) { full += c.textDelta }
        let intent = AssistantIntent.parse(full)
        XCTAssertNil(intent.pointTarget)
        XCTAssertFalse(intent.say.isEmpty)
    }
}
