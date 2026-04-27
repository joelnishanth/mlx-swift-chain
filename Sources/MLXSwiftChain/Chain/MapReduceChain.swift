import Foundation

/// Processes text that exceeds the context window by chunking it,
/// mapping each chunk through the LLM, then reducing the combined
/// chunk results into a final output.
///
/// When the combined reduce prompt exceeds the context budget,
/// hierarchical reduce is used: summaries are grouped, each group
/// is reduced, and the process repeats until the final result fits.
///
/// Set `ChainExecutionOptions.maxConcurrentMapTasks` > 1 for parallel
/// mapping (useful for remote backends; default of 1 is optimal for
/// on-device MLX inference).
public struct MapReduceChain: DocumentChain {
    public let backend: any LLMBackend
    public let chunker: any TextChunker
    public let contextBudget: ContextBudget?

    public init(backend: any LLMBackend, chunker: any TextChunker) {
        self.backend = backend
        self.chunker = chunker
        self.contextBudget = nil
    }

    /// Initialize with an explicit context budget for hierarchical reduce
    /// decisions, budget-aware map chunk sizing, and reduce grouping.
    public init(backend: any LLMBackend, chunker: any TextChunker, contextBudget: ContextBudget) {
        self.backend = backend
        self.chunker = chunker
        self.contextBudget = contextBudget
    }

    private struct MapResult {
        let chunkIndex: Int
        let text: String
    }

