import Foundation
import MLXSwiftChain

final class MockLLMBackend: LLMBackend, @unchecked Sendable {
    var promptsReceived: [String] = []
    var generateCallCount = 0
    var cannedResponse: String = "mock response"

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        promptsReceived.append(prompt)
        generateCallCount += 1
        return cannedResponse
    }
}
