# mlx-swift-chain

[![CI](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml/badge.svg)](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml)

**Swift-native long-document reasoning for private, on-device MLX apps.**

Long-document chunking, map-reduce, prompt budgeting, and source-grounded summarization for MLX Swift apps on macOS and iOS.

Process meeting transcripts, voice notes, Markdown documents, PDF-extracted text, Xcode logs, crash reports, and field manuals locally on macOS and iOS using MLX Swift-compatible backends.

## Why This Exists

[MLX Swift](https://github.com/ml-explore/mlx-swift) and [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) handle model loading and inference. **mlx-swift-chain** handles everything above the model layer:

- **Chunking** — structure-aware splitting for transcripts, documents, logs, and crash reports
- **Prompt/context budgeting** — token-aware routing that accounts for prompt overhead and reserved output
- **Map-reduce** — process every chunk through the LLM, then combine results
- **Hierarchical reduce** — recursive reduction when combined summaries still exceed the context window
- **Retries and cancellation** — configurable retry policy and cooperative `Task` cancellation
- **Progress** — `AsyncStream`-based phase reporting (stuffing, mapping N/M, reducing, complete)
- **Source-grounded outputs** — chunk labels (`[Chunk N]`) and metadata propagate through reduce levels
- **SwiftUI integration** — `@Observable` `ChainRunner` for reactive progress, result, and error state

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/joelnishanth/mlx-swift-chain", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "MLXSwiftChain", package: "mlx-swift-chain"),
        ]
    ),
]
```

## Quick Start

```swift
import MLXSwiftChain
import MLXLMCommon

// 1. Set up a backend
let backend = MLXBackend(
    container: modelContainer,
    generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0.3)
)

// 2. Create an adaptive chain with a domain chunker
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(4096),
    chunker: TranscriptChunker(targetWords: 800, overlapTurns: 1)
)

// 3. Run with a prompt template
let summary = try await chain.run(
    transcript, template: PromptTemplates.transcriptSummary
)
```

For short texts, `AdaptiveChain` uses a single LLM call (zero overhead). For long texts, it automatically chunks the input, maps each chunk through the LLM, and reduces the results.

## Choose Your Workflow

| Use Case | Chunker | Templates | Value |
|---|---|---|---|
| Meeting transcript / voice note | `TranscriptChunker` | `transcriptSummary`, `actionItems`, `voiceNoteSummary`, `personalMemoActions` | Speaker/temporal/topic attribution preserves who said what and when |
| Markdown / PDF-extracted text | `DocumentStructureChunker` or `MarkdownHeadingChunker` | `markdownBrief`, `documentExecutiveSummary`, `documentStudyGuide` | Heading/page/source-aware summaries with `DocumentLocation` metadata |
| Xcode / simulator / crash logs | `LogChunker` or `AppleCrashReportChunker` | `logRootCause`, `appleCrashTriage`, `xcodeBuildFailure`, `testFailureAnalysis` | Source-grounded private developer triage with diagnostic classification |
| Offline field manuals / emergency docs | `DocumentStructureChunker` | `markdownBrief`, `documentExecutiveSummary` | On-device reference material processing with page/section tracking |
| Generic prose | `SentenceAwareChunker` | Custom prompt | Safe fallback for any text |

All templates are accessed via `PromptTemplates.<name>` and work with the `chain.run(_:template:)` convenience.

## Core Concepts

| Type | Role |
|---|---|
| `AdaptiveChain` | Auto-selects Stuff or MapReduce based on input length and prompt overhead. **Start here.** |
| `StuffChain` | Single LLM call when input fits in the context window. |
| `MapReduceChain` | Chunks, maps each through the LLM, reduces combined results. Supports hierarchical reduce for very large documents. |
| `TextChunk` | A chunk of text with word count, index, and metadata. |
| `TextChunkMetadata` | Source word ranges, timestamps, speaker labels, `DocumentLocation`, `LogMetadata`. |
| `PromptTemplates` | Pre-built map/reduce/stuff prompt bundles for common workflows. |
| `ChainRunner` | `@Observable` `@MainActor` class for SwiftUI integration. |
| `ChainProgress` | `AsyncStream<Update>` with phase info and elapsed time. |

## Choose a Chunker

| Chunker | Best For |
|---|---|
| `SentenceAwareChunker` | General text. Splits at sentence boundaries. **Default.** |
| `FixedSizeChunker` | Uniform chunks by word count with optional overlap. |
| `TranscriptChunker` | Meeting transcripts, voice notes, lectures, and memos. Auto-selects speaker, temporal, or topical attribution. |
| `MarkdownHeadingChunker` | Markdown documents. Splits at headings, preserves structure. Falls back to sentence splitting for large sections. |
| `LogChunker` | Xcode/simulator logs. Keeps stack traces intact, splits at timestamp boundaries. Classifies chunks by diagnostic kind. |
| `AppleCrashReportChunker` | Apple crash reports — translated `.crash` text and lightweight grouping for JSON-like `.ips` text. Preserves crashed thread, exception info, and binary images. Detects symbolication status. Does not fully interpret Apple's crash-report JSON schema. |
| `DocumentStructureChunker` | Markdown or PDF-extracted text. Preserves headings, page markers, Markdown-style tables, fenced code blocks, and lists. Populates `DocumentLocation` metadata. PDF parsing and OCR are out of scope — extract text first and preserve page markers when possible. |

All chunkers populate `TextChunkMetadata` with chunk index, source word ranges, discovered timestamps, and speaker labels.

## Examples

**Summarize a meeting transcript:**

```swift
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(4096),
    chunker: TranscriptChunker(targetWords: 800, overlapTurns: 1)
)

