import Foundation

/// Splits text into fixed-size chunks by word count with optional overlap.
public struct FixedSizeChunker: TextChunker {
    public let maxWords: Int
    public let overlapWords: Int

    public init(maxWords: Int = 1500, overlapWords: Int = 0) {
        self.maxWords = max(1, maxWords)
        self.overlapWords = max(0, min(overlapWords, maxWords - 1))
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }

        let step = max(1, maxWords - overlapWords)
        var chunks: [TextChunk] = []
        var start = 0

        while start < words.count {
            let end = min(start + maxWords, words.count)
            let chunkWords = words[start..<end]
            let chunkText = chunkWords.joined(separator: " ")
            let index = chunks.count
            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: start..<end,
                timestamps: extractTimestamps(from: chunkText),
                speakerLabels: extractSpeakerLabels(from: chunkText)
            )
            chunks.append(TextChunk(text: chunkText, index: index, wordCount: chunkWords.count, metadata: metadata))
            start += step
        }

        return chunks
    }

    private func extractTimestamps(from text: String) -> [String] {
        let pattern = #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private func extractSpeakerLabels(from text: String) -> [String] {
        let pattern = #"(?m)^\s*([A-Za-z][A-Za-z\s]{0,30}):"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let labels = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return Array(Set(labels)).sorted()
    }
}
