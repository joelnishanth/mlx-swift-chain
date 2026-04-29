# Issue: Add benchmark harness

## Summary
Create a reproducible benchmark harness for chunking and chain execution paths to track performance and regression over time.

## Problem
There is no standardized benchmark workflow for:
- Chunker throughput/latency
- Token counting overhead
- Chain execution (map/reduce) scaling

Without baseline numbers, optimization and regression detection are ad hoc.

## Goals
- Add a benchmark target/script runnable in CI and locally.
- Capture key metrics and output machine-readable reports.
- Provide baseline fixtures and clear reproducibility steps.

## Proposed scope
1. **Harness structure**
   - Dedicated benchmark entry point (SwiftPM executable or test target).
   - Scenario matrix:
     - short/medium/long documents
     - transcript vs markdown vs logs
     - varying chunk/token budgets
2. **Metrics**
   - Wall clock duration
   - Chunks/sec
   - Mean/95p chunk size (tokens)
   - Memory snapshot (best effort)
3. **Output**
   - JSON + human-readable table.
   - Optional historical baseline comparison.
4. **CI integration**
   - Non-blocking trend report first.
   - Optional threshold-based failure in follow-up.

## Acceptance criteria
- Single documented command runs the benchmark harness locally.
- Results are deterministic enough for trend tracking.
- CI artifact includes benchmark JSON report.

## Risks
- Noisy timings in shared CI runners.
- Mock vs real backend mismatch for representative performance.

## Suggested tasks
- [ ] Create benchmark target and fixture corpus.
- [ ] Implement metrics collector + reporter.
- [ ] Add CI job publishing artifacts.
- [ ] Document usage and interpretation guidance.
