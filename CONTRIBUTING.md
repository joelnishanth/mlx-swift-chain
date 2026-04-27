# Contributing to mlx-swift-chain

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

1. Clone the repo and open in Xcode or your editor of choice
2. Resolve dependencies: `swift package resolve`
3. Build: `swift build`
4. Run tests: `swift test`

The package has one external dependency: [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm).

## Making Changes

1. Fork the repo and create a branch from `main`
2. Write your code — follow the existing style (protocol-oriented, `Sendable` types)
3. Add tests for any new functionality
4. Make sure all tests pass: `swift test`
5. Keep APIs additive and backward-compatible where possible
6. Open a pull request with a clear description of what and why

## Areas for Contribution

- **New chain strategies** (e.g. `RefineChain` — iterative refinement, `SlidingWindowChain`)
- **New chunkers** — implement the `TextChunker` protocol for new document formats. Populate `TextChunkMetadata` with relevant source info.
- **Domain prompt templates** — add `ChainPromptTemplate` bundles to `PromptTemplates` for new workflows
- **Diagnostic chunker improvements** — additional `LogChunkKind` cases, richer crash report parsing, new format support
- **Token counting** — `TokenCounter` implementations backed by real tokenizers
- **Performance improvements** — profiling, memory optimization, streaming reduce
- **Documentation and examples**

## Code Style

- Use Swift's `Sendable` and structured concurrency throughout
- Prefer protocols over concrete types in public API
- Keep the library dependency-light — avoid adding dependencies beyond `mlx-swift-lm`
- Write doc comments for all public types and methods
- New chunkers should include tests with realistic fixtures

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
