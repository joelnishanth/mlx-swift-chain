import Foundation

/// An LLM backend that provides token counting and context window information.
///
/// Conform to this protocol (in addition to `LLMBackend`) to enable
/// accurate token-based budget calculations. Chains check
/// `backend is TokenAwareBackend` and fall back to word heuristics otherwise.
public protocol TokenAwareBackend: LLMBackend {
    /// The maximum number of tokens the model can process in a single call.
    var contextWindowTokens: Int { get }

    /// A token counter for measuring prompt and text token counts.
    var tokenCounter: any TokenCounter { get }
}
