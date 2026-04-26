import Foundation

/// Splits transcript text at speaker-turn boundaries, preserving speaker
/// labels and timestamps within each chunk.
///
/// Recognizes common transcript formats:
/// - `HH:MM:SS Speaker:` or `MM:SS Speaker:`
/// - `Speaker:` at the start of a line
/// - SRT/VTT timestamp lines
public struct TranscriptChunker: TextChunker {
    public let targetWords: Int
    public let overlapTurns: Int

    public init(targetWords: Int = 1500, overlapTurns: Int = 0) {
        self.targetWords = max(1, targetWords)
        self.overlapTurns = max(0, overlapTurns)
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let turns = parseTurns(text)
        guard !turns.isEmpty else { return [] }

        var chunks: [TextChunk] = []
        var turnIndex = 0

        while turnIndex < turns.count {
            let startTurnIndex = turnIndex
            var chunkWordCount = 0
            var endTurnIndex = turnIndex

            while endTurnIndex < turns.count {
                let turnWords = turns[endTurnIndex].wordCount
                if chunkWordCount + turnWords > targetWords && chunkWordCount > 0 {
                    break
                }
                chunkWordCount += turnWords
                endTurnIndex += 1
            }

            let selected = turns[startTurnIndex..<endTurnIndex]
            let chunkText = selected.map(\.text).joined(separator: "\n")
            let index = chunks.count

            let startWord = selected.first?.wordOffset ?? 0
            let endWord = startWord + chunkWordCount

            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: startWord..<endWord,
                timestamps: selected.flatMap(\.timestamps),
                speakerLabels: Array(Set(selected.compactMap(\.speaker))).sorted()
            )

            chunks.append(TextChunk(
                text: chunkText,
                index: index,
                wordCount: chunkWordCount,
                metadata: metadata
            ))

            if endTurnIndex >= turns.count { break }
            let rewind = min(overlapTurns, max(0, endTurnIndex - startTurnIndex - 1))
            turnIndex = max(startTurnIndex + 1, endTurnIndex - rewind)
        }

        return chunks
    }

    // MARK: - Turn Parsing

    private struct Turn {
        let text: String
        let speaker: String?
        let timestamps: [String]
        let wordCount: Int
        let wordOffset: Int
    }

    private static let speakerPattern = try! NSRegularExpression(
        pattern: #"(?m)^(?:(\d{1,2}:\d{2}(?::\d{2})?)\s+)?([A-Za-z][A-Za-z\s]{0,30}):\s"#
    )

    private static let timestampPattern = try! NSRegularExpression(
        pattern: #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#
    )

    private func parseTurns(_ text: String) -> [Turn] {
        let lines = text.components(separatedBy: .newlines)
        var turns: [Turn] = []
        var currentLines: [String] = []
        var currentSpeaker: String?
        var currentTimestamps: [String] = []
        var runningWordOffset = 0

        func flushTurn() {
            let turnText = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !turnText.isEmpty else { return }
            let wc = turnText.split(whereSeparator: \.isWhitespace).count
            turns.append(Turn(
                text: turnText,
                speaker: currentSpeaker,
                timestamps: currentTimestamps,
                wordCount: wc,
                wordOffset: runningWordOffset
            ))
            runningWordOffset += wc
            currentLines = []
            currentSpeaker = nil
            currentTimestamps = []
        }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)

            if let match = Self.speakerPattern.firstMatch(in: line, range: range) {
                flushTurn()

                if let tsRange = Range(match.range(at: 1), in: line) {
                    currentTimestamps.append(String(line[tsRange]))
                }
                if let spkRange = Range(match.range(at: 2), in: line) {
                    currentSpeaker = String(line[spkRange]).trimmingCharacters(in: .whitespaces)
                }
                currentLines.append(line)
            } else {
                let tsMatches = Self.timestampPattern.matches(in: line, range: range)
                for m in tsMatches {
                    if let r = Range(m.range, in: line) {
                        currentTimestamps.append(String(line[r]))
                    }
                }
                currentLines.append(line)
            }
        }
        flushTurn()

        if turns.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wc = text.split(whereSeparator: \.isWhitespace).count
            turns.append(Turn(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                speaker: nil,
                timestamps: extractTimestamps(from: text),
                wordCount: wc,
                wordOffset: 0
            ))
        }

        return turns
    }

    private func extractTimestamps(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return Self.timestampPattern.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
