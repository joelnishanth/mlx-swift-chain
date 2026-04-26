import Testing
@testable import MLXSwiftChain

@Suite("Benchmark Coverage Tests")
struct BenchmarkCoverageTests {
    @Test("Benchmark markers at 25/50/75/100 are always seen")
    func benchmark_markerCoverage() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "ok"

        // Use overlap to simulate robust boundary handling under realistic chunking.
        let chunker = FixedSizeChunker(maxWords: 32, overlapWords: 8)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let totalWords = 400
        var words = (1...totalWords).map { "w\($0)" }
        words[99] = "MARKER_25"
        words[199] = "MARKER_50"
        words[299] = "MARKER_75"
        words[399] = "MARKER_100"

        let text = words.joined(separator: " ")
        _ = try await chain.run(text, mapPrompt: "", reducePrompt: "Final: ")

        let allPrompts = mock.promptsReceived.joined(separator: " ")
        #expect(allPrompts.contains("MARKER_25"))
        #expect(allPrompts.contains("MARKER_50"))
        #expect(allPrompts.contains("MARKER_75"))
        #expect(allPrompts.contains("MARKER_100"))
    }
}
