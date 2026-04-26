import Foundation

/// Processes text that exceeds the context window by chunking it,
/// mapping each chunk through the LLM, then reducing the combined
/// chunk results into a final output.
///
/// When the combined reduce prompt exceeds the context budget,
/// hierarchical reduce is used: summaries are grouped, each group
/// is reduced, and the process repeats until the final result fits.
public struct MapReduceChain: DocumentChain {
    public let backend: any LLMBackend
    public let chunker: any TextChunker
    public let contextBudget: ContextBudget?

    public init(backend: any LLMBackend, chunker: any TextChunker) {
        self.backend = backend
        self.chunker = chunker
        self.contextBudget = nil
    }

    /// Initialize with an explicit context budget for hierarchical reduce decisions.
    public init(backend: any LLMBackend, chunker: any TextChunker, contextBudget: ContextBudget) {
        self.backend = backend
        self.chunker = chunker
        self.contextBudget = contextBudget
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

        let chunks = chunker.chunk(text)

        guard !chunks.isEmpty else {
            progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: .zero))
            return ""
        }

        // Map phase
        var chunkResults: [String] = []
        chunkResults.reserveCapacity(chunks.count)

        for (i, chunk) in chunks.enumerated() {
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .mapping(step: i + 1, of: chunks.count), elapsedTime: elapsed))

            let prompt = mapPrompt + chunk.text
            let result = try await backend.generate(prompt: prompt, systemPrompt: systemPrompt)
            chunkResults.append(result)
        }

        // Reduce phase (hierarchical when needed)
        let labeledSummaries = chunkResults.enumerated().map { i, result in
            "[Chunk \(i + 1)] \(result)"
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
        let reduceInput = reducePrompt + combined

        if fitsInSingleReduce(reduceInput, systemPrompt: systemPrompt, options: options) {
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .reducing, elapsedTime: elapsed))
            return try await backend.generate(prompt: reduceInput, systemPrompt: systemPrompt)
        }

        // Split into groups and reduce each
        let groupSize = max(2, options.maxReduceGroupSize)
        let groups = stride(from: 0, to: summaries.count, by: groupSize).map { startIdx in
            Array(summaries[startIdx..<min(startIdx + groupSize, summaries.count)])
        }

        var intermediateSummaries: [String] = []
        intermediateSummaries.reserveCapacity(groups.count)

        for (_, group) in groups.enumerated() {
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .reducing, elapsedTime: elapsed))

            let groupCombined = formatSummaries(group)
            let groupPrompt = reducePrompt + groupCombined
            let groupResult = try await backend.generate(prompt: groupPrompt, systemPrompt: systemPrompt)

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

    private func fitsInSingleReduce(_ prompt: String, systemPrompt: String?, options: ChainExecutionOptions) -> Bool {
        guard let budget = contextBudget else {
            return true
        }
        let promptWords = prompt.split(whereSeparator: \.isWhitespace).count
        let systemWords = systemPrompt?.split(whereSeparator: \.isWhitespace).count ?? 0
        let reservedWords: Int
        switch budget {
        case .words:
            reservedWords = Int(Double(options.reservedOutputTokens) / 1.33)
        case .tokens(_, let ratio):
            reservedWords = Int(Double(options.reservedOutputTokens) / max(0.1, ratio))
        }
        return budget.fitsInBudget(
            textWords: promptWords,
            promptOverheadWords: systemWords,
            reservedOutputWords: reservedWords
        )
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
