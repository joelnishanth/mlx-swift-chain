# Issue: Add MLX model configuration examples

## Summary
Add practical MLX model configuration examples covering local model selection, context budgets, tokenization, and performance trade-offs.

## Problem
Users need concrete templates for configuring MLX backends effectively. Current guidance is limited, causing trial-and-error and misconfiguration.

## Goals
- Provide copy-pasteable configuration snippets for common scenarios.
- Explain trade-offs (quality, latency, memory) and tuning knobs.
- Align examples with current public API.

## Proposed scope
1. **Example scenarios**
   - Small model for low-latency local QA.
   - Larger model for quality-focused summarize/reason tasks.
   - Token-aware backend with strict context budgeting.
   - Streaming-enabled setup for interactive UI.
2. **Documentation assets**
   - README quick-start section.
   - Extended doc page with scenario table.
3. **Validation**
   - Ensure snippets compile or are covered by doc tests where possible.

## Acceptance criteria
- At least 4 scenario-based examples published.
- Each example includes when-to-use and tuning guidance.
- Snippets map to actual symbols in current package.

## Risks
- API changes making docs stale.
- Hardware variability impacting recommended defaults.

## Suggested tasks
- [ ] Draft scenario matrix and code snippets.
- [ ] Validate snippets against package APIs.
- [ ] Add README + docs page updates.
- [ ] Add maintenance note for version sync.
