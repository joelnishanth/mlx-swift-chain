import Foundation

/// Reports progress of a multi-step chain execution.
public final class ChainProgress: Sendable {
    public enum Phase: Sendable, Equatable {
        case stuffing
        case mapping(step: Int, of: Int)
        case reducing
        case complete
    }

    public struct Update: Sendable {
        public let phase: Phase
        public let elapsedTime: Duration
        /// Partial metrics snapshot at the time of this update, if available.
        public let partialMetrics: ChainMetrics?

        public init(phase: Phase, elapsedTime: Duration, partialMetrics: ChainMetrics? = nil) {
            self.phase = phase
            self.elapsedTime = elapsedTime
            self.partialMetrics = partialMetrics
        }
    }

    private let continuation: AsyncStream<Update>.Continuation
    public let updates: AsyncStream<Update>

    public init() {
        var cont: AsyncStream<Update>.Continuation!
        self.updates = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public func report(_ update: Update) {
        continuation.yield(update)
    }

    public func finish() {
        continuation.finish()
    }
}
