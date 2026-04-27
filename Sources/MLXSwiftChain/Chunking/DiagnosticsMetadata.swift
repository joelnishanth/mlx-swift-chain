import Foundation

/// The diagnostic category of a log or crash report chunk.
public enum LogChunkKind: String, Sendable, Equatable {
    case crashHeader
    case exceptionInfo
    case diagnosticMessage
    case lastExceptionBacktrace
    case crashedThread
    case threadBacktrace
    case registers
    case binaryImages
    case consoleLog
    case simulatorLog
    case xcodeBuildError
    case swiftCompilerError
    case linkerError
    case testFailure
    case stackTrace
    case runtimeWarning
    case memoryWarning
    case unknown
}

/// Whether a crash report's stack frames include human-readable symbols.
public enum SymbolicationStatus: String, Sendable, Equatable {
    case fullySymbolicated
    case partiallySymbolicated
    case unsymbolicated
    case unknown
}

/// Metadata extracted from an Apple crash report header and exception section.
public struct CrashReportMetadata: Sendable, Equatable {
    public let process: String?
    public let identifier: String?
    public let version: String?
    public let hardwareModel: String?
    public let osVersion: String?
    public let exceptionType: String?
    public let exceptionCodes: String?
    public let exceptionSubtype: String?
    public let terminationReason: String?
    public let terminationDescription: String?
    public let applicationSpecificInformation: String?
    public let crashedThread: String?
    public let signal: String?
    public let symbolicationStatus: SymbolicationStatus?

    public init(
        process: String? = nil,
        identifier: String? = nil,
        version: String? = nil,
        hardwareModel: String? = nil,
        osVersion: String? = nil,
        exceptionType: String? = nil,
        exceptionCodes: String? = nil,
        exceptionSubtype: String? = nil,
        terminationReason: String? = nil,
        terminationDescription: String? = nil,
        applicationSpecificInformation: String? = nil,
        crashedThread: String? = nil,
        signal: String? = nil,
        symbolicationStatus: SymbolicationStatus? = nil
    ) {
        self.process = process
        self.identifier = identifier
        self.version = version
        self.hardwareModel = hardwareModel
        self.osVersion = osVersion
        self.exceptionType = exceptionType
        self.exceptionCodes = exceptionCodes
        self.exceptionSubtype = exceptionSubtype
        self.terminationReason = terminationReason
        self.terminationDescription = terminationDescription
        self.applicationSpecificInformation = applicationSpecificInformation
        self.crashedThread = crashedThread
        self.signal = signal
        self.symbolicationStatus = symbolicationStatus
    }
}

/// Diagnostic metadata attached to a chunk produced from log or crash report text.
public struct LogMetadata: Sendable, Equatable {
    public let kind: LogChunkKind
    public let process: String?
    public let subsystem: String?
    public let category: String?
    public let severity: String?
    public let timestampRange: TimestampRange?
    public let crashReport: CrashReportMetadata?

    public init(
        kind: LogChunkKind = .unknown,
        process: String? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        severity: String? = nil,
        timestampRange: TimestampRange? = nil,
        crashReport: CrashReportMetadata? = nil
    ) {
        self.kind = kind
        self.process = process
        self.subsystem = subsystem
        self.category = category
        self.severity = severity
        self.timestampRange = timestampRange
        self.crashReport = crashReport
    }
}