let summary = try await chain.run(
    transcript, template: PromptTemplates.transcriptSummary
)
```

**Summarize a voice note:**

```swift
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(4096),
    chunker: TranscriptChunker(targetWords: 800)
)

let summary = try await chain.run(
    voiceNote, template: PromptTemplates.voiceNoteSummary
)
```

**Extract actions from a personal memo:**

```swift
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(4096),
    chunker: TranscriptChunker(targetWords: 800, attributionMode: .temporal)
)

let actions = try await chain.run(
    memo, template: PromptTemplates.personalMemoActions
)
```

`TranscriptChunker` supports adaptive attribution. Multi-speaker meetings use speaker-turn attribution, preserving who said what. Single-speaker voice notes and lectures use timestamp or topic attribution to avoid repetitive "Speaker 1" labels while preserving source grounding. Use `TranscriptAttributionMode.auto` (the default) to let the chunker select the best strategy, or force a specific mode when you know your input format.

**Analyze Xcode logs for root cause:**

```swift
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(4096),
    chunker: LogChunker(targetWords: 1000)
)

let analysis = try await chain.run(
    logOutput, template: PromptTemplates.logRootCause
)
```

**Triage an Apple crash report:**

```swift
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(8192),
    chunker: AppleCrashReportChunker(targetWords: 1200)
)

let triage = try await chain.run(
    crashReportText, template: PromptTemplates.appleCrashTriage
)
```

**Create a section-aware brief from a Markdown document:**

```swift
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(4096),
    chunker: MarkdownHeadingChunker(targetWords: 1200)
)

let brief = try await chain.run(
    markdownDoc, template: PromptTemplates.markdownBrief
)
```

**Summarize a PDF-extracted document with page tracking:**

```swift
let chain = AdaptiveChain(
    backend: backend,
    contextBudget: .tokens(4096),
    chunker: DocumentStructureChunker(targetWords: 1200, preserveTables: true)
)

let summary = try await chain.run(
    pdfExtractedText, template: PromptTemplates.markdownBrief
)
// Each chunk's metadata.documentLocation includes pageRange, headingPath, and blockTypes
```

**Extract action items with source citations:**

```swift
let actions = try await chain.run(
    notes, template: PromptTemplates.actionItems
)
// Output includes [Chunk N] references for traceability
```

## SwiftUI Integration

```swift
import MLXSwiftChain

struct SummaryView: View {
    @State private var runner = ChainRunner()
    let chain: AdaptiveChain

    var body: some View {
        VStack {
            if runner.isRunning, let phase = runner.phase {
                ProgressView()
                Text(String(describing: phase))
            }
            if let result = runner.result {
                ScrollView { Text(result) }
            }
            Button("Summarize") {
                runner.run(chain, text: document,
                          template: PromptTemplates.transcriptSummary)
            }
        }
    }
}
```

## Production Options

**Token budgeting:** `AdaptiveChain` accounts for system prompt, task prompt, input text, and reserved output tokens when deciding stuff vs. map-reduce routing. Backends conforming to `TokenAwareBackend` enable exact token counting. Map chunks are also budget-aware — if a specialized chunker emits oversized chunks, they are automatically re-split to fit within the map prompt budget. Fallback re-chunking converts token budgets into conservative word targets before using word-based chunkers.

**Hierarchical reduce:** When `MapReduceChain` is initialized with a `contextBudget`, it automatically groups and recursively reduces summaries that exceed the budget, preventing context overflow on large documents. Reduce-fit checks use `PromptBudgeter` (including `TokenAwareBackend` when available), and group sizes are budget-derived up to the `maxReduceGroupSize` cap.

**Reserved output tokens:** `ChainExecutionOptions` reserves 512 tokens for model output by default, providing a conservative margin for budget calculations. Set to 0 for maximum-input / legacy behavior.

**Concurrency:** `ChainExecutionOptions(maxConcurrentMapTasks: 4)` enables bounded parallel mapping. Default is 1, which is optimal for on-device MLX inference. Set `preserveOrder: false` to receive map results in completion order rather than original chunk order.

**Retries:** `ChainExecutionOptions(retryPolicy: RetryPolicy(maxAttempts: 3, delayMilliseconds: 500))` adds retry logic, primarily useful for remote backends.

**Memory awareness:** `MemoryPressure.current()` checks available memory before inference — critical for iOS where jetsam kills memory-hungry processes.

| Option | Type | Purpose |
|---|---|---|
| `ChainExecutionOptions` | struct | Bundles concurrency, retry, reduce depth, and output token reservation |
| `RetryPolicy` | struct | Max attempts and delay for transient backend failures |
| `ContextBudget` | enum | `.words(N)` or `.tokens(N)` budget for adaptive routing |
| `PromptBudgeter` | struct | Checks whether system + task + text + reserved output fits in budget |
| `TokenCounter` | protocol | Pluggable token counting; ships with `WordHeuristicTokenCounter` |
| `TokenAwareBackend` | protocol | Extends `LLMBackend` with context window size and token counter |
| `MemoryPressure` | enum | `.current()` returns `.ok`, `.warning`, or `.critical` based on available memory |

## Progress Reporting

```swift
let progress = ChainProgress()

