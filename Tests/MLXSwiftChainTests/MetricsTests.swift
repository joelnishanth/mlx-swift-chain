import Foundation
import Testing
@testable import MLXSwiftChain

@Suite("ChainMetrics Tests")
struct MetricsTests {

    @Test func metricsAccumulator_finalizesCorrectly() {
        var acc = MetricsAccumulator()
        acc.chunkCount = 5
        acc.mapCallCount = 5
        acc.reduceCallCount = 2
        acc.inputTokens = 1000
        acc.outputTokens = 200

        let metrics = acc.finalize(elapsed: .seconds(10))

        #expect(metrics.chunkCount == 5)
        #expect(metrics.mapCallCount == 5)
        #expect(metrics.reduceCallCount == 2)
        #expect(metrics.elapsedTime == .seconds(10))
        #expect(metrics.estimatedInputTokens == 1000)
        #expect(metrics.estimatedOutputTokens == 200)
        #expect(metrics.tokensPerSecond! == 20.0)
    }

    @Test func metricsAccumulator_nilWhenNoTokens() {
        var acc = MetricsAccumulator()
        acc.chunkCount = 3
        acc.mapCallCount = 3

        let metrics = acc.finalize(elapsed: .seconds(1))

        #expect(metrics.estimatedInputTokens == nil)
        #expect(metrics.estimatedOutputTokens == nil)
        #expect(metrics.tokensPerSecond == nil)
    }

    @Test func metricsAccumulator_zeroElapsedHandled() {
        var acc = MetricsAccumulator()
        acc.outputTokens = 100

        let metrics = acc.finalize(elapsed: .zero)

        #expect(metrics.tokensPerSecond == nil)
    }

    @Test func stuffChain_metrics() async throws {
        let mock = MockLLMBackend()
        let chain = StuffChain(backend: mock)

        let result = try await chain.runWithMetadata(
            "hello world",
            mapPrompt: "M:", reducePrompt: "R:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        let m = result.metrics!
        #expect(m.chunkCount == 0)
        #expect(m.mapCallCount == 0)
        #expect(m.reduceCallCount == 0)
        #expect(m.elapsedTime > .zero)
    }

    @Test func mapReduceChain_metricsTracksCalls() async throws {
        let mock = MockLLMBackend()
        mock.cannedResponse = "summary"
        let words = (0..<60).map { "word\($0)" }.joined(separator: " ")
        let chunker = FixedSizeChunker(maxWords: 20)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let result = try await chain.runWithMetadata(
            words,
            mapPrompt: "M:", reducePrompt: "R:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        let m = result.metrics!
        #expect(m.chunkCount >= 3)
        #expect(m.mapCallCount >= 3)
        #expect(m.reduceCallCount >= 1)
        #expect(m.elapsedTime > .zero)
    }

    @Test func tokenAwareBackend_metricsIncludeTokens() async throws {
        let mock = MockTokenAwareBackend(contextWindowTokens: 10000, tokensPerWord: 1.0)
        mock.cannedResponse = "output word"
        let words = (0..<60).map { "word\($0)" }.joined(separator: " ")
        let chunker = FixedSizeChunker(maxWords: 20)
        let chain = MapReduceChain(backend: mock, chunker: chunker)

        let result = try await chain.runWithMetadata(
            words,
            mapPrompt: "M:", reducePrompt: "R:",
            options: ChainExecutionOptions(reservedOutputTokens: 0)
        )

        let m = result.metrics!
        #expect(m.estimatedInputTokens != nil)
        #expect(m.estimatedInputTokens! > 0)
        #expect(m.estimatedOutputTokens != nil)
        #expect(m.estimatedOutputTokens! > 0)
    }

    @Test func chainMetrics_init() {
        let m = ChainMetrics()
        #expect(m.chunkCount == 0)
        #expect(m.mapCallCount == 0)
        #expect(m.reduceCallCount == 0)
        #expect(m.elapsedTime == .zero)
        #expect(m.estimatedInputTokens == nil)
        #expect(m.tokensPerSecond == nil)
    }

    @Test func progressUpdate_includesPartialMetrics() {
        let metrics = ChainMetrics(chunkCount: 3, mapCallCount: 2)
        let update = ChainProgress.Update(
            phase: .mapping(step: 2, of: 3),
            elapsedTime: .seconds(5),
            partialMetrics: metrics
        )
        #expect(update.partialMetrics?.chunkCount == 3)
        #expect(update.partialMetrics?.mapCallCount == 2)
    }

    @Test func progressUpdate_partialMetricsDefaultsToNil() {
        let update = ChainProgress.Update(phase: .stuffing, elapsedTime: .seconds(1))
        #expect(update.partialMetrics == nil)
    }
}
