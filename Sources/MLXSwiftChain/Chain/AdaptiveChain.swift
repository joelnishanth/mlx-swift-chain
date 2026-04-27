import Foundation

/// Automatically selects between StuffChain and MapReduceChain
/// based on whether the input text fits within the context budget,
/// accounting for prompt overhead and reserved output tokens.
///
/// - If total budget (prompt + text + reserved output) fits, uses StuffChain.
/// - Otherwise, uses MapReduceChain to process in chunks.
///
/// When the backend conforms to `TokenAwareBackend`, budget checks use
/// real token counts. Otherwise, word heuristics are used as a fallback.
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
        let budgeter = PromptBudgeter(backend: backend, budget: contextBudget)
        let taskPrompt = stuffPrompt ?? reducePrompt

        let fits = budgeter.fits(
            systemPrompt: systemPrompt,
            taskPrompt: taskPrompt,
            text: text,
            reservedOutputTokens: options.reservedOutputTokens
        )

        if fits {
            let stuff = StuffChain(backend: backend)
            return stuff.stream(
                text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
                stuffPrompt: stuffPrompt, systemPrompt: systemPrompt,
                options: options, progress: progress
            )
        }

        let mapReduce = MapReduceChain(backend: backend, chunker: chunker, contextBudget: contextBudget)
        return mapReduce.stream(
            text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
            stuffPrompt: stuffPrompt, systemPrompt: systemPrompt,
            options: options, progress: progress
        )
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
        let budgeter = PromptBudgeter(backend: backend, budget: contextBudget)
        let taskPrompt = stuffPrompt ?? reducePrompt

        let fits = budgeter.fits(
            systemPrompt: systemPrompt,
            taskPrompt: taskPrompt,
            text: text,
            reservedOutputTokens: options.reservedOutputTokens
        )

        if fits {
            let stuff = StuffChain(backend: backend)
            return try await stuff.runWithMetadata(
                text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
                stuffPrompt: stuffPrompt, systemPrompt: systemPrompt,
                options: options, progress: progress
            )
        }

        let mapReduce = MapReduceChain(backend: backend, chunker: chunker, contextBudget: contextBudget)
        return try await mapReduce.runWithMetadata(
            text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
            stuffPrompt: stuffPrompt, systemPrompt: systemPrompt,
            options: options, progress: progress
        )
    }
}
