import Foundation

/// Chunks Apple crash report text (.crash / .ips / Console paste) into
/// semantically meaningful sections with diagnostic metadata.
///
/// Detects and preserves:
/// - Header fields (Process, Identifier, OS Version, …)
/// - Exception information (Exception Type, Codes, Subtype)
/// - Diagnostic messages (Application Specific Information, VM Region Info)
/// - Last Exception Backtrace
/// - Crashed thread (kept intact when `preserveCrashedThread` is true)
/// - Other thread backtraces
/// - Register dumps (ARM/x86 Thread State)
/// - Binary Images
///
/// Does **not** acquire logs, call Xcode APIs, or use private frameworks.
public struct AppleCrashReportChunker: TextChunker {
    public let targetWords: Int
    public let preserveCrashedThread: Bool
    public let includeBinaryImages: Bool

    public init(
        targetWords: Int = 1500,
        preserveCrashedThread: Bool = true,
        includeBinaryImages: Bool = true
    ) {
        self.targetWords = max(1, targetWords)
        self.preserveCrashedThread = preserveCrashedThread
        self.includeBinaryImages = includeBinaryImages
    }

    /// Returns `true` if the text contains multiple Apple crash report markers,
    /// suggesting it should be processed with `AppleCrashReportChunker` rather
    /// than a generic chunker.
    public static func isLikelyAppleCrashReport(_ text: String) -> Bool {
        let markers = [
            "Process:", "Identifier:", "Exception Type:",
            "Termination Reason:", "Triggered by Thread:",
            "Binary Images:", "Incident Identifier:",
            "Hardware Model:", "OS Version:",
        ]
        let matched = markers.filter { text.contains($0) }.count
        return matched >= 3
    }

    /// Returns `true` if the text looks like a JSON-style .ips crash report
    /// based on the presence of common .ips JSON keys.
    public static func isLikelyIPSFormat(_ text: String) -> Bool {
        let ipsKeys = [
            "\"app_name\"", "\"bundleID\"", "\"os_version\"",
            "\"exception\"", "\"termination\"", "\"incident\"",
            "\"crashReporterKey\"",
        ]
        let matched = ipsKeys.filter { text.contains($0) }.count
        return matched >= 2
    }

