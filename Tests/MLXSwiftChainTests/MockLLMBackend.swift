import Foundation
import MLXSwiftChain

final class MockLLMBackend: LLMBackend, @unchecked Sendable {
    enum MockError: Error {
        case forced
    }

    var promptsReceived: [String] = []
    var generateCallCount = 0
    var cannedResponse: String = "mock response"
    var shouldThrow = false

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        if shouldThrow {
            throw MockError.forced
        }
        promptsReceived.append(prompt)
        generateCallCount += 1
        return cannedResponse
    }
}

/// Mock backend that also provides token counting for budget tests.
final class MockTokenAwareBackend: TokenAwareBackend, @unchecked Sendable {
    var contextWindowTokens: Int
    var tokenCounter: any TokenCounter

    var promptsReceived: [String] = []
    var generateCallCount = 0
    var cannedResponse: String = "mock response"

    init(contextWindowTokens: Int, tokensPerWord: Double = 1.0) {
        self.contextWindowTokens = contextWindowTokens
        self.tokenCounter = WordHeuristicTokenCounter(tokensPerWord: tokensPerWord)
    }

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        promptsReceived.append(prompt)
        generateCallCount += 1
        return cannedResponse
    }
}
