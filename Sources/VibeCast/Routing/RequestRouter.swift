import Foundation

struct RequestRouter {
    func route(_ request: VibeCastRequest) -> RequestRoute {
        let original = request.prompt
        let p = RequestLanguage.musicCommand(original)
        if let action = DirectCommandClassifier().action(for: p) { return .directSpotify(action) }
        if p.matches(#"^(make|create|build|curate)\b.*\b(playlist|songs|music|tracks|mix)\b"#)
            || p.matches(#"^cast magic\b"#) {
            return .makePlaylist(prompt: original)
        }
        if RequestLanguage.artistPreference(p) != nil { return .findPlaylist(prompt: original) }
        if p.matches(#"^(queue|add to (?:my )?queue)\s+"#) { return .track(prompt: original) }
        if p.matches(#"^(play|start|put on|listen to)\s+["\u{201C}]"#)
            || p.matches(#"^(play|start|put on|listen to)\s+(?:the )?(song|track)\s+"#) {
            return .track(prompt: original)
        }
        let preference = ConversationGuide.preference(in: p)
        // Questions, negations and vague pronouns are clarification, never inferred playback.
        if (preference == nil && p.matches(#"^(what|why|how|who|where|when|do |does |is |are |don'?t|do not|never|no |not )"#))
            || p.matches(#"^(play|start|put on|listen to)\s+(it|that|this|something|anything|whatever|some music|music)$"#) {
            return .conversation(prompt: original)
        }
        let musicCommand = p.matches(#"^(play|find|put on|listen to|start)\b"#)
        if !musicCommand && p.matches(#"\b(tired|stressed|damn|feeling)\b"#) {
            return .conversation(prompt: original)
        }
        if (musicCommand && (preference != nil || p.matches(#"\b(playlist|songs|music|tracks|mix|vibe|vibing)\b"#)
                             || p.hasPrefix("find ") || p.hasPrefix("play some ")))
            || (!musicCommand && preference != nil) {
            return .findPlaylist(prompt: original)
        }
        if p.matches(#"^(play|start|put on|listen to)\s+"#) { return .track(prompt: original) }
        return .conversation(prompt: original)
    }
}

extension String {
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }
    var musicNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
