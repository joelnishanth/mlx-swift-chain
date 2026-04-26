import Foundation

/// Counts the number of tokens in a text string.
///
/// Conform to this protocol with a real tokenizer for accurate budgeting,
/// or use `WordHeuristicTokenCounter` as a lightweight fallback.
public protocol TokenCounter: Sendable {
    func countTokens(_ text: String) -> Int
}

/// Estimates token count using a word-count heuristic.
///
/// English text averages ~1.33 tokens per word. This is a reasonable
/// default when a real tokenizer is not available.
public struct WordHeuristicTokenCounter: TokenCounter, Sendable {
    public var tokensPerWord: Double

    public init(tokensPerWord: Double = 1.33) {
        self.tokensPerWord = max(0.1, tokensPerWord)
    }

    public func countTokens(_ text: String) -> Int {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return max(1, Int(Double(wordCount) * tokensPerWord))
    }
}
