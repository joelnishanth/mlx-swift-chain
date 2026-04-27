import Foundation
import Testing
@testable import MLXSwiftChain

/// Compile-time canary: every public type, protocol, and key method is referenced here.
/// If any public symbol is accidentally removed or renamed, this file will fail to compile.
@Suite("Public API Surface")
struct PublicAPITests {

    // MARK: - Protocols

    @Test func protocols_exist() {
        // LLMBackend
        let _: any LLMBackend.Type = MockLLMBackend.self

        // TokenAwareBackend
        let _: any TokenAwareBackend.Type = MockTokenAwareBackend.self

        // DocumentChain
        let _: any DocumentChain.Type = StuffChain.self

        // TextChunker
        let _: any TextChunker.Type = FixedSizeChunker.self

        // TokenCounter
        let _: any TokenCounter.Type = WordHeuristicTokenCounter.self
    }

    // MARK: - Chain Types

    @Test func stuffChain_api() {
        let backend = MockLLMBackend()
        let chain = StuffChain(backend: backend)
        #expect(chain.backend is MockLLMBackend)
    }

    @Test func mapReduceChain_api() {
        let backend = MockLLMBackend()
        let chunker = FixedSizeChunker(maxWords: 100)

        let chain1 = MapReduceChain(backend: backend, chunker: chunker)
        #expect(chain1.contextBudget == nil)

        let chain2 = MapReduceChain(backend: backend, chunker: chunker, contextBudget: .words(500))
        #expect(chain2.contextBudget != nil)
    }

    @Test func adaptiveChain_api() {
        let backend = MockLLMBackend()
        let chain1 = AdaptiveChain(backend: backend)
        #expect(chain1.contextBudgetWords > 0)

        let chain2 = AdaptiveChain(backend: backend, contextBudgetWords: 2000)
        #expect(chain2.contextBudgetWords == 2000)

        let chain3 = AdaptiveChain(backend: backend, contextBudget: .tokens(4096))
        #expect(chain3.contextBudget.estimatedWordLimit > 0)
    }

    // MARK: - Chain Execution Options

    @Test func chainExecutionOptions_defaults() {
        let opts = ChainExecutionOptions()
        #expect(opts.reservedOutputTokens == 512)
        #expect(opts.maxReduceGroupSize == 8)
        #expect(opts.maxReduceDepth == 5)
        #expect(opts.maxConcurrentMapTasks == 1)
        #expect(opts.preserveOrder == true)
        #expect(opts.retryPolicy == .none)
    }

    // MARK: - Context Budget

    @Test func contextBudget_variants() {
        let words = ContextBudget.words(1000)
        #expect(words.estimatedWordLimit == 1000)
        #expect(words.fitsInBudget(textWords: 500, promptOverheadWords: 100, reservedOutputWords: 100))

        let tokens = ContextBudget.tokens(4096, estimatedTokensPerWord: 1.33)
        #expect(tokens.estimatedWordLimit > 0)
    }

    // MARK: - Chunkers

    @Test func allChunkers_conform() {
        let _: any TextChunker = FixedSizeChunker(maxWords: 100)
        let _: any TextChunker = SentenceAwareChunker(targetWords: 100)
        let _: any TextChunker = MarkdownHeadingChunker(targetWords: 100)
        let _: any TextChunker = TranscriptChunker(targetWords: 100)
        let _: any TextChunker = LogChunker(targetWords: 100)
        let _: any TextChunker = DocumentStructureChunker(targetWords: 100)
        let _: any TextChunker = AppleCrashReportChunker(targetWords: 100)
    }

    // MARK: - TextChunk and Metadata

    @Test func textChunk_structure() {
        let chunk = TextChunk(text: "hello world", index: 0, wordCount: 2)
        #expect(chunk.text == "hello world")
        #expect(chunk.index == 0)
        #expect(chunk.wordCount == 2)
        #expect(chunk.metadata.chunkIndex == 0)
        #expect(chunk.metadata.sourceWordRange == 0..<2)
    }

