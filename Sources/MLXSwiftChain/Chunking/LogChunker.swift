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
///
/// Diagnostic classification populates ``LogMetadata`` on each chunk with
/// the detected ``LogChunkKind`` (Swift compiler errors, Xcode build errors,
/// linker errors, XCTest failures, simulator logs, runtime warnings, etc.).
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

            let kind = dominantKind(currentBlocks)
            let process = currentBlocks.compactMap(\.process).first
            let subsystem = currentBlocks.compactMap(\.subsystem).first
            let category = currentBlocks.compactMap(\.category).first
            let severity = currentBlocks.compactMap(\.severity).first

            let tsRange: TimestampRange?
            if let first = timestamps.first, let last = timestamps.last {
                tsRange = TimestampRange(start: first, end: last)
            } else {
                tsRange = nil
            }

            let logMeta = LogMetadata(
                kind: kind,
                process: process,
                subsystem: subsystem,
                category: category,
                severity: severity,
                timestampRange: tsRange
            )

            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: runningWordOffset..<(runningWordOffset + wc),
                timestamps: timestamps,
                logMetadata: logMeta
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
            let kindChange = !currentBlocks.isEmpty
                && block.kind != .unknown
                && dominantKind(currentBlocks) != .unknown
                && block.kind != dominantKind(currentBlocks)

            if (currentWordCount + block.wordCount > targetWords && currentWordCount > 0)
                || kindChange
            {
                flushChunk()
            }
            currentBlocks.append(block)
            currentWordCount += block.wordCount
        }
        flushChunk()

        return chunks
    }

    private func dominantKind(_ blocks: [Block]) -> LogChunkKind {
        var counts: [LogChunkKind: Int] = [:]
        for b in blocks {
            counts[b.kind, default: 0] += 1
        }
        counts.removeValue(forKey: .unknown)
        return counts.max(by: { $0.value < $1.value })?.key ?? .unknown
    }

    // MARK: - Block Parsing

    private struct Block {
        let text: String
        let timestamps: [String]
        let wordCount: Int
        let isStackTrace: Bool
        let kind: LogChunkKind
        let process: String?
        let subsystem: String?
        let category: String?
        let severity: String?
    }

    // MARK: - Patterns (timestamp / stack / error — existing)

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

    // MARK: - Diagnostic classification patterns

    private static let swiftCompilerErrorPattern = try! NSRegularExpression(
        pattern: #"(?m)(?:^|\s)\S+\.swift:\d+(?::\d+)?:\s*(?:error|warning|note):"#
    )

    private static let xcodeBuildErrorPattern = try! NSRegularExpression(
        pattern: #"(?m)(?:Command (?:SwiftCompile|CompileSwiftSources|PhaseScriptExecution|CodeSign|Ld) failed|BUILD FAILED|The following build commands failed)"#
    )

    private static let linkerErrorPattern = try! NSRegularExpression(
        pattern: #"(?m)(?:Undefined symbols? for architecture|ld: symbol\(s\) not found|clang: error: linker command failed|duplicate symbol)"#
    )

    private static let testFailurePattern = try! NSRegularExpression(
        pattern: #"(?m)(?:Test Case '.*' failed|XCTAssert\w+\s+failed|Executed \d+ tests?,|\.swift:\d+(?::\d+)?:\s*error:.*(?:XCT|test|assert))"#, options: [.caseInsensitive]
    )

    private static let simulatorLogPattern = try! NSRegularExpression(
        pattern: #"(?m)^\s*(?:default\s+)?\d{2,4}[-/]\d{2}[-/]\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+(?:[+-]\d{4})?\s+\S+\[\d+:\d+\]"#
    )

    private static let consoleLogPattern = try! NSRegularExpression(
        pattern: #"(?m)^\s*\d{2}:\d{2}:\d{2}\.\d+[+-]\d{4}\s+\S+\[\d+:\d+\]"#
    )

    private static let runtimeWarningPattern = try! NSRegularExpression(
        pattern: #"(?m)(?:Main Thread Checker:|Thread Sanitizer:|Address Sanitizer:|Undefined Behavior Sanitizer:|Publishing changes from background threads|Simultaneous accesses|Modifying state during view update|Could not cast value)"#
    )

    private static let fatalErrorPattern = try! NSRegularExpression(
        pattern: #"(?m)(?:Fatal error:|assertionFailure|preconditionFailure)"#
    )

    private static let appleStackFramePattern = try! NSRegularExpression(
        pattern: #"(?m)^\d+\s+\S+\s+0x[0-9a-fA-F]+"#
    )

    private static let processSubsystemPattern = try! NSRegularExpression(
        pattern: #"\S+\[(\d+):(\d+)\](?:\s+\[([^\]]+)\])?"#
    )

    private static let processNamePattern = try! NSRegularExpression(
        pattern: #"(\S+)\[\d+:\d+\]"#
    )

    // MARK: - Block Classification

    private func classifyBlock(_ text: String) -> (LogChunkKind, String?, String?, String?, String?) {
        let range = NSRange(text.startIndex..., in: text)

        if Self.testFailurePattern.firstMatch(in: text, range: range) != nil {
            return (.testFailure, nil, nil, nil, "error")
        }
        if Self.linkerErrorPattern.firstMatch(in: text, range: range) != nil {
            return (.linkerError, nil, nil, nil, "error")
        }
        if Self.xcodeBuildErrorPattern.firstMatch(in: text, range: range) != nil {
            return (.xcodeBuildError, nil, nil, nil, "error")
        }
        if Self.swiftCompilerErrorPattern.firstMatch(in: text, range: range) != nil {
            return (.swiftCompilerError, nil, nil, nil, extractSeverity(text))
        }
        if Self.runtimeWarningPattern.firstMatch(in: text, range: range) != nil {
            return (.runtimeWarning, extractProcess(text), nil, nil, "warning")
        }
        if Self.fatalErrorPattern.firstMatch(in: text, range: range) != nil {
            return (.runtimeWarning, nil, nil, nil, "fatal")
        }

        if Self.simulatorLogPattern.firstMatch(in: text, range: range) != nil {
            let (proc, sub, cat) = extractProcessInfo(text)
            return (.simulatorLog, proc, sub, cat, extractSeverity(text))
        }
        if Self.consoleLogPattern.firstMatch(in: text, range: range) != nil {
            let (proc, sub, cat) = extractProcessInfo(text)
            return (.consoleLog, proc, sub, cat, extractSeverity(text))
        }

        let frameMatches = Self.appleStackFramePattern.numberOfMatches(
            in: text, range: range
        )
        if frameMatches >= 3 {
            return (.stackTrace, nil, nil, nil, nil)
        }

        return (.unknown, nil, nil, nil, extractSeverity(text))
    }

    private func extractSeverity(_ text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("fatal") { return "fatal" }
        if lower.contains("error") { return "error" }
        if lower.contains("warning") || lower.contains("warn") { return "warning" }
        if lower.contains("info") { return "info" }
        if lower.contains("debug") { return "debug" }
        return nil
    }

    private func extractProcess(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        if let match = Self.processNamePattern.firstMatch(in: text, range: range),
           let r = Range(match.range(at: 1), in: text)
        {
            return String(text[r])
        }
        return nil
    }

    private func extractProcessInfo(_ text: String) -> (String?, String?, String?) {
        let range = NSRange(text.startIndex..., in: text)
        var process: String?
        var subsystem: String?
        var category: String?

        if let match = Self.processNamePattern.firstMatch(in: text, range: range),
           let r = Range(match.range(at: 1), in: text)
        {
            process = String(text[r])
        }

        if let match = Self.processSubsystemPattern.firstMatch(in: text, range: range),
           match.range(at: 3).location != NSNotFound,
           let r = Range(match.range(at: 3), in: text)
        {
            let sub = String(text[r])
            if sub.contains(".") {
                subsystem = sub
            } else {
                category = sub
            }
        }

        return (process, subsystem, category)
    }

    // MARK: - Block Parsing

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
            let (kind, process, subsystem, category, severity) = classifyBlock(blockText)
            blocks.append(Block(
                text: blockText,
                timestamps: timestamps,
                wordCount: wc,
                isStackTrace: inStackTrace,
                kind: kind,
                process: process,
                subsystem: subsystem,
                category: category,
                severity: severity
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
