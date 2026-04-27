import Foundation

/// Options controlling how document chains execute map and reduce phases.
///
/// Defaults are tuned for on-device MLX inference where the GPU serializes
/// inference calls. For remote backends, increase `maxConcurrentMapTasks`.
public struct ChainExecutionOptions: Sendable, Equatable {
    /// Tokens to reserve for the model's output in budget calculations.
    /// Defaults to 512, which provides a conservative margin for most
    /// on-device models. Set to 0 for maximum-input / legacy behavior.
    public var reservedOutputTokens: Int

    /// Upper bound on summaries to combine in a single reduce call during
    /// hierarchical reduce. When a context budget is available, actual group
    /// size is derived from remaining budget; this acts as a cap.
    public var maxReduceGroupSize: Int

    /// Safety limit on recursive reduce depth to prevent runaway loops
    /// if the model produces verbose intermediate summaries.
    public var maxReduceDepth: Int

    /// Number of map calls to run concurrently. Default is 1 (sequential),
    /// which is optimal for on-device MLX inference since the Apple Silicon
    /// GPU processes one inference at a time.
    public var maxConcurrentMapTasks: Int

    /// When concurrent mapping is enabled, whether to return results in
    /// the original chunk order.
    public var preserveOrder: Bool

    /// Retry policy for failed map and reduce LLM calls.
    /// Default is `.none` (no retry), suitable for on-device inference.
    public var retryPolicy: RetryPolicy

    public init(
        reservedOutputTokens: Int = 512,
        maxReduceGroupSize: Int = 8,
        maxReduceDepth: Int = 5,
        maxConcurrentMapTasks: Int = 1,
        preserveOrder: Bool = true,
        retryPolicy: RetryPolicy = .none
    ) {
        self.reservedOutputTokens = reservedOutputTokens
        self.maxReduceGroupSize = maxReduceGroupSize
        self.maxReduceDepth = maxReduceDepth
        self.maxConcurrentMapTasks = max(1, maxConcurrentMapTasks)
        self.preserveOrder = preserveOrder
        self.retryPolicy = retryPolicy
    }
}
