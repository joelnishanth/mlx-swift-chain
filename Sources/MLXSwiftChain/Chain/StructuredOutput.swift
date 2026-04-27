import Foundation

/// Errors from structured JSON extraction.
public enum StructuredOutputError: Error, LocalizedError {
    /// The LLM output did not contain valid JSON.
    case invalidJSON(underlying: any Error, rawText: String)
    /// The JSON was valid but did not match the expected `Decodable` schema.
    case schemaMismatch(underlying: DecodingError, rawText: String)
    /// All retry attempts produced invalid or mismatched JSON.
    case retriesExhausted(lastError: any Error, rawText: String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let err, _):
            return "Invalid JSON in LLM output: \(err.localizedDescription)"
        case .schemaMismatch(let err, _):
            return "JSON schema mismatch: \(err.localizedDescription)"
        case .retriesExhausted(let err, _):
            return "All retries exhausted. Last error: \(err.localizedDescription)"
        }
    }
}

extension DocumentChain {

    /// Run the chain and decode the output as a typed JSON value.
    ///
    /// The LLM output is cleaned (markdown fences stripped, whitespace trimmed),
    /// the outermost JSON object or array is extracted, and decoded via
    /// `JSONDecoder`. If decoding fails and `options.retryPolicy.maxAttempts > 1`,
    /// the chain is re-run with the error appended to the prompt.
    ///
    /// ```swift
    /// struct ActionItem: Decodable {
    ///     let owner: String
    ///     let task: String
    ///     let deadline: String?
    /// }
    /// let items = try await chain.runJSON(
    ///     [ActionItem].self,
    ///     text: transcript,
    ///     mapPrompt: "Extract action items as JSON array:",
    ///     reducePrompt: "Merge into a single JSON array:",
    ///     options: ChainExecutionOptions(retryPolicy: RetryPolicy(maxAttempts: 2))
    /// )
    /// ```
    public func runJSON<T: Decodable>(
        _ type: T.Type,
        text: String,
        mapPrompt: String,
        reducePrompt: String,
        stuffPrompt: String? = nil,
        systemPrompt: String? = nil,
        options: ChainExecutionOptions = .init(),
        progress: ChainProgress? = nil
    ) async throws -> T {
        var lastError: (any Error)?
        var lastRawText = ""

        for attempt in 1...max(1, options.retryPolicy.maxAttempts) {
            let rawText: String
            if attempt == 1 {
                rawText = try await run(
                    text,
                    mapPrompt: mapPrompt,
                    reducePrompt: reducePrompt,
                    stuffPrompt: stuffPrompt,
                    systemPrompt: systemPrompt,
                    options: options,
                    progress: progress
                )
            } else {
                let errorHint = lastError.map { "\nPrevious attempt produced invalid JSON: \($0.localizedDescription)\nPlease output valid JSON only." } ?? ""
                let retryPrompt = reducePrompt + errorHint
                rawText = try await run(
                    text,
                    mapPrompt: mapPrompt,
                    reducePrompt: retryPrompt,
                    stuffPrompt: stuffPrompt,
                    systemPrompt: systemPrompt,
                    options: ChainExecutionOptions(
                        reservedOutputTokens: options.reservedOutputTokens,
                        maxReduceGroupSize: options.maxReduceGroupSize,
                        maxReduceDepth: options.maxReduceDepth,
                        maxConcurrentMapTasks: options.maxConcurrentMapTasks,
                        preserveOrder: options.preserveOrder,
                        retryPolicy: .none,
                        promptStyle: options.promptStyle
                    ),
                    progress: progress
                )
            }
            lastRawText = rawText

            let cleaned = JSONRepairHelper.extractJSON(from: rawText)
            guard let data = cleaned.data(using: .utf8) else {
                lastError = StructuredOutputError.invalidJSON(
                    underlying: NSError(domain: "MLXSwiftChain", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Could not convert to UTF-8 data"]),
                    rawText: rawText
                )
                continue
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as DecodingError {
                lastError = StructuredOutputError.schemaMismatch(underlying: error, rawText: rawText)
            } catch {
                lastError = StructuredOutputError.invalidJSON(underlying: error, rawText: rawText)
            }

            if attempt < options.retryPolicy.maxAttempts && options.retryPolicy.delayMilliseconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(options.retryPolicy.delayMilliseconds) * 1_000_000)
            }
        }

        if options.retryPolicy.maxAttempts > 1 {
            throw StructuredOutputError.retriesExhausted(lastError: lastError!, rawText: lastRawText)
        }
        throw lastError!
    }
}

/// Deterministic JSON cleanup helpers.
enum JSONRepairHelper {

    /// Extract the outermost JSON object or array from LLM text output.
    ///
    /// Handles common LLM artifacts:
    /// - Markdown code fences (` ```json ... ``` `)
    /// - Leading/trailing prose around JSON
    /// - Whitespace
    static func extractJSON(from text: String) -> String {
        var cleaned = stripCodeFences(text).trimmingCharacters(in: .whitespacesAndNewlines)

        let objRange = findOutermostBraces(in: cleaned, open: "{", close: "}")
        let arrRange = findOutermostBraces(in: cleaned, open: "[", close: "]")

        switch (objRange, arrRange) {
        case (let obj?, let arr?):
            cleaned = String(cleaned[obj.lowerBound < arr.lowerBound ? obj : arr])
        case (let obj?, nil):
            cleaned = String(cleaned[obj])
        case (nil, let arr?):
            cleaned = String(cleaned[arr])
        case (nil, nil):
            break
        }

        return cleaned
    }

    static func stripCodeFences(_ text: String) -> String {
        var result = text
        let fencePattern = #"```(?:json|JSON)?\s*\n?"#
        if let startRange = result.range(of: fencePattern, options: .regularExpression) {
            result = String(result[startRange.upperBound...])
        }
        if let endRange = result.range(of: #"\n?\s*```\s*$"#, options: .regularExpression) {
            result = String(result[..<endRange.lowerBound])
        }
        return result
    }

    private static func findOutermostBraces(
        in text: String,
        open: Character,
        close: Character
    ) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: open) else { return nil }
        var depth = 0
        var inString = false
        var escape = false

        for i in text.indices[start...] {
            let ch = text[i]
            if escape {
                escape = false
                continue
            }
            if ch == "\\" && inString {
                escape = true
                continue
            }
            if ch == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }

            if ch == open { depth += 1 }
            else if ch == close {
                depth -= 1
                if depth == 0 {
                    return start..<text.index(after: i)
                }
            }
        }
        return nil
    }
}
