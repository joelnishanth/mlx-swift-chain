import Foundation
import Testing
@testable import MLXSwiftChain

@Suite("StuffChain Tests")
struct StuffChainTests {

    @Test func stuff_generatesWithFullText() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "summary"
        let chain = StuffChain(backend: mock)

        let result = try await chain.run(
            "Hello world",
            mapPrompt: "Map:", reducePrompt: "Reduce:"
        )
        #expect(result == "summary")
        #expect(mock.generateCallCount == 1)
    }

    @Test func stuff_usesStuffPromptOverReduce() async throws {
        let mock = MockLLMBackend()
        let chain = StuffChain(backend: mock)

        _ = try await chain.run(
            "text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            stuffPrompt: "Stuff:", systemPrompt: nil,
            options: ChainExecutionOptions(reservedOutputTokens: 0),
            progress: nil
        )

        let prompt = mock.promptsReceived.first!
        #expect(prompt.hasPrefix("Stuff:"))
    }

    @Test func stuff_fallsToReduceWhenNoStuffPrompt() async throws {
        let mock = MockLLMBackend()
        let chain = StuffChain(backend: mock)

        _ = try await chain.run(
            "text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            stuffPrompt: nil, systemPrompt: nil,
            options: ChainExecutionOptions(reservedOutputTokens: 0),
            progress: nil
        )

        let prompt = mock.promptsReceived.first!
        #expect(prompt.hasPrefix("Reduce:"))
    }

    @Test func stuff_reportsProgress() async throws {
        let mock = MockLLMBackend()
        let chain = StuffChain(backend: mock)
        let progress = ChainProgress()

        var phases: [ChainProgress.Phase] = []
        Task {
            for await update in progress.updates {
                phases.append(update.phase)
            }
        }

        _ = try await chain.run(
            "text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            stuffPrompt: nil, systemPrompt: nil,
            options: ChainExecutionOptions(reservedOutputTokens: 0),
            progress: progress
        )

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(phases.contains(.stuffing))
        #expect(phases.contains(.complete))
    }

    @Test func stuff_runWithMetadataReturnsResult() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result text"
        let chain = StuffChain(backend: mock)

        let result = try await chain.runWithMetadata(
            "Hello world foo bar baz",
            mapPrompt: "Map:", reducePrompt: "Reduce:"
        )
        #expect(result.text == "result text")
        #expect(result.sourceChunks.count == 1)
        #expect(result.sourceChunks[0].text == "Hello world foo bar baz")
        #expect(result.metrics != nil)
        #expect(result.metrics?.mapCallCount == 0)
    }

    @Test func stuff_delimitedPromptStyle() async throws {
        let mock = MockLLMBackend()
        let chain = StuffChain(backend: mock)

        _ = try await chain.run(
            "some text",
            mapPrompt: "Map:", reducePrompt: "Reduce:",
            stuffPrompt: nil, systemPrompt: nil,
            options: ChainExecutionOptions(reservedOutputTokens: 0, promptStyle: .delimited),
            progress: nil
        )

        let prompt = mock.promptsReceived.first!
        #expect(prompt.contains("<source"))
        #expect(prompt.contains("</source>"))
    }
}
