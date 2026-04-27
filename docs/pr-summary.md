# PR Summary: Adoption-ready long-document reasoning for MLX Swift apps

## Overview

This PR evolves mlx-swift-chain from a small proof-of-concept document chain package into a more complete Swift-native long-document reasoning layer for private, on-device MLX apps.

## Why This Matters

Swift and MLX developers need app-level primitives above raw inference. Long transcripts, documents, logs, and manuals exceed context windows. Naive truncation loses critical evidence — a crash report's root cause may be deep in the stack trace, a contract's liability clause may be in the appendix, and a meeting's key decision may come in the final minutes.

Local/offline workflows need deterministic chunking, budgeting, progress, retries, and source labels — none of which are the model's job. This PR adds those primitives while keeping the package lightweight, Swift-native, and backward-compatible.

## What Changed

### 1. Core chain reliability

- **Prompt-overhead-aware routing:** `AdaptiveChain` now accounts for system prompt, task prompt, and reserved output tokens when deciding stuff vs. map-reduce. Previously only input word count was considered.
- **Token-aware budgeting:** `PromptBudgeter` resolves token vs. word counting from `TokenAwareBackend` or heuristics. `TokenCounter` protocol and `WordHeuristicTokenCounter` ship as defaults.
- **Hierarchical reduce:** `MapReduceChain` recursively groups and reduces summaries when combined output exceeds the context budget, preventing final-prompt overflow on large documents.
- **Bounded map concurrency:** `ChainExecutionOptions.maxConcurrentMapTasks` limits parallel map execution. Default is 1 (optimal for on-device MLX), configurable for remote backends.
- **Retry policy:** `RetryPolicy` with configurable max attempts and delay, primarily for transient remote backend failures.
- **Cooperative cancellation:** `Task.checkCancellation()` at each map and reduce step.
- **Memory pressure:** `MemoryPressure.current()` checks available memory before inference — critical on iOS.
- **`ChainExecutionOptions`:** Single struct bundling concurrency, retry, reduce depth, and reserved output tokens.
- **`ChainError`:** Typed error (`reduceDepthExceeded`) when hierarchical reduce hits the configured max depth.

### 2. Domain chunkers

- **`TranscriptChunker`:** Speaker-turn-based chunking for meeting transcripts. Now supports adaptive attribution modes: `.speaker` for multi-speaker meetings, `.temporal` for timestamped voice notes, `.topical` for heading-segmented content, and `.auto` to select automatically. Single-speaker inputs avoid repetitive "Speaker 1" labels.
- **`MarkdownHeadingChunker`:** Splits at ATX heading boundaries, preserves heading context, falls back to sentence splitting for oversized sections.
- **`DocumentStructureChunker`:** Deterministic Markdown/PDF-extracted document parser. Preserves headings, page ranges, tables, code blocks, lists, and block quotes. Populates `DocumentLocation` metadata with `pageRange`, `headingPath`, and `blockTypes`.
- **`LogChunker`:** Enhanced with diagnostic classification. Classifies chunks by `LogChunkKind` (18 cases: `.swiftCompilerError`, `.linkerError`, `.testFailure`, `.stackTrace`, etc.) and attaches `LogMetadata` with kind, severity, process name, and timestamps.
- **`AppleCrashReportChunker`:** Parses `.crash` and `.ips` crash report text into structured sections (header, exception info, crashed thread, other threads, binary images). Extracts `CrashReportMetadata` with exception type, signal, codes, crashed thread number, hardware model, OS version, and symbolication status heuristic.

### 3. Prompt templates

| Template | Use Case |
|---|---|
| `transcriptSummary` | Meeting transcript summarization |
| `actionItems` | Extract action items with source citations |
| `voiceNoteSummary` | Single-speaker voice note summarization |
| `lectureBrief` | Lecture/talk summarization |
| `personalMemoActions` | Personal memo action extraction |
| `markdownBrief` | Markdown/document section-aware brief |
| `logRootCause` | Generic log root cause analysis |
| `appleCrashTriage` | Apple crash report triage with symbolication guidance |
| `simulatorLogRootCause` | Simulator/Console.app log analysis |
| `xcodeBuildFailure` | Xcode build failure analysis |
| `testFailureAnalysis` | XCTest failure analysis |

### 4. SwiftUI integration

- **`ChainRunner`:** `@Observable` `@MainActor` class that wraps chain execution with reactive `phase`, `isRunning`, `result`, and `error` state. Supports both manual prompts and template-based runs with `cancel()`.

### 5. MLX backend integration

- **`MLXBackend`:** Now exposes `GenerateParameters` as a public property. Accepts `maxTokens`, `temperature`, `topP`, and other `MLXLMCommon` sampling controls at init.
- **`TokenAwareBackend`:** Protocol extending `LLMBackend` with `contextWindowTokens` and `tokenCounter` for exact budget checks.

### 6. Diagnostics / developer tooling

