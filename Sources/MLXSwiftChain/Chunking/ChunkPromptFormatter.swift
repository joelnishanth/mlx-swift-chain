import Foundation

/// Builds labeled text for a chunk, using diagnostic metadata when
/// available and falling back to generic `[Chunk N]` labels otherwise.
///
/// Use this to prepend richer source labels in map prompts for
/// diagnostic workflows:
///
/// ```swift
/// let labeled = ChunkPromptFormatter.labeledText(for: chunk)
/// let prompt = mapPrompt + labeled
/// ```
///
/// For non-diagnostic chunks the output is identical to the default
/// `[Chunk N]` labels used by `MapReduceChain`.
public struct ChunkPromptFormatter: Sendable {

    /// Returns chunk text prefixed with the most informative available label.
    ///
    /// - Diagnostic chunks (`logMetadata != nil`): uses ``DiagnosticSourceLabel``
    ///   to produce `[Chunk N, kind, detail]` labels.
    /// - All other chunks: uses `[Chunk N]` (1-based).
    public static func labeledText(for chunk: TextChunk) -> String {
        if chunk.metadata.logMetadata != nil {
            return "\(DiagnosticSourceLabel.label(for: chunk))\n\(chunk.text)"
        }
        return "[Chunk \(chunk.index + 1)]\n\(chunk.text)"
    }
}
