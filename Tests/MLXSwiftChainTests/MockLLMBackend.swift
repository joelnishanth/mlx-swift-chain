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