- **`LogChunkKind`** (18 cases): `.crashHeader`, `.exceptionInfo`, `.crashedThread`, `.otherThread`, `.binaryImages`, `.swiftCompilerError`, `.linkerError`, `.buildFailure`, `.testFailure`, `.runtimeWarning`, `.stackTrace`, `.simulatorLog`, `.processLifecycle`, `.xcodeBuildSystem`, `.assertionFailure`, `.memoryWarning`, `.signalHandler`, `.unknown`.
- **`SymbolicationStatus`:** `.fullySymbolicated`, `.partiallySymbolicated`, `.unsymbolicated`, `.unknown`.
- **`CrashReportMetadata`:** 14 fields including exception type, signal, codes, crashed thread, hardware, OS, bundle ID, version, and symbolication status.
- **`LogMetadata`:** Kind, severity, process name, PID, subsystem, timestamps, and optional `CrashReportMetadata`.
- **`DiagnosticSourceLabel`:** Generates `[Chunk N, kind, detail]` labels for citing diagnostic chunks in LLM outputs.

### 7. Docs and adoption

- README repositioned around "Swift-native long-document reasoning for private, on-device MLX apps."
- Added "Choose Your Workflow" table, "Core Concepts" section, "Why Not Just Truncate?", "Why Not a Generic LangChain?", and standalone privacy note.
- Architecture docs with Mermaid component graph and data-flow sequence diagram.
- Diagnostic log analysis implementation review with gap matrix and risk assessment.
- Adoption metadata guidance for GitHub sidebar, topics, and social preview.
- CHANGELOG with categorized additions.
- Updated CONTRIBUTING.md with development setup and domain contribution areas.

### 8. Tests and validation

```
swift package resolve   # resolves mlx-swift-lm dependency
swift build             # 0 errors, 0 warnings
swift test              # 96 tests, 0 failures
```

**Test coverage by area:**

| Area | Tests | Suite |
|---|---|---|
| Chain routing (stuff vs map-reduce) | 12 | AdaptiveChainTests |
| Map-reduce, hierarchical reduce, concurrency | 13 | MapReduceChainTests |
| Retry policy | 3 | RetryTests |
| Benchmark coverage | 1 | BenchmarkCoverageTests |
| FixedSize, SentenceAware, Transcript, Markdown, Log chunkers | 34 | ChunkerTests |
| DocumentStructureChunker | 14 | ChunkerTests |
| Log diagnostics (classification, templates) | 10 | LogDiagnosticsTests |
| AppleCrashReportChunker | 9 | AppleCrashReportChunkerTests |

## Compared with Current Upstream

| Area | Current upstream | This PR | Why it matters |
|---|---|---|---|
| Context routing | Word-count only | Prompt-overhead-aware with token hooks | Prevents accidental stuff on inputs that fit by word count but overflow with prompt overhead |
| Long-document reduce | Single reduce pass | Hierarchical reduce with configurable depth | Prevents context overflow when combined summaries exceed window |
| Token budgeting | Word-count heuristic | `TokenCounter` protocol, `PromptBudgeter`, `TokenAwareBackend` | More accurate budget checks for languages and prompts where words are a poor token proxy |
| Transcript handling | Basic chunking | Speaker/temporal/topical attribution, single-speaker support | Better for voice notes, lectures, memos — not just multi-speaker meetings |
| Document summarization | No structure-aware chunker | `DocumentStructureChunker` with page/heading/table/code preservation | Heading-path and page-range metadata for grounded document summaries |
| Log/crash analysis | Basic log chunking | Diagnostic classification, crash report parser, symbolication detection | Strong developer adoption wedge — private on-device triage |
| SwiftUI integration | None | `ChainRunner` with reactive state | Easier app integration |
| MLX generation options | Fixed parameters | Exposed `GenerateParameters` | Control temperature, maxTokens, topP per call |
| Tests | ~30 | 96 | 3x coverage increase |
| Docs/adoption | Basic | Adoption-focused README, architecture, changelog, contribution guide | Easier for MLX/Swift developers to understand and adopt |

## Compatibility

- Public APIs are additive where possible. No existing init signatures were changed.
- Existing `run` overloads remain supported.
- Existing chunkers (`FixedSizeChunker`, `SentenceAwareChunker`) continue to work unchanged.
- All pre-existing tests continue to pass.
- New metadata fields default to `nil` — existing code that ignores metadata is unaffected.

## Limitations

- Does not parse PDFs directly or perform OCR. Input is user-provided text.
- Does not acquire logs from Xcode, devices, or Console.app.
- Does not call Xcode APIs or private Apple frameworks.
- Does not guarantee model quality — output quality depends on the backend model and prompt.
- Source labels help verification but do not replace human review for crash/emergency analysis.
- `AppleCrashReportChunker` uses line-level regex for `.ips` format, not a full JSON parser.

## Suggested Review Order

1. **README and docs** — positioning and adoption framing
2. **Public metadata/API additions** — `TextChunkMetadata`, `LogMetadata`, `CrashReportMetadata`, `DiagnosticSourceLabel`
3. **Core chain behavior** — `AdaptiveChain`, `MapReduceChain`, `PromptBudgeter`, `ChainExecutionOptions`
4. **Domain chunkers** — `TranscriptChunker`, `DocumentStructureChunker`, `LogChunker`, `AppleCrashReportChunker`
5. **Prompt templates** — `PromptTemplates` additions
6. **Tests** — all test suites
