# mlx-swift-chain

[![CI](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml/badge.svg)](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml)

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
    contextBudget: .tokens(4096)
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

## More Examples

These examples show practical long-document workflows that are broadly useful in MLX sample apps.

### Meeting summary

```swift
let chain = AdaptiveChain(backend: model, contextBudget: .words(1000))

let summary = try await chain.run(
    transcript,
    mapPrompt: "Summarize this meeting segment with decisions, blockers, and owners:\n\n",
    reducePrompt: "Produce a concise full-meeting summary from these segment summaries:\n\n"
)
```

### Task extraction

```swift
let chain = AdaptiveChain(backend: model, contextBudget: .words(900))

let tasks = try await chain.run(
    transcript,
    mapPrompt: "Extract action items with owner + due date in JSON:\n\n",
    reducePrompt: "Merge these action items, deduplicate, and output JSON only:\n\n"
)
```

### Key moments and timeline highlights

```swift
let chain = MapReduceChain(
    backend: model,
    chunker: SentenceAwareChunker(targetWords: 350, overlapSentences: 1)
)

let keyMoments = try await chain.run(
    transcript,
    mapPrompt: "Identify noteworthy moments and include timestamps when present:\n\n",
    reducePrompt: "Combine the moments into a chronological highlight list:\n\n"
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
| `FixedSizeChunker` | Splits at word boundaries with optional overlap. |
| `SentenceAwareChunker` | Splits at sentence boundaries, optional sentence overlap. **Default.** |

Chunk metadata preserves chunk index, source word ranges, discovered timestamps, and speaker labels to reduce context loss around boundaries.

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
