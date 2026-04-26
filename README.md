# mlx-swift-chain

Document processing chains for [MLX Swift](https://github.com/ml-explore/mlx-swift). Process documents that exceed your model's context window using map-reduce, stuff, and adaptive chain strategies — built for local inference on Apple Silicon.

## The Problem

Local LLMs have limited context windows (e.g. 8,192 tokens for Gemma models). A 2-hour meeting transcript (~20,000 words) far exceeds this limit. Naive prefix truncation discards most of the content:

| Meeting Length | Prefix Truncation Coverage | mlx-swift-chain Coverage |
|---|---|---|
| 15 min (~2,500 words) | 100% | 100% |
| 30 min (~5,000 words) | ~60% | **100%** |
| 1 hour (~10,000 words) | ~30% | **100%** |
| 2 hours (~20,000 words) | **7%** | **100%** |

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/offlyn/mlx-swift-chain", from: "0.1.0"),
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

let result = try await chain.run(
    transcript,
    mapPrompt: "Summarize this section concisely:\n\n",
    reducePrompt: "Combine these summaries into one:\n\n",
    systemPrompt: "You are a meeting notes assistant."
)
```

That's it. For short texts, `AdaptiveChain` uses a single LLM call (zero overhead). For long texts, it automatically chunks the input, maps each chunk through the LLM, and reduces the results.

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
