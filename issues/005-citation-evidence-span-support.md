# Issue: Add citation/evidence span support

## Summary
Add structured citation support that maps generated claims to source chunk spans, enabling answer traceability and UI-level evidence rendering.

## Problem
Current chain outputs lack standardized evidence spans. Consumers cannot reliably show where a statement came from, reducing trust and debuggability.

## Goals
- Introduce structured citation objects in chain output.
- Track source chunk IDs and offsets/span ranges.
- Provide prompt/template guidance to encourage grounded responses.

## Proposed scope
1. **Data model**
   - `Citation` / `EvidenceSpan` types:
     - `chunkID`
     - `startOffset`, `endOffset` (or line range)
     - `snippet` (optional bounded text)
     - `confidence` (optional)
2. **Chain integration**
   - Extend `ChainResult` and structured output paths.
   - Propagate chunk metadata needed for span mapping.
3. **Prompting**
   - Add prompt templates/instructions for citation-aware generation.
4. **Validation**
   - Post-processor to verify span bounds and known chunk references.
5. **Testing**
   - Unit tests for serialization, validation, and rendering helpers.

## Acceptance criteria
- Structured citation fields available in public result API.
- Invalid spans are rejected or flagged deterministically.
- Docs show end-to-end cited answer example.

## Risks
- Hallucinated citations by model outputs.
- Span drift after text normalization/preprocessing.

## Suggested tasks
- [ ] Add citation/evidence model types.
- [ ] Wire through chain result + structured output.
- [ ] Add validation and helper utilities.
- [ ] Add tests and docs example.
