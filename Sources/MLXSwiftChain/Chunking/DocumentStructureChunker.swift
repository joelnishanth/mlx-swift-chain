import Foundation

/// Splits Markdown or PDF-extracted text into structure-aware chunks,
/// preserving headings, page ranges, tables, code blocks, lists, and
/// block quotes. Produces `DocumentLocation` metadata on each chunk.
///
/// Parsing is deterministic and rule-based (no LLM involvement).
/// Content inside fenced code blocks is treated as a suppression zone
/// where no structural detection is performed.
public struct DocumentStructureChunker: TextChunker {
    public let targetWords: Int
    public let overlapBlocks: Int
    public let preserveTables: Bool
    public let preserveCodeBlocks: Bool

    public init(
        targetWords: Int = 1500,
        overlapBlocks: Int = 0,
        preserveTables: Bool = true,
        preserveCodeBlocks: Bool = true
    ) {
        self.targetWords = max(1, targetWords)
        self.overlapBlocks = max(0, overlapBlocks)
        self.preserveTables = preserveTables
        self.preserveCodeBlocks = preserveCodeBlocks
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let blocks = parseBlocks(text)
        guard !blocks.isEmpty else { return [] }
        let groups = mergeBlocks(blocks)
        return buildTextChunks(groups)
    }

    // MARK: - Internal Block Model

    private struct DocumentBlock {
        let text: String
        let type: DocumentBlockType
        let wordCount: Int
        let page: Int?
        let headingLevel: Int?
        let headingText: String?
        let headingPath: [String]
        let sourceWordRange: Range<Int>
    }

    // MARK: - Regex Patterns

    private static let pageMarkerBracket = try! NSRegularExpression(
        pattern: #"(?i)^\[page\s+(\d+)\]$"#
    )
    private static let pageMarkerDash = try! NSRegularExpression(
        pattern: #"(?i)^-{3,}\s*page\s+(\d+)\s*-{3,}$"#
    )
    private static let pageMarkerEquals = try! NSRegularExpression(
        pattern: #"(?i)^={3,}\s*page\s+(\d+)\s*={3,}$"#
    )
    private static let pageMarkerColon = try! NSRegularExpression(
        pattern: #"(?i)^page\s+(\d+)\s*:$"#
    )

    private static let atxHeadingPattern = try! NSRegularExpression(
        pattern: #"^(#{1,6})\s+(.+)$"#
    )

    private static let setextH1Pattern = try! NSRegularExpression(
        pattern: #"^={3,}\s*$"#
    )
    private static let setextH2Pattern = try! NSRegularExpression(
        pattern: #"^-{3,}\s*$"#
    )

    private static let fencedCodeOpenPattern = try! NSRegularExpression(
        pattern: #"^(`{3,}|~{3,})"#
    )

    private static let pipeTableRowPattern = try! NSRegularExpression(
        pattern: #"^\|.+\|$"#
    )
    private static let pipeTableSeparatorPattern = try! NSRegularExpression(
        pattern: #"^\|[\s:]*-+[\s:]*"#
    )

    private static let blockQuotePattern = try! NSRegularExpression(
        pattern: #"^>\s?"#
    )

    private static let unorderedListPattern = try! NSRegularExpression(
        pattern: #"^\s*[-*+]\s"#
    )
    private static let orderedListPattern = try! NSRegularExpression(
        pattern: #"^\s*\d+[.)]\s"#
    )
    private static let listContinuationPattern = try! NSRegularExpression(
        pattern: #"^\s{2,}\S"#
    )

    private static let thematicBreakStarPattern = try! NSRegularExpression(
        pattern: #"^(\*\s*){3,}$"#
    )
    private static let thematicBreakUnderscorePattern = try! NSRegularExpression(
        pattern: #"^(_\s*){3,}$"#
    )
    private static let thematicBreakDashPattern = try! NSRegularExpression(
        pattern: #"^(-\s*){3,}$"#
    )

