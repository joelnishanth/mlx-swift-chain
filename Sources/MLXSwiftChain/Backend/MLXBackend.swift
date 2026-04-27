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
/// and mutable state is protected by `lock`.
public final class MLXBackend: LLMBackend, @unchecked Sendable {
    private let container: ModelContainer
    private let lock = NSLock()
    private var _generateParameters: GenerateParameters

    /// Parameters controlling token generation (temperature, maxTokens, topP, etc.).
    /// These are passed to each `ChatSession` created per generation call.
    public var generateParameters: GenerateParameters {
        get { lock.withLock { _generateParameters } }
        set { lock.withLock { _generateParameters = newValue } }
    }

    public init(container: ModelContainer, generateParameters: GenerateParameters = .init()) {
        self.container = container
        self._generateParameters = generateParameters
    }

    public func generate(prompt: String, systemPrompt: String?) async throws -> String {
        let params = lock.withLock { _generateParameters }
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params
        )
        return try await session.respond(to: prompt)
    }
}
