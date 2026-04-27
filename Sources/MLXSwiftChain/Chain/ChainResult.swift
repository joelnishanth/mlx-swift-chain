import Foundation

/// Rich result type returned by ``DocumentChain/runWithMetadata(...)``.
///
/// Contains the generated text, the source chunks that were processed,
/// and optional performance metrics. Use this when you need to trace
/// outputs back to source chunks or collect timing data.
public struct ChainResult: Sendable {
    /// The final generated text (same value returned by ``DocumentChain/run(...)``).
    public let text: String
    /// The chunks that were used during processing, in input order.
    public let sourceChunks: [TextChunk]
    /// Performance metrics for the execution, if collected.
    public let metrics: ChainMetrics?

    public init(text: String, sourceChunks: [TextChunk] = [], metrics: ChainMetrics? = nil) {
        self.text = text
        self.sourceChunks = sourceChunks
        self.metrics = metrics
    }
}
