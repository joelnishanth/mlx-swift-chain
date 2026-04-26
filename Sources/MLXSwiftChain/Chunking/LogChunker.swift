import Foundation

/// Splits log text at timestamp boundaries while keeping stack traces intact.
///
/// Recognizes common log formats:
/// - ISO 8601: `2024-01-15T10:30:00`
/// - Common log: `2024-01-15 10:30:00`
/// - Short timestamp: `10:30:00` or `10:30`
///
/// Stack traces (indented lines following error/exception markers) are
/// never split mid-trace.
public struct LogChunker: TextChunker {
    public let targetWords: Int

    public init(targetWords: Int = 1500) {
        self.targetWords = max(1, targetWords)
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let blocks = parseBlocks(text)
        guard !blocks.isEmpty else { return [] }

        var chunks: [TextChunk] = []
        var currentBlocks: [Block] = []
        var currentWordCount = 0
        var runningWordOffset = 0

        func flushChunk() {
            guard !currentBlocks.isEmpty else { return }
            let chunkText = currentBlocks.map(\.text).joined(separator: "\n")
            let index = chunks.count
            let timestamps = currentBlocks.flatMap(\.timestamps)
            let wc = currentWordCount
            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: runningWordOffset..<(runningWordOffset + wc),
                timestamps: timestamps
            )
            chunks.append(TextChunk(
                text: chunkText,
                index: index,
                wordCount: wc,
                metadata: metadata
            ))
            runningWordOffset += wc
            currentBlocks = []
            currentWordCount = 0
        }

        for block in blocks {
            if currentWordCount + block.wordCount > targetWords && currentWordCount > 0 {
                flushChunk()
            }
            currentBlocks.append(block)
            currentWordCount += block.wordCount
        }
        flushChunk()

        return chunks
    }

    // MARK: - Block Parsing

    private struct Block {
        let text: String
        let timestamps: [String]
        let wordCount: Int
        let isStackTrace: Bool
    }

    private static let isoTimestampPattern = try! NSRegularExpression(
        pattern: #"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"#
    )

    private static let shortTimestampPattern = try! NSRegularExpression(
        pattern: #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#
    )

    private static let errorMarkerPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:error|exception|fatal|panic|crash|assert|abort)\b"#
    )

    private static let stackFramePattern = try! NSRegularExpression(
        pattern: #"(?m)^[\t ]+(?:at |frame #|\d+\s+0x|[\w.]+\()"#
    )

    private func parseBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [Block] = []
        var currentLines: [String] = []
        var inStackTrace = false

        func flushBlock() {
            let blockText = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blockText.isEmpty else { return }
            let wc = blockText.split(whereSeparator: \.isWhitespace).count
            let timestamps = extractTimestamps(from: blockText)
            blocks.append(Block(
                text: blockText,
                timestamps: timestamps,
                wordCount: wc,
                isStackTrace: inStackTrace
            ))
            currentLines = []
            inStackTrace = false
        }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            let hasTimestamp = Self.isoTimestampPattern.firstMatch(in: line, range: range) != nil
            let isStackFrame = Self.stackFramePattern.firstMatch(in: line, range: range) != nil
            let hasError = Self.errorMarkerPattern.firstMatch(in: line, range: range) != nil

            if isStackFrame {
                if !inStackTrace {
                    inStackTrace = true
                }
                currentLines.append(line)
            } else if hasTimestamp && !inStackTrace {
                flushBlock()
                currentLines.append(line)
                if hasError {
                    inStackTrace = true
                }
            } else if inStackTrace && !hasTimestamp {
                currentLines.append(line)
            } else {
                if inStackTrace {
                    flushBlock()
                }
                if hasTimestamp && !currentLines.isEmpty {
                    flushBlock()
                }
                currentLines.append(line)
                if hasError {
                    inStackTrace = true
                }
            }
        }
        flushBlock()

        return blocks
    }

    private func extractTimestamps(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var timestamps: [String] = []

        let isoMatches = Self.isoTimestampPattern.matches(in: text, range: range)
        for m in isoMatches {
            if let r = Range(m.range, in: text) {
                timestamps.append(String(text[r]))
            }
        }

        if timestamps.isEmpty {
            let shortMatches = Self.shortTimestampPattern.matches(in: text, range: range)
            for m in shortMatches {
                if let r = Range(m.range, in: text) {
                    timestamps.append(String(text[r]))
                }
            }
        }

        return timestamps
    }
}
