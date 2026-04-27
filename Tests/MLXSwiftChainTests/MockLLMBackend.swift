import Foundation
import MLXSwiftChain

/// Thread-safe mock LLM backend for testing.
///
/// Uses NSLock to protect mutable state, making it safe for concurrent
/// access from TaskGroup-based map phases.
final class MockLLMBackend: LLMBackend, @unchecked Sendable {
    enum MockError: Error {
        case forced
    }

    private let lock = NSLock()
    private var _promptsReceived: [String] = []
    private var _generateCallCount = 0
    private var _cannedResponse: String = "mock response"
    private var _shouldThrow = false

    var promptsReceived: [String] {
        get { lock.withLock { _promptsReceived } }
    }

    var generateCallCount: Int {
        get { lock.withLock { _generateCallCount } }
    }

    var cannedResponse: String {
        get { lock.withLock { _cannedResponse } }
        set { lock.withLock { _cannedResponse = newValue } }
    }

    var shouldThrow: Bool {
        get { lock.withLock { _shouldThrow } }
        set { lock.withLock { _shouldThrow = newValue } }
    }

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        return try lock.withLock {
            if _shouldThrow {
                throw MockError.forced
            }
            _promptsReceived.append(prompt)
            _generateCallCount += 1
            return _cannedResponse
        }
    }
}

/// Thread-safe mock backend that also provides token counting for budget tests.
final class MockTokenAwareBackend: TokenAwareBackend, @unchecked Sendable {
    private let lock = NSLock()
    let contextWindowTokens: Int
    let tokenCounter: any TokenCounter

    private var _promptsReceived: [String] = []
    private var _generateCallCount = 0
    private var _cannedResponse: String = "mock response"

    var promptsReceived: [String] {
        get { lock.withLock { _promptsReceived } }
    }

    var generateCallCount: Int {
        get { lock.withLock { _generateCallCount } }
    }

    var cannedResponse: String {
        get { lock.withLock { _cannedResponse } }
        set { lock.withLock { _cannedResponse = newValue } }
    }

    init(contextWindowTokens: Int, tokensPerWord: Double = 1.0) {
        self.contextWindowTokens = contextWindowTokens
        self.tokenCounter = WordHeuristicTokenCounter(tokensPerWord: tokensPerWord)
    }

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        lock.withLock {
            _promptsReceived.append(prompt)
            _generateCallCount += 1
            return _cannedResponse
        }
    }
}

/// Mock streaming backend that yields the canned response word by word.
final class MockStreamingBackend: StreamingLLMBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _promptsReceived: [String] = []
    private var _generateCallCount = 0
    private var _cannedResponse: String = "streamed mock response"
    private var _shouldThrow = false

    var promptsReceived: [String] {
        lock.withLock { _promptsReceived }
    }

    var generateCallCount: Int {
        lock.withLock { _generateCallCount }
    }

    var cannedResponse: String {
        get { lock.withLock { _cannedResponse } }
        set { lock.withLock { _cannedResponse = newValue } }
    }

    var shouldThrow: Bool {
        get { lock.withLock { _shouldThrow } }
        set { lock.withLock { _shouldThrow = newValue } }
    }

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        try lock.withLock {
            if _shouldThrow { throw MockLLMBackend.MockError.forced }
            _promptsReceived.append(prompt)
            _generateCallCount += 1
            return _cannedResponse
        }
    }

    func stream(prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error> {
        let response = lock.withLock {
            _promptsReceived.append(prompt)
            _generateCallCount += 1
            return _cannedResponse
        }
        let shouldFail = shouldThrow
        return AsyncThrowingStream { continuation in
            Task {
                if shouldFail {
                    continuation.finish(throwing: MockLLMBackend.MockError.forced)
                    return
                }
                let words = response.split(separator: " ")
                for (i, word) in words.enumerated() {
                    let fragment = (i == 0 ? "" : " ") + word
                    continuation.yield(String(fragment))
                }
                continuation.finish()
            }
        }
    }
}

/// Mock backend that returns configurable responses per call (for retry testing).
final class MockSequentialBackend: LLMBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _responses: [String]
    private var _callIndex = 0

    init(responses: [String]) {
        self._responses = responses
    }

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        lock.withLock {
            let idx = min(_callIndex, _responses.count - 1)
            _callIndex += 1
            return _responses[idx]
        }
    }
}
