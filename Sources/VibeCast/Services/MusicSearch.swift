import Foundation

enum MusicSearch {
    static func playlistQuery(_ prompt: String) -> String {
        var normalized = prompt.musicNormalized
        if let command = normalized.range(of: #"\b(play|find|put on|start)\b"#, options: .regularExpression) {
            normalized = String(normalized[command.lowerBound...])
        }
        if let range = normalized.range(of: #"\b(songs|music|tracks) by "#, options: .regularExpression) {
            return "this is " + normalized[range.upperBound...].replacingOccurrences(of: #"\s+please$"#, with: "", options: .regularExpression)
        }
        return normalized
            .replacingOccurrences(of: #"\b(can you|could you|i am|please|find|give|play|start|put on|me|some|a|an|for|songs|music|tracks|playlists?|vibe|vibing)\b"#,
                                  with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trackQuery(_ prompt: String) -> String {
        prompt.replacingOccurrences(of: #"^(add to queue|queue|listen to|put on|play|start)\s+"#,
                                    with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"\u{201C}\u{201D}")))
    }

    static func matchPlaylist(query: String, candidates: [SpotifyResolvedPlaylist]) -> SpotifyResolvedPlaylist? {
        let normalized = query.musicNormalized
        let artistRequest = normalized.hasPrefix("this is ")
        let desired = artistRequest ? String(normalized.dropFirst(8)) : normalized
        guard !desired.isEmpty else { return nil }
        let scores = candidates.map { candidate in
            let name = coverage(desired, candidate.name)
            let description = coverage(desired, candidate.description ?? "") * 0.65
            return (candidate, artistRequest ? name : max(name, description))
        }.sorted { $0.1 > $1.1 }
        guard let best = scores.first, best.1 >= (artistRequest ? 1 : 0.45) else { return nil }
        return best.0
    }

    static func matchTrack(title: String, artist: String?, candidates: [SpotifyResolvedTrack]) -> SpotifyResolvedTrack? {
        let desired = title.musicNormalized
        guard !desired.isEmpty else { return nil }
        let scored = candidates.compactMap { candidate -> (SpotifyResolvedTrack, Double)? in
            let actual = candidate.title.musicNormalized
            var titleScore = desired == actual ? 1.0 : coverage(desired, actual)
            if desired != actual {
                titleScore = min(titleScore, 0.88)
                let extra = Set(actual.split(separator: " ")).subtracting(Set(desired.split(separator: " ")))
                if !extra.isDisjoint(with: ["live", "remix", "karaoke", "instrumental", "cover", "sped", "slowed"]) {
                    titleScore -= 0.3
                }
            }
            guard titleScore >= 0.85 else { return nil }
            if let artist, !artist.isEmpty {
                let artistScore = coverage(artist, candidate.artist)
                guard artistScore >= 0.8 else { return nil }
                return (candidate, titleScore * 0.7 + artistScore * 0.3)
            }
            return (candidate, titleScore)
        }.sorted { $0.1 > $1.1 }
        return scored.first?.0
    }

    private static func coverage(_ needle: String, _ haystack: String) -> Double {
        let a = Set(needle.musicNormalized.split(separator: " "))
        let b = Set(haystack.musicNormalized.split(separator: " "))
        return a.isEmpty ? 0 : Double(a.intersection(b).count) / Double(a.count)
    }
}
