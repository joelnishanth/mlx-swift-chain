import Testing
@testable import MLXSwiftChain

@Suite("AdaptiveChain Tests")
struct AdaptiveChainTests {

    private let zeroReserved = ChainExecutionOptions(reservedOutputTokens: 0)

    @Test("AdaptiveChain uses StuffChain for short text")
    func adaptive_shortText() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "stuffed result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 100)

        let text = "short text within budget"
        let result = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

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
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.generateCallCount > 1, "Long text should trigger MapReduceChain with multiple calls")
    }

    @Test("AdaptiveChain boundary: exactly at budget uses stuff")
    func adaptive_exactBoundary() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 6)

        let text = "one two three four five"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.generateCallCount == 1, "Text at exactly the budget should use StuffChain")
    }

    @Test("AdaptiveChain boundary: one word over budget uses map-reduce")
    func adaptive_overBoundary() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 50)

        let text = (1...50).map { "w\($0)" }.joined(separator: " ")
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.generateCallCount > 1, "Text over budget should use MapReduceChain")
    }

    @Test("AdaptiveChain counts words across mixed whitespace")
    func adaptive_mixedWhitespaceCounting() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 6)

        let text = "one two\tthree\nfour five"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

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
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "Final: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

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
        let chain = AdaptiveChain(backend: mock, contextBudgetWords: 50)

        let text = (1...48).map { "w\($0)" }.joined(separator: " ")
        _ = try await chain.run(
            text, mapPrompt: "Map this section: ",
            reducePrompt: "Combine these results: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
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
            options: zeroReserved, progress: nil
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
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.generateCallCount > 1)
    }

    @Test("AdaptiveChain uses TokenAwareBackend for precise budgeting")
    func adaptive_tokenAwareBackend() async throws {
        let mock = MockTokenAwareBackend(contextWindowTokens: 15, tokensPerWord: 1.0)
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudget: .words(999))

        let text = "one two three four five six seven eight nine ten"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )
        #expect(mock.generateCallCount == 1, "Should stuff when text fits in TokenAwareBackend context window")
    }

    @Test("AdaptiveChain routes to map-reduce when TokenAwareBackend window is exceeded")
    func adaptive_tokenAwareOverflow() async throws {
        // Window 200 tokens, 1:1 ratio. Text + prompt ≈ 210 > 200 → map-reduce.
        // Window large enough for safety margin + individual map chunks.
        let mock = MockTokenAwareBackend(contextWindowTokens: 200, tokensPerWord: 1.0)
        mock.cannedResponse = "result"
        let chain = AdaptiveChain(backend: mock, contextBudget: .words(999))

        let text = (1...210).map { "w\($0)" }.joined(separator: " ")
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )
        #expect(mock.generateCallCount > 1, "Should use map-reduce when exceeding TokenAwareBackend window")
    }

    @Test("AdaptiveChain map-reduce accounts for map prompt in chunk budget")
    func adaptive_mapReduceChunkBudgetAccountsForMapPrompt() async throws {
        // Sentence-delimited text so SentenceAwareChunker fallback can split.
        let text = (1...200).map { "Word\($0)." }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0)

        // Short prompt (1 word): available ≈ 200 - 1 - 96 = 103.
        // FixedSizeChunker produces ~2 chunks of 150 words. 150 > 103 → rechunks.
        // SentenceAwareChunker(targetWords: 103) → ~2 chunks.
        let mock1 = MockLLMBackend()
        mock1.cannedResponse = "ok"
        let chain1 = AdaptiveChain(
            backend: mock1,
            contextBudget: .words(200),
            chunker: FixedSizeChunker(maxWords: 150)
        )
        _ = try await chain1.run(
            text, mapPrompt: "Summarize: ",
            reducePrompt: "Combine: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )
        let shortPromptMapCalls = mock1.promptsReceived.filter { $0.hasPrefix("Summarize") }.count

        // Long prompt (~28 words): available ≈ 200 - 28 - 96 = 76.
        // Same initial chunks (150 words). 150 > 76 → rechunks.
        // SentenceAwareChunker(targetWords: 76) → ~3 chunks.
        let mock2 = MockLLMBackend()
        mock2.cannedResponse = "ok"
        let chain2 = AdaptiveChain(
            backend: mock2,
            contextBudget: .words(200),
            chunker: FixedSizeChunker(maxWords: 150)
        )
        _ = try await chain2.run(
            text, mapPrompt: "Please carefully summarize this particular section of the document text being sure to pay close attention to all the important details and key points within it: ",
            reducePrompt: "Combine: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )
        let longPromptMapCalls = mock2.promptsReceived.filter { $0.hasPrefix("Please") }.count

        #expect(longPromptMapCalls > shortPromptMapCalls, "Longer map prompt should force rechunking into more, smaller chunks")
    }
}