    private static let figureCaptionPattern = try! NSRegularExpression(
        pattern: #"^!\[.+\]\(.+\)$"#
    )
    private static let footnotePattern = try! NSRegularExpression(
        pattern: #"^\[\^.+\]:\s"#
    )

    // MARK: - Stage 1: Parse Blocks

    private func parseBlocks(_ text: String) -> [DocumentBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [DocumentBlock] = []
        var runningWordOffset = 0

        var currentPage: Int?
        var headingStack: [(level: Int, text: String)] = []

        var inFencedCodeBlock = false
        var codeFenceChar: Character = "`"
        var codeFenceCount = 0
        var codeBlockLines: [String] = []
        var codeBlockPage: Int?
        var codeBlockHeadingPath: [String] = []
        var codeBlockStartWordOffset = 0

        var pendingParagraphLines: [String] = []
        var previousNonBlankLine: String?

        var inTable = false
        var tableLines: [String] = []
        var tableHasSeenSeparator = false
        var tablePage: Int?
        var tableHeadingPath: [String] = []
        var tableStartWordOffset = 0

        var inBlockQuote = false
        var blockQuoteLines: [String] = []
        var blockQuotePage: Int?
        var blockQuoteHeadingPath: [String] = []
        var blockQuoteStartWordOffset = 0

        var inList = false
        var listLines: [String] = []
        var listPage: Int?
        var listHeadingPath: [String] = []
        var listStartWordOffset = 0

        func flushParagraph() {
            let paraText = pendingParagraphLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paraText.isEmpty else {
                pendingParagraphLines = []
                return
            }
            let wc = paraText.split(whereSeparator: \.isWhitespace).count
            blocks.append(DocumentBlock(
                text: paraText,
                type: .paragraph,
                wordCount: wc,
                page: currentPage,
                headingLevel: nil,
                headingText: nil,
                headingPath: headingStack.map(\.text),
                sourceWordRange: runningWordOffset..<(runningWordOffset + wc)
            ))
            runningWordOffset += wc
            pendingParagraphLines = []
        }

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            let tableText = tableLines.joined(separator: "\n")
            let wc = tableText.split(whereSeparator: \.isWhitespace).count
            blocks.append(DocumentBlock(
                text: tableText,
                type: .table,
                wordCount: wc,
                page: tablePage,
                headingLevel: nil,
                headingText: nil,
                headingPath: tableHeadingPath,
                sourceWordRange: tableStartWordOffset..<(tableStartWordOffset + wc)
            ))
            runningWordOffset = tableStartWordOffset + wc
            tableLines = []
            inTable = false
            tableHasSeenSeparator = false
        }

        func flushBlockQuote() {
            guard !blockQuoteLines.isEmpty else { return }
            let bqText = blockQuoteLines.joined(separator: "\n")
            let wc = bqText.split(whereSeparator: \.isWhitespace).count
            blocks.append(DocumentBlock(
                text: bqText,
                type: .blockQuote,
                wordCount: wc,
                page: blockQuotePage,
                headingLevel: nil,
                headingText: nil,
                headingPath: blockQuoteHeadingPath,
                sourceWordRange: blockQuoteStartWordOffset..<(blockQuoteStartWordOffset + wc)
            ))
            runningWordOffset = blockQuoteStartWordOffset + wc
            blockQuoteLines = []
            inBlockQuote = false
        }

        func flushList() {
            guard !listLines.isEmpty else { return }
            let listText = listLines.joined(separator: "\n")
            let wc = listText.split(whereSeparator: \.isWhitespace).count
            blocks.append(DocumentBlock(
                text: listText,
                type: .list,
                wordCount: wc,
                page: listPage,
                headingLevel: nil,
                headingText: nil,
                headingPath: listHeadingPath,
                sourceWordRange: listStartWordOffset..<(listStartWordOffset + wc)
            ))
            runningWordOffset = listStartWordOffset + wc
            listLines = []
            inList = false
        }

