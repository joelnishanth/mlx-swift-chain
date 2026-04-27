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

    // MARK: - TranscriptChunker Attribution Modes

    @Test("Single-speaker transcript avoids repetitive speaker-only chunks")
    func transcript_singleSpeakerNoRepetitiveChunks() {
        let chunker = TranscriptChunker(targetWords: 15)
        let text = """
        00:00 Speaker: Today I want to talk about the product roadmap.
        00:30 Speaker: We need to focus on three key areas this quarter.
        01:00 Speaker: First area is performance improvements across the board.
        01:30 Speaker: Second area is the new onboarding flow for users.
        02:00 Speaker: Third area is API stability and documentation updates.
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            #expect(chunk.metadata.attributionType != .speaker,
                    "Single-speaker should not use speaker attribution")
            #expect(chunk.metadata.speakerLabels.isEmpty,
                    "Single-speaker chunks should suppress speaker labels")
        }
    }

    @Test("Single-speaker transcript with timestamps uses temporal chunking")
    func transcript_singleSpeakerTimestampChunking() {
        let chunker = TranscriptChunker(targetWords: 10)
        let text = """
        00:05 Rahul: Thinking about the new feature set for next release.
        00:45 Rahul: We should prioritize the search improvements first.
        01:20 Rahul: Then move on to the notification system redesign.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 2)
        for chunk in chunks {
            #expect(chunk.metadata.attributionType == .temporal)
        }
        if let first = chunks.first, let range = first.metadata.timestampRange {
            #expect(!range.start.isEmpty)
            #expect(!range.end.isEmpty)
        }
    }

    @Test("Multi-speaker transcript still uses speaker turn chunking")
    func transcript_multiSpeakerStillSpeakerTurns() {
        let chunker = TranscriptChunker(targetWords: 15)
        let text = """
        00:05 Alice: Welcome to the standup, let's go around.
        00:10 Bob: I finished the auth module yesterday afternoon.
        00:20 Carol: I'm working on the dashboard components today.
        00:30 Alice: Great progress everyone, any blockers to discuss?
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            #expect(chunk.metadata.attributionType == .speaker)
        }
        let allSpeakers = Set(chunks.flatMap(\.metadata.speakerLabels))
        #expect(allSpeakers.contains("Alice"))
        #expect(allSpeakers.contains("Bob"))
    }

    @Test("Auto mode selects temporal for single speaker and speaker for multi")
    func transcript_autoModeSelects() {
        let chunker = TranscriptChunker(targetWords: 15)

        let singleSpeaker = """
        00:00 Narrator: First point about the architecture decisions.
        00:30 Narrator: Second point about the deployment strategy.
        01:00 Narrator: Third point about the monitoring setup.
        """
        let singleChunks = chunker.chunk(singleSpeaker)
        #expect(!singleChunks.isEmpty)
        for chunk in singleChunks {
            #expect(chunk.metadata.attributionType == .temporal,
                    "Single speaker should resolve to temporal")
        }

        let multiSpeaker = """
        Alice: First turn with enough words to fill space here.
        Bob: Second turn with enough words to fill space here.
        Carol: Third turn with enough words to fill space here.
        """
        let multiChunks = chunker.chunk(multiSpeaker)
        #expect(!multiChunks.isEmpty)
        for chunk in multiChunks {
            #expect(chunk.metadata.attributionType == .speaker,
                    "Multi speaker should resolve to speaker")
        }
    }

    @Test("Topical chunking detects heading structure and populates topic label")
    func transcript_topicalChunking() {
        let chunker = TranscriptChunker(targetWords: 50, attributionMode: .topical)
        let text = """
        # Product Vision
        We want to build the best tool for local inference on Apple Silicon.
        This means fast chunking, smart attribution, and great defaults.

        # Engineering Plan
        The implementation will use map-reduce chains with adaptive routing.
        We need to support both short and very long documents gracefully.

        # Timeline
        Phase one ships in Q3. Phase two follows in Q4 with full API stability.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 2)
        for chunk in chunks {
            #expect(chunk.metadata.attributionType == .topical)
        }
        let topics = chunks.compactMap(\.metadata.topicLabel)
        #expect(!topics.isEmpty, "At least one chunk should have a topic label")
        #expect(topics.contains("Product Vision") || topics.contains("Engineering Plan")
                || topics.contains("Timeline"))
    }

    @Test("Topical chunking falls back to temporal when no headings exist")
    func transcript_topicalFallsBackToTemporal() {
        let chunker = TranscriptChunker(targetWords: 10, attributionMode: .topical)
        let text = """
        00:00 Just thinking out loud about the project.
        00:30 Need to figure out the deployment story.
        01:00 Also the monitoring and alerting setup.
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            #expect(chunk.metadata.attributionType == .temporal,
                    "Should fall back to temporal when no headings found")
        }
    }

    @Test("Forced speaker mode uses speaker attribution even for single speaker")
    func transcript_forcedSpeakerMode() {
        let chunker = TranscriptChunker(targetWords: 15, attributionMode: .speaker)
        let text = """
        00:00 Rahul: First thought about the new feature.
        00:30 Rahul: Second thought about performance tuning.
        01:00 Rahul: Third thought about user experience.
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            #expect(chunk.metadata.attributionType == .speaker,
                    "Forced speaker mode should use speaker attribution")
            #expect(chunk.metadata.speakerLabels.contains("Rahul"),
                    "Speaker label should be preserved in forced mode")
        }
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

    // MARK: - DocumentStructureChunker

    @Test("DocumentStructureChunker splits at ATX headings with headingPath")
    func docStructure_atxHeadings() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        # Introduction
        This is the intro paragraph with some content.

        ## Background
        Background details go here with enough words.

        ## Methods
        Methods are described in this section clearly.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 1)
        let allText = chunks.map(\.text).joined(separator: " ")
        #expect(allText.contains("Introduction"))
        #expect(allText.contains("Background"))
        #expect(allText.contains("Methods"))

        if let lastChunk = chunks.last,
           let loc = lastChunk.metadata.documentLocation {
            #expect(loc.headingPath.contains("Methods") || loc.headingPath.contains("Introduction"))
        }
    }

    @Test("DocumentStructureChunker detects Setext headings")
    func docStructure_setextHeadings() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        Main Title
        ==========
        Content under the main title here.

        Subtitle
        --------
        Content under the subtitle section.
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)

        let allText = chunks.map(\.text).joined(separator: " ")
        #expect(allText.contains("Main Title"))
        #expect(allText.contains("Subtitle"))

        if let loc = chunks.first?.metadata.documentLocation {
            #expect(loc.headingPath.contains("Main Title"))
            #expect(loc.blockTypes.contains(.heading))
        }
    }

    @Test("DocumentStructureChunker detects all page marker formats")
    func docStructure_pageMarkers() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        [Page 1]
        Content on page one here with words.

        --- Page 2 ---
        Content on page two here with words.

        Page 3:
        Content on page three here with words.

        === Page 4 ===
        Content on page four here with words.

        [PAGE 5]
        Content on page five here with words.
        """
        let chunks = chunker.chunk(text)
        #expect(!chunks.isEmpty)

        let allText = chunks.map(\.text).joined(separator: " ")
        #expect(!allText.contains("[Page 1]"), "Page markers should not appear in chunk text")
        #expect(!allText.contains("--- Page 2 ---"), "Page markers should not appear in chunk text")
        #expect(!allText.contains("Page 3:"), "Page markers should not appear in chunk text")

        let allPages = chunks.compactMap { $0.metadata.documentLocation?.pageRange }
        #expect(!allPages.isEmpty, "At least one chunk should have a page range")
    }

    @Test("DocumentStructureChunker preserves fenced code blocks intact")
    func docStructure_codeBlockPreservation() {
        let chunker = DocumentStructureChunker(targetWords: 10)
        let text = """
        # Setup

        Some intro text.

        ```swift
        func hello() {
            print("Hello, world!")
            let x = 42
            let y = x + 1
            return y
        }
        ```

        More text after the code block.
        """
        let chunks = chunker.chunk(text)
        let codeChunk = chunks.first { $0.text.contains("func hello()") }
        #expect(codeChunk != nil, "Code block should be present")
        if let cc = codeChunk {
            #expect(cc.text.contains("return y"), "Code block should not be split")
            if let loc = cc.metadata.documentLocation {
                #expect(loc.blockTypes.contains(.codeBlock))
            }
        }
    }

    @Test("DocumentStructureChunker ignores headings inside code blocks")
    func docStructure_suppressionZoneHeading() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        # Real Heading
        Some content before the code block.

        ```markdown
        # Not A Heading
        This is just example code.
        ```

        More content after.
        """
        let chunks = chunker.chunk(text)
        let allHeadingPaths = chunks.compactMap { $0.metadata.documentLocation?.headingPath }.flatMap { $0 }
        #expect(allHeadingPaths.contains("Real Heading"))
        #expect(!allHeadingPaths.contains("Not A Heading"),
                "Headings inside code blocks must not be parsed")
    }

    @Test("DocumentStructureChunker ignores page markers inside code blocks")
    func docStructure_suppressionZonePageMarker() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        [Page 1]
        Content on page one.

        ```
        [Page 99]
        This is code, not a page marker.
        ```

        Content still on page one.
        """
        let chunks = chunker.chunk(text)
        let allPages = chunks.compactMap { $0.metadata.documentLocation?.pageRange }
        for pr in allPages {
            #expect(pr.start != 99 && pr.end != 99,
                    "Page markers inside code blocks must be ignored")
        }
    }

    @Test("DocumentStructureChunker preserves GFM pipe tables")
    func docStructure_tablePreservation() {
        let chunker = DocumentStructureChunker(targetWords: 10)
        let text = """
        # Data

        | Name  | Value |
        |-------|-------|
        | Alpha | 1     |
        | Beta  | 2     |
        | Gamma | 3     |
        | Delta | 4     |

        Following paragraph.
        """
        let chunks = chunker.chunk(text)
        let tableChunk = chunks.first { $0.text.contains("| Alpha |") }
        #expect(tableChunk != nil, "Table should be present")
        if let tc = tableChunk {
            #expect(tc.text.contains("| Delta |"), "Table should not be split")
            if let loc = tc.metadata.documentLocation {
                #expect(loc.blockTypes.contains(.table))
            }
        }
    }

    @Test("DocumentStructureChunker detects lists")
    func docStructure_listDetection() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        # Items

        - First bullet item
        - Second bullet item
        - Third bullet item

        1. First ordered item
        2. Second ordered item
        """
        let chunks = chunker.chunk(text)
        let allBlockTypes = chunks.compactMap { $0.metadata.documentLocation }
            .flatMap(\.blockTypes)
        #expect(allBlockTypes.contains(.list), "Should detect list blocks")
    }

    @Test("DocumentStructureChunker detects block quotes")
    func docStructure_blockQuoteDetection() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        # Quote Section

        > This is a block quote.
        > It spans multiple lines.
        > And contains important information.

        Regular paragraph after.
        """
        let chunks = chunker.chunk(text)
        let allBlockTypes = chunks.compactMap { $0.metadata.documentLocation }
            .flatMap(\.blockTypes)
        #expect(allBlockTypes.contains(.blockQuote), "Should detect block quote")
    }

    @Test("DocumentStructureChunker disambiguates Setext h2 from thematic break")
    func docStructure_setextVsThematicBreak() {
        let chunker = DocumentStructureChunker(targetWords: 1000)
        let text = """
        Heading Text
        ------------
        Content under heading.

        ---

        Content after thematic break.
        """
        let chunks = chunker.chunk(text)
        let allBlockTypes = chunks.compactMap { $0.metadata.documentLocation }
            .flatMap(\.blockTypes)
        #expect(allBlockTypes.contains(.heading), "Should detect Setext heading")
        #expect(allBlockTypes.contains(.thematicBreak), "Should detect thematic break")
    }

    @Test("DocumentStructureChunker handles mixed document with all block types")
    func docStructure_mixedDocument() {
        let chunker = DocumentStructureChunker(targetWords: 50)
        let text = """
        [Page 1]
        # Product Overview
        This product helps developers build on-device LLM apps.

        ## Features
        - Fast chunking
        - Smart attribution
        - Great defaults

        | Feature    | Status |
        |------------|--------|
        | Chunking   | Done   |
        | Attribution| Done   |

        [Page 2]
        ## Code Example

        ```swift
        let chain = AdaptiveChain(backend: backend)
        let result = try await chain.run(text)
        ```

        > Note: This requires macOS 14 or later.

        ---

        Final paragraph with conclusion text.
        """
        let chunks = chunker.chunk(text)
        #expect(chunks.count >= 2, "Mixed document should produce multiple chunks")
        for chunk in chunks {
            #expect(chunk.metadata.documentLocation != nil,
                    "Every chunk should have documentLocation")
        }
        let allBlockTypes = Set(chunks.compactMap { $0.metadata.documentLocation }
            .flatMap(\.blockTypes))
        #expect(allBlockTypes.contains(.heading))
        #expect(allBlockTypes.contains(.paragraph))
    }

    @Test("DocumentStructureChunker returns empty for empty input")
    func docStructure_empty() {
        let chunker = DocumentStructureChunker(targetWords: 100)
        let chunks = chunker.chunk("")
        #expect(chunks.isEmpty)
    }

    @Test("DocumentStructureChunker keeps headings with following content")
    func docStructure_headingStickiness() {
        let chunker = DocumentStructureChunker(targetWords: 8)
        let text = """
        # First Section
        Content for first section here.

        # Second Section
        Content for second section here.
        """
        let chunks = chunker.chunk(text)
        for chunk in chunks {
            let lines = chunk.text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let lastLine = lines.last, lastLine.hasPrefix("#") {
                #expect(lines.count > 1,
                        "Heading should not be orphaned at the end of a chunk: \(chunk.text)")
            }
        }
    }

    @Test("TextChunkMetadata supports Equatable comparison")
    func docStructure_metadataEquatable() {
        let loc = DocumentLocation(
            pageRange: PageRange(start: 1, end: 2),
            headingPath: ["Intro"],
            primaryBlockType: .heading,
            blockTypes: [.heading, .paragraph]
        )
        let m1 = TextChunkMetadata(
            chunkIndex: 0,
            sourceWordRange: 0..<10,
            documentLocation: loc
        )
        let m2 = TextChunkMetadata(
            chunkIndex: 0,
            sourceWordRange: 0..<10,
            documentLocation: loc
        )
        #expect(m1 == m2, "Identical TextChunkMetadata values should be equal")

        let m3 = TextChunkMetadata(
            chunkIndex: 1,
            sourceWordRange: 0..<10,
            documentLocation: loc
        )
        #expect(m1 != m3, "Different chunkIndex should make metadata unequal")
    }
}
