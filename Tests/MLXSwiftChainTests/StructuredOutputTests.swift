import Foundation
import Testing
@testable import MLXSwiftChain

@Suite("Structured Output Tests")
struct StructuredOutputTests {

    struct SimpleItem: Decodable, Equatable {
        let name: String
        let count: Int
    }

    @Test func validJSON_decodesSuccessfully() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = #"{"name": "test", "count": 42}"#
        let chain = StuffChain(backend: mock)

        let item = try await chain.runJSON(
            SimpleItem.self,
            text: "input",
            mapPrompt: "Extract:", reducePrompt: "Combine:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        #expect(item.name == "test")
        #expect(item.count == 42)
    }

    @Test func validJSON_withMarkdownFences() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = """
            Here's the result:
            ```json
            {"name": "fenced", "count": 7}
            ```
            """
        let chain = StuffChain(backend: mock)

        let item = try await chain.runJSON(
            SimpleItem.self,
            text: "input",
            mapPrompt: "Extract:", reducePrompt: "Combine:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        #expect(item.name == "fenced")
        #expect(item.count == 7)
    }

    @Test func validJSON_withSurroundingProse() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = """
            Based on my analysis, the result is:
            {"name": "embedded", "count": 3}
            I hope this helps!
            """
        let chain = StuffChain(backend: mock)

        let item = try await chain.runJSON(
            SimpleItem.self,
            text: "input",
            mapPrompt: "Extract:", reducePrompt: "Combine:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        #expect(item.name == "embedded")
    }

    @Test func invalidJSON_throwsError() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "not json at all"
        let chain = StuffChain(backend: mock)

        do {
            _ = try await chain.runJSON(
                SimpleItem.self,
                text: "input",
                mapPrompt: "Extract:", reducePrompt: "Combine:",
                options: ChainExecutionOptions(reservedOutputTokens: 0)
            )
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is StructuredOutputError)
        }
    }

    @Test func retryAfterInvalidJSON_succeedsOnSecondAttempt() async throws {
        let responses = [
            "this is not json",
            #"{"name": "retry", "count": 1}"#
        ]
        let mock = MockSequentialBackend(responses: responses)
        let chain = StuffChain(backend: mock)

        let item = try await chain.runJSON(
            SimpleItem.self,
            text: "input",
            mapPrompt: "Extract:", reducePrompt: "Combine:",
            options: ChainExecutionOptions(
                reservedOutputTokens: 0,
                retryPolicy: RetryPolicy(maxAttempts: 2)
            )
        )

        #expect(item.name == "retry")
    }

    @Test func allRetriesExhausted_throwsRetriesExhausted() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "still not json"
        let chain = StuffChain(backend: mock)

        do {
            _ = try await chain.runJSON(
                SimpleItem.self,
                text: "input",
                mapPrompt: "Extract:", reducePrompt: "Combine:",
                options: ChainExecutionOptions(
                    reservedOutputTokens: 0,
                    retryPolicy: RetryPolicy(maxAttempts: 3)
                )
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as StructuredOutputError {
            if case .retriesExhausted = error {
                // expected
            } else {
                #expect(Bool(false), "Expected retriesExhausted, got \(error)")
            }
        }
    }

    @Test func jsonArray_decodesSuccessfully() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = #"[{"name": "a", "count": 1}, {"name": "b", "count": 2}]"#
        let chain = StuffChain(backend: mock)

        let items = try await chain.runJSON(
            [SimpleItem].self,
            text: "input",
            mapPrompt: "Extract:", reducePrompt: "Combine:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        #expect(items.count == 2)
        #expect(items[0].name == "a")
        #expect(items[1].name == "b")
    }

    @Test func schemaMismatch_throwsError() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = #"{"wrong_field": "value"}"#
        let chain = StuffChain(backend: mock)

        do {
            _ = try await chain.runJSON(
                SimpleItem.self,
                text: "input",
                mapPrompt: "Extract:", reducePrompt: "Combine:",
                options: ChainExecutionOptions(reservedOutputTokens: 0)
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as StructuredOutputError {
            if case .schemaMismatch = error {
                // expected
            } else {
                #expect(Bool(false), "Expected schemaMismatch, got \(error)")
            }
        }
    }

    // MARK: - JSON Repair Helper

    @Test func jsonRepair_stripsCodeFences() {
        let input = "```json\n{\"a\": 1}\n```"
        let result = JSONRepairHelper.extractJSON(from: input)
        #expect(result == "{\"a\": 1}")
    }

    @Test func jsonRepair_extractsEmbeddedObject() {
        let input = "The answer is: {\"x\": true} hope that helps"
        let result = JSONRepairHelper.extractJSON(from: input)
        #expect(result == "{\"x\": true}")
    }

    @Test func jsonRepair_extractsEmbeddedArray() {
        let input = "Results: [{\"a\":1}] done"
        let result = JSONRepairHelper.extractJSON(from: input)
        #expect(result == "[{\"a\":1}]")
    }

    @Test func jsonRepair_handlesNestedBraces() {
        let input = #"{"outer": {"inner": {"deep": true}}}"#
        let result = JSONRepairHelper.extractJSON(from: input)
        #expect(result == input)
    }

    @Test func jsonRepair_handlesStringWithBraces() {
        let input = #"{"text": "hello { world }"}"#
        let result = JSONRepairHelper.extractJSON(from: input)
        #expect(result == input)
    }
}