        func pushHeading(level: Int, text: String) {
            while let last = headingStack.last, last.level >= level {
                headingStack.removeLast()
            }
            headingStack.append((level: level, text: text))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineRange = NSRange(trimmed.startIndex..., in: trimmed)

            // --- Suppression zone: inside fenced code block ---
            if inFencedCodeBlock {
                if let match = Self.fencedCodeOpenPattern.firstMatch(in: trimmed, range: lineRange),
                   let r = Range(match.range(at: 1), in: trimmed) {
                    let marker = trimmed[r]
                    if marker.first == codeFenceChar && marker.count >= codeFenceCount
                        && trimmed.trimmingCharacters(in: .whitespaces)
                            .allSatisfy({ $0 == codeFenceChar }) {
                        codeBlockLines.append(line)
                        let codeText = codeBlockLines.joined(separator: "\n")
                        let wc = codeText.split(whereSeparator: \.isWhitespace).count
                        blocks.append(DocumentBlock(
                            text: codeText,
                            type: .codeBlock,
                            wordCount: wc,
                            page: codeBlockPage,
                            headingLevel: nil,
                            headingText: nil,
                            headingPath: codeBlockHeadingPath,
                            sourceWordRange: codeBlockStartWordOffset..<(codeBlockStartWordOffset + wc)
                        ))
                        runningWordOffset = codeBlockStartWordOffset + wc
                        inFencedCodeBlock = false
                        codeBlockLines = []
                        previousNonBlankLine = nil
                        continue
                    }
                }
                codeBlockLines.append(line)
                continue
            }

            // --- Fenced code block opening ---
            if let match = Self.fencedCodeOpenPattern.firstMatch(in: trimmed, range: lineRange),
               let r = Range(match.range(at: 1), in: trimmed) {
                let marker = trimmed[r]
                if marker.count >= 3 {
                    flushParagraph()
                    flushTable()
                    flushBlockQuote()
                    flushList()
                    inFencedCodeBlock = true
                    codeFenceChar = marker.first!
                    codeFenceCount = marker.count
                    codeBlockLines = [line]
                    codeBlockPage = currentPage
                    codeBlockHeadingPath = headingStack.map(\.text)
                    codeBlockStartWordOffset = runningWordOffset
                    previousNonBlankLine = nil
                    continue
                }
            }

            // --- Blank line ---
            if trimmed.isEmpty {
                if inTable { flushTable() }
                if inBlockQuote { flushBlockQuote() }
                if inList { flushList() }
                flushParagraph()
                previousNonBlankLine = nil
                continue
            }

            // --- Page markers (state-only, no content emitted) ---
            if let page = Self.extractPageNumber(from: trimmed) {
                flushParagraph()
                flushTable()
                flushBlockQuote()
                flushList()
                currentPage = page
                previousNonBlankLine = nil
                continue
            }

            // --- ATX headings ---
            if let match = Self.atxHeadingPattern.firstMatch(in: trimmed, range: lineRange),
               let hashRange = Range(match.range(at: 1), in: trimmed),
               let textRange = Range(match.range(at: 2), in: trimmed) {
                flushParagraph()
                flushTable()
                flushBlockQuote()
                flushList()
                let level = trimmed[hashRange].count
                let headingText = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)
                pushHeading(level: level, text: headingText)
                let wc = trimmed.split(whereSeparator: \.isWhitespace).count
                blocks.append(DocumentBlock(
                    text: trimmed,
                    type: .heading,
                    wordCount: wc,
                    page: currentPage,
                    headingLevel: level,
                    headingText: headingText,
                    headingPath: headingStack.map(\.text),
                    sourceWordRange: runningWordOffset..<(runningWordOffset + wc)
                ))
                runningWordOffset += wc
                previousNonBlankLine = nil
                continue
            }

            // --- Setext headings / thematic breaks ---
            let isSetextH1 = Self.setextH1Pattern.firstMatch(in: trimmed, range: lineRange) != nil
            let isSetextH2 = Self.setextH2Pattern.firstMatch(in: trimmed, range: lineRange) != nil

