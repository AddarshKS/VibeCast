import Foundation

enum CodexInterpreterError: LocalizedError {
    case codexUnavailable
    case invalidResponse
    case noCandidates(String)
    case lowConfidence(String)
    case unsupportedMusicRequest(String)

    var errorDescription: String? {
        switch self {
        case .codexUnavailable:
            "Codex is not reachable from VibeCast right now."
        case .invalidResponse:
            "Codex returned an invalid interpreter response."
        case .noCandidates(let phrase):
            "Spotify did not return any playable track candidates for \"\(phrase)\"."
        case .lowConfidence(let reason):
            "I could not confidently resolve that request. \(reason)"
        case .unsupportedMusicRequest(let prompt):
            "I know this is a music request, but I could not confidently resolve it yet: \(prompt)"
        }
    }
}

struct CodexResolvedTrackAction: Equatable {
    let action: SpotifyAction
    let track: SpotifyResolvedTrack
    let confidence: Double
    let reason: String
    let method: String
}

struct CodexInterpreterClient {
    private let confidenceThreshold = 0.75
    private let useCodex: Bool
    private let selector = CandidateTrackSelector()

    init(useCodex: Bool = true) {
        self.useCodex = useCodex
    }

    func searchPhrase(from prompt: String) throws -> String {
        guard let command = InterpretedTrackCommand(prompt: prompt) else {
            throw CodexInterpreterError.unsupportedMusicRequest(prompt)
        }
        return command.phrase
    }

    func resolve(prompt: String, candidates: [SpotifyResolvedTrack]) async throws -> CodexResolvedTrackAction {
        guard let command = InterpretedTrackCommand(prompt: prompt) else {
            throw CodexInterpreterError.unsupportedMusicRequest(prompt)
        }

        guard !candidates.isEmpty else {
            throw CodexInterpreterError.noCandidates(command.phrase)
        }

        if let deterministic = selector.deterministicSelection(prompt: prompt, phrase: command.phrase, candidates: candidates) {
            return resolvedAction(command: command, selection: deterministic, method: "deterministic")
        }

        guard useCodex else {
            throw CodexInterpreterError.lowConfidence("No Spotify candidate was strong enough.")
        }

        do {
            let response = try await CodexCandidateSelector().select(
                prompt: prompt,
                phrase: command.phrase,
                candidates: candidates
            )
            guard candidates.indices.contains(response.selectedIndex) else {
                throw CodexInterpreterError.invalidResponse
            }

            guard response.confidence >= confidenceThreshold else {
                throw CodexInterpreterError.lowConfidence(response.reason)
            }

            let candidate = candidates[response.selectedIndex]
            let score = selector.score(phrase: command.phrase, candidate: candidate, prompt: prompt)
            guard score >= 0.45 else {
                throw CodexInterpreterError.lowConfidence("Codex selected a weak Spotify candidate: \(candidate.displayName).")
            }

            return resolvedAction(
                command: command,
                selection: CandidateSelection(track: candidate, confidence: response.confidence, reason: response.reason),
                method: "codex"
            )
        } catch let error as CodexInterpreterError {
            throw error
        } catch {
            throw CodexInterpreterError.codexUnavailable
        }
    }

    private func resolvedAction(
        command: InterpretedTrackCommand,
        selection: CandidateSelection,
        method: String
    ) -> CodexResolvedTrackAction {
        let action: SpotifyAction = command.isQueue
            ? .queueResolvedTrack(selection.track)
            : .playResolvedTrack(selection.track)

        return CodexResolvedTrackAction(
            action: action,
            track: selection.track,
            confidence: selection.confidence,
            reason: selection.reason,
            method: method
        )
    }
}

struct CandidateSelection: Equatable {
    let track: SpotifyResolvedTrack
    let confidence: Double
    let reason: String
}

struct CandidateTrackSelector {
    func deterministicSelection(prompt: String, phrase: String, candidates: [SpotifyResolvedTrack]) -> CandidateSelection? {
        let scored = candidates
            .map { candidate in
                (candidate: candidate, score: score(phrase: phrase, candidate: candidate, prompt: prompt))
            }
            .sorted { $0.score > $1.score }

        guard let top = scored.first else { return nil }
        let runnerUp = scored.dropFirst().first?.score ?? 0

        if top.score >= 0.94 || (top.score >= 0.86 && top.score - runnerUp >= 0.08) {
            return CandidateSelection(
                track: top.candidate,
                confidence: min(top.score, 0.99),
                reason: "Spotify candidate title strongly matched the request."
            )
        }

        return nil
    }

