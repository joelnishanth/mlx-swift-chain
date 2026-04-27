import Foundation
#if canImport(os)
import os
#endif

/// Indicates the current memory pressure level of the process.
public enum MemoryPressure: Sendable, Equatable {
    /// Sufficient memory available for inference.
    case ok
    /// Memory is constrained; inference may succeed but is risky.
    case warning(availableMB: Int)
    /// Critically low memory; inference will likely fail or be killed.
    case critical(availableMB: Int)

    /// Estimate current memory availability using resident memory vs physical memory.
    ///
    /// This is a heuristic: it compares the process's current resident memory
    /// against total physical memory to estimate remaining headroom. On iOS
    /// this is particularly important as jetsam will kill the process under
    /// memory pressure.
    public static func current() -> MemoryPressure {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let residentBytes = Self.residentMemoryBytes()
        guard residentBytes > 0 else { return .ok }

        let availableBytes = Int64(physicalMemory) - residentBytes
        let mb = Int(max(0, availableBytes) / 1_048_576)

        if mb < 100 { return .critical(availableMB: mb) }
        if mb < 300 { return .warning(availableMB: mb) }
        return .ok
    }

    /// Whether inference should proceed (ok or warning).
    public var shouldProceed: Bool {
        switch self {
        case .ok, .warning: return true
        case .critical: return false
        }
    }

    /// Available memory in megabytes, or nil if ok.
    public var availableMB: Int? {
        switch self {
        case .ok: return nil
        case .warning(let mb): return mb
        case .critical(let mb): return mb
        }
    }

    private static func residentMemoryBytes() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }
}

#if canImport(os)
private let logger = Logger(subsystem: "MLXSwiftChain", category: "Memory")

extension MemoryPressure {
    /// Log the current memory state. Call before starting a chain execution
    /// to surface potential issues early.
    public func logIfConstrained() {
        switch self {
        case .ok:
            break
        case .warning(let mb):
            logger.warning("Memory constrained: \(mb)MB available. Inference may be slow or fail.")
        case .critical(let mb):
            logger.error("Critical memory pressure: \(mb)MB available. Inference will likely fail.")
        }
    }
}
#endif