            if isSetextH1 && previousNonBlankLine != nil {
                let headingText = previousNonBlankLine!.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pendingParagraphLines.isEmpty {
                    pendingParagraphLines.removeLast()
                }
                flushParagraph()
                pushHeading(level: 1, text: headingText)
                let combinedText = headingText + "\n" + trimmed
                let wc = combinedText.split(whereSeparator: \.isWhitespace).count
                blocks.append(DocumentBlock(
                    text: combinedText,
                    type: .heading,
                    wordCount: wc,
                    page: currentPage,
                    headingLevel: 1,
                    headingText: headingText,
                    headingPath: headingStack.map(\.text),
                    sourceWordRange: runningWordOffset..<(runningWordOffset + wc)
                ))
                runningWordOffset += wc
                previousNonBlankLine = nil
                continue
            }

            if isSetextH2 && previousNonBlankLine != nil {
                let headingText = previousNonBlankLine!.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pendingParagraphLines.isEmpty {
                    pendingParagraphLines.removeLast()
                }
                flushParagraph()
                pushHeading(level: 2, text: headingText)
                let combinedText = headingText + "\n" + trimmed
                let wc = combinedText.split(whereSeparator: \.isWhitespace).count
                blocks.append(DocumentBlock(
                    text: combinedText,
                    type: .heading,
                    wordCount: wc,
                    page: currentPage,
                    headingLevel: 2,
                    headingText: headingText,
                    headingPath: headingStack.map(\.text),
                    sourceWordRange: runningWordOffset..<(runningWordOffset + wc)
                ))
                runningWordOffset += wc
                previousNonBlankLine = nil
                continue
            }

            // Thematic breaks (only when no preceding paragraph line)
            if previousNonBlankLine == nil {
                let isDashBreak = Self.thematicBreakDashPattern.firstMatch(in: trimmed, range: lineRange) != nil
                let isStarBreak = Self.thematicBreakStarPattern.firstMatch(in: trimmed, range: lineRange) != nil
                let isUnderscoreBreak = Self.thematicBreakUnderscorePattern.firstMatch(in: trimmed, range: lineRange) != nil

                if isDashBreak || isStarBreak || isUnderscoreBreak {
                    flushParagraph()
                    blocks.append(DocumentBlock(
                        text: trimmed,
                        type: .thematicBreak,
                        wordCount: 0,
                        page: currentPage,
                        headingLevel: nil,
                        headingText: nil,
                        headingPath: headingStack.map(\.text),
                        sourceWordRange: runningWordOffset..<runningWordOffset
                    ))
                    previousNonBlankLine = nil
                    continue
                }
            }

            // --- GFM pipe tables ---
            if Self.pipeTableRowPattern.firstMatch(in: trimmed, range: lineRange) != nil {
                if inTable {
                    if !tableHasSeenSeparator
                        && Self.pipeTableSeparatorPattern.firstMatch(in: trimmed, range: lineRange) != nil {
                        tableHasSeenSeparator = true
                    }
                    tableLines.append(line)
                    previousNonBlankLine = trimmed
                    continue
                }
                flushParagraph()
                flushBlockQuote()
                flushList()
                inTable = true
                tableLines = [line]
                tableHasSeenSeparator = false
                tablePage = currentPage
                tableHeadingPath = headingStack.map(\.text)
                tableStartWordOffset = runningWordOffset
                previousNonBlankLine = trimmed
                continue
            } else if inTable {
                flushTable()
            }

            // --- Block quotes ---
            if Self.blockQuotePattern.firstMatch(in: trimmed, range: lineRange) != nil {
                if inBlockQuote {
                    blockQuoteLines.append(line)
                    previousNonBlankLine = trimmed
                    continue
                }
                flushParagraph()
                flushList()
                inBlockQuote = true
                blockQuoteLines = [line]
                blockQuotePage = currentPage
                blockQuoteHeadingPath = headingStack.map(\.text)
                blockQuoteStartWordOffset = runningWordOffset
                previousNonBlankLine = trimmed
                continue
            } else if inBlockQuote {
                flushBlockQuote()
            }

