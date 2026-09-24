import Foundation

/// Shared, conservative cleanup for commands and their search queries. This deliberately
/// doesn't fuzzy-correct names: a command typo must never change a song or an artist.
enum RequestLanguage {
    static func command(_ prompt: String) -> String {
        var value = prompt.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let terminalPunctuation = CharacterSet(charactersIn: ".!?;,:").union(.whitespacesAndNewlines)
        value = value.trimmingCharacters(in: terminalPunctuation)
        for _ in 0..<3 {
            value = value.replacingOccurrences(of: #"^(hey(?: vibecast)?[, ]+|please[, ]+|(?:can|could|would|will) you (?:please )?|would you mind |i(?:'d| would) like (?:you to |to )?|i want to )"#,
                                               with: "", options: .regularExpression)
            let withoutCourtesy = value.replacingOccurrences(of: #"[, ]+(?:please|thanks|thank you)$"#,
                                                             with: "", options: .regularExpression)
                .trimmingCharacters(in: terminalPunctuation)
            // "Play Please" can name a song. Never strip the entire playback target
            // and turn a catalog request into Resume.
            if !["play", "start", "put on", "listen to", "queue", "add to queue", "add to my queue"].contains(withoutCourtesy) {
                value = withoutCourtesy
            }
        }
        // Common command typos only. Never rewrite words in the song/artist portion.
        let corrections = ["paly": "play", "plaay": "play", "pasue": "pause", "puase": "pause",
                           "resuem": "resume", "prevous": "previous", "previuos": "previous"]
        if let first = value.split(separator: " ").first, let corrected = corrections[String(first)] {
            value = corrected + value.dropFirst(first.count)
        }
        for typo in ["shufle", "shuffel"] {
            if value.matches("^(turn )?" + typo + " (on|off)$") {
                value = value.replacingOccurrences(of: typo, with: "shuffle")
            }
        }
        return value
    }

    static func musicCommand(_ prompt: String) -> String {
        let value = command(prompt)
        // Context such as "I'm tired, play some jazz" must not pollute a catalog query.
        // Limit extraction to a separated clause; prose mentioning a command isn't one.
        if let clause = value.range(of: #"[,;:]\s*(?:please )?(?:play|find|put on|listen to|start|make|create|build|curate)\s+"#,
                                    options: .regularExpression) {
            let suffix = String(value[clause.lowerBound...]).dropFirst()
            return command(String(suffix))
        }
        return value
    }

    static func artistPreference(_ prompt: String) -> String? {
        var value = musicCommand(prompt)
        value = value.replacingOccurrences(of: #"^(?:play|find|put on|listen to|start)\s+"#, with: "", options: .regularExpression)
        let patterns = [
            #"^(?:(?:me )?(?:some |a few |more |some more )?)?(?:songs?|music|tracks|playlists?)(?: more)? (?:by|from) (.+)$"#,
            #"^(?:some |some more |more |anything |something )?(?:by|from) (.+)$"#,
            #"^(?:the )?artist (.+)$"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let range = Range(match.range(at: 1), in: value) else { continue }
            let artist = String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty { return artist }
        }
        return nil
    }

    static func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
