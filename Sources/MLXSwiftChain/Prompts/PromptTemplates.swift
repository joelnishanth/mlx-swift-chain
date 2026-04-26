import Foundation

/// A reusable set of prompts for document chain execution.
public struct ChainPromptTemplate: Sendable, Equatable {
    /// Prompt used for mapping each chunk in map-reduce mode.
    public var mapPrompt: String
    /// Prompt used for reducing combined summaries.
    public var reducePrompt: String
    /// Optional prompt used when the entire document fits in a single call.
    /// Falls back to `reducePrompt` when nil.
    public var stuffPrompt: String?

    public init(mapPrompt: String, reducePrompt: String, stuffPrompt: String? = nil) {
        self.mapPrompt = mapPrompt
        self.reducePrompt = reducePrompt
        self.stuffPrompt = stuffPrompt
    }
}

/// Pre-built prompt templates for common long-document reasoning tasks.
///
/// These templates instruct the model to cite `[Chunk N]` labels from the
/// section headers that MapReduceChain inserts, enabling source traceability
/// in outputs.
public enum PromptTemplates {

    /// Summarize a meeting transcript, preserving speaker attribution and timestamps.
    public static let transcriptSummary = ChainPromptTemplate(
        mapPrompt: """
            Summarize this section of a transcript. Preserve speaker names and key timestamps. \
            Reference the section label at the top.\n\n
            """,
        reducePrompt: """
            Combine these section summaries into a coherent meeting summary. \
            Cite [Chunk N] labels when referencing specific sections. \
            Include key decisions, action items, and who said what.\n\n
            """,
        stuffPrompt: """
            Summarize this transcript. Preserve speaker names, key timestamps, decisions, \
            and action items.\n\n
            """
    )

    /// Extract action items and tasks from meeting notes or long-form text.
    public static let actionItems = ChainPromptTemplate(
        mapPrompt: """
            Extract action items, deadlines, and assigned owners from this section. \
            Format each as: "- [Owner] Task (Deadline)". Reference the section label.\n\n
            """,
        reducePrompt: """
            Merge and deduplicate these action items into a single prioritized list. \
            Cite [Chunk N] for each item's source. Remove duplicates.\n\n
            """,
        stuffPrompt: """
            Extract all action items, deadlines, and assigned owners. \
            Format each as: "- [Owner] Task (Deadline)".\n\n
            """
    )

    /// Identify root cause and key errors from log output.
    public static let logRootCause = ChainPromptTemplate(
        mapPrompt: """
            Identify errors, exceptions, warnings, and anomalies in this log section. \
            Note timestamps, error types, and stack traces. Reference the section label.\n\n
            """,
        reducePrompt: """
            Analyze these error reports and determine the probable root cause. \
            Cite [Chunk N] for key evidence. List: (1) root cause, \
            (2) key errors in order, (3) suggested next debugging steps.\n\n
            """,
        stuffPrompt: """
            Analyze this log output. Identify the probable root cause of any errors. \
            List: (1) root cause, (2) key errors in order, (3) next debugging steps.\n\n
            """
    )

    /// Create a section-aware brief from a Markdown document.
    public static let markdownBrief = ChainPromptTemplate(
        mapPrompt: """
            Summarize this section of the document concisely. \
            Preserve the section heading and key points. Reference the section label.\n\n
            """,
        reducePrompt: """
            Combine these section summaries into a structured document brief. \
            Preserve the section hierarchy. Cite [Chunk N] for each section.\n\n
            """,
        stuffPrompt: """
            Create a concise brief of this document. Preserve the section structure \
            and key points from each section.\n\n
            """
    )
}

extension DocumentChain {
    /// Run the chain using a pre-built prompt template.
    public func run(
        _ text: String,
        template: ChainPromptTemplate,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions(),
        progress: ChainProgress? = nil
    ) async throws -> String {
        try await run(
            text,
            mapPrompt: template.mapPrompt,
            reducePrompt: template.reducePrompt,
            stuffPrompt: template.stuffPrompt,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress
        )
    }
}
