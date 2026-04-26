# Contributing to mlx-swift-chain

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

1. Clone the repo and open in Xcode or your editor of choice
2. The package has one dependency: `mlx-swift-lm`
3. Run tests: `swift test`

## Making Changes

1. Fork the repo and create a branch from `main`
2. Write your code — follow the existing style (protocol-oriented, `Sendable` types)
3. Add tests for any new functionality
4. Make sure all tests pass: `swift test`
5. Open a pull request with a clear description of what and why

## Areas for Contribution

- **New chain strategies** (e.g. `RefineChain` — iterative refinement, `SlidingWindowChain`)
- **New chunkers** (e.g. paragraph-aware, markdown-heading-aware, speaker-turn-aware)
- **Performance improvements** (e.g. concurrent map phase, token-level budget estimation)
- **Documentation and examples**

## Code Style

- Use Swift's `Sendable` and structured concurrency throughout
- Prefer protocols over concrete types in public API
- Keep the library dependency-light — avoid adding dependencies beyond `mlx-swift-lm`
- Write doc comments for all public types and methods

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
