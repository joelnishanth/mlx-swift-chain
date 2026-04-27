import Foundation

/// Determines whether a prompt + text + reserved output fits within the
/// context budget, using the best available token-counting strategy.
///
/// Resolution order:
/// 1. If the backend conforms to `TokenAwareBackend`, use its `tokenCounter`
///    and `contextWindowTokens` for exact counting.
/// 2. If the budget is `.tokens(n, ratio)`, use `WordHeuristicTokenCounter`
///    with the given ratio and token limit `n`.
/// 3. If the budget is `.words(n)`, use raw word count with word limit `n`.
public struct PromptBudgeter: Sendable {
    private let counter: any TokenCounter
    private let limit: Int
    private let mode: Mode

    private enum Mode {
        case tokenBased
        case wordBased
    }

    /// Create a budgeter from a backend and context budget.
    public init(backend: any LLMBackend, budget: ContextBudget) {
        if let tokenAware = backend as? (any TokenAwareBackend) {
            self.counter = tokenAware.tokenCounter
            self.limit = tokenAware.contextWindowTokens
            self.mode = .tokenBased
        } else {
            switch budget {
            case .tokens(let tokens, let ratio):
                self.counter = WordHeuristicTokenCounter(tokensPerWord: ratio)
                self.limit = tokens
                self.mode = .tokenBased
            case .words(let words):
                self.counter = WordCounter()
                self.limit = words
                self.mode = .wordBased
            }
        }
    }

    /// Check whether all components fit within the budget.
    public func fits(
        systemPrompt: String?,
        taskPrompt: String,
        text: String,
        reservedOutputTokens: Int
    ) -> Bool {
        let systemCount = count(systemPrompt ?? "")
        let taskCount = count(taskPrompt)
        let textCount = count(text)
        let reservedCount: Int

        switch mode {
        case .tokenBased:
            reservedCount = reservedOutputTokens
        case .wordBased:
            reservedCount = Int(Double(reservedOutputTokens) / 1.33)
        }

        return systemCount + taskCount + textCount + reservedCount <= limit
    }

    /// Count units (tokens or words) for the given text.
    public func count(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return counter.countTokens(text)
    }

    /// The total budget limit in the counter's units.
    public var budgetLimit: Int { limit }

    /// Returns the number of units (tokens or words, matching the budgeter's
    /// counting mode) available for input text after accounting for prompt
    /// overhead, reserved output, and a safety margin.
    ///
    /// Both `reservedOutputTokens` and `safetyMargin` are specified in tokens
    /// and converted to word-equivalent units when the budgeter is in word mode.
    public func availableTextBudget(
        systemPrompt: String?,
        taskPrompt: String,
        reservedOutputTokens: Int,
        safetyMargin: Int = 128
    ) -> Int {
        let systemCount = count(systemPrompt ?? "")
        let taskCount = count(taskPrompt)
        let reservedCount: Int
        let marginCount: Int

        switch mode {
        case .tokenBased:
            reservedCount = reservedOutputTokens
            marginCount = safetyMargin
        case .wordBased:
            reservedCount = Int(Double(reservedOutputTokens) / 1.33)
            marginCount = Int(Double(safetyMargin) / 1.33)
        }

        let overhead = systemCount + taskCount + reservedCount + marginCount
        return max(1, limit - overhead)
    }
}

/// Simple word counter conforming to TokenCounter for word-based budgeting.
private struct WordCounter: TokenCounter, Sendable {
    func countTokens(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
