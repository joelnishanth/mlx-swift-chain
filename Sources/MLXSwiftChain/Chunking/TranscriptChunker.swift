import Foundation

/// Splits transcript text using speaker-turn, timestamp, or topic-based
/// boundaries depending on the detected structure of the input.
///
/// Recognizes common transcript formats:
/// - `HH:MM:SS Speaker:` or `MM:SS Speaker:`
/// - `Speaker:` at the start of a line
/// - SRT/VTT timestamp lines
/// - Bracketed/parenthesized timestamps: `[00:12]`, `(01:30)`
///
/// For single-speaker transcripts (voice notes, lectures, memos) the chunker
/// avoids repetitive speaker attribution and prefers timestamp or topic
/// boundaries instead. See ``TranscriptAttributionMode`` for details.
public struct TranscriptChunker: TextChunker {
    public let targetWords: Int
    public let overlapTurns: Int
    public let attributionMode: TranscriptAttributionMode

    public init(
        targetWords: Int = 1500,
        overlapTurns: Int = 0,
        attributionMode: TranscriptAttributionMode = .auto
    ) {
        self.targetWords = max(1, targetWords)
        self.overlapTurns = max(0, overlapTurns)
        self.attributionMode = attributionMode
    }

    public func chunk(_ text: String) -> [TextChunk] {
        let turns = parseTurns(text)
        guard !turns.isEmpty else { return [] }

        let uniqueSpeakers = Set(turns.compactMap(\.speaker))
        let mode = resolvedMode(
            for: text,
            turns: turns,
            uniqueSpeakerCount: uniqueSpeakers.count
        )

        switch mode {
        case .speaker:
            return chunkBySpeakerTurns(turns)
        case .temporal:
            return chunkByTimestampsAndParagraphs(
                text, turns: turns, uniqueSpeakerCount: uniqueSpeakers.count
            )
        case .topical:
            let topical = chunkByTopics(
                text, turns: turns, uniqueSpeakerCount: uniqueSpeakers.count
            )
            if topical.isEmpty {
                return chunkByTimestampsAndParagraphs(
                    text, turns: turns, uniqueSpeakerCount: uniqueSpeakers.count
                )
            }
            return topical
        case .auto:
            fatalError("resolvedMode should never return .auto")
        }
    }

    // MARK: - Mode Resolution

    private func resolvedMode(
        for text: String,
        turns: [Turn],
        uniqueSpeakerCount: Int
    ) -> TranscriptAttributionMode {
        switch attributionMode {
        case .speaker, .temporal, .topical:
            return attributionMode
        case .auto:
            if uniqueSpeakerCount >= 2 {
                return .speaker
            }
            if detectsTopicStructure(text) {
                return .topical
            }
            return .temporal
        }
    }

    // MARK: - Speaker-Turn Chunking (existing behavior)

    private func chunkBySpeakerTurns(_ turns: [Turn]) -> [TextChunk] {
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

            let allTimestamps = selected.flatMap(\.timestamps)
            let tsRange = Self.makeTimestampRange(allTimestamps)

            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: startWord..<endWord,
                timestamps: allTimestamps,
                speakerLabels: Array(Set(selected.compactMap(\.speaker))).sorted(),
                attributionType: .speaker,
                timestampRange: tsRange
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

    // MARK: - Temporal Chunking

    private func chunkByTimestampsAndParagraphs(
        _ text: String,
        turns: [Turn],
        uniqueSpeakerCount: Int
    ) -> [TextChunk] {
        let segments = parseTemporalSegments(text)
        guard !segments.isEmpty else { return [] }

        let suppressSpeakers = uniqueSpeakerCount <= 1
        var chunks: [TextChunk] = []
        var segIndex = 0
        var runningWordOffset = 0

        while segIndex < segments.count {
            var chunkWordCount = 0
            var chunkSegments: [TemporalSegment] = []

            while segIndex < segments.count {
                let seg = segments[segIndex]
                if chunkWordCount + seg.wordCount > targetWords && chunkWordCount > 0 {
                    break
                }
                chunkWordCount += seg.wordCount
                chunkSegments.append(seg)
                segIndex += 1
            }

            let chunkText = chunkSegments.map(\.text).joined(separator: "\n\n")
            let index = chunks.count
            let startWord = runningWordOffset
            let endWord = startWord + chunkWordCount

            let allTimestamps = chunkSegments.flatMap(\.timestamps)
            let tsRange = Self.makeTimestampRange(allTimestamps)
            let speakers: [String] = suppressSpeakers
                ? []
                : Array(Set(chunkSegments.flatMap(\.speakers))).sorted()

            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: startWord..<endWord,
                timestamps: allTimestamps,
                speakerLabels: speakers,
                attributionType: .temporal,
                timestampRange: tsRange
            )

            chunks.append(TextChunk(
                text: chunkText,
                index: index,
                wordCount: chunkWordCount,
                metadata: metadata
            ))

            runningWordOffset = endWord
        }

        return chunks
    }

