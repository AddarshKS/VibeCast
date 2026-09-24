import Foundation

enum MusicSearch {
    static func playlistQuery(_ prompt: String) -> String {
        if let artist = RequestLanguage.artistPreference(prompt) { return "this is " + artist.musicNormalized }
        if let preference = ConversationGuide.preference(in: prompt) { return preference }
        return RequestLanguage.musicCommand(prompt).musicNormalized
            .replacingOccurrences(of: #"\b(can you|could you|i am|please|find|give|play|start|put on|listen to|me|some|a|an|for|songs|music|tracks|playlists?|vibe|vibing)\b"#,
                                  with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trackQuery(_ prompt: String) -> String {
        let value = RequestLanguage.musicCommand(prompt)
            .replacingOccurrences(of: #"^(add to (?:my )?queue|queue|listen to|put on|play|start)\s+"#,
                                  with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(?:the )?(?:song|track)\s+"#, with: "", options: .regularExpression)
        return RequestLanguage.unquoted(value)
    }

    static func isQueueRequest(_ prompt: String) -> Bool {
        RequestLanguage.musicCommand(prompt).matches(#"^(queue|add to (?:my )?queue)\s+"#)
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
        let desiredArtist = artist?.musicNormalized
        let scored = candidates.compactMap { candidate -> (SpotifyResolvedTrack, Double)? in
            let actual = candidate.title.musicNormalized
            let artistScore: Double
            if let desiredArtist, !desiredArtist.isEmpty {
                artistScore = artistSimilarity(desiredArtist, candidate.artist.musicNormalized)
                guard artistScore >= 0.9 else { return nil }
            } else { artistScore = 1 }

            let titleScore: Double
            if desired == actual {
                titleScore = 1
            } else if isRemaster(of: desired, candidate: actual) {
                titleScore = 0.96
            } else if featuredTitle(candidate.title).musicNormalized == desired {
                titleScore = 0.96
            } else if desiredArtist?.isEmpty == false, artistScore == 1,
                      isSingleTypo(desired, actual) {
                // A near title alone is insufficient evidence to start playback. Require
                // an explicitly supplied artist and reject competing matches below.
                titleScore = 0.91
            } else { return nil }
            return (candidate, titleScore * 0.8 + artistScore * 0.2)
        }.sorted { $0.1 > $1.1 }
        guard let best = scored.first else { return nil }
        let identity = trackIdentity(best.0)
        guard !scored.dropFirst().contains(where: { abs($0.1 - best.1) < 0.025 && trackIdentity($0.0) != identity }) else {
            return nil
        }
        return best.0
    }

    private static func trackIdentity(_ track: SpotifyResolvedTrack) -> String {
        track.title.musicNormalized + "|" + track.artist.musicNormalized
    }

    private static func artistSimilarity(_ desired: String, _ actual: String) -> Double {
        if desired == actual { return 1 }
        // Spotify may include featured collaborators in its combined artist label.
        if coverage(desired, actual) == 1 { return 1 }
        return isSingleTypo(desired, actual) ? 0.92 : 0
    }

    private static func featuredTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s*[\[(](?:feat\.?|featuring|with)\s+[^\])]+[\])]$"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func isRemaster(of desired: String, candidate: String) -> Bool {
        guard candidate.hasPrefix(desired + " ") else { return false }
        let suffix = String(candidate.dropFirst(desired.count + 1))
        return suffix.matches(#"^(?:(?:19|20)\d{2} )?(?:remaster|remastered)(?: (?:19|20)\d{2})?$"#)
    }

    /// One insertion, deletion, substitution, or adjacent transposition in a sufficiently
    /// long name. Short names and multiple spelling changes are too ambiguous to correct.
    private static func isSingleTypo(_ desired: String, _ actual: String) -> Bool {
        let lhs = Array(desired), rhs = Array(actual)
        guard min(lhs.count, rhs.count) >= 5, abs(lhs.count - rhs.count) <= 1 else { return false }
        if lhs.count == rhs.count {
            let differing = lhs.indices.filter { lhs[$0] != rhs[$0] }
            if differing.count == 1 { return true }
            return differing.count == 2 && differing[1] == differing[0] + 1
                && lhs[differing[0]] == rhs[differing[1]] && lhs[differing[1]] == rhs[differing[0]]
        }
        let shorter = lhs.count < rhs.count ? lhs : rhs
        let longer = lhs.count < rhs.count ? rhs : lhs
        var i = 0, j = 0, skipped = false
        while i < shorter.count && j < longer.count {
            if shorter[i] == longer[j] { i += 1; j += 1 }
            else if !skipped { skipped = true; j += 1 }
            else { return false }
        }
        return true
    }

    private static func coverage(_ needle: String, _ haystack: String) -> Double {
        let a = Set(needle.musicNormalized.split(separator: " "))
        let b = Set(haystack.musicNormalized.split(separator: " "))
        return a.isEmpty ? 0 : Double(a.intersection(b).count) / Double(a.count)
    }
}
