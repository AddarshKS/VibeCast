import Foundation

struct RequestRouter {
    func route(_ request: VibeCastRequest) -> RequestRoute {
        let original = request.prompt
        let p = original.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let action = DirectCommandClassifier().action(for: p) { return .directSpotify(action) }
        if p.matches(#"\b(make|create|build|curate)\b.*\b(playlist|songs|music|tracks|mix)\b"#) || p.contains("cast magic") {
            return .makePlaylist(prompt: original)
        }
        if p.contains("what should i play") || p.contains("what do you think") || p.contains("how are you") {
            return .conversation(prompt: original)
        }
        let musicCommand = p.matches(#"\b(play|find|put on|listen to|start)\b"#)
        if !musicCommand && p.matches(#"\b(tired|stressed|damn|feeling)\b"#) {
            return .conversation(prompt: original)
        }
        if p.matches(#"^(queue|add to queue)\s+"#) { return .track(prompt: original) }
        if p.matches(#"^(play|start|put on|listen to)\s+["\u{201C}]"#) { return .track(prompt: original) }
        if p.matches(#"\b(playlist|songs|music|tracks|edm|jazz|lofi|lo-fi|chill|workout|focus|coding|party|vibe|vibing)\b"#)
            || p.contains("road trip") || p.contains("late night") || p.contains("late-night")
            || p.hasPrefix("find me ") || p.hasPrefix("play some ") {
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