    // MARK: - Topical Chunking

    private static let headingPatterns: [NSRegularExpression] = {
        let patterns = [
            #"(?m)^#{1,3}\s+.+"#,                          // markdown headings
            #"(?m)^\*\*.+\*\*\s*$"#,                       // **bold** lines
            #"(?m)^[A-Z][A-Z\s]{2,40}$"#,                  // ALL CAPS short lines
            #"(?m)^(?:Topic|Section|Chapter|Part)\s*:\s*.+"# // label headings
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private func detectsTopicStructure(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in Self.headingPatterns {
            if pattern.firstMatch(in: text, range: range) != nil {
                return true
            }
        }
        return false
    }

    private func chunkByTopics(
        _ text: String,
        turns: [Turn],
        uniqueSpeakerCount: Int
    ) -> [TextChunk] {
        let sections = parseTopicSections(text)
        guard sections.count >= 2 else { return [] }

        let suppressSpeakers = uniqueSpeakerCount <= 1
        var chunks: [TextChunk] = []
        var secIndex = 0
        var runningWordOffset = 0

        while secIndex < sections.count {
            var chunkWordCount = 0
            var chunkSections: [TopicSection] = []

            while secIndex < sections.count {
                let sec = sections[secIndex]
                if chunkWordCount + sec.wordCount > targetWords && chunkWordCount > 0 {
                    break
                }
                chunkWordCount += sec.wordCount
                chunkSections.append(sec)
                secIndex += 1
            }

            let chunkText = chunkSections.map(\.text).joined(separator: "\n\n")
            let index = chunks.count
            let startWord = runningWordOffset
            let endWord = startWord + chunkWordCount

            let allTimestamps = chunkSections.flatMap(\.timestamps)
            let tsRange = Self.makeTimestampRange(allTimestamps)
            let topicLabel = chunkSections.first?.heading
            let speakers: [String] = suppressSpeakers
                ? []
                : Array(Set(chunkSections.flatMap(\.speakers))).sorted()

            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: startWord..<endWord,
                timestamps: allTimestamps,
                speakerLabels: speakers,
                attributionType: .topical,
                topicLabel: topicLabel,
                timestampRange: tsRange
            )

            chunks.append(TextChunk(
                text: chunkText,
                index: index,
                wordCount: chunkWordCount,
                metadata: metadata
            ))

            runningWordOffset = endWord
        }

        return chunks
    }

    // MARK: - Temporal Segment Parsing

    private struct TemporalSegment {
        let text: String
        let timestamps: [String]
        let speakers: [String]
        let wordCount: Int
    }

    private func parseTemporalSegments(_ text: String) -> [TemporalSegment] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var segments: [TemporalSegment] = []

        for paragraph in paragraphs {
            let lines = paragraph.components(separatedBy: .newlines)
            var currentLines: [String] = []
            var currentTimestamps: [String] = []
            var currentSpeakers: [String] = []

            func flush() {
                let segText = currentLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !segText.isEmpty else { return }
                let wc = segText.split(whereSeparator: \.isWhitespace).count
                segments.append(TemporalSegment(
                    text: segText,
                    timestamps: currentTimestamps,
                    speakers: Array(Set(currentSpeakers)),
                    wordCount: wc
                ))
                currentLines = []
                currentTimestamps = []
                currentSpeakers = []
            }

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let lineRange = NSRange(line.startIndex..., in: line)
                let lineTimestamps = Self.timestampPattern.matches(in: line, range: lineRange).compactMap {
                    Range($0.range, in: line).map { String(line[$0]) }
                }
                let hasTsStart = !lineTimestamps.isEmpty
                    && trimmed.hasPrefix(lineTimestamps.first ?? "")
                    || Self.bracketedTimestampPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil

                if hasTsStart && !currentLines.isEmpty {
                    flush()
                }

                currentLines.append(line)
                currentTimestamps.append(contentsOf: lineTimestamps)

                if let match = Self.speakerPattern.firstMatch(in: line, range: lineRange),
                   let spkRange = Range(match.range(at: 2), in: line) {
                    currentSpeakers.append(
                        String(line[spkRange]).trimmingCharacters(in: .whitespaces)
                    )
                }
            }
            flush()
        }

