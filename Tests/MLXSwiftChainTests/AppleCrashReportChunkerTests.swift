import Testing
@testable import MLXSwiftChain

@Suite("AppleCrashReportChunker Tests")
struct AppleCrashReportChunkerTests {

    // MARK: - Test fixtures

    private static let sampleCrashReport = """
    Process:               MyApp [12345]
    Path:                  /Applications/MyApp.app/Contents/MacOS/MyApp
    Identifier:            com.example.MyApp
    Version:               2.1.0 (100)
    Code Type:             ARM-64
    Parent Process:        launchd [1]
    Date/Time:             2026-04-25 14:22:01.123 +0000
    Launch Time:           2026-04-25 14:20:00.000 +0000
    OS Version:            macOS 15.4 (24E5XXX)
    Report Version:        12
    Hardware Model:        Mac14,2

    Exception Type:        EXC_BAD_ACCESS (SIGSEGV)
    Exception Subtype:     KERN_INVALID_ADDRESS at 0x0000000000000010
    Exception Codes:       0x0000000000000001, 0x0000000000000010
    Termination Reason:    Namespace SIGNAL, Code 11 Segmentation fault: 11
    Termination Description: SEGV
    Triggered by Thread:   0

    Application Specific Information:
    objc_msgSend() selector name: release

    VM Region Info: 0x10 is not in any region.

    Thread 0 Crashed:
    0   MyApp                  0x0000000100abc123 MyApp.ViewModel.loadData() + 42
    1   MyApp                  0x0000000100abc456 specialized MyApp.ContentView.body.getter + 128
    2   SwiftUI                0x00000001a0def789 SwiftUI.ViewGraph.update() + 312
    3   UIKitCore              0x00000001b0123456 -[UIViewController viewDidLoad] + 88

    Thread 1:
    0   libsystem_kernel.dylib 0x00000001c0111111 __psynch_cvwait + 8
    1   libsystem_pthread.dylib 0x00000001c0222222 _pthread_cond_wait + 1228

    Thread 0 crashed with ARM Thread State (64-bit):
        x0: 0x0000000000000010   x1: 0x00000001deadbeef
        x2: 0x0000000000000000   x3: 0x0000000000000001

    Binary Images:
    0x100000000 - 0x100ffffff  MyApp   arm64  <UUID> /Applications/MyApp.app/Contents/MacOS/MyApp
    0x1a0000000 - 0x1a0ffffff  SwiftUI arm64  <UUID> /System/Library/Frameworks/SwiftUI.framework/SwiftUI
    """

    // MARK: - 1. Header metadata

    @Test("crashReport_extractsHeaderMetadata")
    func crashReport_extractsHeaderMetadata() {
        let chunker = AppleCrashReportChunker(targetWords: 2000)
        let chunks = chunker.chunk(Self.sampleCrashReport)
        #expect(!chunks.isEmpty)

        let headerChunk = chunks.first { $0.metadata.logMetadata?.kind == .crashHeader }
        #expect(headerChunk != nil)

        let crash = headerChunk?.metadata.logMetadata?.crashReport
        #expect(crash != nil)
        #expect(crash?.process?.contains("MyApp") == true)
        #expect(crash?.identifier == "com.example.MyApp")
        #expect(crash?.version?.contains("2.1.0") == true)
        #expect(crash?.osVersion?.contains("macOS 15.4") == true)
        #expect(crash?.hardwareModel == "Mac14,2")
    }

    // MARK: - 2. Exception info

    @Test("crashReport_extractsExceptionInfo")
    func crashReport_extractsExceptionInfo() {
        let chunker = AppleCrashReportChunker(targetWords: 2000)
        let chunks = chunker.chunk(Self.sampleCrashReport)

        let exChunk = chunks.first { $0.metadata.logMetadata?.kind == .exceptionInfo }
        #expect(exChunk != nil)

        let crash = exChunk?.metadata.logMetadata?.crashReport
        #expect(crash?.exceptionType?.contains("EXC_BAD_ACCESS") == true)
        #expect(crash?.exceptionSubtype?.contains("KERN_INVALID_ADDRESS") == true)
        #expect(crash?.exceptionCodes != nil)
        #expect(crash?.signal == "SIGSEGV")
    }

