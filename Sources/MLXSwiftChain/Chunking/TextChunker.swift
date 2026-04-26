import Foundation

/// Splits text into chunks suitable for sequential LLM processing.
public protocol TextChunker: Sendable {
    func chunk(_ text: String) -> [TextChunk]
}
