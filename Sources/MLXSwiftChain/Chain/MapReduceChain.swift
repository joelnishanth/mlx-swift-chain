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
        let start = ContinuousClock.now
        defer { progress?.finish() }

        let initialChunks = chunker.chunk(text)

        guard !initialChunks.isEmpty else {
            progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: .zero))
            return ""
        }

        let chunks = rechunkIfNeeded(
            text,
            existingChunks: initialChunks,
            mapPrompt: mapPrompt,
            systemPrompt: systemPrompt,
            options: options
        )

        // Map phase
        let mapResults: [MapResult]
        if options.maxConcurrentMapTasks > 1 {
            mapResults = try await concurrentMap(
                chunks: chunks,
                mapPrompt: mapPrompt,
                systemPrompt: systemPrompt,
                options: options,
                progress: progress,
                start: start
            )
        } else {
            mapResults = try await sequentialMap(
                chunks: chunks,
                mapPrompt: mapPrompt,
                systemPrompt: systemPrompt,
                options: options,
                progress: progress,
                start: start
            )
        }

        // Reduce phase (hierarchical when needed)
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
            depth: 1
        )

        let totalElapsed = ContinuousClock.now - start
        progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: totalElapsed))
        return finalResult
    }

    // MARK: - Budget-Aware Rechunking

    /// Re-chunks text when the user-provided chunker produces chunks that
    /// exceed the available map budget (context minus prompt overhead,
    /// reserved output, and safety margin).
    ///
    /// `availableTextBudget` may return tokens or words depending on the
    /// budgeter's counting mode. Fallback chunkers split by words, so
    /// token budgets are converted to a conservative word target first.
    ///
    /// Specialized chunker metadata may be reduced for oversized chunks
    /// that require fallback splitting to prevent prompt overflow.
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

    /// Converts available budget units into a safe word target for
    /// `SentenceAwareChunker`. Word budgets pass through directly;
    /// token budgets are divided by a conservative tokens-per-word ratio
    /// so that the resulting word-sized chunks stay within the token limit.
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
        start: ContinuousClock.Instant
    ) async throws -> [MapResult] {
        var results: [MapResult] = []
        results.reserveCapacity(chunks.count)

        for (i, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .mapping(step: i + 1, of: chunks.count), elapsedTime: elapsed))

            let prompt = mapPrompt + chunk.text
            let result = try await withRetry(policy: options.retryPolicy) {
                try await self.backend.generate(prompt: prompt, systemPrompt: systemPrompt)
            }
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
        start: ContinuousClock.Instant
    ) async throws -> [MapResult] {
        try await withThrowingTaskGroup(of: MapResult.self) { group in
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
                    let prompt = mapPrompt + chunk.text
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
    }

    // MARK: - Hierarchical Reduce

    private func hierarchicalReduce(
        summaries: [String],
        reducePrompt: String,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?,
        start: ContinuousClock.Instant,
        depth: Int
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
            let reduceInput = reducePrompt + combined
            return try await withRetry(policy: options.retryPolicy) {
                try await self.backend.generate(prompt: reduceInput, systemPrompt: systemPrompt)
            }
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

            let groupCombined = formatSummaries(group)
            let groupPrompt = reducePrompt + groupCombined
            let groupResult = try await withRetry(policy: options.retryPolicy) {
                try await self.backend.generate(prompt: groupPrompt, systemPrompt: systemPrompt)
            }

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
            depth: depth + 1
        )
    }

    // MARK: - Helpers

    /// Uses `PromptBudgeter` for reduce-fit checks, supporting exact token
    /// counting when the backend conforms to `TokenAwareBackend`.
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

    /// Groups summaries for hierarchical reduce. When a context budget is
    /// available, accumulates summaries into a group while the combined
    /// text fits within budget, capped by `maxReduceGroupSize`. Without a
    /// budget, uses fixed-size grouping.
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
