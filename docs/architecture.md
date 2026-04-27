# Architecture

## Component Graph

```mermaid
graph TD
    subgraph lib ["MLXSwiftChain (Library)"]
        LLMBackend["LLMBackend protocol"]
        TokenAwareBackend["TokenAwareBackend protocol"]
        TextChunker["TextChunker protocol"]
        FixedChunker["FixedSizeChunker"]
        SentenceChunker["SentenceAwareChunker"]
        TranscriptChunker["TranscriptChunker"]
        MarkdownChunker["MarkdownHeadingChunker"]
        LogChunker["LogChunker"]
        StuffChain["StuffChain"]
        MapReduceChain["MapReduceChain"]
        AdaptiveChain["AdaptiveChain"]
        PromptBudgeter["PromptBudgeter"]
        ChainProgress["ChainProgress"]
        ChainRunner["ChainRunner (@Observable)"]
        PromptTemplates["PromptTemplates"]
        MemoryCheck["MemoryPressure"]

        TextChunker --> FixedChunker
        TextChunker --> SentenceChunker
        TextChunker --> TranscriptChunker
        TextChunker --> MarkdownChunker
        TextChunker --> LogChunker
        LLMBackend --> TokenAwareBackend
        LLMBackend --> StuffChain
        LLMBackend --> MapReduceChain
        StuffChain --> AdaptiveChain
        MapReduceChain --> AdaptiveChain
        TextChunker --> AdaptiveChain
        PromptBudgeter --> AdaptiveChain
        ChainProgress --> MapReduceChain
        AdaptiveChain --> ChainRunner
        PromptTemplates --> ChainRunner
    end

    subgraph app ["Your App"]
        MLXAdapter["MLXBackend + GenerateParameters"]
        Service1["Summarization Service"]
        Service2["Log Analysis Service"]
        Service3["Transcript Processing"]
        SwiftUI["SwiftUI View"]
    end

    MLXAdapter --> LLMBackend
    AdaptiveChain --> Service1
    AdaptiveChain --> Service2
    AdaptiveChain --> Service3
    ChainRunner --> SwiftUI
```

## Key Design Decisions

### Protocol-Oriented
- `LLMBackend` is a simple `Sendable` protocol: `generate(prompt:systemPrompt:) async throws -> String`
- `TextChunker` defines how text is split: `chunk(_:) -> [TextChunk]`
- `DocumentChain` defines the processing contract with full options support
- `TokenAwareBackend` extends `LLMBackend` for backends that can provide context window size and token counting (opt-in)

### Strategy Selection
`AdaptiveChain` automatically picks the right strategy using `PromptBudgeter`:
- **Short text** (system prompt + task prompt + text + reserved output fits in budget): uses `StuffChain` — single LLM call, zero overhead
- **Long text** (exceeds budget): uses `MapReduceChain` — chunks, maps each, reduces combined results
- When `TokenAwareBackend` is available, budget checks use real token counts instead of word heuristics

### Hierarchical Reduce
When combined chunk summaries exceed the context budget, `MapReduceChain` automatically groups summaries and reduces in levels, preventing context overflow for very large documents. Chunk labels (`[Chunk N]`, `[Chunks X-Y]`) propagate through reduce levels for source traceability.

### Domain Chunkers
Five chunkers optimized for different document types:
- **FixedSizeChunker** / **SentenceAwareChunker**: general-purpose text
- **TranscriptChunker**: splits at speaker turns, preserves speaker labels and timestamps
- **MarkdownHeadingChunker**: splits at heading boundaries, preserves document structure
- **LogChunker**: splits at timestamp boundaries, keeps stack traces intact

### MLX-First
Ships with `MLXBackend` that wraps `ModelContainer` and `ChatSession` from `mlx-swift-lm`. Accepts `GenerateParameters` for temperature, maxTokens, topP, and other MLXLMCommon sampling controls. Designed for on-device inference on Apple Silicon.

### SwiftUI Integration
`ChainRunner` is an `@Observable` `@MainActor` class that wraps chain execution with reactive state (phase, isRunning, result, error) for direct use in SwiftUI views.

### Progress Reporting
`ChainProgress` provides an `AsyncStream<Update>` with phase information (stuffing, mapping step N of M, reducing, complete) and elapsed time. Optional — pass `nil` if you don't need it.

### Production Reliability
- **Memory pressure**: `MemoryPressure.current()` checks available memory before inference
- **Retry policy**: Configurable retries for transient failures (primarily for remote backends)
- **Bounded concurrency**: Configurable parallel map execution (default 1 for on-device)
- **Cancellation**: Cooperative cancellation via `Task.checkCancellation()` at each step
