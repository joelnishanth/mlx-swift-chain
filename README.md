# mlx-swift-chain

[![CI](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml/badge.svg)](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml)

**Swift-native long-document reasoning for private, on-device MLX apps.**

Process documents that exceed your model's context window using map-reduce, stuff, and adaptive chain strategies — built for local inference on Apple Silicon.

## How This Fits

[MLX Swift](https://github.com/ml-explore/mlx-swift) and [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) handle model loading and inference. **mlx-swift-chain** handles everything above the model layer: chunking, token/context budgeting, map-reduce orchestration, hierarchical reduce, progress reporting, and source-aware long-document outputs. This is not a full RAG framework or LangChain clone — it solves one problem well: reasoning over documents that don't fit in a single context window.

## Target Use Cases

- **Meeting transcript summarization** — speaker-aware chunking preserves who said what
- **Markdown / PDF document summarization** — heading-aware chunking respects document structure
- **Xcode and simulator log analysis** — stack-trace-aware chunking keeps crash reports intact
- **Offline field manuals / emergency docs** — process long reference material entirely on-device

## The Problem

Local LLMs have limited context windows (e.g. 8,192 tokens for Gemma models). Long documents — research papers, legal contracts, codebases, transcripts — easily exceed this limit. Naive prefix truncation discards most of the content:

| Document Size | Prefix Truncation Coverage | mlx-swift-chain Model-Visible Coverage |
|---|---|---|
| ~2,500 words | 100% | 100% |
| ~5,000 words | ~60% | **100%** |
| ~10,000 words | ~30% | **100%** |
| ~20,000 words | **7%** | **100%** |

Coverage here means input/model-visible coverage across chunks, not guaranteed perfect retention in the final reduced answer.

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

### 1. Set up your backend

Use the built-in `MLXBackend` or conform your own service to `LLMBackend`:

```swift
import MLXSwiftChain
import MLXLMCommon

let backend = MLXBackend(
    container: modelContainer,
    generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0.3)
)
```

### 2. Summarize a document

```swift
let chain = AdaptiveChain(backend: backend, contextBudget: .tokens(4096))

let summary = try await chain.run(
    document,
    mapPrompt: "Summarize this section concisely:\n\n",
    reducePrompt: "Combine these summaries into a coherent summary:\n\n",
    systemPrompt: "You are a helpful assistant."
)
```

For short texts, `AdaptiveChain` uses a single LLM call (zero overhead). For long texts, it automatically chunks the input, maps each chunk through the LLM, and reduces the results.

### 3. Or use a prompt template

```swift
let summary = try await chain.run(document, template: PromptTemplates.transcriptSummary)
```

## Choose a Chain

| Chain | When to Use |
|---|---|
| `StuffChain` | Input fits in context window. Single LLM call. |
| `MapReduceChain` | Input exceeds context. Chunks, maps each, reduces combined. Supports hierarchical reduce for very large documents. |
| `AdaptiveChain` | Auto-selects Stuff or MapReduce based on input length and prompt overhead. **Start here.** |

## Choose a Chunker

| Chunker | Best For |
|---|---|
| `SentenceAwareChunker` | General text. Splits at sentence boundaries. **Default.** |
| `FixedSizeChunker` | Uniform chunks by word count with optional overlap. |
| `TranscriptChunker` | Meeting transcripts and voice notes. Splits at speaker turns, preserves labels and timestamps. |
| `MarkdownHeadingChunker` | Markdown documents. Splits at headings, preserves structure. Falls back to sentence splitting for large sections. |
| `LogChunker` | Xcode/simulator logs. Keeps stack traces intact, splits at timestamp boundaries. |

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

**Token budgeting:** `AdaptiveChain` accounts for system prompt, task prompt, input text, and reserved output tokens when deciding stuff vs. map-reduce routing. Backends conforming to `TokenAwareBackend` enable exact token counting.

**Hierarchical reduce:** When `MapReduceChain` is initialized with a `contextBudget`, it automatically groups and recursively reduces summaries that exceed the budget, preventing context overflow on large documents.

**Concurrency:** `ChainExecutionOptions(maxConcurrentMapTasks: 4)` enables bounded parallel mapping. Default is 1, which is optimal for on-device MLX inference.

**Retries:** `ChainExecutionOptions(retryPolicy: RetryPolicy(maxAttempts: 3, delayMilliseconds: 500))` adds retry logic, primarily useful for remote backends.

**Memory awareness:** `MemoryPressure.current()` checks available memory before inference — critical for iOS where jetsam kills memory-hungry processes.

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

## Architecture

See [docs/architecture.md](docs/architecture.md) for the component graph and [docs/data-flow.md](docs/data-flow.md) for the map-reduce sequence diagram.

## Requirements

- macOS 14.0+ / iOS 17.0+
- Swift 6.1+
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) 3.31.3+

## License

Apache 2.0 — see [LICENSE](LICENSE).
