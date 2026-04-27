import Foundation
import Testing
@testable import MLXSwiftChain

@Suite("CodeBlockAwareChunker Tests")
struct CodeBlockAwareChunkerTests {

    @Test func preservesCodeBlock() {
        let text = """
        Some introduction text here.

        ```swift
        func hello() {
            print("Hello, World!")
        }
        ```

        Some conclusion text here.
        """
        let chunker = CodeBlockAwareChunker(targetWords: 5)
        let chunks = chunker.chunk(text)

        let codeChunks = chunks.filter {
            $0.metadata.documentLocation?.primaryBlockType == .codeBlock
        }
        #expect(codeChunks.count >= 1)
        #expect(codeChunks[0].text.contains("func hello()"))
        #expect(codeChunks[0].text.contains("```swift"))
    }

    @Test func doesNotSplitInsideCodeBlock() {
        let longCode = (0..<50).map { "    let x\($0) = \($0)" }.joined(separator: "\n")
        let text = """
        Intro paragraph.

        ```python
        \(longCode)
        ```

        Outro paragraph.
        """

        let chunker = CodeBlockAwareChunker(targetWords: 20)
        let chunks = chunker.chunk(text)

        for chunk in chunks {
            if chunk.text.contains("```python") {
                #expect(chunk.text.contains("```"))
                let backtickCount = chunk.text.components(separatedBy: "```").count - 1
                #expect(backtickCount >= 2)
            }
        }
    }

    @Test func oversizedCodeBlockBecomesOwnChunk() {
        let longCode = (0..<100).map { "line\($0) = value" }.joined(separator: "\n")
        let text = """
        Before.

        ```
        \(longCode)
        ```

        After.
        """

        let chunker = CodeBlockAwareChunker(targetWords: 10)
        let chunks = chunker.chunk(text)

        #expect(chunks.count >= 2)
        let codeChunk = chunks.first { $0.text.contains("line0") }
        #expect(codeChunk != nil)
        #expect(codeChunk!.metadata.documentLocation?.primaryBlockType == .codeBlock)
    }

    @Test func mixedContent_splitsAtParagraphBoundaries() {
        let text = """
        First paragraph with some words here.

        Second paragraph with more words here.

        Third paragraph finishing up the text.
        """

        let chunker = CodeBlockAwareChunker(targetWords: 8)
        let chunks = chunker.chunk(text)

        #expect(chunks.count >= 2)
        for chunk in chunks {
            #expect(chunk.wordCount > 0)
        }
    }

    @Test func emptyInput_returnsEmpty() {
        let chunker = CodeBlockAwareChunker(targetWords: 100)
        let chunks = chunker.chunk("")
        #expect(chunks.isEmpty)
    }

    @Test func tildeCodeFences_alsoPreserved() {
        let text = """
        Intro.

        ~~~ruby
        puts "hello"
        ~~~

        Outro.
        """

        let chunker = CodeBlockAwareChunker(targetWords: 3)
        let chunks = chunker.chunk(text)

        let rubyChunk = chunks.first { $0.text.contains("puts") }
        #expect(rubyChunk != nil)
        #expect(rubyChunk!.metadata.documentLocation?.primaryBlockType == .codeBlock)
    }

    @Test func noCodeBlocks_chunksNormally() {
        let paragraphs = (0..<5).map { i in
            (0..<12).map { "w\(i)_\($0)" }.joined(separator: " ")
        }
        let text = paragraphs.joined(separator: "\n\n")
        let chunker = CodeBlockAwareChunker(targetWords: 15)
        let chunks = chunker.chunk(text)

        #expect(chunks.count >= 3)
        for chunk in chunks {
            #expect(chunk.metadata.documentLocation?.primaryBlockType == nil)
        }
    }

    @Test func metadata_hasCorrectIndices() {
        let text = """
        Paragraph one with words.

        ```
        code here
        ```

        Paragraph two with words.
        """

        let chunker = CodeBlockAwareChunker(targetWords: 5)
        let chunks = chunker.chunk(text)

        for (i, chunk) in chunks.enumerated() {
            #expect(chunk.index == i)
            #expect(chunk.metadata.chunkIndex == i)
        }
    }
}
