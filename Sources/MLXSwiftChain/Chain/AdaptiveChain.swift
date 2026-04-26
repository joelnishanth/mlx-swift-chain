import Foundation

/// Automatically selects between StuffChain and MapReduceChain
/// based on whether the input text fits within the context budget,
/// accounting for prompt overhead and reserved output tokens.
///
/// - If total budget (prompt + text + reserved output) fits, uses StuffChain.
/// - Otherwise, uses MapReduceChain to process in chunks.
public struct AdaptiveChain: DocumentChain {
    public let backend: any LLMBackend
    public let chunker: any TextChunker
    public let contextBudget: ContextBudget

    /// Backward-compatible word-budget view.
    public var contextBudgetWords: Int {
        contextBudget.estimatedWordLimit
    }

    /// - Parameters:
    ///   - backend: The LLM backend for text generation.
    ///   - contextBudget: Context fit strategy (word- or token-oriented).
    ///   - chunker: Strategy for splitting text when it exceeds the budget.
    public init(
        backend: any LLMBackend,
        contextBudget: ContextBudget = .words(1500),
        chunker: (any TextChunker)? = nil
    ) {
        self.backend = backend
        self.contextBudget = contextBudget
        self.chunker = chunker ?? SentenceAwareChunker(targetWords: contextBudget.estimatedWordLimit)
    }

    /// - Parameters:
    ///   - backend: The LLM backend for text generation.
    ///   - contextBudgetWords: Maximum words the model can handle in one call.
    ///   - chunker: Strategy for splitting text when it exceeds the budget.
    public init(
        backend: any LLMBackend,
        contextBudgetWords: Int,
        chunker: (any TextChunker)? = nil
    ) {
        self.init(backend: backend, contextBudget: .words(contextBudgetWords), chunker: chunker)
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
        let textWordCount = text.split(whereSeparator: \.isWhitespace).count

        let taskPrompt = stuffPrompt ?? reducePrompt
        let promptOverheadWords = wordCount(taskPrompt) + wordCount(systemPrompt)
        let reservedOutputWords = estimateWords(forTokens: options.reservedOutputTokens)

        let fits = contextBudget.fitsInBudget(
            textWords: textWordCount,
            promptOverheadWords: promptOverheadWords,
            reservedOutputWords: reservedOutputWords
        )

        if fits {
            let stuff = StuffChain(backend: backend)
            return try await stuff.run(
                text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
                stuffPrompt: stuffPrompt, systemPrompt: systemPrompt,
                options: options, progress: progress
            )
        }

        let mapReduce = MapReduceChain(backend: backend, chunker: chunker)
        return try await mapReduce.run(
            text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
            stuffPrompt: stuffPrompt, systemPrompt: systemPrompt,
            options: options, progress: progress
        )
    }

    private func wordCount(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        return text.split(whereSeparator: \.isWhitespace).count
    }

    private func estimateWords(forTokens tokens: Int) -> Int {
        switch contextBudget {
        case .words:
            return Int(Double(tokens) / 1.33)
        case .tokens(_, let ratio):
            return Int(Double(tokens) / max(0.1, ratio))
        }
    }
}
