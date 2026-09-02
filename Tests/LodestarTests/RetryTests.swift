import XCTest
@testable import Lodestar

/// Category 3/7 — Retry: external calls retry with backoff, never a silent single shot.
final class RetryTests: XCTestCase {

    func testRetrySucceedsOnThirdAttempt() async throws {
        var calls = 0
        let result = try await Retry.run(attempts: 3, backoff: { _ in 0 }) { _ -> String in
            calls += 1
            if calls < 3 { throw ProviderError.badResponse("transient") }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls, 3, "should have retried until success")
    }

    func testRetryExhaustsThenThrows() async {
        var calls = 0
        do {
            _ = try await Retry.run(attempts: 2, backoff: { _ in 0 }) { _ -> String in
                calls += 1
                throw ProviderError.badResponse("always")
            }
            XCTFail("should have thrown after exhausting attempts")
        } catch {
            XCTAssertEqual(calls, 2, "should attempt exactly the configured number of times")
        }
    }

    func testRetryHonorsSingleAttemptFloor() async throws {
        var calls = 0
        let r = try await Retry.run(attempts: 0, backoff: { _ in 0 }) { _ -> Int in
            calls += 1; return 42
        }
        XCTAssertEqual(r, 42)
        XCTAssertEqual(calls, 1)
    }
}
