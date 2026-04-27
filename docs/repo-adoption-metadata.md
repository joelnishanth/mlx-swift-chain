# Repository Adoption Metadata

Recommended GitHub About/sidebar settings and metadata for maintainers.

## GitHub About Description

> Long-document chunking, map-reduce, prompt budgeting, and source-grounded summarization for MLX Swift apps on macOS and iOS.

## GitHub Tagline (Short)

> The long-document reasoning layer for private MLX Swift apps.

## Website

Leave blank unless a project site is established.

## Topics

Add these topics to the GitHub repository settings:

```
swift
mlx
mlx-swift
llm
local-llm
on-device-ai
ios
macos
swiftui
summarization
map-reduce
document-ai
transcripts
crash-reports
xcode
developer-tools
offline-ai
```

## Social Preview

Use a simple left-to-right diagram as the social preview image:

```
Input (document / log / transcript)
    → Chunker (structure-aware splitting)
    → AdaptiveChain (stuff or map-reduce)
    → Local MLX backend (on-device inference)
    → Source-grounded output (with [Chunk N] citations)
```

Recommended dimensions: 1280x640px. Keep it clean with a light background, the package name, and the flow above.

## README Badge

The CI badge is already configured:

```markdown
[![CI](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml/badge.svg)](https://github.com/joelnishanth/mlx-swift-chain/actions/workflows/ci.yml)
```

## Release Strategy

- Tag releases as `vX.Y.Z` (e.g. `v0.1.0`).
- Use GitHub Releases with notes from `CHANGELOG.md`.
- Swift Package Manager resolves tags automatically from the `from:` version specifier.
