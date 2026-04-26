import Foundation
import MLXLMCommon

/// LLMBackend backed by an MLX `ModelContainer`.
///
/// Creates a fresh `ChatSession` for each generation call, which is the
/// correct policy for stateless document processing where each map/reduce
/// call is independent. The `generateParameters` property controls
/// temperature, maxTokens, topP, and other sampling parameters.
///
/// `@unchecked Sendable` is safe because `ModelContainer` is an actor
/// and `GenerateParameters` is `Sendable`.
public final class MLXBackend: LLMBackend, @unchecked Sendable {
    private let container: ModelContainer

    /// Parameters controlling token generation (temperature, maxTokens, topP, etc.).
    /// These are passed to each `ChatSession` created per generation call.
    public var generateParameters: GenerateParameters

    public init(container: ModelContainer, generateParameters: GenerateParameters = .init()) {
        self.container = container
        self.generateParameters = generateParameters
    }

    public func generate(prompt: String, systemPrompt: String?) async throws -> String {
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters
        )
        return try await session.respond(to: prompt)
    }
}
