import Foundation

/// Generates human-readable labels for diagnostic chunks used in
/// map-reduce output citations (e.g. `[Chunk 2, exceptionInfo, EXC_BAD_ACCESS]`).
public struct DiagnosticSourceLabel: Sendable, Equatable {

    /// Returns a bracketed label for display in chain outputs.
    ///
    /// Format: `[Chunk N, kind, detail]` where N is 1-based,
    /// kind is the ``LogChunkKind`` raw value, and detail is the most
    /// salient metadata (exception type, process name, etc.).
    public static func label(for chunk: TextChunk) -> String {
        let number = chunk.index + 1
        var parts = ["Chunk \(number)"]

        guard let logMeta = chunk.metadata.logMetadata else {
            return "[\(parts.joined(separator: ", "))]"
        }

        if logMeta.kind != .unknown {
            parts.append(logMeta.kind.rawValue)
        }

        if let crash = logMeta.crashReport {
            switch logMeta.kind {
            case .exceptionInfo, .crashHeader:
                if let et = crash.exceptionType, !et.isEmpty {
                    parts.append(et)
                }
            case .crashedThread:
                if let ct = crash.crashedThread, !ct.isEmpty {
                    parts.append("Thread \(ct)")
                }
            default:
                break
            }
        }

        if let process = logMeta.process, !process.isEmpty,
           logMeta.kind == .simulatorLog
            || logMeta.kind == .consoleLog
            || logMeta.kind == .runtimeWarning
        {
            if !parts.contains(process) {
                parts.append(process)
            }
        }

        if logMeta.kind == .xcodeBuildError {
            if let detail = extractBuildCommand(from: chunk.text) {
                parts.append(detail)
            }
        } else if logMeta.kind == .testFailure {
            if let detail = extractTestName(from: chunk.text) {
                parts.append(detail)
            }
        }

        if let severity = logMeta.severity, !severity.isEmpty,
           logMeta.kind == .xcodeBuildError
            || logMeta.kind == .swiftCompilerError
            || logMeta.kind == .testFailure
        {
            if !parts.contains(severity) {
                parts.append(severity)
            }
        }

        return "[\(parts.joined(separator: ", "))]"
    }

    // MARK: - Detail Extraction

    private static let buildCommandPattern = try! NSRegularExpression(
        pattern: #"Command (\w+) failed"#
    )
    private static let testCasePattern = try! NSRegularExpression(
        pattern: #"Test Case '(?:-\[)?(\S+?)(?:\])?' failed"#
    )

    private static func extractBuildCommand(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        if let match = buildCommandPattern.firstMatch(in: text, range: range),
           let r = Range(match.range(at: 1), in: text)
        {
            return String(text[r])
        }
        return nil
    }

    private static func extractTestName(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        if let match = testCasePattern.firstMatch(in: text, range: range),
           let r = Range(match.range(at: 1), in: text)
        {
            return String(text[r])
        }
        return nil
    }
}