    public func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) async throws -> String {
        try await runWithMetadata(
            text,
            mapPrompt: mapPrompt,
            reducePrompt: reducePrompt,
            stuffPrompt: stuffPrompt,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress
        ).text
    }

    public func stream(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) -> AsyncThrowingStream<ChainEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let progressRelay = ChainProgress()
                    Task {
                        for await update in progressRelay.updates {
                            progress?.report(update)
                            continuation.yield(.progress(update))
                        }
                    }
                    let result = try await runWithMetadata(
                        text,
                        mapPrompt: mapPrompt,
                        reducePrompt: reducePrompt,
                        stuffPrompt: stuffPrompt,
                        systemPrompt: systemPrompt,
                        options: options,
                        progress: progressRelay
                    )
                    continuation.yield(.chunk(result.text))
                    continuation.yield(.result(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func runWithMetadata(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) async throws -> ChainResult {
        let start = ContinuousClock.now
        defer { progress?.finish() }

        let initialChunks = chunker.chunk(text)

        guard !initialChunks.isEmpty else {
            progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: .zero))
            return ChainResult(text: "", sourceChunks: [], metrics: MetricsAccumulator().finalize(elapsed: .zero))
        }

        let chunks = rechunkIfNeeded(
            text,
            existingChunks: initialChunks,
            mapPrompt: mapPrompt,
            systemPrompt: systemPrompt,
            options: options
        )

        var acc = MetricsAccumulator()
        acc.chunkCount = chunks.count

        let mapResults: [MapResult]
        if options.maxConcurrentMapTasks > 1 {
            mapResults = try await concurrentMap(
                chunks: chunks,
                mapPrompt: mapPrompt,
                systemPrompt: systemPrompt,
                options: options,
                progress: progress,
                start: start,
                acc: &acc
            )
        } else {
            mapResults = try await sequentialMap(
                chunks: chunks,
                mapPrompt: mapPrompt,
                systemPrompt: systemPrompt,
                options: options,
                progress: progress,
                start: start,
                acc: &acc
            )
        }

        let labeledSummaries = mapResults.map { result in
            "[Chunk \(result.chunkIndex + 1)] \(result.text)"
        }

        let finalResult = try await hierarchicalReduce(
            summaries: labeledSummaries,
            reducePrompt: reducePrompt,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress,
            start: start,
            depth: 1,
            acc: &acc
        )

        let totalElapsed = ContinuousClock.now - start
        progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: totalElapsed))

        return ChainResult(
            text: finalResult,
            sourceChunks: chunks,
            metrics: acc.finalize(elapsed: totalElapsed)
        )
    }

    // MARK: - Budget-Aware Rechunking

    private func rechunkIfNeeded(
        _ text: String,
        existingChunks: [TextChunk],
        mapPrompt: String,
        systemPrompt: String?,
        options: ChainExecutionOptions
    ) -> [TextChunk] {
        guard let budget = contextBudget else { return existingChunks }
        let budgeter = PromptBudgeter(backend: backend, budget: budget)
        let available = budgeter.availableTextBudget(
            systemPrompt: systemPrompt,
            taskPrompt: mapPrompt,
            reservedOutputTokens: options.reservedOutputTokens
        )
        let maxChunkSize = existingChunks.map { budgeter.count($0.text) }.max() ?? 0
        if maxChunkSize <= available { return existingChunks }

        let targetWords = fallbackWordTarget(
            availableBudgetUnits: available,
            budget: budget,
            backend: backend
        )
        let fallback = SentenceAwareChunker(targetWords: targetWords)
        return fallback.chunk(text)
    }

    private func fallbackWordTarget(
        availableBudgetUnits: Int,
        budget: ContextBudget,
        backend: any LLMBackend
    ) -> Int {
        switch budget {
        case .words:
            return max(1, availableBudgetUnits)
        case .tokens(_, let estimatedTokensPerWord):
            let heuristicRatio = max(0.1, estimatedTokensPerWord)
            let conservativeRatio: Double
            if backend is any TokenAwareBackend {
                conservativeRatio = max(heuristicRatio, 1.5)
            } else {
                conservativeRatio = heuristicRatio
            }
            return max(1, Int(Double(availableBudgetUnits) / conservativeRatio))
        }
    }

    // MARK: - Map Strategies

    private func sequentialMap(
        chunks: [TextChunk],
        mapPrompt: String,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?,
        start: ContinuousClock.Instant,
        acc: inout MetricsAccumulator
    ) async throws -> [MapResult] {
        var results: [MapResult] = []
        results.reserveCapacity(chunks.count)

        for (i, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .mapping(step: i + 1, of: chunks.count), elapsedTime: elapsed))

            let prompt = ChainPromptBuilder.mapPrompt(
                task: mapPrompt, chunk: chunk,
                totalChunks: chunks.count, style: options.promptStyle
            )
            if let tokenBackend = backend as? any TokenAwareBackend {
                acc.inputTokens += tokenBackend.tokenCounter.countTokens(prompt)
            }
            let result = try await withRetry(policy: options.retryPolicy) {
                try await self.backend.generate(prompt: prompt, systemPrompt: systemPrompt)
            }
            if let tokenBackend = backend as? any TokenAwareBackend {
                acc.outputTokens += tokenBackend.tokenCounter.countTokens(result)
            }
            acc.mapCallCount += 1
            results.append(MapResult(chunkIndex: i, text: result))
        }
        return results
    }

    private func concurrentMap(
        chunks: [TextChunk],
        mapPrompt: String,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?,
        start: ContinuousClock.Instant,
        acc: inout MetricsAccumulator
    ) async throws -> [MapResult] {
        var localInputTokens = 0
        var localOutputTokens = 0
        let tokenBackend = backend as? any TokenAwareBackend

        let results = try await withThrowingTaskGroup(of: MapResult.self) { group in
            var inFlight = 0
            var nextIndex = 0
            var orderedResults = [Int: String]()
            var completionOrder: [MapResult] = []
            orderedResults.reserveCapacity(chunks.count)
            completionOrder.reserveCapacity(chunks.count)
            var completedCount = 0

            while nextIndex < chunks.count || !group.isEmpty {
                while inFlight < options.maxConcurrentMapTasks && nextIndex < chunks.count {
                    let idx = nextIndex
                    let chunk = chunks[idx]
                    let prompt = ChainPromptBuilder.mapPrompt(
                        task: mapPrompt, chunk: chunk,
                        totalChunks: chunks.count, style: options.promptStyle
                    )
                    if let counter = tokenBackend?.tokenCounter {
                        localInputTokens += counter.countTokens(prompt)
                    }
                    group.addTask {
                        try Task.checkCancellation()
                        let result = try await withRetry(policy: options.retryPolicy) {
                            try await self.backend.generate(prompt: prompt, systemPrompt: systemPrompt)
                        }
                        return MapResult(chunkIndex: idx, text: result)
                    }
                    inFlight += 1
                    nextIndex += 1
                }
                if let mapResult = try await group.next() {
                    if let counter = tokenBackend?.tokenCounter {
                        localOutputTokens += counter.countTokens(mapResult.text)
                    }
                    orderedResults[mapResult.chunkIndex] = mapResult.text
                    completionOrder.append(mapResult)
                    inFlight -= 1
                    completedCount += 1
                    let elapsed = ContinuousClock.now - start
                    progress?.report(ChainProgress.Update(phase: .mapping(step: completedCount, of: chunks.count), elapsedTime: elapsed))
                }
            }

            if options.preserveOrder {
                return (0..<chunks.count).map { MapResult(chunkIndex: $0, text: orderedResults[$0]!) }
            } else {
                return completionOrder
            }
        }
        acc.mapCallCount += results.count
        acc.inputTokens += localInputTokens
        acc.outputTokens += localOutputTokens
        return results
    }

    // MARK: - Hierarchical Reduce

    private func hierarchicalReduce(
        summaries: [String],
        reducePrompt: String,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?,
        start: ContinuousClock.Instant,
        depth: Int,
        acc: inout MetricsAccumulator
    ) async throws -> String {
        guard depth <= options.maxReduceDepth else {
            throw ChainError.reduceDepthExceeded(maxDepth: options.maxReduceDepth)
        }

        let combined = formatSummaries(summaries)

        if fitsInSingleReduce(
            combined: combined,
            reducePrompt: reducePrompt,
            systemPrompt: systemPrompt,
            options: options
        ) {
            try Task.checkCancellation()
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .reducing, elapsedTime: elapsed))
            let reduceInput = ChainPromptBuilder.reducePrompt(
                task: reducePrompt, summaries: summaries,
                totalSections: summaries.count, style: options.promptStyle
            )
            if let tokenBackend = backend as? any TokenAwareBackend {
                acc.inputTokens += tokenBackend.tokenCounter.countTokens(reduceInput)
            }
            let result = try await withRetry(policy: options.retryPolicy) {
                try await self.backend.generate(prompt: reduceInput, systemPrompt: systemPrompt)
            }
            if let tokenBackend = backend as? any TokenAwareBackend {
                acc.outputTokens += tokenBackend.tokenCounter.countTokens(result)
            }
            acc.reduceCallCount += 1
            return result
        }

        let groups = makeReduceGroups(
            summaries: summaries,
            reducePrompt: reducePrompt,
            systemPrompt: systemPrompt,
            options: options
        )

        var intermediateSummaries: [String] = []
        intermediateSummaries.reserveCapacity(groups.count)

        for group in groups {
            try Task.checkCancellation()
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .reducing, elapsedTime: elapsed))

            let groupPrompt = ChainPromptBuilder.reducePrompt(
                task: reducePrompt, summaries: group,
                totalSections: group.count, style: options.promptStyle
            )
            if let tokenBackend = backend as? any TokenAwareBackend {
                acc.inputTokens += tokenBackend.tokenCounter.countTokens(groupPrompt)
            }
            let groupResult = try await withRetry(policy: options.retryPolicy) {
                try await self.backend.generate(prompt: groupPrompt, systemPrompt: systemPrompt)
            }
            if let tokenBackend = backend as? any TokenAwareBackend {
                acc.outputTokens += tokenBackend.tokenCounter.countTokens(groupResult)
            }
            acc.reduceCallCount += 1

            let firstChunkLabel = extractChunkRange(from: group.first ?? "")
            let lastChunkLabel = extractChunkRange(from: group.last ?? "")
            let rangeLabel = "[Chunks \(firstChunkLabel)-\(lastChunkLabel)]"
            intermediateSummaries.append("\(rangeLabel) \(groupResult)")
        }

        return try await hierarchicalReduce(
            summaries: intermediateSummaries,
            reducePrompt: reducePrompt,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress,
            start: start,
            depth: depth + 1,
            acc: &acc
        )
    }

    // MARK: - Helpers

    private func fitsInSingleReduce(
        combined: String,
        reducePrompt: String,
        systemPrompt: String?,
        options: ChainExecutionOptions
    ) -> Bool {
        guard let budget = contextBudget else { return true }
        let budgeter = PromptBudgeter(backend: backend, budget: budget)
        return budgeter.fits(
            systemPrompt: systemPrompt,
            taskPrompt: reducePrompt,
            text: combined,
            reservedOutputTokens: options.reservedOutputTokens
        )
    }

    private func makeReduceGroups(
        summaries: [String],
        reducePrompt: String,
        systemPrompt: String?,
        options: ChainExecutionOptions
    ) -> [[String]] {
        let maxSize = max(2, options.maxReduceGroupSize)

        guard let budget = contextBudget else {
            return stride(from: 0, to: summaries.count, by: maxSize).map { startIdx in
                Array(summaries[startIdx..<min(startIdx + maxSize, summaries.count)])
            }
        }

        let budgeter = PromptBudgeter(backend: backend, budget: budget)
        var groups: [[String]] = []
        var current: [String] = []

        for summary in summaries {
            let candidate = current + [summary]
            if candidate.count > maxSize {
                if !current.isEmpty { groups.append(current) }
                current = [summary]
                continue
            }
            let candidateText = formatSummaries(candidate)
            if current.isEmpty || budgeter.fits(
                systemPrompt: systemPrompt,
                taskPrompt: reducePrompt,
                text: candidateText,
                reservedOutputTokens: options.reservedOutputTokens
            ) {
                current = candidate
            } else {
                groups.append(current)
                current = [summary]
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    private func formatSummaries(_ summaries: [String]) -> String {
        summaries.enumerated().map { i, summary in
            "--- Section \(i + 1) of \(summaries.count) ---\n\(summary)"
        }.joined(separator: "\n\n")
    }

    private func extractChunkRange(from text: String) -> String {
        if let range = text.range(of: #"\[Chunk[s]? ([\d\-]+)\]"#, options: .regularExpression) {
            let match = text[range]
            let inner = match.dropFirst(1).dropLast(1)
            let parts = inner.split(separator: " ")
            return parts.count > 1 ? String(parts[1]) : "?"
        }
        return "?"
    }
}
