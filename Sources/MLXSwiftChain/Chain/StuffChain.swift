import Foundation

/// Sends the entire text in a single LLM call.
/// Use when the input fits within the model's context window.
public struct StuffChain: DocumentChain {
    public let backend: any LLMBackend

    public init(backend: any LLMBackend) {
        self.backend = backend
    }

    public func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        systemPrompt: String?,
        progress: ChainProgress?
    ) async throws -> String {
        let start = ContinuousClock.now
        progress?.report(ChainProgress.Update(phase: .stuffing, elapsedTime: .zero))

        let prompt = reducePrompt + text
        let result = try await backend.generate(prompt: prompt, systemPrompt: systemPrompt)

        let elapsed = ContinuousClock.now - start
        progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: elapsed))
        progress?.finish()
        return result
    }
}
