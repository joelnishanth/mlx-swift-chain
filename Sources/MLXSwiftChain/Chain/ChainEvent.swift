import Foundation

/// Events emitted during streaming chain execution.
public enum ChainEvent: Sendable {
    /// A text fragment from the streaming LLM output.
    case chunk(String)
    /// A progress update from the chain.
    case progress(ChainProgress.Update)
    /// The final complete result (emitted once, at the end of the stream).
    case result(ChainResult)
}
