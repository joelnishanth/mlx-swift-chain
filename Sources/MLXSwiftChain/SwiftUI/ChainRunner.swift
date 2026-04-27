import Foundation
import Observation

/// An `@Observable` wrapper for running document chains with SwiftUI.
///
/// Tracks execution phase, running state, result, and errors so SwiftUI
/// views can react to chain progress without manual state management.
///
/// ```swift
/// struct SummaryView: View {
///     @State private var runner = ChainRunner()
///     let chain: AdaptiveChain
///
///     var body: some View {
///         VStack {
///             if runner.isRunning {
///                 ProgressView()
///                 if let phase = runner.phase {
///                     Text(String(describing: phase))
///                 }
///             }
///             if let result = runner.result {
///                 Text(result)
///             }
///             Button("Summarize") {
///                 runner.run(chain, text: document,
///                           mapPrompt: "Summarize:", reducePrompt: "Combine:")
///             }
///         }
///     }
/// }
/// ```
@available(macOS 14, iOS 17, *)
@MainActor
@Observable
public final class ChainRunner {
    /// Current chain execution phase, nil when idle.
    public private(set) var phase: ChainProgress.Phase?
    /// Whether a chain is currently executing.
    public private(set) var isRunning = false
    /// The final result from the most recent chain execution.
    public private(set) var result: String?
    /// Rich result with source chunks and metrics from the most recent execution.
    public private(set) var chainResult: ChainResult?
    /// Error from the most recent chain execution, if any.
    public private(set) var error: (any Error)?
    /// Partial text accumulated during streaming execution.
    public private(set) var partialText: String?

    private var currentTask: Task<Void, Never>?

    public init() {}

    /// Run a document chain with explicit prompts.
    public func run(
        _ chain: any DocumentChain,
        text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String? = nil,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions()
    ) {
        cancel()
        isRunning = true
        result = nil
        chainResult = nil
        error = nil
        phase = nil
        partialText = nil

        let progress = ChainProgress()

        currentTask = Task {
            async let observeProgress: Void = {
                for await update in progress.updates {
                    await MainActor.run {
                        self.phase = update.phase
                    }
                }
            }()

            let runResult: Result<ChainResult, any Error>
            do {
                let output = try await chain.runWithMetadata(
                    text,
                    mapPrompt: mapPrompt,
                    reducePrompt: reducePrompt,
                    stuffPrompt: stuffPrompt,
                    systemPrompt: systemPrompt,
                    options: options,
                    progress: progress
                )
                runResult = .success(output)
            } catch {
                runResult = .failure(error)
            }

            _ = await observeProgress

            switch runResult {
            case .success(let output):
                self.result = output.text
                self.chainResult = output
            case .failure(let error):
                self.error = error
            }
            self.isRunning = false
        }
    }

    /// Run a document chain using a prompt template.
    public func run(
        _ chain: any DocumentChain,
        text: String,
        template: ChainPromptTemplate,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions()
    ) {
        run(
            chain,
            text: text,
            mapPrompt: template.mapPrompt,
            reducePrompt: template.reducePrompt,
            stuffPrompt: template.stuffPrompt,
            systemPrompt: systemPrompt,
            options: options
        )
    }

    /// Run a document chain with streaming output.
    ///
    /// Partial text is accumulated in ``partialText`` as tokens arrive.
    /// The final result is available in ``result`` and ``chainResult``.
    public func runStreaming(
        _ chain: any DocumentChain,
        text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String? = nil,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = ChainExecutionOptions()
    ) {
        cancel()
        isRunning = true
        result = nil
        chainResult = nil
        error = nil
        phase = nil
        partialText = ""

        currentTask = Task {
            do {
                let stream = chain.stream(
                    text,
                    mapPrompt: mapPrompt,
                    reducePrompt: reducePrompt,
                    stuffPrompt: stuffPrompt,
                    systemPrompt: systemPrompt,
                    options: options,
                    progress: nil
                )

                for try await event in stream {
                    switch event {
                    case .chunk(let fragment):
                        self.partialText = (self.partialText ?? "") + fragment
                    case .progress(let update):
                        self.phase = update.phase
                    case .result(let chainResult):
                        self.result = chainResult.text
                        self.chainResult = chainResult
                    }
                }
            } catch {
                self.error = error
            }
            self.isRunning = false
        }
    }

    /// Cancel the current chain execution.
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}
