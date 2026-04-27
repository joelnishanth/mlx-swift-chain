import Foundation

/// An LLM backend that supports token-by-token streaming output.
///
/// Conform to this protocol (in addition to `LLMBackend`) to enable
/// streaming chain execution. Non-streaming backends continue to work
/// with all existing APIs — streaming is opt-in per backend.
public protocol StreamingLLMBackend: LLMBackend {
    /// Stream the model's response token by token.
    ///
    /// Each element in the returned stream is a text fragment (one or
    /// more tokens decoded to a string). The stream completes when
    /// generation finishes.
    func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error>
}
