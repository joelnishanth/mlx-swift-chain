import Foundation

/// Describes how a chunk's boundaries were determined.
public enum ChunkAttributionType: String, Sendable, Equatable {
    case speaker
    case temporal
    case topical
}

/// The first and last timestamp found within a chunk.
public struct TimestampRange: Sendable, Equatable {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

/// A range of pages spanned by a chunk in the original document.
public struct PageRange: Sendable, Equatable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// The structural role of a block within a document.
public enum DocumentBlockType: String, Sendable, Equatable {
    case heading
    case paragraph
    case list
    case table
    case codeBlock
    case blockQuote
    case figureCaption
    case footnote
    case pageBreak
    case thematicBreak
    case unknown
}

/// Describes where a chunk sits within the document's structure.
public struct DocumentLocation: Sendable, Equatable {
    public let pageRange: PageRange?
    public let headingPath: [String]
    public let primaryBlockType: DocumentBlockType?
    public let blockTypes: [DocumentBlockType]

    public init(
        pageRange: PageRange? = nil,
        headingPath: [String] = [],
        primaryBlockType: DocumentBlockType? = nil,
        blockTypes: [DocumentBlockType] = []
    ) {
        self.pageRange = pageRange
        self.headingPath = headingPath
        self.primaryBlockType = primaryBlockType
        self.blockTypes = blockTypes
    }
}

/// Rich metadata associated with a chunked text segment.
public struct TextChunkMetadata: Sendable, Equatable {
    /// Zero-based index within the sequence of chunks.
    public let chunkIndex: Int
    /// Range of words covered by this chunk in the original source text.
    public let sourceWordRange: Range<Int>
    /// Timestamps found inside this chunk (for transcript-like inputs).
    public let timestamps: [String]
    /// Speaker labels found inside this chunk (for transcript-like inputs).
    public let speakerLabels: [String]
    /// How this chunk's boundaries were determined, if known.
    public let attributionType: ChunkAttributionType?
    /// Inferred topic heading for this chunk (topical attribution only).
    public let topicLabel: String?
    /// Convenience range of the first and last timestamp in this chunk.
    public let timestampRange: TimestampRange?
    /// Structural location within a document (headings, pages, block types).
    public let documentLocation: DocumentLocation?
    /// Diagnostic metadata for log or crash report chunks.
    public let logMetadata: LogMetadata?

    public init(
        chunkIndex: Int,
        sourceWordRange: Range<Int>,
        timestamps: [String] = [],
        speakerLabels: [String] = [],
        attributionType: ChunkAttributionType? = nil,
        topicLabel: String? = nil,
        timestampRange: TimestampRange? = nil,
        documentLocation: DocumentLocation? = nil,
        logMetadata: LogMetadata? = nil
    ) {
        self.chunkIndex = chunkIndex
        self.sourceWordRange = sourceWordRange
        self.timestamps = timestamps
        self.speakerLabels = speakerLabels
        self.attributionType = attributionType
        self.topicLabel = topicLabel
        self.timestampRange = timestampRange
        self.documentLocation = documentLocation
        self.logMetadata = logMetadata
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
