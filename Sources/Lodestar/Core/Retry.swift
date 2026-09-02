import Foundation

/// Every external call (HTTP, subprocess) goes through this: 2–3 attempts with
/// backoff, never a silent single-shot failure. Kept generic so it's unit-testable
/// on its own without a live server.
enum Retry {
    static func run<T>(
        attempts: Int = 3,
        backoff: @Sendable (Int) -> TimeInterval = { 0.4 * Double($0 + 1) },
        _ operation: (Int) async throws -> T
    ) async throws -> T {
        var last: Error?
        let n = max(1, attempts)
        for i in 0..<n {
            do {
                return try await operation(i)
            } catch {
                last = error
                if i < n - 1 {
                    let seconds = backoff(i)
                    if seconds > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    }
                }
            }
        }
        throw last ?? ProviderError.badResponse("retry: no attempts made")
    }
}
