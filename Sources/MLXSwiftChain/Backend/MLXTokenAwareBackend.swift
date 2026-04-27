import Foundation
import MLXLMCommon

/// An MLX backend that provides real token counting for budget calculations.
///
/// Wraps ``MLXBackend`` and adds ``TokenAwareBackend`` conformance using a
/// real ``MLXLMCommon/Tokenizer``. Use this when you need accurate
/// token-based budgeting instead of word heuristics.
///
/// ```swift
/// let container: ModelContainer = ...
/// let tokenizer = await container.tokenizer
/// let backend = MLXTokenAwareBackend(
///     container: container,
///     tokenizer: tokenizer,
///     contextWindowTokens: 4096
/// )
/// let chain = AdaptiveChain(
///     backend: backend,
///     contextBudget: .tokens(4096)
/// )
/// ```
///
/// `@unchecked Sendable` because the underlying ``MLXBackend`` and
/// ``MLXTokenCounter`` are both internally thread-safe.
public final class MLXTokenAwareBackend: LLMBackend, TokenAwareBackend, StreamingLLMBackend, @unchecked Sendable {
    private let base: MLXBackend

    /// The maximum number of tokens the model can process in a single call.
    public let contextWindowTokens: Int

    /// Token counter using the real model tokenizer.
    public let tokenCounter: any TokenCounter

    /// Access the underlying ``MLXBackend`` for parameter adjustments.
    public var mlxBackend: MLXBackend { base }

    /// - Parameters:
    ///   - container: The MLX model container.
    ///   - tokenizer: A resolved tokenizer (from `await container.tokenizer`).
    ///   - contextWindowTokens: The model's maximum context window in tokens.
    ///   - generateParameters: Sampling parameters for generation.
    public init(
        container: ModelContainer,
        tokenizer: any MLXLMCommon.Tokenizer,
        contextWindowTokens: Int,
        generateParameters: GenerateParameters = .init()
    ) {
        self.base = MLXBackend(container: container, generateParameters: generateParameters)
        self.contextWindowTokens = contextWindowTokens
        self.tokenCounter = MLXTokenCounter(tokenizer: tokenizer)
    }

    public func generate(prompt: String, systemPrompt: String?) async throws -> String {
        try await base.generate(prompt: prompt, systemPrompt: systemPrompt)
    }

    public func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
        base.stream(prompt: prompt, systemPrompt: systemPrompt)
    }
}
