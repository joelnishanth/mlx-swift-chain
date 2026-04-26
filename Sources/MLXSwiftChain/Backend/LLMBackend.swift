import Foundation

/// A backend capable of generating text from a prompt.
/// Conform your model service to this protocol to use it with document chains.
public protocol LLMBackend: Sendable {
    func generate(prompt: String, systemPrompt: String?) async throws -> String
}

extension LLMBackend {
    public func generate(prompt: String) async throws -> String {
        try await generate(prompt: prompt, systemPrompt: nil)
    }
}
