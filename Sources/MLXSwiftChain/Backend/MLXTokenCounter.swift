import Foundation
import MLXLMCommon

/// Token counter backed by a real MLXLMCommon ``Tokenizer``.
///
/// Wraps ``Tokenizer/encode(text:)`` to provide exact token counts for
/// budget calculations. Pass the tokenizer resolved from
/// ``ModelContainer/tokenizer`` at initialization time.
///
/// `@unchecked Sendable` because `MLXLMCommon.Tokenizer` is already
/// `Sendable` but the existential wrapper requires the annotation.
public struct MLXTokenCounter: TokenCounter, @unchecked Sendable {
    private let tokenizer: any MLXLMCommon.Tokenizer

    public init(tokenizer: any MLXLMCommon.Tokenizer) {
        self.tokenizer = tokenizer
    }

    public func countTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return tokenizer.encode(text: text).count
    }
}
