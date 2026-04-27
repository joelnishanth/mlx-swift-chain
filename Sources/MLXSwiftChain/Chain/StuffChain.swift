import Foundation

/// Sends the entire text in a single LLM call.
/// Use when the input fits within the model's context window.
public struct StuffChain: DocumentChain {
    public let backend: any LLMBackend

    public init(backend: any LLMBackend) {
        self.backend = backend
    }

    public func run(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) async throws -> String {
        try await runWithMetadata(
            text,
            mapPrompt: mapPrompt,
            reducePrompt: reducePrompt,
            stuffPrompt: stuffPrompt,
            systemPrompt: systemPrompt,
            options: options,
            progress: progress
        ).text
    }

    public func stream(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) -> AsyncThrowingStream<ChainEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let start = ContinuousClock.now
                    defer { progress?.finish() }
                    progress?.report(ChainProgress.Update(phase: .stuffing, elapsedTime: .zero))
                    continuation.yield(.progress(ChainProgress.Update(phase: .stuffing, elapsedTime: .zero)))

                    let taskPrompt = stuffPrompt ?? reducePrompt
                    let prompt = ChainPromptBuilder.stuffPrompt(
                        task: taskPrompt, text: text, metadata: nil, style: options.promptStyle
                    )

                    var acc = MetricsAccumulator()
                    if let tokenBackend = backend as? any TokenAwareBackend {
                        acc.inputTokens = tokenBackend.tokenCounter.countTokens(prompt)
                    }

                    var fullText = ""
                    if let streamingBackend = backend as? any StreamingLLMBackend {
                        for try await fragment in streamingBackend.stream(prompt: prompt, systemPrompt: systemPrompt) {
                            try Task.checkCancellation()
                            fullText += fragment
                            continuation.yield(.chunk(fragment))
                        }
                    } else {
                        fullText = try await backend.generate(prompt: prompt, systemPrompt: systemPrompt)
                        continuation.yield(.chunk(fullText))
                    }

                    if let tokenBackend = backend as? any TokenAwareBackend {
                        acc.outputTokens = tokenBackend.tokenCounter.countTokens(fullText)
                    }

                    let elapsed = ContinuousClock.now - start
                    let chunk = TextChunk(
                        text: text, index: 0,
                        wordCount: text.split(whereSeparator: \.isWhitespace).count
                    )
                    let result = ChainResult(
                        text: fullText, sourceChunks: [chunk],
                        metrics: acc.finalize(elapsed: elapsed)
                    )
                    progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: elapsed))
                    continuation.yield(.progress(ChainProgress.Update(phase: .complete, elapsedTime: elapsed)))
                    continuation.yield(.result(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func runWithMetadata(
        _ text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String?,
        systemPrompt: String?,
        options: ChainExecutionOptions,
        progress: ChainProgress?
    ) async throws -> ChainResult {
        let start = ContinuousClock.now
        defer { progress?.finish() }
        progress?.report(ChainProgress.Update(phase: .stuffing, elapsedTime: .zero))

        let taskPrompt = stuffPrompt ?? reducePrompt
        let prompt = ChainPromptBuilder.stuffPrompt(
            task: taskPrompt,
            text: text,
            metadata: nil,
            style: options.promptStyle
        )

        var acc = MetricsAccumulator()
        if let tokenBackend = backend as? any TokenAwareBackend {
            acc.inputTokens = tokenBackend.tokenCounter.countTokens(prompt)
        }

        let result = try await backend.generate(prompt: prompt, systemPrompt: systemPrompt)

        if let tokenBackend = backend as? any TokenAwareBackend {
            acc.outputTokens = tokenBackend.tokenCounter.countTokens(result)
        }

        let elapsed = ContinuousClock.now - start
        progress?.report(ChainProgress.Update(phase: .complete, elapsedTime: elapsed))

        let chunk = TextChunk(
            text: text,
            index: 0,
            wordCount: text.split(whereSeparator: \.isWhitespace).count
        )
        return ChainResult(
            text: result,
            sourceChunks: [chunk],
            metrics: acc.finalize(elapsed: elapsed)
        )
    }
}
