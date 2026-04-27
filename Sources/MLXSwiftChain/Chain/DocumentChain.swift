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

    /// Run the chain and return a rich result with source chunks and metrics.
    func runWithMetadata(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) async throws -> ChainResult

    /// Stream chain execution events.
    func stream(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) -> AsyncThrowingStream<ChainEvent, Error>
}

// MARK: - Default Implementations

extension DocumentChain {

    /// Default `runWithMetadata` — delegates to `run()` and wraps in `ChainResult`.
    public func runWithMetadata(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) async throws -> ChainResult {
        let output = try await run(
            text,
            mapPrompt: mapPrompt,
            reducePrompt: reducePrompt,
            stuffPrompt: stuffPrompt,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress
        )
        return ChainResult(text: output)
    }

    /// Default `stream` — runs to completion, then emits result.
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
                    let result = try await self.runWithMetadata(
                        text,
                        mapPrompt: mapPrompt,
                        reducePrompt: reducePrompt,
                        stuffPrompt: stuffPrompt,
                        systemPrompt: systemPrompt,
                        options: options,
                        progress: progress
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
}

// MARK: - Convenience Overloads

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
            text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
            stuffPrompt: nil, systemPrompt: systemPrompt,
            options: ChainExecutionOptions(), progress: progress
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
            text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
            stuffPrompt: nil, systemPrompt: systemPrompt,
            options: options, progress: progress
        )
    }

    /// Convenience `runWithMetadata` without stuffPrompt.
    public func runWithMetadata(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions(),
        progress: ChainProgress? = nil
    ) async throws -> ChainResult {
        try await runWithMetadata(
            text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
            stuffPrompt: nil, systemPrompt: systemPrompt,
            options: options, progress: progress
        )
    }

    /// Convenience `stream` without stuffPrompt.
    public func stream(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions(),
        progress: ChainProgress? = nil
    ) -> AsyncThrowingStream<ChainEvent, Error> {
        stream(
            text, mapPrompt: mapPrompt, reducePrompt: reducePrompt,
            stuffPrompt: nil, systemPrompt: systemPrompt,
            options: options, progress: progress
        )
    }
}
