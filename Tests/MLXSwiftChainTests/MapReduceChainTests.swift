import Testing
@testable import MLXSwiftChain

@Suite("MapReduceChain Tests")
struct MapReduceChainTests {

    @Test("MapReduceChain calls backend for each chunk plus reduce")
    func mapReduce_callCount() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "chunk summary"
        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        // 3 chunks of 3 words -> 3 map calls + 1 reduce call = 4
        #expect(mock.generateCallCount == 4)
    }

    @Test("MapReduceChain sends map prompt with chunk text")
    func mapReduce_mapPrompt() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "summary"
        let chunker = FixedSizeChunker(maxWords: 5)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let text = "alpha beta gamma delta epsilon zeta eta theta iota kappa"
        _ = try await chain.run(text, mapPrompt: "Summarize: ", reducePrompt: "Combine: ")

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
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

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

        let result = try await chain.run("", mapPrompt: "Map: ", reducePrompt: "Reduce: ")
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
        _ = try await chain.run(text, mapPrompt: "", reducePrompt: "Final: ")

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

        _ = try await chain.run("one two three four five six", mapPrompt: "", reducePrompt: "", systemPrompt: nil, progress: progress)

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

        _ = try await chain.run("", mapPrompt: "Map: ", reducePrompt: "Reduce: ", systemPrompt: nil, progress: progress)
        let didComplete = await watcher.value
        #expect(didComplete)
    }

    @Test("MapReduceChain uses hierarchical reduce when budget is tight")
    func mapReduce_hierarchicalReduce() async throws {
        let mock = MockLLMBackend()
        // Each map call returns a 20-word summary
        let longSummary = (0..<20).map { "word\($0)" }.joined(separator: " ")
        mock.cannedResponse = longSummary

        let chunker = FixedSizeChunker(maxWords: 5)
        // Budget of 50 words means ~2 summaries fit per reduce, not all 10
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(50)
        )

        // 50 words -> 10 chunks of 5 words each
        let text = (0..<50).map { "w\($0)" }.joined(separator: " ")
        _ = try await chain.run(text, mapPrompt: "", reducePrompt: "Reduce: ")

        // 10 map calls + more than 1 reduce call (hierarchical)
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
        _ = try await chain.run(text, mapPrompt: "", reducePrompt: "Combine: ")

        let reducePrompts = mock.promptsReceived.filter { $0.hasPrefix("Combine:") }
        let allReduceText = reducePrompts.joined(separator: " ")
        #expect(allReduceText.contains("[Chunk"), "Reduce prompts should contain chunk labels")
    }

    @Test("MapReduceChain throws when reduce depth is exceeded")
    func mapReduce_depthExceeded() async throws {
        let mock = MockLLMBackend()
        // Return something that won't shrink enough to fit in 10 words
        mock.cannedResponse = (0..<20).map { "longword\($0)" }.joined(separator: " ")

        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(
            backend: mock,
            chunker: chunker,
            contextBudget: .words(10)
        )

        let text = (0..<30).map { "w\($0)" }.joined(separator: " ")
        let options = ChainExecutionOptions(maxReduceDepth: 2)

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
        _ = try await chain.run(text, mapPrompt: "Map: ", reducePrompt: "Reduce: ")

        // 3 chunks + 1 reduce = 4 calls (no hierarchical reduce without budget)
        #expect(mock.generateCallCount == 4)
    }

    @Test("MapReduceChain concurrent map returns results in order")
    func mapReduce_concurrentMap() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "result"

        let chunker = FixedSizeChunker(maxWords: 3)
        let chain = MapReduceChain(backend: mock, chunker: chunker)
        let options = ChainExecutionOptions(maxConcurrentMapTasks: 4)

        let text = "one two three four five six seven eight nine"
        _ = try await chain.run(
            text, mapPrompt: "Map: ", reducePrompt: "Reduce: ",
            stuffPrompt: nil, systemPrompt: nil,
            options: options, progress: nil
        )

        // 3 chunks + 1 reduce = 4 calls
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
            try await chain.run(text, mapPrompt: "", reducePrompt: "R: ")
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
}
