# Issue: Add token-aware chunking

## Summary
Add first-class token-aware chunking support so chunk boundaries are determined by token budgets (model-specific), not just character/line heuristics.

## Problem
Current chunking implementations are primarily text-structure driven. This can produce chunks that fit character limits but overflow model context/token budgets, especially with:
- Multilingual content
- Code blocks and stack traces
- High-symbol-density text

This leads to truncation risk, inaccurate prompt budgeting, and unnecessary retries.

## Goals
- Add a `TokenAwareChunker` (or equivalent strategy) that guarantees `maxTokens` per chunk.
- Support pluggable token counters (`TokenCounter`) so behavior matches configured backend/model.
- Preserve semantic boundaries where possible (sentence/heading/code block aware fallback).
- Surface chunk token counts in diagnostics metadata.

## Non-goals
- Perfect semantic segmentation in all languages.
- Building a tokenizer implementation in this issue (reuse existing counters).

## Proposed scope
1. **New API**
   - Add token-budget-based chunking configuration:
     - `maxChunkTokens`
     - `minChunkTokens` (optional)
     - `preferredSplitStrategy` (sentence/paragraph/hard split)
2. **Implementation**
   - Progressive split pipeline:
     1. try semantic boundaries,
     2. fallback to smaller boundaries,
     3. final hard split by token window.
3. **Metadata**
   - Extend `TextChunk` metadata with token count fields.
4. **Tests**
   - Deterministic tests using `MockLLMBackend`/mock token counter.
   - Boundary tests for edge cases (single sentence > budget, code fences, unicode).
5. **Docs**
   - README examples showing token-aware chunking in chain setup.

## Acceptance criteria
- No produced chunk exceeds configured token budget in tests.
- Existing chunkers remain backward compatible.
- Bench test demonstrates lower overflow/retry incidence versus char-based chunking.

## Dependencies
- Existing `TokenCounter` abstractions.
- Prompt budget integration (`PromptBudgeter`) for end-to-end utilization.

## Risks
- Token counter variance between backend implementations.
- Performance overhead from repeated tokenization passes.

## Suggested tasks
- [ ] Design public API and configuration structs.
- [ ] Implement token-aware split core.
- [ ] Integrate diagnostics/token metadata.
- [ ] Add unit tests + pathological fixtures.
- [ ] Add README/docs snippet.
