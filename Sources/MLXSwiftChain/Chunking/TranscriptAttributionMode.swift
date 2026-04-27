import Foundation

/// Controls how `TranscriptChunker` segments and attributes chunks.
///
/// - ``auto``: Inspects detected speaker labels and selects the best strategy.
/// - ``speaker``: Forces speaker-turn chunking regardless of speaker count.
/// - ``temporal``: Chunks by timestamp boundaries and paragraph breaks.
/// - ``topical``: Chunks by detected topic headings and section structure.
public enum TranscriptAttributionMode: Sendable, Equatable {
    case auto
    case speaker
    case temporal
    case topical
}
