import Foundation

/// Strategy used by `AdaptiveChain` to decide whether the document fits in a single call.
public enum ContextBudget: Sendable {
    /// Budget based on word count.
    case words(Int)
    /// Token budget with configurable conversion heuristic.
    ///
    /// This keeps API forward-compatible with true tokenizer-based budgeting.
    case tokens(Int, estimatedTokensPerWord: Double = 1.33)

    public var estimatedWordLimit: Int {
        switch self {
        case .words(let words):
            return max(1, words)
        case .tokens(let tokens, let estimatedTokensPerWord):
            let ratio = max(0.1, estimatedTokensPerWord)
            return max(1, Int(Double(tokens) / ratio))
        }
    }

    /// Check whether the total prompt (overhead + text + reserved output) fits.
    /// All values are in estimated word-equivalent units.
    public func fitsInBudget(textWords: Int, promptOverheadWords: Int, reservedOutputWords: Int) -> Bool {
        let total = textWords + promptOverheadWords + reservedOutputWords
        return total <= estimatedWordLimit
    }
}