        return segments
    }

    // MARK: - Topic Section Parsing

    private struct TopicSection {
        let heading: String?
        let text: String
        let timestamps: [String]
        let speakers: [String]
        let wordCount: Int
    }

    private func parseTopicSections(_ text: String) -> [TopicSection] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [TopicSection] = []
        var currentHeading: String?
        var currentLines: [String] = []

        func flush() {
            let body = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            let wc = body.split(whereSeparator: \.isWhitespace).count
            let range = NSRange(body.startIndex..., in: body)
            let ts = Self.timestampPattern.matches(in: body, range: range).compactMap {
                Range($0.range, in: body).map { String(body[$0]) }
            }
            let spk = Self.speakerExtractPattern.matches(in: body, range: range).compactMap {
                Range($0.range(at: 1), in: body).map {
                    String(body[$0]).trimmingCharacters(in: .whitespaces)
                }
            }
            sections.append(TopicSection(
                heading: currentHeading,
                text: body,
                timestamps: ts,
                speakers: Array(Set(spk)),
                wordCount: wc
            ))
            currentLines = []
            currentHeading = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isHeadingLine(trimmed) {
                flush()
                currentHeading = cleanHeading(trimmed)
                currentLines.append(line)
            } else {
                currentLines.append(line)
            }
        }
        flush()

        return sections
    }

    private func isHeadingLine(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        for pattern in Self.headingPatterns {
            if pattern.firstMatch(in: line, range: range) != nil {
                return true
            }
        }
        return false
    }

    private func cleanHeading(_ line: String) -> String {
        var h = line
        while h.hasPrefix("#") { h = String(h.dropFirst()) }
        h = h.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("**") && h.hasSuffix("**") {
            h = String(h.dropFirst(2).dropLast(2))
        }
        if let colonIdx = h.range(of: ":") {
            let prefix = h[h.startIndex..<colonIdx.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let labelPrefixes = ["Topic", "Section", "Chapter", "Part"]
            if labelPrefixes.contains(prefix) {
                h = String(h[colonIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return h.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static let speakerExtractPattern = try! NSRegularExpression(
        pattern: #"(?m)^\s*(?:\d{1,2}:\d{2}(?::\d{2})?\s+)?([A-Za-z][A-Za-z\s]{0,30}):"#
    )

    private static let timestampPattern = try! NSRegularExpression(
        pattern: #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#
    )

    private static let bracketedTimestampPattern = try! NSRegularExpression(
        pattern: #"^[\[\(]\d{1,2}:\d{2}(?::\d{2})?[\]\)]"#
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

    // MARK: - Helpers

    private static func makeTimestampRange(_ timestamps: [String]) -> TimestampRange? {
        guard let first = timestamps.first, let last = timestamps.last else { return nil }
        return TimestampRange(start: first, end: last)
    }
}