    @Test func textChunkMetadata_allFields() {
        let ts = TimestampRange(start: "00:00", end: "01:00")
        let pr = PageRange(start: 1, end: 5)
        let dl = DocumentLocation(pageRange: pr, headingPath: ["H1"], primaryBlockType: .heading)
        let meta = TextChunkMetadata(
            chunkIndex: 0,
            sourceWordRange: 0..<100,
            timestamps: ["00:00"],
            speakerLabels: ["Alice"],
            attributionType: .speaker,
            topicLabel: "Intro",
            timestampRange: ts,
            documentLocation: dl
        )
        #expect(meta.timestamps.count == 1)
        #expect(meta.speakerLabels == ["Alice"])
        #expect(meta.attributionType == .speaker)
        #expect(meta.documentLocation?.headingPath == ["H1"])
    }

    @Test func documentBlockTypes_exist() {
        let types: [DocumentBlockType] = [
            .heading, .paragraph, .list, .table, .codeBlock,
            .blockQuote, .figureCaption, .footnote, .pageBreak,
            .thematicBreak, .unknown
        ]
        #expect(types.count == 11)
    }

    // MARK: - Progress

    @Test func chainProgress_phases() {
        let phases: [ChainProgress.Phase] = [
            .stuffing,
            .mapping(step: 1, of: 3),
            .reducing,
            .complete
        ]
        #expect(phases.count == 4)

        let update = ChainProgress.Update(phase: .stuffing, elapsedTime: .seconds(1))
        #expect(update.phase == .stuffing)
    }

    // MARK: - Prompt Templates

    @Test func promptTemplates_exist() {
        let templates: [ChainPromptTemplate] = [
            PromptTemplates.transcriptSummary,
            PromptTemplates.actionItems,
            PromptTemplates.logRootCause,
            PromptTemplates.markdownBrief,
            PromptTemplates.voiceNoteSummary,
            PromptTemplates.lectureBrief,
            PromptTemplates.appleCrashTriage,
            PromptTemplates.simulatorLogRootCause,
            PromptTemplates.xcodeBuildFailure,
            PromptTemplates.testFailureAnalysis,
            PromptTemplates.personalMemoActions,
        ]
        for t in templates {
            #expect(!t.mapPrompt.isEmpty)
            #expect(!t.reducePrompt.isEmpty)
        }
    }

    // MARK: - Token Counter

    @Test func wordHeuristicTokenCounter_api() {
        let counter = WordHeuristicTokenCounter(tokensPerWord: 1.5)
        #expect(counter.tokensPerWord == 1.5)
        let count = counter.countTokens("hello world")
        #expect(count > 0)
    }

    // MARK: - Error Types

    @Test func chainError_equatable() {
        let e1 = ChainError.reduceDepthExceeded(maxDepth: 5)
        let e2 = ChainError.reduceDepthExceeded(maxDepth: 5)
        #expect(e1 == e2)
        #expect(e1.errorDescription != nil)
    }

    // MARK: - Retry Policy

    @Test func retryPolicy_api() {
        let none = RetryPolicy.none
        #expect(none.maxAttempts == 1)
        #expect(none.delayMilliseconds == 0)

        let custom = RetryPolicy(maxAttempts: 3, delayMilliseconds: 100)
        #expect(custom.maxAttempts == 3)
        #expect(custom != none)
    }

    // MARK: - MemoryPressure

    @Test func memoryPressure_api() {
        let ok = MemoryPressure.ok
        #expect(ok.shouldProceed)
        #expect(ok.availableMB == nil)

        let warning = MemoryPressure.warning(availableMB: 500)
        #expect(warning.shouldProceed)
        #expect(warning.availableMB == 500)

        let critical = MemoryPressure.critical(availableMB: 50)
        #expect(!critical.shouldProceed)
    }

    // MARK: - Diagnostic Types

