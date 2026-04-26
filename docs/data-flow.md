# Data Flow

## Map-Reduce Sequence

```mermaid
sequenceDiagram
    participant Svc as Your Service
    participant AC as AdaptiveChain
    participant Ch as SentenceAwareChunker
    participant MR as MapReduceChain
    participant LLM as LLMBackend

    Svc->>AC: run(transcript, mapPrompt, reducePrompt)
    AC->>AC: count words
    alt words <= contextBudgetWords
        AC->>LLM: generate(reducePrompt + transcript)
        LLM-->>AC: result
        AC-->>Svc: result (single call)
    else words > contextBudgetWords
        AC->>Ch: chunk(transcript)
        Ch-->>AC: [chunk1, chunk2, ..., chunkN]
        AC->>MR: run(chunks)

        loop Map Phase (for each chunk)
            MR->>LLM: generate(mapPrompt + chunk_i)
            LLM-->>MR: mini-summary_i
        end

        MR->>MR: combine mini-summaries
        MR->>LLM: generate(reducePrompt + combined)
        LLM-->>MR: final structured result
        MR-->>Svc: result string
    end
```

## Coverage Guarantee

The map-reduce approach guarantees **100% transcript coverage**:

| Meeting Length | Old (Prefix Truncation) | New (Map-Reduce) |
|---|---|---|
| 15 min (~2,500 words) | 100% coverage | 100% coverage |
| 30 min (~5,000 words) | ~60% coverage | 100% coverage |
| 1 hour (~10,000 words) | ~30% coverage | 100% coverage |
| 2 hours (~20,000 words) | ~7% coverage | 100% coverage |

The tradeoff is additional LLM calls (one per chunk + one reduce), which increases total processing time linearly with transcript length. For local inference on Apple Silicon, this is acceptable since the alternative is losing most of the content.
