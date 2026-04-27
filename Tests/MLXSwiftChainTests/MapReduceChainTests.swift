import Testing
@testable import MLXSwiftChain

@Suite("MapReduceChain Tests")
struct MapReduceChainTests {

    private let zeroReserved = ChainExecutionOptions(reservedOutputTokens: 0)

    @Test("MapReduceChain calls backend for each chunk plus reduce")
    func mapReduce_callCount() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "chunk summary"
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.generateCallCount == 4)
    }

    @Test("MapReduceChain sends map prompt with chunk text")
    func mapReduce_mapPrompt() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "summary"
        let chunker = FixedSizeChunker(maxWords: 5)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "alpha beta gamma delta epsilon zeta eta theta iota kappa"
        _ = try await chain.run(
            text, mapPrompt: "Summarize: ", reducePrompt: "Combine: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.promptsReceived[0].hasPrefix("Summarize: "))
        #expect(mock.promptsReceived[0].contains("alpha"))
        #expect(mock.promptsReceived[1].hasPrefix("Summarize: "))
        #expect(mock.promptsReceived[1].contains("zeta"))
    }

    @Test("MapReduceChain reduce prompt contains all chunk results")
    func mapReduce_reducePrompt() async throws {
        let mock = MockLLMBackend()
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "one two three four five six"
        mock.cannedResponse = "chunk summary"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        let reduceCall = mock.promptsReceived.last!
        #expect(reduceCall.hasPrefix("Reduce: "))
        #expect(reduceCall.contains("Section 1"))
        #expect(reduceCall.contains("Section 2"))
    }

    @Test("MapReduceChain returns empty for empty input")
    func mapReduce_emptyInput() async throws {
        let mock = MockLLMBackend()
        let chunker = FixedSizeChunker(maxWords: 100)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let result = try await chain.run(
            "", mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )
        #expect(result.isEmpty)
        #expect(mock.generateCallCount == 0)
    }

    @Test("MapReduceChain sees all markers across chunks")
    func mapReduce_fullCoverage() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "processed"
        let chunker = FixedSizeChunker(maxWords: 5)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "MARKER_25 word word word word MARKER_50 word word word word MARKER_75 word word word word MARKER_100"
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "Final: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        let allPrompts = mock.promptsReceived.joined(separator: " ")
        #expect(allPrompts.contains("MARKER_25"))
        #expect(allPrompts.contains("MARKER_50"))
        #expect(allPrompts.contains("MARKER_75"))
        #expect(allPrompts.contains("MARKER_100"))
    }

    @Test("MapReduceChain reports progress")
    func mapReduce_progress() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let progress = ChainProgress()
        var phases: [ChainProgress.Phase] = []

        Task {
            for await update in progress.updates {
                phases.append(update.phase)
            }
        }

        _ = try await chain.run(
            "one two three four five six", mapPrompt: "", reducePrompt: "",
            systemPrompt: nil, progress: progress
        )

        try await Task.sleep(for: .milliseconds(50))

        #expect(phases.contains(.mapping(step: 1, of: 2)))
        #expect(phases.contains(.mapping(step: 2, of: 2)))
        #expect(phases.contains(.reducing))
        #expect(phases.contains(.complete))
    }

    @Test("MapReduceChain finishes progress stream for empty input")
    func mapReduce_emptyInput_finishesProgress() async throws {
        let mock = MockLLMBackend()
        let chunker = FixedSizeChunker(maxWords: 100)
        let chain = MapReduceChain(backend: mock, chunker: chunker)
        let progress = ChainProgress()

        let watcher = Task {
            for await _ in progress.updates {}
            return true
        }

        _ = try await chain.run(
            "", mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            systemPrompt: nil, progress: progress
        )
        let didComplete = await watcher.value
        #expect(didComplete)
    }

    @Test("MapReduceChain uses hierarchical reduce when budget is tight")
    func mapReduce_hierarchicalReduce() async throws {
        let mock = MockLLMBackend()
        let longSummary = (0..<20).map { "word\($0)" }.joined(separator: " ")
        mock.cannedResponse = longSummary

        let chunker = FixedSizeChunker(maxWords: 5)
        // Budget large enough for map chunks (5 words < available ~104)
        // but too small for 10 × 20-word summaries combined (~250 words)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(200)
        )

        let text = (0..<50).map { "w\($0)" }.joined(separator: " ")
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.generateCallCount > 11, "Hierarchical reduce should require multiple reduce calls")
    }

    @Test("MapReduceChain hierarchical reduce preserves chunk labels")
    func mapReduce_chunkLabels() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "summary"

        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(20)
        )

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "Combine: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        let reducePrompts = mock.promptsReceived.filter { $0.hasPrefix("Combine:") }
        let allReduceText = reducePrompts.joined(separator: " ")
        #expect(allReduceText.contains("[Chunk"), "Reduce prompts should contain chunk labels")
    }

    @Test("MapReduceChain throws when reduce depth is exceeded")
    func mapReduce_depthExceeded() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = (0..<20).map { "longword\($0)" }.joined(separator: " ")

        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(10)
        )

        let text = (0..<30).map { "w\($0)" }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0, maxReduceDepth: 2)

        await #expect(throws: ChainError.self) {
            _ = try await chain.run(
                text, mapPrompt: "", reducePrompt: "R: ",
                stuffPrompt: nil, systemPrompt: nil,
                options: options, progress: nil
            )
        }
    }

    @Test("MapReduceChain single reduce still works without budget")
    func mapReduce_singleReduceNoBudget() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "chunk summary"
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: zeroReserved, progress: nil
        )

        #expect(mock.generateCallCount == 4)
    }

    @Test("MapReduceChain concurrent map returns results in order")
    func mapReduce_concurrentMap() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"

        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)
        let options = ChainExecutionOptions(reservedOutputTokens: 0, maxConcurrentMapTasks: 4)

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        #expect(mock.generateCallCount == 4)
        let mapPrompts = mock.promptsReceived.filter { $0.hasPrefix("Map: ") }
        #expect(mapPrompts.count == 3)
    }

    @Test("MapReduceChain respects cancellation in map phase")
    func mapReduce_cancellation() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = (0..<30).map { "w\($0)" }.joined(separator: " ")

        let task = Task {
            try await chain.run(
                text, mapPrompt: "", reducePrompt: "R: ",
                stuffPrompt: nil, systemPrompt: nil,
                options: zeroReserved, progress: nil
            )
        }
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors are acceptable during cancellation
        }
    }

    // MARK: - Budget-aware rechunking (Issue 1)

    @Test("MapReduceChain rechunks oversized chunks for prompt overhead")
    func mapReduce_rechunksOversizedChunksForPromptOverhead() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"

        let chunker = FixedSizeChunker(maxWords: 50)
        // Budget 150: available ≈ 150 - 4(sys) - 3(map) - 0 - 96(margin) = 47
        // Chunks are 50 words > 47 → rechunks
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(150)
        )

        // Use sentence-delimited text so SentenceAwareChunker fallback can split.
        // 100 sentences of ~1 word each → rechunked to ~47-word chunks ≈ 3 chunks.
        let text = (1...100).map { "Word\($0)." }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0)
        _ = try await chain.run(
            text, mapPrompt: "Summarize this: ",
            reducePrompt: "Combine: ",
            stuffPrompt: nil, systemPrompt: "You are a helper.",
            options: options, progress: nil
        )

        let mapPrompts = mock.promptsReceived.filter { $0.hasPrefix("Summarize") }
        #expect(mapPrompts.count > 2, "Should rechunk into more chunks when originals exceed map budget")
    }

    // MARK: - Token-aware reduce (Issue 2)

    @Test("MapReduceChain reduce uses token-aware budgeter")
    func mapReduce_reduceUsesTokenAwareBudgeter() async throws {
        // 1:1 token ratio, window 200 → enough for map chunks but not all summaries
        let mock = MockTokenAwareBackend(contextWindowTokens: 200, tokensPerWord: 1.0)
        mock.cannedResponse = (1...30).map { "w\($0)" }.joined(separator: " ")

        let chunker = FixedSizeChunker(maxWords: 5)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(999)
        )

        // 30 words → 6 chunks. Each returns 30-word summary.
        // 6 × 30-word summaries + formatting ≈ 240 tokens > 200 → hierarchical
        let text = (1...30).map { "w\($0)" }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0)
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        #expect(mock.generateCallCount > 7, "Should trigger hierarchical reduce with token-aware budget")
    }

    @Test("MapReduceChain reduce honors reserved output tokens")
    func mapReduce_reduceHonorsReservedOutputTokens() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"

        let chunker = FixedSizeChunker(maxWords: 5)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(80)
        )

        let text = (1...30).map { "w\($0)" }.joined(separator: " ")

        // With 0 reserved, reduce prompt for 6 chunks fits → single reduce
        let noReserved = ChainExecutionOptions(reservedOutputTokens: 0)
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "R: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: noReserved, progress: nil
        )
        let callsNoReserved = mock.generateCallCount

        // Reset and run with large reserved output
        let mock2 = MockLLMBackend()
        mock2.cannedResponse = "ok"
        let chain2 = MapReduceChain(
            backend: mock2,
            chunker: chunker,
            contextBudget: .words(80)
        )
        let highReserved = ChainExecutionOptions(reservedOutputTokens: 50)
        _ = try await chain2.run(
            text, mapPrompt: "", reducePrompt: "R: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: highReserved, progress: nil
        )
        let callsHighReserved = mock2.generateCallCount

        #expect(callsHighReserved >= callsNoReserved, "Higher reserved output should not produce fewer calls")
    }

    // MARK: - preserveOrder (Issue 3)

    @Test("Concurrent map with preserveOrder true returns original order")
    func concurrentMap_preserveOrderTrueReturnsOriginalOrder() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"

        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)
        let options = ChainExecutionOptions(
            reservedOutputTokens: 0,
            maxConcurrentMapTasks: 4,
            preserveOrder: true
        )

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        let reducePrompt = mock.promptsReceived.last!
        #expect(reducePrompt.contains("Section 1"))
        #expect(reducePrompt.contains("Section 2"))
        #expect(reducePrompt.contains("Section 3"))

        let sec1Pos = reducePrompt.range(of: "Section 1")!.lowerBound
        let sec2Pos = reducePrompt.range(of: "Section 2")!.lowerBound
        let sec3Pos = reducePrompt.range(of: "Section 3")!.lowerBound
        #expect(sec1Pos < sec2Pos)
        #expect(sec2Pos < sec3Pos)
    }

    @Test("Concurrent map with preserveOrder false preserves chunk labels")
    func concurrentMap_preserveOrderFalsePreservesLabels() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"

        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)
        let options = ChainExecutionOptions(
            reservedOutputTokens: 0,
            maxConcurrentMapTasks: 4,
            preserveOrder: false
        )

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        let reducePrompt = mock.promptsReceived.last!
        #expect(reducePrompt.contains("[Chunk 1]"))
        #expect(reducePrompt.contains("[Chunk 2]"))
        #expect(reducePrompt.contains("[Chunk 3]"))
    }

    // MARK: - Budget-derived reduce grouping (Issue 4)

    @Test("Hierarchical reduce groups by budget, not only fixed size")
    func hierarchicalReduce_groupsByBudgetNotOnlyFixedSize() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = (1...15).map { "w\($0)" }.joined(separator: " ")

        let chunker = FixedSizeChunker(maxWords: 3)
        // Budget 120: available ≈ 120 - 96 = 24, chunks are 3 words → no rechunk.
        // Combined 6 × 15-word summaries + formatting ≈ 132 words → exceeds 120 → hierarchical.
        // Budget-aware grouping can only fit ~5 summaries per group → more groups than
        // fixed maxReduceGroupSize (8) would produce.
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(120)
        )

        let text = (1...18).map { "w\($0)" }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0, maxReduceGroupSize: 8)
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        let reduceCalls = mock.promptsReceived.filter { $0.hasPrefix("Reduce:") }.count
        #expect(reduceCalls > 1, "Budget-aware grouping should create more reduce groups than maxReduceGroupSize alone")
    }

    @Test("Hierarchical reduce respects maxReduceGroupSize cap")
    func hierarchicalReduce_respectsMaxReduceGroupSize() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = (1...15).map { "w\($0)" }.joined(separator: " ")

        let chunker = FixedSizeChunker(maxWords: 3)
        // Budget 200: enough for map chunks but combined 10 × 15-word summaries
        // ≈ 200 words + formatting exceeds budget → forces hierarchical reduce.
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(200)
        )

        let text = (1...30).map { "w\($0)" }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0, maxReduceGroupSize: 3)
        _ = try await chain.run(
            text, mapPrompt: "", reducePrompt: "R: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        let reduceCalls = mock.promptsReceived.filter { $0.hasPrefix("R:") }.count
        #expect(reduceCalls >= 4, "Should respect maxReduceGroupSize even with large budget")
    }

    // MARK: - Token-to-word conversion in rechunking

    @Test("Token-mode rechunking converts token budget to conservative word target")
    func mapReduce_rechunkingConvertsTokenBudgetToWordTarget() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"

        // 2:1 token ratio → 1 word ≈ 2 tokens.
        // Budget 300 tokens, safety margin 128 tokens → available ≈ 300 - 2 - 128 = 170 tokens.
        // Without conversion: SentenceAwareChunker(targetWords: 170) → ~170-word chunks.
        // With conversion: 170 tokens / 2.0 = 85 words → ~85-word chunks.
        let chunker = FixedSizeChunker(maxWords: 200)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .tokens(300, estimatedTokensPerWord: 2.0)
        )

        let text = (1...200).map { "Word\($0)." }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0)
        _ = try await chain.run(
            text, mapPrompt: "Map: ",
            reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        let mapPrompts = mock.promptsReceived.filter { $0.hasPrefix("Map:") }
        #expect(mapPrompts.count >= 3, "Token-to-word conversion should produce smaller chunks than raw token count")
        for prompt in mapPrompts {
            let wordCount = prompt.split(whereSeparator: \.isWhitespace).count
            #expect(wordCount <= 110, "Each map prompt should be under ~110 words (85-word target + prompt + formatting)")
        }
    }

    @Test("Word-mode rechunking passes word budget directly as word target")
    func mapReduce_wordBudgetRechunkingStillUsesWordTarget() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"

        // Budget 150 words. mapPrompt ~3 words, safety ~96 words → available ≈ 51 words.
        // Word mode: targetWords = 51 directly (no conversion needed).
        let chunker = FixedSizeChunker(maxWords: 100)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(150)
        )

        let text = (1...200).map { "Word\($0)." }.joined(separator: " ")
        let options = ChainExecutionOptions(reservedOutputTokens: 0)
        _ = try await chain.run(
            text, mapPrompt: "Summarize this: ",
            reducePrompt: "Combine: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        let mapPrompts = mock.promptsReceived.filter { $0.hasPrefix("Summarize") }
        #expect(mapPrompts.count >= 4, "Word budget should rechunk into several smaller chunks")
    }

    // MARK: - Default reserved output (Issue 6)

    @Test("ChainExecutionOptions defaults reservedOutputTokens to 512")
    func chainExecutionOptions_defaultReservedOutputTokensIsConservative() {
        let options = ChainExecutionOptions()
        #expect(options.reservedOutputTokens == 512)
    }
}
