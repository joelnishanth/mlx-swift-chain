import Foundation

/// Errors thrown during chain execution.
public enum ChainError: Error, LocalizedError, Equatable {
    /// Hierarchical reduce exceeded the maximum allowed depth.
    case reduceDepthExceeded(maxDepth: Int)

    public var errorDescription: String? {
        switch self {
        case .reduceDepthExceeded(let maxDepth):
            return "Hierarchical reduce exceeded maximum depth of \(maxDepth). The model may be producing excessively verbose intermediate summaries."
        }
    }
}
