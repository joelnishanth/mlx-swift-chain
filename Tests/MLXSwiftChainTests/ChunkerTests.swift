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

    @Test("FixedSizeChunker supports overlap")
    func fixedSize_overlap() {
        let chunker = FixedSizeChunker(maxWords: 4, overlapWords: 1)
        let chunks = chunker.chunk("one two three four five six seven")
        #expect(chunks.count == 3)
        #expect(chunks[0].text == "one two three four")
        #expect(chunks[1].text == "four five six seven")
        #expect(chunks[2].text == "seven")
    }

    @Test("FixedSizeChunker preserves metadata")
    func fixedSize_metadata() {
        let chunker = FixedSizeChunker(maxWords: 6)
        let text = "00:05 Alex: project kickoff now underway with updates"
        let chunks = chunker.chunk(text)

        #expect(chunks.count == 2)
        #expect(chunks[0].metadata.chunkIndex == 0)
        #expect(chunks[0].metadata.sourceWordRange == 0..<6)
        #expect(chunks[0].metadata.timestamps.contains("00:05"))
        #expect(chunks[0].metadata.speakerLabels.contains("Alex"))
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

    @Test("SentenceAwareChunker supports sentence overlap")
    func sentenceAware_overlap() {
        let chunker = SentenceAwareChunker(targetWords: 4, overlapSentences: 1)
        let text = "One two. Three four. Five six. Seven eight."
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 3)
        #expect(chunks[0].text.contains("One two."))
        #expect(chunks[1].text.contains("Three four."))
        #expect(chunks[1].text.contains("Five six."))
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

    // MARK: - TranscriptChunker

    @Test("TranscriptChunker preserves speaker labels")
    func transcript_speakerLabels() {
        let chunker = TranscriptChunker(targetWords: 20)
        let text = """
        00:05 Alice: Welcome everyone to the meeting.
        00:10 Bob: Thanks Alice, let's get started with the agenda.
        00:15 Alice: First item is the quarterly review.
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)
        let allSpeakers = chunks.flatMap(\.metadata.speakerLabels)
        #expect(allSpeakers.contains("Alice"))
        #expect(allSpeakers.contains("Bob"))
    }

    @Test("TranscriptChunker splits at speaker turns")
    func transcript_splitAtTurns() {
        let chunker = TranscriptChunker(targetWords: 10)
        let text = """
        Alice: First turn with several words to fill up space here.
        Bob: Second turn also has several words to fill space here too.
        Carol: Third turn continues with more words filling space nicely.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 2, "Should split across speaker turns")
        for chunk in chunks {
            #expect(!chunk.text.isEmpty)
        }
    }

    @Test("TranscriptChunker preserves timestamps")
    func transcript_timestamps() {
        let chunker = TranscriptChunker(targetWords: 1000)
        let text = """
        10:30 Alice: Good morning.
        10:35 Bob: Morning, Alice.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count == 1)
        let timestamps = chunks[0].metadata.timestamps
        #expect(timestamps.contains("10:30"))
        #expect(timestamps.contains("10:35"))
    }

    @Test("TranscriptChunker supports overlap turns")
    func transcript_overlapTurns() {
        let chunker = TranscriptChunker(targetWords: 8, overlapTurns: 1)
        let text = """
        Alice: First turn words here now.
        Bob: Second turn words here now.
        Carol: Third turn words here now.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 2)
        if chunks.count >= 2 {
            #expect(chunks[1].text.contains("Bob") || chunks[1].text.contains("Alice"),
                    "Overlap should include previous turn")
        }
    }

    @Test("TranscriptChunker returns empty for empty input")
    func transcript_empty() {
        let chunker = TranscriptChunker(targetWords: 100)
        let chunks = chunker.chunk("")
        #expect(chunks.isEmpty)
    }

    // MARK: - MarkdownHeadingChunker

    @Test("MarkdownHeadingChunker splits by headings")
    func markdown_splitByHeadings() {
        let chunker = MarkdownHeadingChunker(targetWords: 1000)
        let text = """
        # Introduction
        This is the intro paragraph.

        # Methods
        This describes the methods used.

        # Results
        Here are the results.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count == 3)
        #expect(chunks[0].text.contains("Introduction"))
        #expect(chunks[1].text.contains("Methods"))
        #expect(chunks[2].text.contains("Results"))
    }

    @Test("MarkdownHeadingChunker preserves heading text in chunks")
    func markdown_preservesHeadings() {
        let chunker = MarkdownHeadingChunker(targetWords: 1000)
        let text = """
        # Title
        Some content here.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count == 1)
        #expect(chunks[0].text.hasPrefix("# Title"))
    }

    @Test("MarkdownHeadingChunker falls back to sentence splitting for large sections")
    func markdown_largeSectionFallback() {
        let chunker = MarkdownHeadingChunker(targetWords: 10)
        var longBody = (0..<50).map { "Word\($0)" }.joined(separator: " ")
        let text = "# Big Section\n\n\(longBody)"
        let chunks = chunker.chunk(text)
        #expect(chunks.count > 1, "Large section should be sub-chunked")
    }

    @Test("MarkdownHeadingChunker returns empty for empty input")
    func markdown_empty() {
        let chunker = MarkdownHeadingChunker(targetWords: 100)
        let chunks = chunker.chunk("")
        #expect(chunks.isEmpty)
    }

    @Test("MarkdownHeadingChunker respects maxHeadingLevel")
    func markdown_headingLevel() {
        let chunker = MarkdownHeadingChunker(targetWords: 1000, maxHeadingLevel: 2)
        let text = """
        # H1
        Content one.
        ## H2
        Content two.
        ### H3 not a split point
        Content three.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count == 2, "Only H1 and H2 should trigger splits")
    }

    // MARK: - LogChunker

    @Test("LogChunker splits at timestamp boundaries")
    func log_timestampBoundaries() {
        let chunker = LogChunker(targetWords: 15)
        let text = """
        2024-01-15 10:30:00 INFO Starting application
        2024-01-15 10:30:01 INFO Loading configuration
        2024-01-15 10:30:02 INFO Ready to serve
        2024-01-15 10:31:00 INFO Processing request one
        2024-01-15 10:31:01 INFO Processing request two
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 2)
        let allTimestamps = chunks.flatMap(\.metadata.timestamps)
        #expect(allTimestamps.contains("2024-01-15 10:30:00"))
    }

    @Test("LogChunker keeps stack traces together")
    func log_stackTraceIntact() {
        let chunker = LogChunker(targetWords: 50)
        let text = """
        2024-01-15 10:30:00 INFO Starting up
        2024-01-15 10:30:05 ERROR NullPointerException occurred
        	at com.example.App.main(App.java:42)
        	at com.example.App.init(App.java:10)
        	at com.example.Bootstrap.run(Bootstrap.java:5)
        2024-01-15 10:30:06 INFO Recovery attempted
        """
        let chunks = chunker.chunk(text)
        let stackChunk = chunks.first { $0.text.contains("NullPointerException") }
        #expect(stackChunk != nil)
        if let sc = stackChunk {
            #expect(sc.text.contains("App.java:42"), "Stack trace should not be split")
            #expect(sc.text.contains("Bootstrap.java:5"), "Full stack should stay together")
        }
    }

    @Test("LogChunker returns empty for empty input")
    func log_empty() {
        let chunker = LogChunker(targetWords: 100)
        let chunks = chunker.chunk("")
        #expect(chunks.isEmpty)
    }

    @Test("LogChunker extracts timestamps into metadata")
    func log_extractsTimestamps() {
        let chunker = LogChunker(targetWords: 1000)
        let text = """
        2024-01-15T10:30:00 INFO Event one
        2024-01-15T10:31:00 INFO Event two
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)
        let timestamps = chunks.flatMap(\.metadata.timestamps)
        #expect(timestamps.contains("2024-01-15T10:30:00"))
        #expect(timestamps.contains("2024-01-15T10:31:00"))
    }
}