    func score(phrase: String, candidate: SpotifyResolvedTrack, prompt: String) -> Double {
        let phraseNorm = phrase.normalizedForCandidateMatch
        let titleNorm = candidate.title.normalizedForCandidateMatch
        let artistNorm = candidate.artist.normalizedForCandidateMatch
        let promptNorm = prompt.normalizedForCandidateMatch

        guard !phraseNorm.isEmpty, !titleNorm.isEmpty else { return 0 }

        var score: Double
        if phraseNorm == titleNorm {
            score = 0.98
        } else if titleNorm.contains(phraseNorm) || phraseNorm.contains(titleNorm) {
            score = 0.9
        } else {
            let distance = Self.levenshtein(phraseNorm, titleNorm)
            let maxLength = max(phraseNorm.count, titleNorm.count)
            let similarity = maxLength == 0 ? 0 : 1.0 - (Double(distance) / Double(maxLength))
            let tokenScore = tokenContainmentScore(needle: phraseNorm, haystack: titleNorm)
            score = max(similarity, tokenScore)
        }

        if !artistNorm.isEmpty, promptNorm.contains(artistNorm) {
            score += 0.08
        }

        return min(score, 1.0)
    }

    private func tokenContainmentScore(needle: String, haystack: String) -> Double {
        let needleTokens = Set(needle.split(separator: " ").map(String.init))
        let haystackTokens = Set(haystack.split(separator: " ").map(String.init))
        guard !needleTokens.isEmpty else { return 0 }
        let matches = needleTokens.intersection(haystackTokens).count
        return Double(matches) / Double(needleTokens.count)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }

        return previous[b.count]
    }
}

private struct InterpretedTrackCommand {
    let phrase: String
    let isQueue: Bool

    init?(prompt: String) {
        let normalized = prompt.normalizedInterpreterPrompt
        if let phrase = normalized.removingCommandPrefix(["queue", "add", "add to queue"]) {
            self.phrase = phrase
            self.isQueue = true
            return
        }

        if let phrase = normalized.removingCommandPrefix(["play", "start", "listen to", "put on"]) {
            self.phrase = phrase
            self.isQueue = false
            return
        }

        return nil
    }
}

private struct CodexCandidateSelector {
    func select(prompt: String, phrase: String, candidates: [SpotifyResolvedTrack]) async throws -> CodexSelectionResponse {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibecast-codex-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = codexExecutableURL()
        process.arguments = codexArguments(outputURL: outputURL, prompt: prompt, phrase: phrase, candidates: candidates)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try await run(process)

        let output = try String(contentsOf: outputURL, encoding: .utf8)
        guard let data = extractJSON(from: output) else {
            throw CodexInterpreterError.invalidResponse
        }

        return try JSONDecoder().decode(CodexSelectionResponse.self, from: data)
    }

    private func codexExecutableURL() -> URL {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private func codexArguments(outputURL: URL, prompt: String, phrase: String, candidates: [SpotifyResolvedTrack]) -> [String] {
        let commandPrefix = codexExecutableURL().lastPathComponent == "env" ? ["codex"] : []
        return commandPrefix + [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "-C",
            NSHomeDirectory(),
            "-s",
            "read-only",
            "--output-last-message",
            outputURL.path,
            interpreterPrompt(prompt: prompt, phrase: phrase, candidates: candidates)
        ]
    }

    private func interpreterPrompt(prompt: String, phrase: String, candidates: [SpotifyResolvedTrack]) -> String {
        let candidateLines = candidates.enumerated()
            .map { index, track in "\(index): \(track.title) by \(track.artist)" }
            .joined(separator: "\n")

        return """
        You are VibeCast's Spotify candidate selector.
        The user asked: \(prompt)
        Extracted song phrase: \(phrase)
        Choose only from these zero-based Spotify candidates:
        \(candidateLines)
        Return only minified JSON with keys: selectedIndex,confidence,reason.
        selectedIndex must be one of the supplied candidate indexes.
        Use confidence below 0.75 when none of the candidates likely match.
        Do not invent tracks, artists, titles, or indexes.
        """
    }

    private func run(_ process: Process) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = ProcessCompletion()
            process.terminationHandler = { terminatedProcess in
                completion.resumeOnce(continuation) {
                    if terminatedProcess.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: CodexInterpreterError.codexUnavailable)
                    }
                }
            }

            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 18) {
                    guard process.isRunning else { return }
                    process.terminate()
                    completion.resumeOnce(continuation) {
                        continuation.resume(throwing: CodexInterpreterError.codexUnavailable)
                    }
                }
            } catch {
                completion.resumeOnce(continuation) {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func extractJSON(from output: String) -> Data? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}"),
            start <= end
        else {
            return nil
        }

        return String(trimmed[start...end]).data(using: .utf8)
    }
}

private final class ProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce(_ continuation: CheckedContinuation<Void, Error>, _ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        body()
    }
}

private struct CodexSelectionResponse: Decodable {
    let selectedIndex: Int
    let confidence: Double
    let reason: String
}

private extension String {
    var normalizedInterpreterPrompt: String {
        lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var normalizedForCandidateMatch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingCommandPrefix(_ prefixes: [String]) -> String? {
        for prefix in prefixes {
            let fullPrefix = "\(prefix) "
            guard hasPrefix(fullPrefix) else { continue }
            let value = String(dropFirst(fullPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return nil
    }
}