    @Test func diagnosticTypes_exist() {
        let label = DiagnosticSourceLabel.label(for: TextChunk(text: "x", index: 0, wordCount: 1))
        #expect(!label.isEmpty)

        let formatted = ChunkPromptFormatter.labeledText(for: TextChunk(text: "x", index: 0, wordCount: 1))
        #expect(!formatted.isEmpty)
    }

    // MARK: - PromptBudgeter

    @Test func promptBudgeter_api() {
        let backend = MockLLMBackend()
        let budgeter = PromptBudgeter(backend: backend, budget: .words(1000))
        #expect(budgeter.budgetLimit == 1000)
        #expect(budgeter.count("hello world") > 0)
        let fits = budgeter.fits(systemPrompt: nil, taskPrompt: "test", text: "short", reservedOutputTokens: 0)
        #expect(fits)
        let available = budgeter.availableTextBudget(systemPrompt: nil, taskPrompt: "test", reservedOutputTokens: 0)
        #expect(available > 0)
    }

    // MARK: - Transcript Attribution

    @Test func transcriptAttributionMode_variants() {
        let modes: [TranscriptAttributionMode] = [.auto, .speaker, .temporal, .topical]
        #expect(modes.count == 4)
    }

    // MARK: - New Production APIs (Phase 2-8)

    @Test func chainResult_structure() {
        let result = ChainResult(text: "output", sourceChunks: [], metrics: nil)
        #expect(result.text == "output")
        #expect(result.sourceChunks.isEmpty)
        #expect(result.metrics == nil)
    }

    @Test func chainMetrics_structure() {
        let m = ChainMetrics(chunkCount: 5, mapCallCount: 5, reduceCallCount: 1,
                            elapsedTime: .seconds(10))
        #expect(m.chunkCount == 5)
        #expect(m.estimatedInputTokens == nil)
    }

    @Test func chainEvent_cases() {
        let progress = ChainProgress.Update(phase: .stuffing, elapsedTime: .zero)
        let result = ChainResult(text: "x")
        let events: [ChainEvent] = [
            .chunk("token"),
            .progress(progress),
            .result(result)
        ]
        #expect(events.count == 3)
    }

    @Test func promptStyle_variants() {
        let styles: [PromptStyle] = [.raw, .delimited]
        #expect(styles.count == 2)
    }

    @Test func chainPromptBuilder_exists() {
        let chunk = TextChunk(text: "x", index: 0, wordCount: 1)
        let _ = ChainPromptBuilder.mapPrompt(task: "T:", chunk: chunk, totalChunks: 1, style: .raw)
        let _ = ChainPromptBuilder.reducePrompt(task: "T:", summaries: ["A"], totalSections: 1, style: .raw)
        let _ = ChainPromptBuilder.stuffPrompt(task: "T:", text: "x", metadata: nil, style: .raw)
    }

    @Test func streamingLLMBackend_protocol() {
        let _: any StreamingLLMBackend.Type = MockStreamingBackend.self
    }

    @Test func codeBlockAwareChunker_conforms() {
        let _: any TextChunker = CodeBlockAwareChunker(targetWords: 100)
    }

    @Test func structuredOutputError_cases() {
        let err1 = StructuredOutputError.invalidJSON(
            underlying: NSError(domain: "", code: 0), rawText: "bad"
        )
        #expect(err1.errorDescription != nil)
    }

    @Test func chainExecutionOptions_promptStyle() {
        let opts = ChainExecutionOptions(promptStyle: .delimited)
        #expect(opts.promptStyle == .delimited)

        let defaultOpts = ChainExecutionOptions()
        #expect(defaultOpts.promptStyle == .raw)
    }

    @Test func progressUpdate_partialMetrics() {
        let update = ChainProgress.Update(
            phase: .stuffing, elapsedTime: .seconds(1),
            partialMetrics: ChainMetrics()
        )
        #expect(update.partialMetrics != nil)
    }
}
