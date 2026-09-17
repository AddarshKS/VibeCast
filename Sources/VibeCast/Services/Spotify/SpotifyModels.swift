import Foundation

struct SpotifyToken: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let scope: String?
    let expiresAt: Date
    var serviceSession: String? = nil
    var isExpired: Bool { Date().addingTimeInterval(60) >= expiresAt }
    func hasScopes(_ required: [String]) -> Bool {
        let granted = Set((scope ?? "").split(separator: " ").map(String.init))
        return required.allSatisfy { granted.contains($0) }
    }
}

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let scope: String?
    let expiresIn: Int
    let refreshToken: String?
    let serviceSession: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
        case serviceSession = "vibecast_session"
        case scope
    }
    func token(replacingRefreshToken existing: String? = nil, replacingScope existingScope: String? = nil) -> SpotifyToken {
        SpotifyToken(accessToken: accessToken, refreshToken: refreshToken ?? existing,
                     scope: scope ?? existingScope, expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
                     serviceSession: serviceSession)
    }
}

struct SpotifyUserProfile: Decodable {
    let id: String
    let displayName: String?
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
}

struct SpotifySearchResponse: Decodable { let tracks: SpotifyTrackPage }
struct SpotifyPlaylistSearchResponse: Decodable { let playlists: SpotifyPlaylistPage }
struct SpotifyTrackPage: Decodable { let items: [SpotifyTrack?] }
struct SpotifyPlaylistPage: Decodable { let items: [SpotifyPlaylist?] }
struct SpotifyImage: Decodable { let url: URL }
struct SpotifyAlbum: Decodable {
    let images: [SpotifyImage]?
    var name: String? = nil
}
struct SpotifyArtist: Decodable { let name: String }

struct SpotifyTrack: Decodable {
    let uri: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let isPlayable: Bool?
    var durationMS: Int? = nil
    enum CodingKeys: String, CodingKey {
        case uri, name, artists, album, isPlayable = "is_playable", durationMS = "duration_ms"
    }
    var resolvedTrack: SpotifyResolvedTrack {
        SpotifyResolvedTrack(uri: uri, title: name, artist: artists.map(\.name).joined(separator: ", "),
                             artworkURL: album?.images?.first?.url)
    }
}

struct SpotifyPlaylist: Decodable {
    let id: String
    let uri: String
    let name: String
    let description: String?
    let owner: SpotifyPlaylistOwner?
    let images: [SpotifyImage]?
    var resolvedPlaylist: SpotifyResolvedPlaylist {
        SpotifyResolvedPlaylist(uri: uri, name: name, ownerName: owner?.displayName,
                                description: description, artworkURL: images?.first?.url)
    }
}
struct SpotifyPlaylistOwner: Decodable {
    let displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}
struct SpotifyDevicesResponse: Decodable { let devices: [SpotifyDevice] }
struct SpotifyDevice: Decodable, Equatable {
    let id: String?
    let name: String
    let isActive: Bool
    let isRestricted: Bool?
    enum CodingKeys: String, CodingKey {
        case id, name, isActive = "is_active", isRestricted = "is_restricted"
    }
}
struct SpotifyPlayback: Decodable {
    let isPlaying: Bool
    let item: SpotifyTrack?
    let device: SpotifyDevice?
    let shuffleState: Bool
    let repeatState: String
    var progressMS: Int? = nil
    var actions: Actions? = nil
    struct Actions: Decodable { let disallows: [String: Bool]? }
    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing", item, device, shuffleState = "shuffle_state", repeatState = "repeat_state"
        case progressMS = "progress_ms"
        case actions
    }

    func elapsedMS(observedAt: Date, now: Date) -> Int {
        guard let progressMS, let duration = item?.durationMS, duration > 0 else { return 0 }
        let elapsed = isPlaying ? max(0, now.timeIntervalSince(observedAt)) * 1000 : 0
        return min(duration, max(0, progressMS + Int(elapsed)))
    }
}

extension SpotifyPlayback {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isPlaying = try values.decode(Bool.self, forKey: .isPlaying)
        device = try values.decodeIfPresent(SpotifyDevice.self, forKey: .device)
        shuffleState = try values.decode(Bool.self, forKey: .shuffleState)
        repeatState = try values.decode(String.self, forKey: .repeatState)
        progressMS = try values.decodeIfPresent(Int.self, forKey: .progressMS)
        actions = try values.decodeIfPresent(Actions.self, forKey: .actions)
        // Episodes and ads must clear the old song, not leave stale artwork/lyrics onscreen.
        item = try? values.decodeIfPresent(SpotifyTrack.self, forKey: .item)
    }
}

struct SpotifyQueue: Decodable {
    let queue: [SpotifyQueueItem?]
}

// The queue can contain episodes as well as tracks, and may repeat the same URI.
struct SpotifyQueueItem: Decodable {
    let uri: String
    let name: String
    let artists: [SpotifyArtist]?
    let album: SpotifyAlbum?
    let images: [SpotifyImage]?
    let show: Show?
    var isPlayable: Bool? = nil
    enum CodingKeys: String, CodingKey {
        case uri, name, artists, album, images, show
        case isPlayable = "is_playable"
    }
    struct Show: Decodable { let name: String }
    var playableTrack: SpotifyResolvedTrack? {
        guard uri.hasPrefix("spotify:track:"), spotifyURL != nil, isPlayable != false else { return nil }
        return SpotifyResolvedTrack(uri: uri, title: name, artist: subtitle, artworkURL: artworkURL)
    }
    var subtitle: String { artists?.map(\.name).joined(separator: ", ") ?? show?.name ?? "Podcast episode" }
    var artworkURL: URL? { album?.images?.first?.url ?? images?.first?.url }
    var spotifyURL: URL? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", ["track", "episode"].contains(String(parts[1])),
              parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }
}
