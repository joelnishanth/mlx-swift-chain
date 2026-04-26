# mlx-swift-chain

Document processing chains for [MLX Swift](https://github.com/ml-explore/mlx-swift). Process documents that exceed your model's context window using map-reduce, stuff, and adaptive chain strategies — built for local inference on Apple Silicon.

## The Problem

Local LLMs have limited context windows (e.g. 8,192 tokens for Gemma models). Long documents — research papers, legal contracts, codebases, transcripts — easily exceed this limit. Naive prefix truncation discards most of the content:

| Document Size | Prefix Truncation Coverage | mlx-swift-chain Coverage |
|---|---|---|
| ~2,500 words | 100% | 100% |
| ~5,000 words | ~60% | **100%** |
| ~10,000 words | ~30% | **100%** |
| ~20,000 words | **7%** | **100%** |

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

### 1. Conform your model service to `LLMBackend`

```swift
import MLXSwiftChain
import MLXLMCommon

class MyModelService: LLMBackend {
    let container: ModelContainer

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        let session = ChatSession(container, instructions: systemPrompt)
        return try await session.respond(to: prompt)
    }
}
```

### 2. Use `AdaptiveChain` to process documents

```swift
let chain = AdaptiveChain(
    backend: myModelService,
    contextBudgetWords: 1200
)

// Summarize a long document
let summary = try await chain.run(
    document,
    mapPrompt: "Summarize this section concisely:\n\n",
    reducePrompt: "Combine these section summaries into a single coherent summary:\n\n",
    systemPrompt: "You are a helpful assistant that produces clear, structured summaries."
)
```

For short texts, `AdaptiveChain` uses a single LLM call (zero overhead). For long texts, it automatically chunks the input, maps each chunk through the LLM, and reduces the results.

### More Examples

**Extract key information from a research paper:**

```swift
let chain = AdaptiveChain(backend: model, contextBudgetWords: 1000)

let findings = try await chain.run(
    paper,
    mapPrompt: "List the key findings and methodology from this section:\n\n",
    reducePrompt: "Consolidate these findings into a structured overview:\n\n"
)
```

**Analyze a codebase or log file:**

```swift
let chain = AdaptiveChain(backend: model, contextBudgetWords: 800)

let analysis = try await chain.run(
    logOutput,
    mapPrompt: "Identify errors, warnings, and anomalies in this log section:\n\n",
    reducePrompt: "Merge and deduplicate these issues into a prioritized list:\n\n"
)
```

**Extract action items from any long-form text:**

```swift
let chain = AdaptiveChain(backend: model, contextBudgetWords: 900)

let tasks = try await chain.run(
    notes,
    mapPrompt: "Extract action items and to-dos from this section as JSON:\n\n",
    reducePrompt: "Merge and deduplicate these action items into a single JSON array:\n\n"
)
```

## Chains

| Chain | When to Use |
|---|---|
| `StuffChain` | Input fits in context window. Single LLM call. |
| `MapReduceChain` | Input exceeds context. Chunks → map each → reduce combined. |
| `AdaptiveChain` | Auto-selects Stuff or MapReduce based on input length. **Start here.** |

## Chunkers

| Chunker | Strategy |
|---|---|
| `FixedSizeChunker` | Splits at word boundaries, fixed chunk size. |
| `SentenceAwareChunker` | Splits at sentence boundaries, respects target word count. **Default.** |

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
- Swift 5.9+
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) 3.31.3+

## License

Apache 2.0 — see [LICENSE](LICENSE).
