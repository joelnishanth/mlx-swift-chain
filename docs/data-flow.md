# Data Flow

## Map-Reduce Sequence

```mermaid
sequenceDiagram
    participant Svc as Your Service
    participant AC as AdaptiveChain
    participant Ch as SentenceAwareChunker
    participant MR as MapReduceChain
    participant LLM as LLMBackend

    Svc->>AC: run(document, mapPrompt, reducePrompt)
    AC->>AC: count words
    alt words <= contextBudgetWords
        AC->>LLM: generate(reducePrompt + document)
        LLM-->>AC: result
        AC-->>Svc: result (single call)
    else words > contextBudgetWords
        AC->>Ch: chunk(document)
        Ch-->>AC: [chunk1, chunk2, ..., chunkN]
        AC->>MR: run(chunks)

        loop Map Phase (for each chunk)
            MR->>LLM: generate(mapPrompt + chunk_i)
            LLM-->>MR: chunk_result_i
        end

        MR->>MR: combine chunk results
        MR->>LLM: generate(reducePrompt + combined)
        LLM-->>MR: final structured result
        MR-->>Svc: result string
    end
```

## Coverage Guarantee

The map-reduce approach guarantees **100% document coverage**:

| Document Size | Prefix Truncation | Map-Reduce |
|---|---|---|
| ~2,500 words | 100% coverage | 100% coverage |
| ~5,000 words | ~60% coverage | 100% coverage |
| ~10,000 words | ~30% coverage | 100% coverage |
| ~20,000 words | ~7% coverage | 100% coverage |

The tradeoff is additional LLM calls (one per chunk + one reduce), which increases total processing time linearly with document length. For local inference on Apple Silicon, this is acceptable since the alternative is losing most of the content.
