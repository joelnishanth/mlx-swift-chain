import Foundation

/// A chain that processes a document (potentially exceeding the model's context window)
/// and produces a text result via one or more LLM calls.
public protocol DocumentChain: Sendable {
    func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String?,
        progress: ChainProgress?
    ) async throws -> String
}

extension DocumentChain {
    public func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        try await run(text, mapPrompt: mapPrompt, reducePrompt: reducePrompt, systemPrompt: systemPrompt, progress: nil)
    }
}
