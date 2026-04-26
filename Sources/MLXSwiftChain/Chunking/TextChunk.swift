import Foundation

/// A segment of text produced by a `TextChunker`.
public struct TextChunk: Sendable {
    /// The chunk's text content.
    public let text: String
    /// Zero-based index within the sequence of chunks.
    public let index: Int
    /// Estimated word count.
    public let wordCount: Int

    public init(text: String, index: Int, wordCount: Int) {
        self.text = text
        self.index = index
        self.wordCount = wordCount
    }
}
