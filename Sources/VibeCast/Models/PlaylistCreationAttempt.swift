import Foundation

/// Saved before the non-idempotent create request. An unknown outcome must be looked up,
/// never retried as a fresh POST, even after relaunch or a long offline interval.
struct PlaylistCreationAttempt: Codable, Equatable {
    var id = UUID()
    let accountID: String
    let name: String
    let description: String
    let tracks: [SpotifyResolvedTrack]
    var createdAt = Date()

    var marker: String { "[VibeCast:\(id.uuidString.lowercased())]" }

    var spotifyDescription: String {
        let brief = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(brief.prefix(300 - marker.count - 1))
        return prefix.isEmpty ? marker : "\(prefix) \(marker)"
    }

    func matches(description: String?) -> Bool {
        guard let description else { return false }
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == marker || value.hasSuffix(" " + marker)
    }
}

enum PlaylistRecoveryError: LocalizedError, Equatable {
    case missingReadAccess
    case accountChanged
    case ambiguousCreation
    case incompleteLookup
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .missingReadAccess:
            "Reconnect Spotify in Settings to let VibeCast check and recover your private playlists."
        case .accountChanged:
            "Connect the Spotify account that started this playlist to finish it."
        case .ambiguousCreation:
            "More than one playlist matches this unfinished request. Check your Spotify library before starting another."
        case .incompleteLookup:
            "Spotify's playlist list couldn't be fully checked. Keep this request and check again shortly."
        case .verificationFailed:
            "Spotify hasn't confirmed the playlist's songs, order, and privacy yet. Keep the unfinished playlist and check again."
        }
    }
}