    // MARK: - 3. Crashed thread preserved

    @Test("crashReport_preservesCrashedThread")
    func crashReport_preservesCrashedThread() {
        let chunker = AppleCrashReportChunker(targetWords: 2000, preserveCrashedThread: true)
        let chunks = chunker.chunk(Self.sampleCrashReport)

        let crashedChunk = chunks.first { $0.metadata.logMetadata?.kind == .crashedThread }
        #expect(crashedChunk != nil)

        if let text = crashedChunk?.text {
            #expect(text.contains("Thread 0 Crashed"))
            #expect(text.contains("MyApp.ViewModel.loadData()"))
            #expect(text.contains("UIKitCore"))
        }
    }

    // MARK: - 4. Last Exception Backtrace preserved

    @Test("crashReport_preservesLastExceptionBacktrace")
    func crashReport_preservesLastExceptionBacktrace() {
        let input = """
        Process:               CrashApp [999]
        Identifier:            com.example.CrashApp

        Exception Type:        EXC_CRASH (SIGABRT)

        Last Exception Backtrace:
        0   CoreFoundation         0x00000001a0111111 __exceptionPreprocess + 220
        1   libobjc.A.dylib        0x00000001a0222222 objc_exception_throw + 60
        2   CrashApp               0x0000000100aaa111 CrashApp.DataManager.fetch() + 84
        3   CrashApp               0x0000000100aaa222 specialized CrashApp.ViewModel.refresh() + 200

        Thread 0 Crashed:
        0   CrashApp               0x0000000100aaa111 CrashApp.DataManager.fetch() + 84
        """
        let chunker = AppleCrashReportChunker(targetWords: 2000)
        let chunks = chunker.chunk(input)

        let btChunk = chunks.first { $0.metadata.logMetadata?.kind == .lastExceptionBacktrace }
        #expect(btChunk != nil)
        if let text = btChunk?.text {
            #expect(text.contains("Last Exception Backtrace"))
            #expect(text.contains("CoreFoundation"))
            #expect(text.contains("CrashApp.DataManager.fetch()"))
            #expect(text.contains("CrashApp.ViewModel.refresh()"))
        }
    }

    // MARK: - 5. Unsymbolicated detection

    @Test("crashReport_detectsUnsymbolicated")
    func crashReport_detectsUnsymbolicated() {
        let input = """
        Process:               MyApp [111]
        Identifier:            com.example.MyApp

        Exception Type:        EXC_BAD_ACCESS (SIGSEGV)

        Thread 0 Crashed:
        0   MyApp   0x0000000100abc111 0x100000000 + 703761
        1   MyApp   0x0000000100abc222 0x100000000 + 703778
        2   MyApp   0x0000000100abc333 0x100000000 + 704051
        3   MyApp   0x0000000100abc444 0x100000000 + 704324
        4   MyApp   0x0000000100abc555 0x100000000 + 704597
        5   UIKitCore   0x00000001b0111111 0x1b0000000 + 1118481

        Thread 1:
        0   libsystem_kernel.dylib 0x00000001c0111111 0x1c0000000 + 11111
        1   libsystem_pthread.dylib 0x00000001c0222222 0x1c0000000 + 22222
        2   libsystem_pthread.dylib 0x00000001c0333333 0x1c0000000 + 33333
        """
        let chunker = AppleCrashReportChunker(targetWords: 2000)
        let chunks = chunker.chunk(input)

        let anyMeta = chunks.compactMap { $0.metadata.logMetadata?.crashReport?.symbolicationStatus }.first
        #expect(anyMeta != nil)
        #expect(anyMeta == .unsymbolicated || anyMeta == .partiallySymbolicated)
    }

