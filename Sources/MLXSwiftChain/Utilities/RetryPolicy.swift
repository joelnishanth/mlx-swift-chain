import Foundation

/// Configuration for retrying failed LLM calls.
///
/// Primarily useful for remote backends where transient network errors
/// can occur. On-device MLX inference either succeeds or fails
/// deterministically (OOM, model not loaded), so retries rarely help.
public struct RetryPolicy: Sendable, Equatable {
    /// Maximum number of attempts (1 = no retry).
    public var maxAttempts: Int
    /// Delay between attempts in milliseconds.
    public var delayMilliseconds: Int

    /// No retry — execute once and propagate any error.
    public static let none = RetryPolicy(maxAttempts: 1, delayMilliseconds: 0)

    public init(maxAttempts: Int = 1, delayMilliseconds: Int = 0) {
        self.maxAttempts = max(1, maxAttempts)
        self.delayMilliseconds = max(0, delayMilliseconds)
    }
}

/// Execute an async operation with retry according to the given policy.
///
/// `CancellationError` is never retried — it propagates immediately so that
/// cooperative task cancellation is respected.
func withRetry<T: Sendable>(
    policy: RetryPolicy,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: (any Error)?
    for attempt in 1...policy.maxAttempts {
        try Task.checkCancellation()
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error
            if attempt < policy.maxAttempts && policy.delayMilliseconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(policy.delayMilliseconds) * 1_000_000)
            }
        }
    }
    throw lastError!
}
