import Foundation

/// Automatically selects between StuffChain and MapReduceChain
/// based on whether the input text fits within the context budget.
///
/// - If total words <= `contextBudgetWords`, uses StuffChain (single call).
/// - Otherwise, uses MapReduceChain to process in chunks.
public struct AdaptiveChain: DocumentChain {
    public let backend: any LLMBackend
    public let chunker: any TextChunker
    public let contextBudgetWords: Int

    /// - Parameters:
    ///   - backend: The LLM backend for text generation.
    ///   - contextBudgetWords: Maximum words the model can handle in one call
    ///     (accounting for prompt overhead). Defaults to 1500.
    ///   - chunker: Strategy for splitting text when it exceeds the budget.
    public init(
        backend: any LLMBackend,
        contextBudgetWords: Int = 1500,
        chunker: (any TextChunker)? = nil
    ) {
        self.backend = backend
        self.contextBudgetWords = contextBudgetWords
        self.chunker = chunker ?? SentenceAwareChunker(targetWords: contextBudgetWords)
    }

    public func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String?,
        progress: ChainProgress?
    ) async throws -> String {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count

        if wordCount <= contextBudgetWords {
            let stuff = StuffChain(backend: backend)
            return try await stuff.run(text, mapPrompt: mapPrompt, reducePrompt: reducePrompt, systemPrompt: systemPrompt, progress: progress)
        }

        let mapReduce = MapReduceChain(backend: backend, chunker: chunker)
        return try await mapReduce.run(text, mapPrompt: mapPrompt, reducePrompt: reducePrompt, systemPrompt: systemPrompt, progress: progress)
    }
}
