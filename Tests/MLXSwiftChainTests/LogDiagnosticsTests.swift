import Testing
@testable import MLXSwiftChain

@Suite("Log Diagnostics Tests")
struct LogDiagnosticsTests {

    // MARK: - 8. Swift compiler error

    @Test("logChunker_preservesSwiftCompilerError")
    func logChunker_preservesSwiftCompilerError() {
        let chunker = LogChunker(targetWords: 500)
        let input = """
        Sources/App/View.swift:12:34: error: cannot find 'foo' in scope
            let x = foo
                    ^~~
        Sources/App/View.swift:12:34: note: did you mean 'bar'?
        """
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let compilerChunk = chunks.first { $0.metadata.logMetadata?.kind == .swiftCompilerError }
        #expect(compilerChunk != nil)
        #expect(compilerChunk?.text.contains("View.swift:12:34") == true)
        #expect(compilerChunk?.text.contains("cannot find 'foo'") == true)
    }

    // MARK: - 9. Xcode build error

    @Test("logChunker_preservesXcodeBuildError")
    func logChunker_preservesXcodeBuildError() {
        let chunker = LogChunker(targetWords: 500)
        let input = """
        CompileSwift normal arm64 /Sources/App/View.swift
        Command SwiftCompile failed with a nonzero exit code
        BUILD FAILED
        The following build commands failed:
            CompileSwift normal arm64 /Sources/App/View.swift
        """
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let buildChunk = chunks.first { $0.metadata.logMetadata?.kind == .xcodeBuildError }
        #expect(buildChunk != nil)
        #expect(buildChunk?.text.contains("BUILD FAILED") == true)
    }

    // MARK: - 10. Linker error

    @Test("logChunker_preservesLinkerError")
    func logChunker_preservesLinkerError() {
        let chunker = LogChunker(targetWords: 500)
        let input = """
        Undefined symbols for architecture arm64:
          "_OBJC_CLASS_$_MyMissingClass", referenced from:
              objc-class-ref in ViewController.o
        ld: symbol(s) not found for architecture arm64
        clang: error: linker command failed with exit code 1
        """
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let linkerChunk = chunks.first { $0.metadata.logMetadata?.kind == .linkerError }
        #expect(linkerChunk != nil)
        #expect(linkerChunk?.text.contains("Undefined symbols") == true)
    }

    // MARK: - 11. XCTest failure

    @Test("logChunker_preservesXCTestFailure")
    func logChunker_preservesXCTestFailure() {
        let chunker = LogChunker(targetWords: 500)
        let input = """
        Test Suite 'MyAppTests' started at 2026-04-26 10:00:00
        Test Case '-[MyAppTests testLogin]' started.
        XCTAssertEqual failed: ("200") is not equal to ("401")
        /Tests/MyAppTests/LoginTests.swift:42: error: -[MyAppTests testLogin] : XCTAssertEqual failed
        Test Case '-[MyAppTests testLogin]' failed (0.123 seconds).
        Executed 1 test, with 1 failure in 0.123 seconds
        """
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let testChunk = chunks.first { $0.metadata.logMetadata?.kind == .testFailure }
        #expect(testChunk != nil)
        #expect(testChunk?.text.contains("testLogin") == true)
    }

    // MARK: - 12. Main Thread Checker

    @Test("logChunker_detectsMainThreadChecker")
    func logChunker_detectsMainThreadChecker() {
        let chunker = LogChunker(targetWords: 500)
        let input = """
        Main Thread Checker: UI API called on a background thread: -[UIView setNeedsLayout]
        PID: 12345, TID: 67890
        """
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let rtChunk = chunks.first { $0.metadata.logMetadata?.kind == .runtimeWarning }
        #expect(rtChunk != nil)
        #expect(rtChunk?.text.contains("Main Thread Checker") == true)
    }

    // MARK: - 13. Stack trace preserved

    @Test("logChunker_preservesStackTrace")
    func logChunker_preservesStackTrace() {
        let chunker = LogChunker(targetWords: 500)
        var frames = (0..<10).map { i in
            "\(i)   MyApp   0x000000010\(String(format: "%07x", i * 0x100)) MyApp.func\(i)() + \(i * 10)"
        }
        let input = frames.joined(separator: "\n")
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let stackChunk = chunks.first { $0.metadata.logMetadata?.kind == .stackTrace }
        #expect(stackChunk != nil)
        if let text = stackChunk?.text {
            #expect(text.contains("func0()"))
            #expect(text.contains("func9()"))
        }
    }

