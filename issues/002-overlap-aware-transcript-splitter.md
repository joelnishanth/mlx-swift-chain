# Issue: Add overlap-aware transcript splitter

## Summary
Implement a transcript splitter that supports configurable overlap windows between adjacent chunks to preserve conversational context across boundaries.

## Problem
Transcript chunking can lose speaker intent when context spans chunk boundaries (Q/A pairs, pronoun references, deferred clarifications). Non-overlapping chunks reduce answer quality in map-reduce and retrieval flows.

## Goals
- Add overlap support in transcript chunking (`TranscriptChunker` path).
- Preserve speaker turn boundaries while injecting overlap where feasible.
- Make overlap configurable by tokens and/or turns.

## Proposed behavior
- Config options:
  - `overlapTokens` (default 0)
  - `overlapTurns` (optional alternative)
  - `maxChunkTokens`
- Each chunk includes trailing overlap from previous chunk (except first).
- Mark overlap segments in metadata so consumers can de-duplicate during reduce.

## Scope details
1. **Splitter algorithm**
   - Build chunk on turns until budget reached.
   - Compute overlap from tail turns/token window.
   - Seed next chunk with overlap then continue.
2. **Metadata additions**
   - `isOverlap`
   - `sourceTurnRange`
   - `overlapSourceChunkID`
3. **Compatibility**
   - Default behavior remains unchanged when overlap is 0.
4. **Testing**
   - Verify deterministic overlap boundaries.
   - Ensure no chunk exceeds token budget after overlap insertion.
   - Ensure downstream reduce can identify and avoid double counting.

## Acceptance criteria
- Overlap option is publicly configurable.
- Tests cover turn-based and token-based overlap.
- Documentation includes before/after example for transcript QA quality.

## Risks
- Prompt token inflation due to overlap.
- Duplication side effects if reduce stage ignores overlap markers.

## Suggested tasks
- [ ] Add API/config surface for transcript overlap.
- [ ] Implement overlap logic and metadata tags.
- [ ] Add reducer de-dup guidance/utilities.
- [ ] Add unit tests and docs.
