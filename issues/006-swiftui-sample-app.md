# Issue: Add SwiftUI sample app

## Summary
Create a standalone SwiftUI sample app demonstrating document loading, chunking, chain execution, streaming updates, and cited results.

## Problem
Library users currently rely on tests/docs for integration patterns. A runnable sample would reduce adoption friction and clarify best practices.

## Goals
- Provide an end-to-end SwiftUI reference app.
- Demonstrate both non-streaming and streaming flows.
- Showcase diagnostics, progress events, and citations.

## Proposed scope
1. **App features**
   - Input text/transcript panel.
   - Config controls (chunk size, model config, overlap).
   - Run chain and display incremental output.
   - Display chunk list and evidence/citation highlights.
2. **Architecture**
   - Use existing `ChainRunner` patterns where possible.
   - Keep app small and educational.
3. **Safety and UX**
   - Cancellation support.
   - Error presentation for token-budget failures.
4. **Docs**
   - README section with build/run instructions and screenshots.

## Acceptance criteria
- Sample builds and runs on supported Apple platforms.
- Demonstrates at least one streaming scenario.
- Includes clear minimal setup instructions.

## Risks
- Platform/version drift for SwiftUI APIs.
- Sample complexity creeping beyond educational scope.

## Suggested tasks
- [ ] Scaffold sample app target.
- [ ] Implement core demo views + view model.
- [ ] Integrate chain runner and streaming events.
- [ ] Add docs and screenshots.
