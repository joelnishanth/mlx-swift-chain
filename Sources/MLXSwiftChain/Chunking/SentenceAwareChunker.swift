import Foundation

/// Splits text into chunks that respect sentence boundaries.
/// Accumulates complete sentences until approaching `targetWords`,
/// then starts a new chunk at the next sentence boundary.
/// Optionally keeps sentence overlap between adjacent chunks.
public struct SentenceAwareChunker: TextChunker {
    public let targetWords: Int
    public let overlapSentences: Int

    public init(targetWords: Int = 1500, overlapSentences: Int = 0) {
        self.targetWords = max(1, targetWords)
        self.overlapSentences = max(0, overlapSentences)
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let rawSentences = splitSentences(text)
        guard !rawSentences.isEmpty else { return [] }

        let sentenceWords = rawSentences.map { $0.split(whereSeparator: \.isWhitespace).count }
        var sentenceStartWordOffsets: [Int] = []
        sentenceStartWordOffsets.reserveCapacity(rawSentences.count)

        var rollingOffset = 0
        for words in sentenceWords {
            sentenceStartWordOffsets.append(rollingOffset)
            rollingOffset += words
        }

        var chunks: [TextChunk] = []
        var sentenceIndex = 0

        while sentenceIndex < rawSentences.count {
            let startSentenceIndex = sentenceIndex
            var endSentenceIndex = sentenceIndex
            var chunkWordCount = 0

            while endSentenceIndex < rawSentences.count {
                let nextSentenceWords = sentenceWords[endSentenceIndex]
                if chunkWordCount + nextSentenceWords > targetWords && chunkWordCount > 0 {
                    break
                }
                chunkWordCount += nextSentenceWords
                endSentenceIndex += 1
            }

            let selected = rawSentences[startSentenceIndex..<endSentenceIndex]
            let chunkText = selected.joined(separator: " ")
            let startWord = sentenceStartWordOffsets[startSentenceIndex]
            let endWord = startWord + chunkWordCount
            let index = chunks.count

            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: startWord..<endWord,
                timestamps: extractTimestamps(from: chunkText),
                speakerLabels: extractSpeakerLabels(from: chunkText)
            )
            chunks.append(TextChunk(text: chunkText, index: index, wordCount: chunkWordCount, metadata: metadata))

            if endSentenceIndex >= rawSentences.count { break }
            let rewind = min(overlapSentences, max(0, endSentenceIndex - startSentenceIndex - 1))
            sentenceIndex = max(startSentenceIndex + 1, endSentenceIndex - rewind)
        }

        return chunks
    }

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        if sentences.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return sentences
    }

    private func extractTimestamps(from text: String) -> [String] {
        let pattern = #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private func extractSpeakerLabels(from text: String) -> [String] {
        let pattern = #"(?m)^\s*(?:\d{1,2}:\d{2}(?::\d{2})?\s+)?([A-Za-z][A-Za-z\s]{0,30}):"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let labels = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return Array(Set(labels)).sorted()
    }
}
