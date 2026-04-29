# Issue: Add streaming reduce support

## Summary
Enable streaming output during the reduce phase of map-reduce chains so consumers can render partial final answers in real time.

## Problem
Streaming currently emphasizes map-stage token flow; reduce results often arrive only at completion. This increases perceived latency and limits UI responsiveness.

## Goals
- Add streaming-capable reduce execution in `MapReduceChain`.
- Emit progressive reduce events through existing `ChainEvent`/progress channels.
- Preserve existing non-streaming behavior by default.

## Proposed design
1. **API updates**
   - Add option in `ChainExecutionOptions` to enable streaming reduce.
   - Define event payloads for partial reduce text and completion.
2. **Backend integration**
   - Use `StreamingLLMBackend` when available.
   - Graceful fallback to buffered reduce when streaming unsupported.
3. **Event model**
   - Distinguish map token events vs reduce token events.
   - Include correlation IDs and stage metadata.
4. **Threading and cancellation**
   - Ensure cancellation interrupts reduce stream cleanly.

## Acceptance criteria
- Streaming reduce works with streaming backend in tests.
- Event ordering is deterministic and documented.
- Existing API users remain source-compatible.

## Risks
- Interleaving map and reduce events causing consumer confusion.
- Partial outputs requiring post-processing when model revises text.

## Suggested tasks
- [ ] Extend options/events for reduce streaming.
- [ ] Implement reduce streaming path in chain.
- [ ] Add tests for ordering/cancellation/fallback.
- [ ] Add integration example in SwiftUI runner path.
