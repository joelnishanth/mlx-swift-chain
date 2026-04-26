# Repository Improvement Opportunities

This document captures high-impact follow-up ideas identified during a code review of `mlx-swift-chain`.

## 1) Parallel map phase

`MapReduceChain` currently maps chunks sequentially. Adding bounded concurrency (for example, max `N` in-flight requests) can reduce latency for large documents while still protecting local model throughput.

## 2) Token-aware budgeting

`AdaptiveChain` uses word count as a context heuristic. Introducing an optional tokenizer-backed budget mode (or a pluggable estimator) would improve fit/overflow behavior for languages and prompts where words are a poor token proxy.

## 3) Hierarchical reduce for very large inputs

For many chunks, a single final reduce prompt can itself become large. Add recursive/hierarchical reduce (reduce groups, then reduce summaries) to improve scale and reliability on large corpora.

## 4) Retry and backoff strategy

LLM backends may intermittently fail. Add configurable retry policies for map and reduce calls, with clear behavior for partial progress and cancellation.

## 5) Expand CI quality gates

Add a GitHub Actions workflow with at least:
- `swift test`
- SwiftLint (optional but recommended)
- Documentation link check

This would improve confidence for external contributors and make regressions visible in pull requests.