    // MARK: - 6. Binary Images separated

    @Test("crashReport_binaryImagesSeparated")
    func crashReport_binaryImagesSeparated() {
        let chunker = AppleCrashReportChunker(targetWords: 2000, includeBinaryImages: true)
        let chunks = chunker.chunk(Self.sampleCrashReport)

        let biChunk = chunks.first { $0.metadata.logMetadata?.kind == .binaryImages }
        #expect(biChunk != nil)
        #expect(biChunk?.text.contains("Binary Images") == true)

        let chunkerExclude = AppleCrashReportChunker(targetWords: 2000, includeBinaryImages: false)
        let chunksExclude = chunkerExclude.chunk(Self.sampleCrashReport)
        let biExclude = chunksExclude.first { $0.metadata.logMetadata?.kind == .binaryImages }
        #expect(biExclude == nil)
    }

    // MARK: - 7. DiagnosticSourceLabel

    @Test("diagnosticSourceLabel_crash")
    func diagnosticSourceLabel_crash() {
        let crashMeta = CrashReportMetadata(
            exceptionType: "EXC_BAD_ACCESS (SIGSEGV)"
        )
        let logMeta = LogMetadata(
            kind: .exceptionInfo,
            crashReport: crashMeta
        )
        let metadata = TextChunkMetadata(
            chunkIndex: 1,
            sourceWordRange: 0..<50,
            logMetadata: logMeta
        )
        let chunk = TextChunk(
            text: "Exception Type: EXC_BAD_ACCESS",
            index: 1,
            wordCount: 50,
            metadata: metadata
        )

        let label = DiagnosticSourceLabel.label(for: chunk)
        #expect(label.contains("Chunk 2"))
        #expect(label.contains("exceptionInfo"))
        #expect(label.contains("EXC_BAD_ACCESS"))
    }

    // MARK: - 8. Likely detector

    @Test("crashReport_likelyDetector")
    func crashReport_likelyDetector() {
        #expect(AppleCrashReportChunker.isLikelyAppleCrashReport(Self.sampleCrashReport))

        #expect(!AppleCrashReportChunker.isLikelyAppleCrashReport("Hello world"))
        #expect(!AppleCrashReportChunker.isLikelyAppleCrashReport(
            "2024-01-15 10:30:00 INFO Starting application\n2024-01-15 10:30:01 ERROR Something failed"
        ))
    }

    // MARK: - 9. IPS JSON-like input

    @Test("crashReport_ipsJSONLikeInputDoesNotCollapse")
    func crashReport_ipsJSONLikeInputDoesNotCollapse() {
        let ipsInput = """
        {
          "app_name": "MyApp",
          "bundleID": "com.example.MyApp",
          "build_version": "100",
          "os_version": "iPhone OS 17.4 (21E5XXX)",
          "incident": "ABCD-1234-EFGH-5678",
          "crashReporterKey": "abc123def456",
          "exception": {
            "type": "EXC_BAD_ACCESS",
            "subtype": "KERN_INVALID_ADDRESS at 0x0000000000000010",
            "codes": "0x0000000000000001, 0x0000000000000010"
          },
          "termination": {
            "reason": "Namespace SIGNAL, Code 11",
            "description": "SEGV"
          },
          "faultingThread": 0,
          "threads": [
            { "id": 0, "frames": [] },
            { "id": 1, "frames": [] }
          ],
          "usedImages": [
            { "name": "MyApp", "base": "0x100000000" }
          ]
        }
        """
        #expect(AppleCrashReportChunker.isLikelyIPSFormat(ipsInput))

        let chunker = AppleCrashReportChunker(targetWords: 500)
        let chunks = chunker.chunk(ipsInput)
        #expect(chunks.count > 1)

        let kinds = Set(chunks.compactMap { $0.metadata.logMetadata?.kind })
        #expect(kinds.contains { $0 != .unknown })
    }
}
