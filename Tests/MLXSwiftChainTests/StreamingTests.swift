import Foundation
import Testing
@testable import MLXSwiftChain

@Suite("Streaming Tests")
struct StreamingTests {

    @Test func streamingBackend_deliversTokens() async throws {
        let mock = MockStreamingBackend()
        mock.cannedResponse = "hello beautiful world"
        let chain = StuffChain(backend: mock)

        var fragments: [String] = []
        var gotResult = false

        let stream = chain.stream(
            "text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            stuffPrompt: nil, systemPrompt: nil,
            options: ChainExecutionOptions(reservedOutputTokens: 0),
            progress: nil
        )

        for try await event in stream {
            switch event {
            case .chunk(let text): fragments.append(text)
            case .result: gotResult = true
            case .progress: break
            }
        }

        #expect(fragments.count >= 2)
        #expect(fragments.joined() == "hello beautiful world")
        #expect(gotResult)
    }

    @Test func nonStreamingBackend_emitsSingleChunk() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "full response"
        let chain = StuffChain(backend: mock)

        var fragments: [String] = []
        var gotResult = false

        let stream = chain.stream(
            "text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            stuffPrompt: nil, systemPrompt: nil,
            options: ChainExecutionOptions(reservedOutputTokens: 0),
            progress: nil
        )

        for try await event in stream {
            switch event {
            case .chunk(let text): fragments.append(text)
            case .result: gotResult = true
            case .progress: break
            }
        }

        #expect(fragments.count == 1)
        #expect(fragments.first == "full response")
        #expect(gotResult)
    }

    @Test func mapReduceChain_streamEmitsResult() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "mr output"
        let words = (0..<60).map { "word\($0)" }.joined(separator: " ")
        let chunker = FixedSizeChunker(maxWords: 20)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        var gotResult = false
        var resultText = ""

        let stream = chain.stream(
            words,
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        for try await event in stream {
            if case .result(let r) = event {
                gotResult = true
                resultText = r.text
            }
        }

        #expect(gotResult)
        #expect(resultText == "mr output")
    }

    @Test func adaptiveChain_streamDelegatesCorrectly() async throws {
        let mock = MockStreamingBackend()
        mock.cannedResponse = "adaptive stream"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 5000)

        var fragments: [String] = []

        let stream = chain.stream(
            "short input",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        for try await event in stream {
            if case .chunk(let text) = event {
                fragments.append(text)
            }
        }

        #expect(fragments.joined() == "adaptive stream")
    }

    @Test func stream_resultContainsMetrics() async throws {
        let mock = MockStreamingBackend()
        mock.cannedResponse = "output"
        let chain = StuffChain(backend: mock)

        var metrics: ChainMetrics?

        let stream = chain.stream(
            "text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        for try await event in stream {
            if case .result(let r) = event {
                metrics = r.metrics
            }
        }

        #expect(metrics != nil)
        #expect(metrics!.elapsedTime > .zero)
    }

    @Test func defaultDocumentChain_streamFallback() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "fallback result"
        let chain = StuffChain(backend: mock)

        var gotChunk = false
        var gotResult = false

        for try await event in chain.stream("x", mapPrompt: "M:", reducePrompt: "R:") {
            switch event {
            case .chunk: gotChunk = true
            case .result: gotResult = true
            case .progress: break
            }
        }

        #expect(gotChunk)
        #expect(gotResult)
    }
}