            // --- Lists ---
            let isUnorderedItem = Self.unorderedListPattern.firstMatch(in: trimmed, range: lineRange) != nil
            let isOrderedItem = Self.orderedListPattern.firstMatch(in: trimmed, range: lineRange) != nil
            let isListContinuation = inList
                && Self.listContinuationPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil

            if isUnorderedItem || isOrderedItem || isListContinuation {
                if inList {
                    listLines.append(line)
                    previousNonBlankLine = trimmed
                    continue
                }
                flushParagraph()
                inList = true
                listLines = [line]
                listPage = currentPage
                listHeadingPath = headingStack.map(\.text)
                listStartWordOffset = runningWordOffset
                previousNonBlankLine = trimmed
                continue
            } else if inList {
                flushList()
            }

            // --- Figure captions ---
            if Self.figureCaptionPattern.firstMatch(in: trimmed, range: lineRange) != nil {
                flushParagraph()
                let wc = trimmed.split(whereSeparator: \.isWhitespace).count
                blocks.append(DocumentBlock(
                    text: trimmed,
                    type: .figureCaption,
                    wordCount: wc,
                    page: currentPage,
                    headingLevel: nil,
                    headingText: nil,
                    headingPath: headingStack.map(\.text),
                    sourceWordRange: runningWordOffset..<(runningWordOffset + wc)
                ))
                runningWordOffset += wc
                previousNonBlankLine = trimmed
                continue
            }

            // --- Footnotes ---
            if Self.footnotePattern.firstMatch(in: trimmed, range: lineRange) != nil {
                flushParagraph()
                let wc = trimmed.split(whereSeparator: \.isWhitespace).count
                blocks.append(DocumentBlock(
                    text: trimmed,
                    type: .footnote,
                    wordCount: wc,
                    page: currentPage,
                    headingLevel: nil,
                    headingText: nil,
                    headingPath: headingStack.map(\.text),
                    sourceWordRange: runningWordOffset..<(runningWordOffset + wc)
                ))
                runningWordOffset += wc
                previousNonBlankLine = trimmed
                continue
            }

