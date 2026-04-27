import Foundation
import Testing
@testable import MLXSwiftChain

@Suite("ChainResult Tests")
struct ChainResultTests {

    @Test func stuffChain_resultContainsSourceChunks() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "output"
        let chain = StuffChain(backend: mock)

        let result = try await chain.runWithMetadata(
            "Hello world test",
            mapPrompt: "Map:", reducePrompt: "Reduce:"
        )

        #expect(result.text == "output")
        #expect(result.sourceChunks.count == 1)
        #expect(result.sourceChunks[0].wordCount == 3)
    }

    @Test func mapReduceChain_resultContainsAllChunks() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "mapped"
        let words = (0..<100).map { "word\($0)" }.joined(separator: " ")
        let chunker = FixedSizeChunker(maxWords: 30)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let result = try await chain.runWithMetadata(
            words,
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        #expect(result.sourceChunks.count >= 3)
        #expect(result.metrics != nil)
        #expect(result.metrics!.chunkCount >= 3)
        #expect(result.metrics!.mapCallCount >= 3)
        #expect(result.metrics!.reduceCallCount >= 1)
    }

    @Test func adaptiveChain_stuffPathReturnsResult() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "adaptive result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 5000)

        let result = try await chain.runWithMetadata(
            "short text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        #expect(result.text == "adaptive result")
        #expect(result.sourceChunks.count == 1)
        #expect(result.metrics?.mapCallCount == 0)
    }

    @Test func adaptiveChain_mapReducePathReturnsResult() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "mr result"
        let sentences = (0..<20).map { "Sentence number \($0) with extra words for padding." }
        let text = sentences.joined(separator: " ")
        let chunker = FixedSizeChunker(maxWords: 30)
        let chain = AdaptiveChain(backend: mock, contextBudget: .words(100), chunker: chunker)

        let result = try await chain.runWithMetadata(
            text,
            mapPrompt: "M:", reducePrompt: "R:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        #expect(result.text == "mr result")
        #expect(result.sourceChunks.count > 1)
        #expect(result.metrics!.mapCallCount > 1)
    }

    @Test func metrics_elapsedTimeIsPositive() async throws {
        let mock = MockLLMBackend()
        let chain = StuffChain(backend: mock)

        let result = try await chain.runWithMetadata(
            "test text",
            mapPrompt: "Map:", reducePrompt: "Reduce:"
        )

        #expect(result.metrics!.elapsedTime > .zero)
    }

    @Test func metrics_tokenAwareBackendCountsTokens() async throws {
        let mock = MockTokenAwareBackend(contextWindowTokens: 10000, tokensPerWord: 1.0)
        mock.cannedResponse = "output text here"
        let chain = StuffChain(backend: mock)

        let result = try await chain.runWithMetadata(
            "hello world test",
            mapPrompt: "Map:", reducePrompt: "Reduce:"
        )

        #expect(result.metrics?.estimatedInputTokens != nil)
        #expect(result.metrics!.estimatedInputTokens! > 0)
        #expect(result.metrics?.estimatedOutputTokens != nil)
        #expect(result.metrics!.estimatedOutputTokens! > 0)
    }

    @Test func defaultDocumentChain_runWithMetadataFallback() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "default result"
        let chain = StuffChain(backend: mock)

        let result: ChainResult = try await chain.runWithMetadata(
            "text",
            mapPrompt: "M:", reducePrompt: "R:"
        )

        #expect(result.text == "default result")
    }
}
