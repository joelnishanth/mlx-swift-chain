## Summary

This PR evolves `mlx-swift-chain` into a more complete Swift-native long-document reasoning layer for private, on-device MLX apps.

It adds production-oriented primitives for long transcripts, Markdown/PDF-extracted docs, Xcode/simulator logs, crash reports, and offline reference material while preserving the package's lightweight Swift-first design.

## Why this matters

MLX Swift and MLX Swift LM provide the model/runtime layer. This package now provides the app workflow layer above inference:

- structure-aware chunking
- prompt/context budgeting
- adaptive stuff vs map-reduce routing
- hierarchical reduce for large inputs
- progress and SwiftUI integration
- retry/cancellation options
- source-grounded prompt templates
- diagnostics-focused chunking for Swift developer workflows

## Highlights

### Core reliability
- Added prompt-overhead-aware chain routing.
- Added token-aware budgeting hooks (`TokenCounter`, `PromptBudgeter`, `TokenAwareBackend`).
- Added hierarchical reduce to prevent final-prompt overflow.
- Added bounded concurrent map execution.
- Added retry policy and cooperative cancellation.
- Added memory pressure utility for on-device workflows.

### Domain workflows
- Improved transcript handling for meetings, voice notes, lectures, and memos with adaptive attribution modes.
- Added `DocumentStructureChunker` for Markdown/PDF-extracted documents with heading, page, table, and code block preservation.
- Added `AppleCrashReportChunker` for `.crash`/`.ips` crash report analysis with section detection, metadata extraction, and symbolication heuristic.
- Enhanced `LogChunker` with diagnostic classification (18 `LogChunkKind` cases) and severity metadata.
- Added `DiagnosticSourceLabel` for human-readable chunk citations.

### Prompt templates
- Added templates for transcript summaries, action items, voice notes, lectures, personal memos, document briefs, crash triage, simulator root cause, build failures, and test failures.

### SwiftUI / app integration
- Added `ChainRunner` for reactive progress, result, and error state in SwiftUI apps.

### Docs and adoption
- Repositioned README around "Swift-native long-document reasoning for private, on-device MLX apps."
- Added workflow table, core concepts, and explicit positioning sections.
- Added adoption metadata guidance, PR summary, and changelog.

## Compared with current repo

| Area | Current upstream | This PR | Why it matters |
|---|---|---|---|
| Long input handling | Basic stuff/map-reduce | Adaptive routing with prompt budgeting and hierarchical reduce | Safer for large docs |
| Token/context budgeting | Word-count oriented | Token-aware hooks and prompt overhead accounting | Reduces context overflow |
| Transcript support | Basic transcript chunking | Meeting + single-speaker voice note/memo support with adaptive attribution | Better voice note and lecture workflows |
| Document summarization | No structure-aware chunker | `DocumentStructureChunker` with page/heading/Markdown-table preservation | Grounded document summaries |
| Logs/crash | Generic log chunking | Diagnostic classification and crash-report support | Strong developer adoption wedge |
| SwiftUI | Manual integration | Reactive `ChainRunner` | Easier app adoption |
| Prompts | Few generic templates | 11 domain-specific templates | Faster time-to-value |
| Tests | ~30 tests | 107 tests | 3.5x coverage increase |
| Docs | Basic package docs | Adoption-focused README and docs | Easier for MLX/Swift developers to understand |

## Follow-up fixes from expert review

- Map chunks are now budget-aware and account for prompt/system/output overhead.
- Hierarchical reduce now uses `PromptBudgeter`, including `TokenAwareBackend` when available.
- `preserveOrder` now controls concurrent map result ordering while preserving source chunk labels.
- Reduce grouping is now budget-derived and capped by `maxReduceGroupSize`.
- Default reserved output budget is now 512 tokens.
- README wording now accurately frames PDF-extracted text and `.ips` support.
- Added `ChunkPromptFormatter` for richer diagnostic chunk labels.
- `MLXBackend` `@unchecked Sendable` comment now precisely describes lock protection.
- Token-mode fallback re-chunking now converts available token budget into a conservative word target before invoking `SentenceAwareChunker`.

## Validation

- [x] `swift package resolve`
- [x] `swift build` — 0 errors, 0 warnings
- [x] `swift test` — 107 tests, 0 failures

Final local status:
- Tests passing: 107
- Warnings: 0 (2 pre-existing in test files)

## Compatibility

- Existing public APIs are preserved. No init signatures were changed.
- Existing chunkers continue to work unchanged.
- New metadata fields are additive (default `nil`).
- All pre-existing tests continue to pass.

## Limitations

- This package does not parse PDFs directly or perform OCR. For PDFs, extract text first and preserve page markers when possible. Table preservation is best-effort and primarily supports Markdown-style tables.
- `AppleCrashReportChunker` handles translated `.crash` text and lightweight grouping for JSON-like `.ips` text. It does not fully interpret Apple's crash-report JSON schema.
- This package does not acquire logs from Xcode, devices, or Console.app.
- It analyzes user-provided text.
- Whether inference stays local depends on the backend supplied by the app.
- Diagnostic and emergency outputs should be reviewed by humans for high-stakes use cases.

## Suggested review order

1. README and docs positioning
2. Public metadata/API additions (`TextChunkMetadata`, `LogMetadata`, `DiagnosticSourceLabel`)
3. Core chain behavior (`AdaptiveChain`, `MapReduceChain`, `PromptBudgeter`)
4. Domain chunkers (`TranscriptChunker`, `DocumentStructureChunker`, `LogChunker`, `AppleCrashReportChunker`)
5. Prompt templates
6. Tests
