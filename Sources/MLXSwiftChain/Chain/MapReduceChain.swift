import Foundation

/// Processes text that exceeds the context window by chunking it,
/// mapping each chunk through the LLM, then reducing the combined
/// chunk results into a final output.
public struct MapReduceChain: DocumentChain {
    public let backend: any LLMBackend
    public let chunker: any TextChunker

    public init(backend: any LLMBackend, chunker: any TextChunker) {
        self.backend = backend
        self.chunker = chunker
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

        var chunkResults: [String] = []
        chunkResults.reserveCapacity(chunks.count)

        for (i, chunk) in chunks.enumerated() {
            let elapsed = ContinuousClock.now - start
            progress?.report(ChainProgress.Update(phase: .mapping(step: i + 1, of: chunks.count), elapsedTime: elapsed))

            let prompt = mapPrompt + chunk.text
            let result = try await backend.generate(prompt: prompt, systemPrompt: systemPrompt)
            chunkResults.append(result)
        }

        let reduceElapsed = ContinuousClock.now - start
        progress?.report(ChainProgress.Update(phase: .reducing, elapsedTime: reduceElapsed))

        let combined = chunkResults.enumerated().map { i, result in
            "--- Section \(i + 1) of \(chunkResults.count) ---\n\(result)"
        }.joined(separator: "\n\n")

        let finalPrompt = reducePrompt + combined
        let finalResult = try await backend.generate(prompt: finalPrompt, systemPrompt: systemPrompt)

        let totalElapsed = ContinuousClock.now - start
        progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: totalElapsed))
        return finalResult
    }
}
