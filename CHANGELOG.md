# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added
- Token-aware prompt budgeting with `PromptBudgeter`, `TokenCounter` protocol, and `WordHeuristicTokenCounter`.
- `TokenAwareBackend` protocol for backends that expose context window size and token counting.
- Hierarchical reduce in `MapReduceChain` — recursive grouping and reduction when combined summaries exceed the context budget.
- Bounded concurrent map phase via `ChainExecutionOptions.maxConcurrentMapTasks`.
- `RetryPolicy` for configurable retry with delay on transient backend failures.
- Cooperative cancellation via `Task.checkCancellation()` at each map/reduce step.
- `ChainExecutionOptions` struct bundling concurrency, retry, reduce depth, and reserved output tokens.
- `ChainError.reduceDepthExceeded` for when hierarchical reduce hits the configured max depth.
- `MemoryPressure` utility for checking available memory before inference on iOS/macOS.
- `@Observable` `ChainRunner` for SwiftUI integration with reactive progress, result, and error state.
- `ChainProgress` async stream with phase reporting (stuffing, mapping, reducing, complete).
- `PromptTemplates` with domain-specific prompt bundles: `transcriptSummary`, `actionItems`, `voiceNoteSummary`, `lectureBrief`, `personalMemoActions`, `markdownBrief`, `logRootCause`.
- `TranscriptChunker` with adaptive speaker/temporal/topical attribution modes.
- `TranscriptAttributionMode` enum (`.auto`, `.speaker`, `.temporal`, `.topical`).
- Single-speaker voice note and lecture support — avoids repetitive speaker labels.
- `MarkdownHeadingChunker` for heading-boundary-aware Markdown splitting.
- `DocumentStructureChunker` for Markdown and PDF-extracted documents with heading path, page range, table, code block, and list preservation.
- `LogChunker` with diagnostic classification — classifies chunks by `LogChunkKind` (compiler error, linker error, test failure, stack trace, etc.).
- `AppleCrashReportChunker` for `.crash` and `.ips` crash report text with section detection, `CrashReportMetadata`, and symbolication status heuristic.
- `DiagnosticsMetadata` types: `LogChunkKind` (18 cases), `SymbolicationStatus`, `CrashReportMetadata`, `LogMetadata`.
- `DiagnosticSourceLabel` for human-readable `[Chunk N, kind, detail]` citation labels.
- Diagnostic prompt templates: `appleCrashTriage`, `simulatorLogRootCause`, `xcodeBuildFailure`, `testFailureAnalysis`.
- `logMetadata` field on `TextChunkMetadata` for diagnostic chunk metadata.
- `DocumentLocation` metadata with `pageRange`, `headingPath`, and `blockTypes`.
- `stuffPrompt` parameter on `DocumentChain` for customizing the single-call prompt separately from the reduce prompt.
- `GenerateParameters` exposed on `MLXBackend` for temperature, maxTokens, topP control.
- Source-grounded chunk labels (`[Chunk N]`) that propagate through hierarchical reduce levels.

### Added (expert review follow-up)
- Budget-aware map chunk sizing — `PromptBudgeter.availableTextBudget(...)` and automatic rechunking in `MapReduceChain` when specialized chunkers emit oversized chunks.
- Token-aware hierarchical reduce — `fitsInSingleReduce` and reduce grouping now use `PromptBudgeter`, including `TokenAwareBackend` when available.
- Budget-derived reduce grouping — `makeReduceGroups` accumulates summaries up to the context budget, capped by `maxReduceGroupSize`.
- `preserveOrder` option is now functional — `concurrentMap` returns results in completion order when `preserveOrder` is false, preserving correct chunk labels via `MapResult`.
- `ChunkPromptFormatter` for richer chunk labels using `DiagnosticSourceLabel` metadata.
- Conservative default `reservedOutputTokens` of 512 in `ChainExecutionOptions`.

### Changed
- README repositioned around "Swift-native long-document reasoning for private, on-device MLX apps."
- `AdaptiveChain` now considers prompt overhead (system prompt + task prompt + reserved output) when routing between stuff and map-reduce.
- `LogChunker` now classifies chunks with `LogMetadata` including diagnostic kind and severity.
- `ContextBudget` extended with `fitsInBudget(textWords:promptOverheadWords:reservedOutputWords:)` for prompt-overhead-aware checks.
- Architecture docs expanded with component graph, domain chunker descriptions, and production reliability notes.
- CI workflow streamlined to resolve, build, test on macOS 15.

### Changed (expert review follow-up)
- `MapReduceChain.fitsInSingleReduce` replaced with `PromptBudgeter`-based logic for token-accurate reduce checks.
- `maxReduceGroupSize` docs updated — actual group size is now budget-derived when a context budget exists.
- `MLXBackend` `@unchecked Sendable` comment now precisely describes lock protection and resource constraints.
- README and docs now accurately describe `.ips` support as lightweight JSON-like grouping, and PDF/table support as Markdown-style / best-effort.

### Fixed
- Long-document reduce overflow risk reduced with hierarchical reduce — prevents final prompt from exceeding context window.
- Single-speaker transcript attribution avoids repetitive "Speaker 1" labels when only one speaker is detected.

### Documentation
- Added adoption-focused README with workflow table, core concepts, and positioning sections.
- Added `docs/architecture.md` with Mermaid component graph.
- Added `docs/data-flow.md` with map-reduce sequence diagram.
- Added `docs/diagnostic-log-analysis-review.md` with implementation review and gap matrix.
- Added `docs/repo-adoption-metadata.md` with GitHub sidebar and topic recommendations.
- Added `docs/pr-summary.md` with detailed reviewer-friendly PR summary.
- Added `CHANGELOG.md`.
- Updated `CONTRIBUTING.md` with development setup, build, and test guidance.
