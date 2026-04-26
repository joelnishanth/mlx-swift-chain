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

/// Backend that fails a configurable number of times, then succeeds.
final class TransientFailBackend: LLMBackend, @unchecked Sendable {
    enum TransientError: Error {
        case transient
    }

    private var failCount: Int
    private var callCount = 0

    init(failCount: Int) {
        self.failCount = failCount
    }

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        callCount += 1
        if callCount <= failCount {
            throw TransientError.transient
        }
        return "recovered response"
    }
}