Task {
    for await update in progress.updates {
        switch update.phase {
        case .stuffing: print("Processing in single call...")
        case .mapping(let step, let total): print("Chunk \(step)/\(total)...")
        case .reducing: print("Combining results...")
        case .complete: print("Done in \(update.elapsedTime)")
        }
    }
}

let result = try await chain.run(text, mapPrompt: "...", reducePrompt: "...", progress: progress)
```

## Diagnostic Log Analysis

mlx-swift-chain can chunk and summarize long diagnostic logs entirely on-device. Use `AppleCrashReportChunker` for translated `.crash` text and lightweight grouping of JSON-like `.ips` text, and `LogChunker` for simulator logs, Xcode build output, and test failures. The crash chunker does not fully interpret Apple's crash-report JSON schema.

For diagnostic workflows, `ChunkPromptFormatter.labeledText(for:)` produces richer chunk labels using `DiagnosticSourceLabel` metadata when available (e.g. `[Chunk 2, exceptionInfo, EXC_BAD_ACCESS]`).

| Input | Chunker | Prompt Template |
|---|---|---|
| Apple crash report (`.crash` / `.ips`) | `AppleCrashReportChunker` | `PromptTemplates.appleCrashTriage` |
| Simulator / Console.app logs | `LogChunker` | `PromptTemplates.simulatorLogRootCause` |
| Xcode build failure | `LogChunker` | `PromptTemplates.xcodeBuildFailure` |
| XCTest failure | `LogChunker` | `PromptTemplates.testFailureAnalysis` |

Each chunk carries `LogMetadata` with a `LogChunkKind` (e.g. `.crashedThread`, `.swiftCompilerError`, `.testFailure`), process name, severity, and — for crash reports — full `CrashReportMetadata` including exception type, symbolication status, and crashed thread number.

## Why Not Just Truncate?

Local LLMs have limited context windows (e.g. 8,192 tokens for Gemma models). Long documents — research papers, legal contracts, codebases, transcripts — easily exceed this limit. Naive prefix truncation discards most of the content:

| Document Size | Prefix Truncation Coverage | mlx-swift-chain Model-Visible Coverage |
|---|---|---|
| ~2,500 words | 100% | 100% |
| ~5,000 words | ~60% | **100%** |
| ~10,000 words | ~30% | **100%** |
| ~20,000 words | **7%** | **100%** |

Coverage here means input/model-visible coverage across chunks, not guaranteed perfect retention in the final reduced answer.

- **Truncation loses evidence.** A crash report's root cause may be on page 5. A contract's liability clause may be in the appendix. Truncation throws it away.
- **Map-reduce improves coverage.** Every chunk is processed by the LLM. Nothing is silently dropped.
- **Hierarchical reduce prevents overflow.** When combined summaries still exceed the context window, recursive grouping and reduction keeps the final prompt within budget.
- **Source labels help verification.** `[Chunk N]` references let users trace claims back to the original text.

## Why Not a Generic LangChain?

- **Apple-native Swift package.** No Python bridge, no HTTP overhead, no serialization layer. Just Swift protocols and structured concurrency.
- **MLX-first / local-backend-first.** Designed for on-device inference on Apple Silicon with `MLXBackend`, not cloud API wrappers.
- **Offline and private.** All processing can stay on-device. No telemetry, no network calls unless your backend makes them.
- **SwiftUI-ready progress.** `ChainRunner` is `@Observable` and `@MainActor` — drop it into a SwiftUI view.
- **Domain chunkers.** Purpose-built for transcripts, documents, logs, and crash reports — not generic text splitting.
- **One problem, solved well.** This is not a framework for agents, tool use, vector stores, or retrieval. It handles long-document reasoning above the model layer.

## Privacy

MLX Swift Chain analyzes user-provided text. It does not acquire logs, read files, call Xcode APIs, or transmit data by itself. Whether inference stays local depends on the backend you provide.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the component graph and [docs/data-flow.md](docs/data-flow.md) for the map-reduce sequence diagram.

## Requirements

- macOS 14.0+ / iOS 17.0+
- Swift 6.1+
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) 3.31.3+

## Links

- [CHANGELOG](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Architecture](docs/architecture.md)
- [Data Flow](docs/data-flow.md)
- [Diagnostic Log Analysis Review](docs/diagnostic-log-analysis-review.md)
- [Tests](Tests/MLXSwiftChainTests/)

## License

Apache 2.0 — see [LICENSE](LICENSE).