    public func chunk(_ text: String) -> [TextChunk] {
        if Self.isLikelyIPSFormat(text) {
            return chunkIPS(text)
        }
        let sections = parseSections(text)
        guard !sections.isEmpty else { return [] }

        let headerFields = extractHeaderFields(from: sections)
        let exceptionFields = extractExceptionFields(from: sections)
        let symbStatus = detectSymbolication(sections: sections)

        let crashMeta = CrashReportMetadata(
            process: headerFields["Process"],
            identifier: headerFields["Identifier"],
            version: headerFields["Version"],
            hardwareModel: headerFields["Hardware Model"],
            osVersion: headerFields["OS Version"],
            exceptionType: exceptionFields["Exception Type"],
            exceptionCodes: exceptionFields["Exception Codes"],
            exceptionSubtype: exceptionFields["Exception Subtype"],
            terminationReason: exceptionFields["Termination Reason"],
            terminationDescription: exceptionFields["Termination Description"],
            applicationSpecificInformation: exceptionFields["Application Specific Information"],
            crashedThread: exceptionFields["Triggered by Thread"],
            signal: extractSignal(from: exceptionFields["Exception Type"]),
            symbolicationStatus: symbStatus
        )

        var chunks: [TextChunk] = []
        var runningWordOffset = 0

        for section in sections {
            if section.kind == .binaryImages && !includeBinaryImages {
                continue
            }

            let lines = section.lines
            let splitGroups = splitIfNeeded(
                lines: lines,
                kind: section.kind,
                targetWords: targetWords,
                preserve: section.kind == .crashedThread && preserveCrashedThread
                    || section.kind == .lastExceptionBacktrace
            )

            for group in splitGroups {
                let chunkText = group.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !chunkText.isEmpty else { continue }
                let wc = chunkText.split(whereSeparator: \.isWhitespace).count
                let index = chunks.count

                let logMeta = LogMetadata(
                    kind: section.kind,
                    process: crashMeta.process,
                    crashReport: crashMeta
                )
                let metadata = TextChunkMetadata(
                    chunkIndex: index,
                    sourceWordRange: runningWordOffset..<(runningWordOffset + wc),
                    logMetadata: logMeta
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

        return chunks
    }

    // MARK: - Section Parsing

    private struct Section {
        let kind: LogChunkKind
        let lines: [String]
    }

    private static let headerKeys: Set<String> = [
        "Process", "Path", "Identifier", "Version", "Code Type",
        "Role", "Parent Process", "Coalition", "Date/Time",
        "Launch Time", "OS Version", "Release Type",
        "Report Version", "Hardware Model", "Baseband Version",
        "Incident Identifier", "CrashReporter Key",
    ]

    private static let exceptionKeys: Set<String> = [
        "Exception Type", "Exception Subtype", "Exception Codes",
        "Exception Note", "Termination Reason", "Termination Description",
        "Triggered by Thread",
    ]

    private static let threadCrashedPattern = try! NSRegularExpression(
        pattern: #"^Thread \d+\s+Crashed"#
    )
    private static let threadPattern = try! NSRegularExpression(
        pattern: #"^Thread \d+(?:\s+name:|\s*:)"#
    )
    private static let registerPattern = try! NSRegularExpression(
        pattern: #"^Thread \d+\s+crashed with (?:ARM|[Xx]86)"#
    )
    private static let binaryImagesPattern = try! NSRegularExpression(
        pattern: #"^Binary Images:"#
    )
    private static let lastExceptionBTPattern = try! NSRegularExpression(
        pattern: #"^Last Exception Backtrace:"#
    )
    private static let appSpecificInfoPattern = try! NSRegularExpression(
        pattern: #"^Application Specific (?:Information|Backtrace|Signatures):"#
    )
    private static let vmRegionPattern = try! NSRegularExpression(
        pattern: #"^VM Region Info:"#
    )
    private static let dyldErrorPattern = try! NSRegularExpression(
        pattern: #"^Dyld Error Message:"#
    )
    private static let crashingOnExceptionPattern = try! NSRegularExpression(
        pattern: #"^Crashing on exception:"#
    )

    private func parseSections(_ text: String) -> [Section] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [Section] = []
        var currentLines: [String] = []
        var currentKind: LogChunkKind = .crashHeader

        func flush() {
            let trimmed = currentLines.filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
            if !trimmed.isEmpty {
                sections.append(Section(kind: currentKind, lines: currentLines))
            }
            currentLines = []
        }

        var inHeader = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)

            if Self.binaryImagesPattern.firstMatch(in: line, range: range) != nil {
                flush()
                currentKind = .binaryImages
                currentLines.append(line)
                continue
            }

            if Self.registerPattern.firstMatch(in: line, range: range) != nil {
                flush()
                currentKind = .registers
                currentLines.append(line)
                continue
            }

            if Self.lastExceptionBTPattern.firstMatch(in: line, range: range) != nil {
                flush()
                currentKind = .lastExceptionBacktrace
                inHeader = false
                currentLines.append(line)
                continue
            }

            if Self.appSpecificInfoPattern.firstMatch(in: line, range: range) != nil
                || Self.vmRegionPattern.firstMatch(in: line, range: range) != nil
                || Self.dyldErrorPattern.firstMatch(in: line, range: range) != nil
                || Self.crashingOnExceptionPattern.firstMatch(in: line, range: range) != nil
            {
                flush()
                currentKind = .diagnosticMessage
                inHeader = false
                currentLines.append(line)
                continue
            }

            if Self.threadCrashedPattern.firstMatch(in: line, range: range) != nil {
                flush()
                currentKind = .crashedThread
                inHeader = false
                currentLines.append(line)
                continue
            }

            if Self.threadPattern.firstMatch(in: line, range: range) != nil
                && currentKind != .crashedThread
            {
                flush()
                currentKind = .threadBacktrace
                inHeader = false
                currentLines.append(line)
                continue
            }

            let colonIdx = trimmed.firstIndex(of: ":")
            if let ci = colonIdx {
                let key = String(trimmed[trimmed.startIndex..<ci])
                    .trimmingCharacters(in: .whitespaces)
                if Self.exceptionKeys.contains(key) {
                    if currentKind != .exceptionInfo {
                        flush()
                    }
                    currentKind = .exceptionInfo
                    inHeader = false
                    currentLines.append(line)
                    continue
                }
                if inHeader && Self.headerKeys.contains(key) {
                    currentLines.append(line)
                    continue
                }
            }

            if inHeader && trimmed.isEmpty && !currentLines.isEmpty
                && currentKind == .crashHeader
            {
                let hasHeaderKey = currentLines.contains { l in
                    let t = l.trimmingCharacters(in: .whitespaces)
                    guard let ci = t.firstIndex(of: ":") else { return false }
                    let k = String(t[t.startIndex..<ci]).trimmingCharacters(in: .whitespaces)
                    return Self.headerKeys.contains(k)
                }
                if hasHeaderKey {
                    flush()
                    inHeader = false
                }
            }

            currentLines.append(line)
        }
        flush()

        return sections
    }