    // MARK: - 14. Simulator logs

    @Test("logChunker_groupsSimulatorLogs")
    func logChunker_groupsSimulatorLogs() {
        let chunker = LogChunker(targetWords: 500)
        let input = """
        2026-04-26 14:22:01.123 MyApp[1234:56789] Starting application
        2026-04-26 14:22:01.456 MyApp[1234:56789] Loading main view
        2026-04-26 14:22:02.789 MyApp[1234:56789] Network request initiated
        """
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let simChunk = chunks.first {
            $0.metadata.logMetadata?.kind == .simulatorLog
                || $0.metadata.logMetadata?.kind == .consoleLog
        }
        #expect(simChunk != nil)
        #expect(simChunk?.metadata.logMetadata?.process?.contains("MyApp") == true)

        let timestamps = simChunk?.metadata.timestamps ?? []
        #expect(!timestamps.isEmpty)
    }

    // MARK: - 15. Compiler error before BUILD FAILED

    @Test("logChunker_primaryCompilerErrorBeforeBuildFailed")
    func logChunker_primaryCompilerErrorBeforeBuildFailed() {
        let chunker = LogChunker(targetWords: 500)
        let input = """
        Sources/App/View.swift:12:34: error: cannot find 'foo' in scope
            let x = foo
                    ^~~
        BUILD FAILED
        The following build commands failed:
            CompileSwift normal arm64 /Sources/App/View.swift
        """
        let chunks = chunker.chunk(input)
        #expect(!chunks.isEmpty)

        let compilerIdx = chunks.firstIndex { $0.metadata.logMetadata?.kind == .swiftCompilerError }
        let buildIdx = chunks.firstIndex { $0.metadata.logMetadata?.kind == .xcodeBuildError }

        if let ci = compilerIdx, let bi = buildIdx {
            #expect(ci < bi, "Compiler error chunk should appear before BUILD FAILED chunk")
        } else {
            let combined = chunks.first {
                $0.text.contains("cannot find 'foo'") && $0.text.contains("BUILD FAILED")
            }
            if let c = combined {
                let errorRange = c.text.range(of: "cannot find 'foo'")
                let buildRange = c.text.range(of: "BUILD FAILED")
                if let er = errorRange, let br = buildRange {
                    #expect(er.lowerBound < br.lowerBound,
                            "Compiler error should appear before BUILD FAILED in text")
                }
            }
        }
    }

    // MARK: - 16. Prompt templates exist

    @Test("diagnosticPromptTemplates_exist")
    func diagnosticPromptTemplates_exist() {
        #expect(!PromptTemplates.appleCrashTriage.mapPrompt.isEmpty)
        #expect(!PromptTemplates.appleCrashTriage.reducePrompt.isEmpty)
        #expect(PromptTemplates.appleCrashTriage.stuffPrompt != nil)

        #expect(!PromptTemplates.simulatorLogRootCause.mapPrompt.isEmpty)
        #expect(!PromptTemplates.simulatorLogRootCause.reducePrompt.isEmpty)
        #expect(PromptTemplates.simulatorLogRootCause.stuffPrompt != nil)

        #expect(!PromptTemplates.xcodeBuildFailure.mapPrompt.isEmpty)
        #expect(!PromptTemplates.xcodeBuildFailure.reducePrompt.isEmpty)
        #expect(PromptTemplates.xcodeBuildFailure.stuffPrompt != nil)

        #expect(!PromptTemplates.testFailureAnalysis.mapPrompt.isEmpty)
        #expect(!PromptTemplates.testFailureAnalysis.reducePrompt.isEmpty)
        #expect(PromptTemplates.testFailureAnalysis.stuffPrompt != nil)
    }

    // MARK: - 17. Prompt templates warn on unsymbolicated evidence

    @Test("diagnosticPromptTemplates_warnOnUnsymbolicatedEvidence")
    func diagnosticPromptTemplates_warnOnUnsymbolicatedEvidence() {
        let reduce = PromptTemplates.appleCrashTriage.reducePrompt
        let stuff = PromptTemplates.appleCrashTriage.stuffPrompt ?? ""
        let hasUnsymbolicatedGuidance =
            reduce.contains("unsymbolicated") || reduce.contains("dSYM")
            || stuff.contains("unsymbolicated") || stuff.contains("dSYM")
        #expect(hasUnsymbolicatedGuidance,
                "appleCrashTriage should warn about unsymbolicated reports")
    }
}
