import Foundation

/// Splits text into chunks that respect sentence boundaries.
/// Accumulates complete sentences until approaching `targetWords`,
/// then starts a new chunk at the next sentence boundary.
public struct SentenceAwareChunker: TextChunker {
    public let targetWords: Int

    public init(targetWords: Int = 1500) {
        self.targetWords = max(1, targetWords)
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else { return [] }

        var chunks: [TextChunk] = []
        var currentSentences: [String] = []
        var currentWordCount = 0

        for sentence in sentences {
            let sentenceWords = sentence.split(whereSeparator: \.isWhitespace).count
            if currentWordCount + sentenceWords > targetWords && !currentSentences.isEmpty {
                let chunkText = currentSentences.joined(separator: " ")
                chunks.append(TextChunk(text: chunkText, index: chunks.count, wordCount: currentWordCount))
                currentSentences.removeAll()
                currentWordCount = 0
            }
            currentSentences.append(sentence)
            currentWordCount += sentenceWords
        }

        if !currentSentences.isEmpty {
            let chunkText = currentSentences.joined(separator: " ")
            chunks.append(TextChunk(text: chunkText, index: chunks.count, wordCount: currentWordCount))
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
}
