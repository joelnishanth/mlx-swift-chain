import Testing
@testable import MLXSwiftChain

@Suite("AdaptiveChain Tests")
struct AdaptiveChainTests {

    @Test("AdaptiveChain uses StuffChain for short text")
    func adaptive_shortText() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "stuffed result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 100)

        let text = "short text within budget"
        let result = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(result == "stuffed result")
        #expect(mock.generateCallCount == 1, "Short text should use a single StuffChain call")
        #expect(mock.promptsReceived[0].hasPrefix("Reduce: "), "StuffChain uses the reduce prompt")
    }

    @Test("AdaptiveChain uses MapReduceChain for long text")
    func adaptive_longText() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "chunk result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 5)

        let text = "one two three four five six seven eight nine ten eleven twelve"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount > 1, "Long text should trigger MapReduceChain with multiple calls")
    }

    @Test("AdaptiveChain boundary: exactly at budget uses stuff")
    func adaptive_exactBoundary() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 5)

        let text = "one two three four five"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount == 1, "Text at exactly the budget should use StuffChain")
    }

    @Test("AdaptiveChain boundary: one word over budget uses map-reduce")
    func adaptive_overBoundary() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 5)

        let text = "one two three four five six"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount > 1, "Text over budget should use MapReduceChain")
    }

    @Test("AdaptiveChain preserves full coverage on large text")
    func adaptive_fullCoverage() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 10)

        var words: [String] = []
        for i in 0..<100 {
            words.append("word\(i)")
        }
        words[0] = "MARKER_START"
        words[24] = "MARKER_25"
        words[49] = "MARKER_50"
        words[74] = "MARKER_75"
        words[99] = "MARKER_END"

        let text = words.joined(separator: " ")
        _ = try await chain.run(text, mapPrompt: "", reducePrompt: "Final: ")

        let allPrompts = mock.promptsReceived.joined(separator: " ")
        #expect(allPrompts.contains("MARKER_START"))
        #expect(allPrompts.contains("MARKER_25"))
        #expect(allPrompts.contains("MARKER_50"))
        #expect(allPrompts.contains("MARKER_75"))
        #expect(allPrompts.contains("MARKER_END"))
    }
}
