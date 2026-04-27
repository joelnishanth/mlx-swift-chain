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

    /// Summarize a single-speaker voice note, solo brainstorm, or founder memo.
    public static let voiceNoteSummary = ChainPromptTemplate(
        mapPrompt: """
            Summarize this section of a voice note. Preserve key timestamps, topics, \
            decisions, open questions, and important details. \
            Reference the section label at the top.\n\n
            """,
        reducePrompt: """
            Combine these voice note section summaries into a coherent summary \
            organized by topic. Cite [Chunk N] labels when referencing specific sections. \
            Preserve important timestamps for verification.\n\n
            """,
        stuffPrompt: """
            Summarize this voice note. Organize by topic. Preserve key timestamps, \
            decisions, open questions, and important details.\n\n
            """
    )

    /// Create a structured brief from a lecture, course segment, or talk.
    public static let lectureBrief = ChainPromptTemplate(
        mapPrompt: """
            Extract key concepts, definitions, examples, claims, and timestamps \
            from this lecture section. Reference the section label at the top.\n\n
            """,
        reducePrompt: """
            Organize these lecture section notes into a structured lecture brief \
            with key takeaways, concepts, examples, and review questions. \
            Cite [Chunk N] for each section.\n\n
            """,
        stuffPrompt: """
            Create a structured lecture brief from this transcript. Include key \
            concepts, definitions, examples, and review questions.\n\n
            """
    )

    /// Triage an Apple crash report (.crash / .ips / Console paste).
    public static let appleCrashTriage = ChainPromptTemplate(
        mapPrompt: """
            Analyze this Apple crash report section. Extract exception type, \
            termination reason, crashed thread clues, suspicious app frames, \
            diagnostic messages, symbolication quality, memory access clues, \
            and source chunk IDs. Do not invent missing details.\n\n
            """,
        reducePrompt: """
            Create a concise Apple crash triage report. Include likely root cause, \
            crash mechanism, exception type, termination reason, crashed thread, \
            relevant app frames, symbolication warning if needed, recommended Xcode \
            debugging tools, next steps, and source chunk IDs. \
            For EXC_BAD_ACCESS, SIGSEGV, or SIGBUS, consider Address Sanitizer and \
            Malloc debugging tools. For threading issues, consider Thread Sanitizer or \
            Main Thread Checker. If the report is unsymbolicated or partially \
            symbolicated, note that strong conclusions may be unreliable and recommend \
            dSYM verification. Do not claim certainty when evidence is incomplete. \
            If evidence is insufficient, say what is missing.\n\n
            """,
        stuffPrompt: """
            Triage this Apple crash report. Identify the likely root cause, crash \
            mechanism (exception type, termination reason, crashed thread), suspicious \
            app frames, symbolication quality, and recommended next debugging steps. \
            For EXC_BAD_ACCESS, SIGSEGV, or SIGBUS, consider Address Sanitizer and \
            Malloc debugging tools. For threading issues, consider Thread Sanitizer or \
            Main Thread Checker. If the report is unsymbolicated or partially \
            symbolicated, note that strong conclusions may be unreliable and recommend \
            dSYM verification. Do not claim certainty when evidence is incomplete.\n\n
            """
    )

    /// Root-cause analysis for simulator or Console.app logs.
    public static let simulatorLogRootCause = ChainPromptTemplate(
        mapPrompt: """
            Analyze this simulator or Console log section. Extract errors, warnings, \
            timestamps, process, subsystem, category, repeated patterns, and likely \
            failure signals. Preserve source chunk IDs.\n\n
            """,
        reducePrompt: """
            Create a root-cause hypothesis from these simulator logs. Group by process \
            or subsystem, identify the first meaningful error, repeated failures, likely \
            cause, and next debugging steps. Preserve source chunk IDs.\n\n
            """,
        stuffPrompt: """
            Analyze these simulator or Console logs. Identify the first meaningful error, \
            group by process or subsystem, find repeated patterns, determine the likely \
            root cause, and suggest next debugging steps.\n\n
            """
    )

    /// Diagnose Xcode build failures (compiler, linker, signing).
    public static let xcodeBuildFailure = ChainPromptTemplate(
        mapPrompt: """
            Analyze this Xcode build section. Extract compiler errors, linker errors, \
            failing files, line numbers, commands, missing dependencies, signing issues, \
            and source chunk IDs.\n\n
            """,
        reducePrompt: """
            Create a build failure diagnosis. Include primary error, affected files, \
            likely cause, fix suggestions, and source chunk IDs. Do not over-index on \
            secondary cascading errors.\n\n
            """,
        stuffPrompt: """
            Diagnose this Xcode build failure. Identify the primary error, affected \
            files, likely cause, and fix suggestions. Ignore secondary cascading errors \
            when a single root cause is apparent.\n\n
            """
    )

    /// Analyze XCTest failures with assertion details and reproduction notes.
    public static let testFailureAnalysis = ChainPromptTemplate(
        mapPrompt: """
            Analyze this test failure section. Extract failing test names, assertions, \
            expected and actual values, file and line references, logs, and source \
            chunk IDs.\n\n
            """,
        reducePrompt: """
            Create a test failure analysis. Include failing tests, assertion mismatches, \
            likely cause, reproduction notes, and next debugging steps. Preserve source \
            chunk IDs.\n\n
            """,
        stuffPrompt: """
            Analyze these test failures. List failing tests with assertion mismatches, \
            identify the likely cause, and suggest reproduction and debugging steps.\n\n
            """
    )

    /// Extract tasks and actions from a personal memo or to-do capture.
    public static let personalMemoActions = ChainPromptTemplate(
        mapPrompt: """
            Extract tasks, reminders, ideas, decisions, deadlines, people, and \
            follow-ups from this memo section. Reference the section label at the top.\n\n
            """,
        reducePrompt: """
            Merge these memo notes into a prioritized action list and a concise list \
            of key ideas. Deduplicate repeated actions and preserve timestamps where \
            useful. Cite [Chunk N] for each item's source.\n\n
            """,
        stuffPrompt: """
            Extract all tasks, reminders, ideas, decisions, and follow-ups from this \
            memo. Organize into a prioritized action list and key ideas.\n\n
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

    /// Stream chain execution using a pre-built prompt template.
    public func stream(
        _ text: String,
        template: ChainPromptTemplate,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions(),
        progress: ChainProgress? = nil
    ) -> AsyncThrowingStream<ChainEvent, Error> {
        stream(
            text,
            mapPrompt: template.mapPrompt,
            reducePrompt: template.reducePrompt,
            stuffPrompt: template.stuffPrompt,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress
        )
    }

    /// Run the chain using a pre-built prompt template and return rich metadata.
    public func runWithMetadata(
        _ text: String,
        template: ChainPromptTemplate,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions(),
        progress: ChainProgress? = nil
    ) async throws -> ChainResult {
        try await runWithMetadata(
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
