import Foundation

/// A chain that processes a document (potentially exceeding the model's context window)
/// and produces a text result via one or more LLM calls.
public protocol DocumentChain: Sendable {
    func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) async throws -> String
}

extension DocumentChain {
    /// Backward-compatible overload without stuffPrompt or options.
    public func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String? = nil,
        progress: ChainProgress? = nil
    ) async throws -> String {
        try await run(
            text,
            mapPrompt: mapPrompt,
            reducePrompt: reducePrompt,
            stuffPrompt: nil,
            systemPrompt: systemPrompt,
            options: ChainExecutionOptions(),
            progress: progress
        )
    }

    /// Overload with options but no stuffPrompt.
    public func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions,
        progress: ChainProgress? = nil
    ) async throws -> String {
        try await run(
            text,
            mapPrompt: mapPrompt,
            reducePrompt: reducePrompt,
            stuffPrompt: nil,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress
        )
    }
}
