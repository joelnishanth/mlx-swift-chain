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
        mock.cannedResponse = "ok"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 50)

        let text = (1...100).map { "word\($0)" }.joined(separator: " ")
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount > 1, "Long text should trigger MapReduceChain with multiple calls")
    }

    @Test("AdaptiveChain boundary: exactly at budget uses stuff")
    func adaptive_exactBoundary() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        // Budget must cover text + prompt overhead: 5 words text + 1 word "Reduce:" = 6
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 6)

        let text = "one two three four five"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount == 1, "Text at exactly the budget should use StuffChain")
    }

    @Test("AdaptiveChain boundary: one word over budget uses map-reduce")
    func adaptive_overBoundary() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 50)

        // 50 words text + 1 word "Reduce:" = 51 > budget 50 → map-reduce
        let text = (1...50).map { "w\($0)" }.joined(separator: " ")
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount > 1, "Text over budget should use MapReduceChain")
    }

    @Test("AdaptiveChain counts words across mixed whitespace")
    func adaptive_mixedWhitespaceCounting() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        // Budget must cover text + prompt: 5 words text + 1 word "Reduce:" = 6
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 6)

        let text = "one two\tthree\nfour five"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount == 1, "Whitespace variations should still count as 5 words")
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

    @Test("AdaptiveChain routes to map-reduce when prompt overhead pushes over budget")
    func adaptive_promptOverhead() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"
        // 48 words text + 1 word "Reduce:" = 49 < 50 → stuff
        // But "Combine these results: " = 3 words → 48 + 3 = 51 > 50 → map-reduce
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 50)

        let text = (1...48).map { "w\($0)" }.joined(separator: " ")
        _ = try await chain.run(
            text, mapPrompt: "Map this section: ",
            reducePrompt: "Combine these results: "
        )

        #expect(mock.generateCallCount > 1, "Prompt overhead should push text over budget to map-reduce")
    }

    @Test("AdaptiveChain uses stuffPrompt when provided")
    func adaptive_stuffPrompt() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "stuffed"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 100)

        let text = "short text"
        let result = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: "StuffOverride: ", systemPrompt: nil,
            options: ChainExecutionOptions(), progress: nil
        )

        #expect(result == "stuffed")
        #expect(mock.generateCallCount == 1)
        #expect(mock.promptsReceived[0].hasPrefix("StuffOverride: "), "StuffChain should use stuffPrompt")
    }

    @Test("AdaptiveChain accounts for reservedOutputTokens in budget")
    func adaptive_reservedOutput() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 20)

        let text = "one two three four five six seven eight nine ten"
        // 10 words text + 1 word prompt + ~7 reserved (10 tokens / 1.33) = 18 fits in 20
        let fitsOptions = ChainExecutionOptions(reservedOutputTokens: 10)
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "R: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: fitsOptions, progress: nil
        )
        #expect(mock.generateCallCount == 1, "Should fit with small reserved output")
    }

    @Test("AdaptiveChain supports token-oriented budget strategy")
    func adaptive_tokenBudget() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"
        let chain = AdaptiveChain(backend: mock, contextBudget: .tokens(50, estimatedTokensPerWord: 1.0))

        let text = (1...60).map { "word\($0)" }.joined(separator: " ")
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        #expect(mock.generateCallCount > 1)
    }

    @Test("AdaptiveChain uses TokenAwareBackend for precise budgeting")
    func adaptive_tokenAwareBackend() async throws {
        // 1:1 token ratio, context window of 15 tokens
        let mock = MockTokenAwareBackend(contextWindowTokens: 15, tokensPerWord: 1.0)
        mock.cannedResponse = "result"
        // Budget doesn't matter when backend provides context window
        let chain = AdaptiveChain(backend: mock, contextBudget: .words(999))

        // 10 words text + "Reduce:" 1 word = 11 tokens -> fits in 15
        let text = "one two three four five six seven eight nine ten"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")
        #expect(mock.generateCallCount == 1, "Should stuff when text fits in TokenAwareBackend context window")
    }

    @Test("AdaptiveChain routes to map-reduce when TokenAwareBackend window is exceeded")
    func adaptive_tokenAwareOverflow() async throws {
        let mock = MockTokenAwareBackend(contextWindowTokens: 8, tokensPerWord: 1.0)
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudget: .words(999))

        // 10 words + 1 word prompt = 11 tokens > 8 window
        let text = "one two three four five six seven eight nine ten"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")
        #expect(mock.generateCallCount > 1, "Should use map-reduce when exceeding TokenAwareBackend window")
    }

}