            // --- Default: paragraph accumulation ---
            pendingParagraphLines.append(line)
            previousNonBlankLine = trimmed
        }

        // Flush any remaining state
        if inFencedCodeBlock && !codeBlockLines.isEmpty {
            let codeText = codeBlockLines.joined(separator: "\n")
            let wc = codeText.split(whereSeparator: \.isWhitespace).count
            blocks.append(DocumentBlock(
                text: codeText,
                type: .codeBlock,
                wordCount: wc,
                page: codeBlockPage,
                headingLevel: nil,
                headingText: nil,
                headingPath: codeBlockHeadingPath,
                sourceWordRange: codeBlockStartWordOffset..<(codeBlockStartWordOffset + wc)
            ))
            runningWordOffset = codeBlockStartWordOffset + wc
        }
        flushTable()
        flushBlockQuote()
        flushList()
        flushParagraph()

        return blocks
    }

    // MARK: - Page Number Extraction

    private static func extractPageNumber(from line: String) -> Int? {
        let range = NSRange(line.startIndex..., in: line)
        let patterns: [NSRegularExpression] = [
            pageMarkerBracket, pageMarkerDash, pageMarkerEquals, pageMarkerColon
        ]
        for pattern in patterns {
            if let match = pattern.firstMatch(in: line, range: range),
               let numRange = Range(match.range(at: 1), in: line),
               let page = Int(line[numRange]) {
                return page
            }
        }
        return nil
    }

    // MARK: - Stage 2: Merge Blocks

    private func mergeBlocks(_ blocks: [DocumentBlock]) -> [[DocumentBlock]] {
        var groups: [[DocumentBlock]] = []
        var current: [DocumentBlock] = []
        var currentWordCount = 0

        func flush() {
            guard !current.isEmpty else { return }
            groups.append(current)
            current = []
            currentWordCount = 0
        }

        var i = 0
        while i < blocks.count {
            let block = blocks[i]

            let isAtomic = (block.type == .codeBlock && preserveCodeBlocks)
                || (block.type == .table && preserveTables)

            if isAtomic && block.wordCount > targetWords {
                flush()
                groups.append([block])
                i += 1
                continue
            }

            if currentWordCount + block.wordCount > targetWords && currentWordCount > 0 {
                if let last = current.last, last.type == .heading, current.count > 1 {
                    let orphanedHeading = current.removeLast()
                    currentWordCount -= orphanedHeading.wordCount
                    flush()
                    current.append(orphanedHeading)
                    currentWordCount = orphanedHeading.wordCount
                } else {
                    flush()
                }
            }

            current.append(block)
            currentWordCount += block.wordCount

            // Heading stickiness: if this is a heading and it's the last block,
            // pull the next content block in
            if block.type == .heading && i + 1 < blocks.count && current.count == 1
                && currentWordCount == block.wordCount {
                // Will be handled naturally on next iteration
            }

            i += 1
        }
        flush()

        // Heading stickiness final check: if a group ends with only a heading,
        // merge it into the next group
        var merged: [[DocumentBlock]] = []
        for group in groups {
            if let prev = merged.last,
               prev.allSatisfy({ $0.type == .heading }),
               !group.isEmpty {
                var combined = prev
                combined.append(contentsOf: group)
                merged[merged.count - 1] = combined
            } else {
                merged.append(group)
            }
        }

        // Apply overlap
        if overlapBlocks > 0 && merged.count > 1 {
            var overlapped: [[DocumentBlock]] = [merged[0]]
            for gi in 1..<merged.count {
                let prevGroup = merged[gi - 1]
                let overlapCount = min(overlapBlocks, prevGroup.count)
                let overlapSlice = Array(prevGroup.suffix(overlapCount))
                var newGroup = overlapSlice
                newGroup.append(contentsOf: merged[gi])
                overlapped.append(newGroup)
            }
            return overlapped
        }

        return merged
    }

    // MARK: - Stage 3: Build TextChunks

    private func buildTextChunks(_ groups: [[DocumentBlock]]) -> [TextChunk] {
        var chunks: [TextChunk] = []

        for group in groups {
            let chunkText = group.map(\.text).joined(separator: "\n\n")
            let wordCount = group.reduce(0) { $0 + $1.wordCount }
            let index = chunks.count

            let pages = group.compactMap(\.page)
            let pageRange: PageRange? = pages.isEmpty ? nil : PageRange(
                start: pages.min()!,
                end: pages.max()!
            )

            let headingPath = group.first?.headingPath ?? []

            var seenTypes = Set<DocumentBlockType>()
            var orderedTypes: [DocumentBlockType] = []
            for block in group {
                if seenTypes.insert(block.type).inserted {
                    orderedTypes.append(block.type)
                }
            }

            let primaryBlockType: DocumentBlockType? = orderedTypes.first(where: {
                $0 != .paragraph && $0 != .unknown && $0 != .thematicBreak
            }) ?? (orderedTypes.isEmpty ? nil : .paragraph)

            let startWord = group.first?.sourceWordRange.lowerBound ?? 0
            let endWord = group.last?.sourceWordRange.upperBound ?? startWord

            let location = DocumentLocation(
                pageRange: pageRange,
                headingPath: headingPath,
                primaryBlockType: primaryBlockType,
                blockTypes: orderedTypes
            )

            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: startWord..<endWord,
                documentLocation: location
            )

            chunks.append(TextChunk(
                text: chunkText,
                index: index,
                wordCount: wordCount,
                metadata: metadata
            ))
        }

        return chunks
    }
}
