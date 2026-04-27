import Foundation

/// Splits Markdown text at heading boundaries, preserving document structure.
///
/// Each chunk starts with its heading (including parent heading context)
/// and contains the section body. Sections exceeding `targetWords` are
/// further split using sentence-aware chunking.
public struct MarkdownHeadingChunker: TextChunker {
    public let targetWords: Int
    public let maxHeadingLevel: Int

    public init(targetWords: Int = 1500, maxHeadingLevel: Int = 3) {
        self.targetWords = max(1, targetWords)
        self.maxHeadingLevel = max(1, min(6, maxHeadingLevel))
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let sections = parseSections(text)
        guard !sections.isEmpty else { return [] }

        var chunks: [TextChunk] = []
        var runningWordOffset = 0

        for section in sections {
            let sectionWords = section.text.split(whereSeparator: \.isWhitespace).count

            if sectionWords <= targetWords {
                let index = chunks.count
                let metadata = TextChunkMetadata(
                    chunkIndex: index,
                    sourceWordRange: runningWordOffset..<(runningWordOffset + sectionWords)
                )
                chunks.append(TextChunk(
                    text: section.text,
                    index: index,
                    wordCount: sectionWords,
                    metadata: metadata
                ))
                runningWordOffset += sectionWords
            } else {
                let subChunker = SentenceAwareChunker(targetWords: targetWords)
                let subChunks = subChunker.chunk(section.text)
                for sub in subChunks {
                    let index = chunks.count
                    let headingPrefix = section.heading.map { $0 + "\n\n" } ?? ""
                    let chunkText = headingPrefix + sub.text
                    let wc = chunkText.split(whereSeparator: \.isWhitespace).count
                    let metadata = TextChunkMetadata(
                        chunkIndex: index,
                        sourceWordRange: runningWordOffset..<(runningWordOffset + wc)
                    )
                    chunks.append(TextChunk(
                        text: chunkText,
                        index: index,
                        wordCount: wc,
                        metadata: metadata
                    ))
                    runningWordOffset += wc
                }
            }
        }

        return chunks
    }

    // MARK: - Section Parsing

    private struct Section {
        let heading: String?
        let text: String
        let level: Int
    }

    private func parseSections(_ text: String) -> [Section] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [Section] = []
        var currentHeading: String?
        var currentLevel = 0
        var currentBody: [String] = []

        func flushSection() {
            let bodyText: String
            if let heading = currentHeading {
                let body = currentBody.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                bodyText = body.isEmpty ? heading : heading + "\n\n" + body
            } else {
                bodyText = currentBody.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !bodyText.isEmpty else { return }
            sections.append(Section(
                heading: currentHeading,
                text: bodyText,
                level: currentLevel
            ))
            currentBody = []
            currentHeading = nil
        }

        for line in lines {
            if let (level, _) = parseHeadingLine(line), level <= maxHeadingLevel {
                flushSection()
                currentHeading = line.trimmingCharacters(in: .whitespacesAndNewlines)
                currentLevel = level
            } else {
                currentBody.append(line)
            }
        }
        flushSection()

        return sections
    }

    private func parseHeadingLine(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 }
            else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }

        let headingText = String(trimmed.dropFirst(level))
            .trimmingCharacters(in: .whitespaces)
        return (level, headingText)
    }
}
