import Foundation
import Testing
@testable import MLXSwiftChain

@Suite("Retry Tests")
struct RetryTests {

    @Test("Retry succeeds after transient failure")
    func retry_succeedsAfterFailure() async throws {
        let mock = TransientFailBackend(failCount: 1)
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)
        let options = ChainExecutionOptions(retryPolicy: RetryPolicy(maxAttempts: 3, delayMilliseconds: 0))

        let text = "one two three four five six"
        let result = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        #expect(!result.isEmpty)
    }

    @Test("Retry throws after exhausting all attempts")
    func retry_exhaustsAttempts() async throws {
        let mock = TransientFailBackend(failCount: 10)
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)
        let options = ChainExecutionOptions(retryPolicy: RetryPolicy(maxAttempts: 2, delayMilliseconds: 0))

        let text = "one two three four five six"

        await #expect(throws: TransientFailBackend.TransientError.self) {
            _ = try await chain.run(
                text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
                stuffPrompt: nil, systemPrompt: nil,
                options: options, progress: nil
            )
        }
    }

    @Test("No retry when policy is .none")
    func retry_nonePolicy() async throws {
        let mock = TransientFailBackend(failCount: 1)
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "one two three four five six"

        await #expect(throws: TransientFailBackend.TransientError.self) {
            _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")
        }
    }
}

/// Thread-safe backend that fails a configurable number of times, then succeeds.
final class TransientFailBackend: LLMBackend, @unchecked Sendable {
    enum TransientError: Error {
        case transient
    }

    private let lock = NSLock()
    private let failCount: Int
    private var _callCount = 0

    init(failCount: Int) {
        self.failCount = failCount
    }

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        try lock.withLock {
            _callCount += 1
            if _callCount <= failCount {
                throw TransientError.transient
            }
            return "recovered response"
        }
    }
}
