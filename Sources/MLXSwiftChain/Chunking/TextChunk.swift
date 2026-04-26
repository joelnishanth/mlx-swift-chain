import Foundation

/// Rich metadata associated with a chunked text segment.
public struct TextChunkMetadata: Sendable {
    /// Zero-based index within the sequence of chunks.
    public let chunkIndex: Int
    /// Range of words covered by this chunk in the original source text.
    public let sourceWordRange: Range<Int>
    /// Timestamps found inside this chunk (for transcript-like inputs).
    public let timestamps: [String]
    /// Speaker labels found inside this chunk (for transcript-like inputs).
    public let speakerLabels: [String]

    public init(
        chunkIndex: Int,
        sourceWordRange: Range<Int>,
        timestamps: [String] = [],
        speakerLabels: [String] = []
    ) {
        self.chunkIndex = chunkIndex
        self.sourceWordRange = sourceWordRange
        self.timestamps = timestamps
        self.speakerLabels = speakerLabels
    }
}

/// A segment of text produced by a `TextChunker`.
public struct TextChunk: Sendable {
    /// The chunk's text content.
    public let text: String
    /// Zero-based index within the sequence of chunks.
    public let index: Int
    /// Estimated word count.
    public let wordCount: Int
    /// Metadata preserving source and transcript context.
    public let metadata: TextChunkMetadata

    public init(text: String, index: Int, wordCount: Int, metadata: TextChunkMetadata? = nil) {
        self.text = text
        self.index = index
        self.wordCount = wordCount
        self.metadata = metadata ?? TextChunkMetadata(
            chunkIndex: index,
            sourceWordRange: 0..<wordCount
        )
    }
}
