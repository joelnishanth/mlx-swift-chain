import Foundation
import MLXLMCommon

/// LLMBackend backed by an MLX `ModelContainer`.
/// Uses `ChatSession` for each generation call.
public final class MLXBackend: LLMBackend, @unchecked Sendable {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func generate(prompt: String, systemPrompt: String?) async throws -> String {
        let session = ChatSession(container, instructions: systemPrompt)
        return try await session.respond(to: prompt)
    }
}
