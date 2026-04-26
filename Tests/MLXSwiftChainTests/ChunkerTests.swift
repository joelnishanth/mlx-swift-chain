import Testing
@testable import MLXSwiftChain

@Suite("TextChunker Tests")
struct ChunkerTests {

    // MARK: - FixedSizeChunker

    @Test("FixedSizeChunker splits at word boundaries")
    func fixedSize_basic() {
        let chunker = FixedSizeChunker(maxWords: 3)
        let chunks = chunker.chunk("one two three four five six seven")
        #expect(chunks.count == 3)
        #expect(chunks[0].text == "one two three")
        #expect(chunks[1].text == "four five six")
        #expect(chunks[2].text == "seven")
        #expect(chunks[0].index == 0)
        #expect(chunks[2].index == 2)
    }

    @Test("FixedSizeChunker returns empty for empty input")
    func fixedSize_empty() {
        let chunker = FixedSizeChunker(maxWords: 100)
        let chunks = chunker.chunk("")
        #expect(chunks.isEmpty)
    }

    @Test("FixedSizeChunker returns single chunk for small input")
    func fixedSize_singleChunk() {
        let chunker = FixedSizeChunker(maxWords: 100)
        let chunks = chunker.chunk("hello world")
        #expect(chunks.count == 1)
        #expect(chunks[0].wordCount == 2)
    }

    @Test("FixedSizeChunker handles mixed whitespace")
    func fixedSize_mixedWhitespace() {
        let chunker = FixedSizeChunker(maxWords: 2)
        let chunks = chunker.chunk("one\t two\nthree")
        #expect(chunks.count == 2)
        #expect(chunks[0].text == "one two")
        #expect(chunks[1].text == "three")
    }

    @Test("FixedSizeChunker scales linearly")
    func fixedSize_scaling() {
        let chunker = FixedSizeChunker(maxWords: 500)
        let words = (0..<5000).map { "word\($0)" }.joined(separator: " ")
        let chunks = chunker.chunk(words)
        #expect(chunks.count == 10)
        for (i, chunk) in chunks.enumerated() {
            #expect(chunk.index == i)
        }
    }

    // MARK: - SentenceAwareChunker

    @Test("SentenceAwareChunker respects sentence boundaries")
    func sentenceAware_basic() {
        let chunker = SentenceAwareChunker(targetWords: 5)
        let text = "This is sentence one. This is sentence two. This is sentence three."
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 2)
        for chunk in chunks {
            let trimmed = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!trimmed.isEmpty)
        }
    }

    @Test("SentenceAwareChunker returns single chunk for short text")
    func sentenceAware_short() {
        let chunker = SentenceAwareChunker(targetWords: 1000)
        let chunks = chunker.chunk("Hello world. Short text.")
        #expect(chunks.count == 1)
    }

    @Test("SentenceAwareChunker handles text without sentence punctuation")
    func sentenceAware_noPunctuation() {
        let chunker = SentenceAwareChunker(targetWords: 3)
        let text = "one\ttwo\nthree four five six"
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)
    }

    @Test("SentenceAwareChunker returns empty for empty input")
    func sentenceAware_empty() {
        let chunker = SentenceAwareChunker(targetWords: 100)
        let chunks = chunker.chunk("")
        #expect(chunks.isEmpty)
    }

    @Test("SentenceAwareChunker preserves all content")
    func sentenceAware_noContentLoss() {
        let chunker = SentenceAwareChunker(targetWords: 10)
        let text = "First sentence here. Second sentence there. Third one follows. And a fourth appears."
        let chunks = chunker.chunk(text)
        let reassembled = chunks.map(\.text).joined(separator: " ")
        for word in text.split(separator: " ") {
            #expect(reassembled.contains(word), "Missing word: \(word)")
        }
    }
}
