import Foundation

/// How source text is injected into LLM prompts.
public enum PromptStyle: Sendable, Equatable {
    /// Legacy: raw concatenation (`taskPrompt + text`). Default for backward compatibility.
    case raw
    /// Source text wrapped in `<source>` delimiters with metadata attributes.
    /// Recommended for new projects — improves source traceability and
    /// reduces prompt injection surface.
    case delimited
}

/// Centralized, injection-resistant prompt builder for document chains.
///
/// When ``PromptStyle/delimited`` is active, source text is wrapped in
/// explicit `<source>` tags with optional metadata (chunk index, word range,
/// speaker labels, timestamps, heading path, log kind).
///
/// When ``PromptStyle/raw`` is active, prompts use the legacy format
/// (`taskPrompt + text`) for backward compatibility.
public struct ChainPromptBuilder: Sendable {

    // MARK: - Map Prompt

    /// Build a map-phase prompt for a single chunk.
    public static func mapPrompt(
        task: String,
        chunk: TextChunk,
        totalChunks: Int,
        style: PromptStyle
    ) -> String {
        switch style {
        case .raw:
            return task + chunk.text
        case .delimited:
            let sourceTag = sourceTag(for: chunk, totalChunks: totalChunks)
            return "\(task)\n\n\(sourceTag)"
        }
    }

    // MARK: - Reduce Prompt

    /// Build a reduce-phase prompt from intermediate summaries.
    public static func reducePrompt(
        task: String,
        summaries: [String],
        totalSections: Int,
        style: PromptStyle
    ) -> String {
        let combined = summaries.enumerated().map { i, summary in
            "--- Section \(i + 1) of \(totalSections) ---\n\(summary)"
        }.joined(separator: "\n\n")

        switch style {
        case .raw:
            return task + combined
        case .delimited:
            return "\(task)\n\n<summaries count=\"\(totalSections)\">\n\(combined)\n</summaries>"
        }
    }

    // MARK: - Stuff Prompt

    /// Build a stuff-mode prompt for the full document.
    public static func stuffPrompt(
        task: String,
        text: String,
        metadata: TextChunkMetadata?,
        style: PromptStyle
    ) -> String {
        switch style {
        case .raw:
            return task + text
        case .delimited:
            let wordCount = text.split(whereSeparator: \.isWhitespace).count
            var attrs = "words=\"0-\(wordCount)\""
            if let meta = metadata {
                attrs += metadataAttributes(meta)
            }
            return "\(task)\n\n<source \(attrs)>\n\(text)\n</source>"
        }
    }

    // MARK: - Source Tag Builder

    static func sourceTag(for chunk: TextChunk, totalChunks: Int) -> String {
        let meta = chunk.metadata
        var attrs = "index=\"\(chunk.index)\" of=\"\(totalChunks)\""
        attrs += " words=\"\(meta.sourceWordRange.lowerBound)-\(meta.sourceWordRange.upperBound)\""
        attrs += metadataAttributes(meta)
        return "<source \(attrs)>\n\(chunk.text)\n</source>"
    }

    private static func metadataAttributes(_ meta: TextChunkMetadata) -> String {
        var parts: [String] = []

        if !meta.speakerLabels.isEmpty {
            parts.append("speaker=\"\(meta.speakerLabels.joined(separator: ", "))\"")
        }
        if let ts = meta.timestampRange {
            parts.append("time=\"\(ts.start)-\(ts.end)\"")
        }
        if let loc = meta.documentLocation {
            if !loc.headingPath.isEmpty {
                parts.append("heading=\"\(loc.headingPath.joined(separator: " > "))\"")
            }
            if let blockType = loc.primaryBlockType {
                parts.append("block=\"\(blockType.rawValue)\"")
            }
            if let pages = loc.pageRange {
                parts.append("pages=\"\(pages.start)-\(pages.end)\"")
            }
        }
        if let logMeta = meta.logMetadata {
            parts.append("logKind=\"\(logMeta.kind.rawValue)\"")
            if let severity = logMeta.severity {
                parts.append("severity=\"\(severity)\"")
            }
        }

        return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }
}
