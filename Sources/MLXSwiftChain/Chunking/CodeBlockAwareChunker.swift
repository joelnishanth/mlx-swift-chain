import Foundation

/// Splits text at paragraph boundaries while preserving fenced code blocks intact.
///
/// Useful for Markdown/code-heavy notes where splitting mid-code-block
/// would lose context. If a single code block exceeds ``targetWords``,
/// it becomes its own chunk rather than being split.
///
/// Metadata includes ``DocumentBlockType/codeBlock`` for chunks dominated
/// by code content.
public struct CodeBlockAwareChunker: TextChunker {
    /// Target word count per chunk.
    public let targetWords: Int

    public init(targetWords: Int = 1500) {
        self.targetWords = max(1, targetWords)
    }

    public func chunk(_ text: String) -> [TextChunk] {
        guard !text.isEmpty else { return [] }

        let blocks = splitIntoBlocks(text)
        var chunks: [TextChunk] = []
        var currentLines: [String] = []
        var currentWords = 0
        var currentIsCode = false
        var globalWordOffset = 0

        func flush() {
            guard !currentLines.isEmpty else { return }
            let joined = currentLines.joined(separator: "\n")
            let wc = joined.split(whereSeparator: \.isWhitespace).count
            let idx = chunks.count
            let meta = TextChunkMetadata(
                chunkIndex: idx,
                sourceWordRange: globalWordOffset..<(globalWordOffset + wc),
                documentLocation: DocumentLocation(
                    primaryBlockType: currentIsCode ? .codeBlock : nil
                )
            )
            chunks.append(TextChunk(text: joined, index: idx, wordCount: wc, metadata: meta))
            globalWordOffset += wc
            currentLines = []
            currentWords = 0
            currentIsCode = false
        }

        for block in blocks {
            let blockWords = block.text.split(whereSeparator: \.isWhitespace).count

            if block.isCode {
                if currentWords > 0 && !currentIsCode {
                    flush()
                }
                if currentWords + blockWords > targetWords && currentWords > 0 {
                    flush()
                }
                currentLines.append(block.text)
                currentWords += blockWords
                currentIsCode = true

                if currentWords >= targetWords {
                    flush()
                }
            } else {
                if currentIsCode && currentWords > 0 {
                    flush()
                }

                let paragraphs = block.text.components(separatedBy: "\n\n")
                for para in paragraphs {
                    let paraWords = para.split(whereSeparator: \.isWhitespace).count
                    if paraWords == 0 { continue }

                    if currentWords + paraWords > targetWords && currentWords > 0 {
                        flush()
                    }
                    currentLines.append(para)
                    currentWords += paraWords
                }
            }
        }

        flush()
        return chunks
    }

    // MARK: - Block Splitting

    private struct Block {
        let text: String
        let isCode: Bool
    }

    private func splitIntoBlocks(_ text: String) -> [Block] {
        let fencePattern = #"^(`{3,}|~{3,})"#
        var blocks: [Block] = []
        var currentLines: [String] = []
        var inCodeBlock = false
        var fenceMarker = ""

        let lines = text.components(separatedBy: "\n")

        for line in lines {
            if inCodeBlock {
                currentLines.append(line)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix(fenceMarker)
                    && line.trimmingCharacters(in: .whitespacesAndNewlines).count <= fenceMarker.count + 1 {
                    blocks.append(Block(text: currentLines.joined(separator: "\n"), isCode: true))
                    currentLines = []
                    inCodeBlock = false
                    fenceMarker = ""
                }
            } else if let match = line.range(of: fencePattern, options: .regularExpression) {
                if !currentLines.isEmpty {
                    blocks.append(Block(text: currentLines.joined(separator: "\n"), isCode: false))
                    currentLines = []
                }
                let marker = String(line[match])
                fenceMarker = String(repeating: marker.first!, count: marker.count)
                inCodeBlock = true
                currentLines.append(line)
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            blocks.append(Block(text: currentLines.joined(separator: "\n"), isCode: inCodeBlock))
        }

        return blocks
    }
}
