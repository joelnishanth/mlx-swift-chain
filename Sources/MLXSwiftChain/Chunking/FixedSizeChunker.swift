import Foundation

/// Splits text into fixed-size chunks by word count with no overlap.
public struct FixedSizeChunker: TextChunker {
    public let maxWords: Int

    public init(maxWords: Int = 1500) {
        self.maxWords = max(1, maxWords)
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let words = text.split(separator: " ")
        guard !words.isEmpty else { return [] }

        var chunks: [TextChunk] = []
        var current: [Substring] = []

        for word in words {
            current.append(word)
            if current.count >= maxWords {
                let chunkText = current.joined(separator: " ")
                chunks.append(TextChunk(text: chunkText, index: chunks.count, wordCount: current.count))
                current.removeAll()
            }
        }
        if !current.isEmpty {
            let chunkText = current.joined(separator: " ")
            chunks.append(TextChunk(text: chunkText, index: chunks.count, wordCount: current.count))
        }
        return chunks
    }
}