    // MARK: - Field Extraction

    private func extractHeaderFields(from sections: [Section]) -> [String: String] {
        var fields: [String: String] = [:]
        for section in sections where section.kind == .crashHeader {
            for line in section.lines {
                if let (key, value) = parseKeyValue(line),
                   Self.headerKeys.contains(key)
                {
                    fields[key] = value
                }
            }
        }
        return fields
    }

    private func extractExceptionFields(from sections: [Section]) -> [String: String] {
        var fields: [String: String] = [:]
        for section in sections where section.kind == .exceptionInfo {
            for line in section.lines {
                if let (key, value) = parseKeyValue(line) {
                    fields[key] = value
                }
            }
        }
        for section in sections where section.kind == .diagnosticMessage {
            for line in section.lines {
                if let (key, value) = parseKeyValue(line) {
                    if key == "Application Specific Information" {
                        fields[key] = value
                    }
                }
            }
        }
        return fields
    }

    private func parseKeyValue(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }
        let key = String(trimmed[trimmed.startIndex..<colonIndex])
            .trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        let value = String(trimmed[trimmed.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private func extractSignal(from exceptionType: String?) -> String? {
        guard let et = exceptionType else { return nil }
        let range = NSRange(et.startIndex..., in: et)
        let pattern = try! NSRegularExpression(pattern: #"\((\w+)\)"#)
        if let match = pattern.firstMatch(in: et, range: range),
           let r = Range(match.range(at: 1), in: et)
        {
            return String(et[r])
        }
        return nil
    }

    // MARK: - Symbolication Detection

    private static let symbolicatedFramePattern = try! NSRegularExpression(
        pattern: #"\d+\s+\S+\s+0x[0-9a-fA-F]+\s+(?!0x)[A-Za-z_]"#
    )
    private static let unsymbolicatedFramePattern = try! NSRegularExpression(
        pattern: #"\d+\s+\S+\s+0x[0-9a-fA-F]+\s+0x[0-9a-fA-F]+\s*\+"#
    )

    private func detectSymbolication(sections: [Section]) -> SymbolicationStatus {
        var symbolicated = 0
        var unsymbolicated = 0

        let threadKinds: Set<LogChunkKind> = [
            .crashedThread, .threadBacktrace, .lastExceptionBacktrace,
        ]

        for section in sections where threadKinds.contains(section.kind) {
            for line in section.lines {
                let range = NSRange(line.startIndex..., in: line)
                if Self.symbolicatedFramePattern.firstMatch(in: line, range: range) != nil {
                    symbolicated += 1
                } else if Self.unsymbolicatedFramePattern.firstMatch(in: line, range: range) != nil {
                    unsymbolicated += 1
                }
            }
        }

        let total = symbolicated + unsymbolicated
        guard total >= 3 else { return .unknown }

        let ratio = Double(symbolicated) / Double(total)
        if ratio >= 0.8 { return .fullySymbolicated }
        if ratio >= 0.3 { return .partiallySymbolicated }
        return .unsymbolicated
    }

    // MARK: - Safe Splitting

    private static let stackFrameLinePattern = try! NSRegularExpression(
        pattern: #"^\d+\s+"#
    )

    private func splitIfNeeded(
        lines: [String],
        kind: LogChunkKind,
        targetWords: Int,
        preserve: Bool
    ) -> [[String]] {
        let text = lines.joined(separator: "\n")
        let totalWords = text.split(whereSeparator: \.isWhitespace).count

        if preserve || totalWords <= targetWords {
            return [lines]
        }

        var groups: [[String]] = []
        var current: [String] = []
        var currentWC = 0

        for line in lines {
            let lineWC = line.split(whereSeparator: \.isWhitespace).count
            let range = NSRange(line.startIndex..., in: line)
            let isFrame = Self.stackFrameLinePattern.firstMatch(in: line, range: range) != nil

            if currentWC + lineWC > targetWords && currentWC > 0 && isFrame {
                groups.append(current)
                current = []
                currentWC = 0
            }
            current.append(line)
            currentWC += lineWC
        }
        if !current.isEmpty {
            groups.append(current)
        }

        return groups
    }

    // MARK: - Lightweight .ips JSON Handling

    private static let ipsKeyMapping: [(pattern: String, kind: LogChunkKind)] = [
        ("\"app_name\"", .crashHeader),
        ("\"bundleID\"", .crashHeader),
        ("\"build_version\"", .crashHeader),
        ("\"os_version\"", .crashHeader),
        ("\"incident\"", .crashHeader),
        ("\"crashReporterKey\"", .crashHeader),
        ("\"exception\"", .exceptionInfo),
        ("\"termination\"", .diagnosticMessage),
        ("\"threads\"", .threadBacktrace),
        ("\"usedImages\"", .binaryImages),
        ("\"asi\"", .diagnosticMessage),
        ("\"lastExceptionBacktrace\"", .lastExceptionBacktrace),
        ("\"faultingThread\"", .crashedThread),
    ]

    private func chunkIPS(_ text: String) -> [TextChunk] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [(kind: LogChunkKind, lines: [String])] = []
        var currentKind: LogChunkKind = .crashHeader
        var currentLines: [String] = []

        for line in lines {
            var detectedKind: LogChunkKind?
            for (pattern, kind) in Self.ipsKeyMapping {
                if line.contains(pattern) {
                    detectedKind = kind
                    break
                }
            }

            if let newKind = detectedKind, newKind != currentKind {
                if !currentLines.isEmpty {
                    sections.append((kind: currentKind, lines: currentLines))
                    currentLines = []
                }
                currentKind = newKind
            }
            currentLines.append(line)
        }
        if !currentLines.isEmpty {
            sections.append((kind: currentKind, lines: currentLines))
        }

        var chunks: [TextChunk] = []
        var runningWordOffset = 0

        for section in sections {
            if section.kind == .binaryImages && !includeBinaryImages {
                continue
            }

            let chunkText = section.lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkText.isEmpty else { continue }
            let wc = chunkText.split(whereSeparator: \.isWhitespace).count
            let index = chunks.count

            let logMeta = LogMetadata(kind: section.kind)
            let metadata = TextChunkMetadata(
                chunkIndex: index,
                sourceWordRange: runningWordOffset..<(runningWordOffset + wc),
                logMetadata: logMeta
            )

            chunks.append(TextChunk(
                text: chunkText,
                index: index,
                wordCount: wc,
                metadata: metadata
            ))
            runningWordOffset += wc
        }

        return chunks
    }
}
