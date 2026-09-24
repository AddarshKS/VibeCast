import Foundation

enum SpotifyAPIError: LocalizedError {
    case missingTrack, missingDevice, noAvailableDevices, unauthorized, missingPlaylistScopes
    case refused(path: String, message: String)
    case playbackRefused(path: String, reason: SpotifyPlaybackRefusal)
    case rateLimited(Int?)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingTrack: "No matching song turned up. Try the song title and artist."
        case .missingDevice: "That Spotify device isn't available. Open Spotify on it and try again."
        case .noAvailableDevices: "Open Spotify on your Mac, phone, or speaker, then try again."
        case .unauthorized: "Your Spotify connection expired. Reconnect in Settings."
        case .missingPlaylistScopes: "Reconnect Spotify to allow VibeCast to create private playlists."
        case .refused(let path, let message):
            "Spotify declined \(path.contains("/player") ? "playback" : "this request"). Check your app's tester access and Spotify permissions\(path.contains("/player") ? ", and make sure you have Premium" : "").\(message.isEmpty || message == "Forbidden" ? "" : " " + message)"
        case .playbackRefused(let path, let reason): reason.message(path: path)
        case .rateLimited(let seconds):
            seconds.map { "Spotify is busy. Try again in \($0) seconds." } ?? "Spotify is busy. Try again in a moment."
        case .requestFailed(let status, _): "Spotify couldn't complete that request (\(status)). Please try again."
        }
    }
}

struct PlaylistDraft: Codable, Equatable {
    let accountID: String
    let playlist: SpotifyResolvedPlaylist
    let tracks: [SpotifyResolvedTrack]
    var createdAt = Date()
    var isRecoverable: Bool {
        // A known playlist does not disappear from Spotify after a day. Recovery is
        // retained until completion or an explicit choice to stop it.
        !accountID.isEmpty && playlist.spotifyURL != nil && !tracks.isEmpty
    }
}

@MainActor
protocol SpotifyServing {
    func execute(_ action: SpotifyAction, deviceID: String?) async throws -> VibeCastResult
    func profile() async throws -> SpotifyUserProfile
    func playback() async throws -> SpotifyPlayback?
    func queue() async throws -> [SpotifyQueueItem]
    func devices() async throws -> [SpotifyDevice]
    func searchTrackCandidates(query: String, limit: Int) async throws -> [SpotifyResolvedTrack]
    func searchPlaylistCandidates(query: String, limit: Int) async throws -> [SpotifyResolvedPlaylist]
    func createPlaylist(name: String, description: String) async throws -> SpotifyResolvedPlaylist
    func setPlaylistTracks(_ playlist: SpotifyResolvedPlaylist, tracks: [SpotifyResolvedTrack]) async throws
    func findCreatedPlaylist(for attempt: PlaylistCreationAttempt) async throws -> SpotifyResolvedPlaylist?
    func verifyPlaylist(_ playlist: SpotifyResolvedPlaylist, tracks: [SpotifyResolvedTrack], accountID: String) async throws
}

extension SpotifyServing {
    func execute(_ action: SpotifyAction) async throws -> VibeCastResult {
        try await execute(action, deviceID: nil)
    }

    func resolveTrack(_ query: TrackQuery) async throws -> SpotifyResolvedTrack {
        let candidates = try await searchTrackCandidates(query: "track:\"\(query.title)\" artist:\"\(query.artist ?? "")\"", limit: 8)
        try Task.checkCancellation()
        guard let track = MusicSearch.matchTrack(title: query.title, artist: query.artist, candidates: candidates) else {
            throw SpotifyAPIError.missingTrack
        }
        return track
    }
}

@MainActor
final class SpotifyAPIClient: SpotifyServing {
    private let auth: any SpotifyAuthorizing
    private let transport: any HTTPTransport
    init(auth: any SpotifyAuthorizing, transport: any HTTPTransport = URLSessionTransport()) {
        self.auth = auth
        self.transport = transport
    }

    func profile() async throws -> SpotifyUserProfile { try await request(path: "/me") }
    func playback() async throws -> SpotifyPlayback? {
        let data = try await send(method: "GET", path: "/me/player")
        return data.isEmpty ? nil : try JSONDecoder().decode(SpotifyPlayback.self, from: data)
    }

    func queue() async throws -> [SpotifyQueueItem] {
        let data = try await send(method: "GET", path: "/me/player/queue")
        return data.isEmpty ? [] : try JSONDecoder().decode(SpotifyQueue.self, from: data).queue.compactMap { $0 }
    }

    func devices() async throws -> [SpotifyDevice] {
        let response: SpotifyDevicesResponse = try await request(path: "/me/player/devices")
        return response.devices
    }

    func execute(_ action: SpotifyAction, deviceID: String? = nil) async throws -> VibeCastResult {
        var resolved: String?
        var playlist: SpotifyResolvedPlaylist?
        let target = deviceID.flatMap { $0.isEmpty ? nil : $0 }.map { ["device_id": $0] }
        switch action {
        case .pause: try await send(method: "PUT", path: "/me/player/pause", query: target ?? [:])
        case .resume:
            try await send(method: "PUT", path: "/me/player/play", query: deviceQuery(preferred: target))
        case .next: try await send(method: "POST", path: "/me/player/next", query: target ?? [:])
        case .previous: try await send(method: "POST", path: "/me/player/previous", query: target ?? [:])
        case .advanceQueue(_, let id):
            try await send(method: "POST", path: "/me/player/next", query: ["device_id": id])
        case .rewindQueue(_, let id):
            try await send(method: "POST", path: "/me/player/previous", query: ["device_id": id])
        case .seek(let position, let uri):
            guard let current = try await playback(), current.item?.uri == uri,
                  let duration = current.item?.durationMS, position >= 0, position < duration,
                  let device = current.device, device.isRestricted != true, let id = device.id,
                  !id.isEmpty, (deviceID == nil || id == deviceID), current.actions?.disallows?["seeking"] != true else {
                throw UserFacingError("The song or Spotify device changed, or seeking isn't available. Refresh the player and try again.")
            }
            try await send(method: "PUT", path: "/me/player/seek", query: ["position_ms": String(position), "device_id": id])
        case .shuffle(let enabled):
            try await send(method: "PUT", path: "/me/player/shuffle", query: (target ?? [:]).merging(["state": String(enabled)]) { _, new in new })
        case .repeatMode(let mode):
            try await send(method: "PUT", path: "/me/player/repeat", query: (target ?? [:]).merging(["state": mode.rawValue]) { _, new in new })
        case .playTrack(let query), .queueTrack(let query):
            let track = try await resolveTrack(query)
            return try await execute(action.isQueue ? .queueResolvedTrack(track) : .playResolvedTrack(track), deviceID: deviceID)
        case .playResolvedTrack(let track):
            try await send(method: "PUT", path: "/me/player/play", query: deviceQuery(preferred: target), body: ["uris": [track.uri]])
            resolved = track.displayName
        case .queueResolvedTrack(let track):
            try await send(method: "POST", path: "/me/player/queue", query: (target ?? [:]).merging(["uri": track.uri]) { _, new in new })
            resolved = track.displayName
        case .playResolvedPlaylist(let value):
            try await send(method: "PUT", path: "/me/player/play", query: deviceQuery(preferred: target), body: ["context_uri": value.uri])
            resolved = value.name
            playlist = value
        case .transferToDevice(let target):
            guard let id = target.id, !id.isEmpty,
                  try await devices().contains(where: { $0.id == id && $0.isRestricted != true }) else {
                throw SpotifyAPIError.missingDevice
            }
            try await send(method: "PUT", path: "/me/player", body: ["device_ids": [id], "play": false])
            resolved = target.name
        case .transferPlayback(let name):
            let devices: SpotifyDevicesResponse = try await request(path: "/me/player/devices")
            guard let device = devices.devices.first(where: {
                $0.id != nil && $0.isRestricted != true &&
                    (deviceID == nil ? $0.name.localizedCaseInsensitiveContains(name) : $0.id == deviceID)
            }), let id = device.id else { throw SpotifyAPIError.missingDevice }
            try await send(method: "PUT", path: "/me/player", body: ["device_ids": [id], "play": true])
            resolved = device.name
        }
        return VibeCastResult(title: action.notificationTitle, source: .spotifyAPI, resolvedItem: resolved, playlist: playlist)
    }

    func createPlaylist(name: String, description: String) async throws -> SpotifyResolvedPlaylist {
        _ = try await auth.validAccessToken(forceRefresh: false)
        guard try auth.currentToken()?.hasScopes(["playlist-modify-private"]) == true else {
            throw SpotifyAPIError.missingPlaylistScopes
        }
        let data = try await send(method: "POST", path: "/me/playlists",
                                  body: ["name": String(name.prefix(100)), "description": String(description.prefix(300)), "public": false])
        return try JSONDecoder().decode(SpotifyPlaylist.self, from: data).resolvedPlaylist
    }

    func setPlaylistTracks(_ playlist: SpotifyResolvedPlaylist, tracks: [SpotifyResolvedTrack]) async throws {
        guard let id = playlist.spotifyURL?.lastPathComponent, !tracks.isEmpty, tracks.count <= 100,
              tracks.allSatisfy({ $0.uri.range(of: "^spotify:track:[A-Za-z0-9]{22}$", options: .regularExpression) != nil }) else {
            throw UserFacingError("The playlist contains an invalid Spotify track. Please try a new request.")
        }
        // Replacing a newly created playlist is idempotent, including after an uncertain network failure.
        try await send(method: "PUT", path: "/playlists/\(id)/items", body: ["uris": tracks.map(\.uri)])
    }

    func findCreatedPlaylist(for attempt: PlaylistCreationAttempt) async throws -> SpotifyResolvedPlaylist? {
        try await requirePlaylistReadAccess(accountID: attempt.accountID)
        var offset = 0
        var match: SpotifyPlaylist?
        var seenIDs = Set<String>()
        while true {
            let page: SpotifyOwnedPlaylistPage = try await request(path: "/me/playlists", query: ["limit": "50", "offset": String(offset)])
            try Task.checkCancellation()
            guard page.offset == offset, page.total >= offset + page.items.count else {
                throw PlaylistRecoveryError.incompleteLookup
            }
            for playlist in page.items.compactMap({ $0 }) {
                guard seenIDs.insert(playlist.id).inserted else { throw PlaylistRecoveryError.incompleteLookup }
                guard playlist.owner?.id == attempt.accountID, attempt.matches(description: playlist.description) else { continue }
                guard match == nil else { throw PlaylistRecoveryError.ambiguousCreation }
                guard playlist.isPublic == false, playlist.uri == "spotify:playlist:\(playlist.id)",
                      playlist.resolvedPlaylist.spotifyURL != nil else { throw PlaylistRecoveryError.verificationFailed }
                match = playlist
            }
            offset += page.items.count
            if page.next == nil {
                guard offset == page.total else { throw PlaylistRecoveryError.incompleteLookup }
                break
            }
            guard !page.items.isEmpty, offset < page.total, offset <= 100_000 else {
                throw PlaylistRecoveryError.incompleteLookup
            }
            // Construct the next request ourselves; never follow a returned URL with a bearer token.
        }
        guard try await profile().id == attempt.accountID else { throw PlaylistRecoveryError.accountChanged }
        try Task.checkCancellation()
        return match?.resolvedPlaylist
    }

    func verifyPlaylist(_ playlist: SpotifyResolvedPlaylist, tracks: [SpotifyResolvedTrack], accountID: String) async throws {
        guard let id = playlist.spotifyURL?.lastPathComponent, !tracks.isEmpty, tracks.count <= 100 else {
            throw PlaylistRecoveryError.verificationFailed
        }
        try await requirePlaylistReadAccess(accountID: accountID)
        let before: SpotifyPlaylist = try await request(path: "/playlists/\(id)")
        guard before.owner?.id == accountID, before.isPublic == false,
              before.uri == playlist.uri, let snapshot = before.snapshotID, !snapshot.isEmpty else {
            throw PlaylistRecoveryError.verificationFailed
        }
        var uris: [String] = []
        while true {
            let offset = uris.count
            let page: SpotifyPlaylistItemsPage = try await request(path: "/playlists/\(id)/items", query: ["limit": "50", "offset": String(offset)])
            try Task.checkCancellation()
            guard page.offset == offset, page.total == tracks.count, offset + page.items.count <= tracks.count else {
                throw PlaylistRecoveryError.verificationFailed
            }
            for entry in page.items {
                guard let uri = entry?.item?.requestedURI else { throw PlaylistRecoveryError.verificationFailed }
                uris.append(uri)
            }
            if page.next == nil { break }
            guard !page.items.isEmpty, uris.count < tracks.count else { throw PlaylistRecoveryError.verificationFailed }
        }
        guard uris == tracks.map(\.uri) else { throw PlaylistRecoveryError.verificationFailed }
        let after: SpotifyPlaylist = try await request(path: "/playlists/\(id)")
        guard after.owner?.id == accountID, after.isPublic == false,
              after.uri == playlist.uri, after.snapshotID == snapshot else {
            throw PlaylistRecoveryError.verificationFailed
        }
        guard try await profile().id == accountID else { throw PlaylistRecoveryError.accountChanged }
        try Task.checkCancellation()
    }

    private func requirePlaylistReadAccess(accountID: String) async throws {
        _ = try await auth.validAccessToken(forceRefresh: false)
        guard try auth.currentToken()?.hasScopes(["playlist-read-private"]) == true else {
            throw PlaylistRecoveryError.missingReadAccess
        }
        guard try await profile().id == accountID else { throw PlaylistRecoveryError.accountChanged }
        try Task.checkCancellation()
    }

    func searchTrackCandidates(query: String, limit: Int = 8) async throws -> [SpotifyResolvedTrack] {
        let page: SpotifySearchResponse = try await request(path: "/search", query: [
            "type": "track", "q": query, "limit": String(min(10, max(1, limit)))
        ])
        return page.tracks.items.compactMap { track in
            guard let track, track.isPlayable != false else { return nil }
            return track.resolvedTrack
        }
    }

    func searchPlaylistCandidates(query: String, limit: Int = 8) async throws -> [SpotifyResolvedPlaylist] {
        let page: SpotifyPlaylistSearchResponse = try await request(path: "/search", query: [
            "type": "playlist", "q": query, "limit": String(min(10, max(1, limit)))
        ])
        return page.playlists.items.compactMap { $0?.resolvedPlaylist }
    }

    private func deviceQuery(preferred: [String: String]? = nil) async throws -> [String: String] {
        if let preferred { return preferred }
        let page: SpotifyDevicesResponse = try await request(path: "/me/player/devices")
        let available = page.devices.filter { $0.id != nil && $0.isRestricted != true }
        guard let device = available.first(where: \.isActive) ?? available.first, let id = device.id else {
            throw SpotifyAPIError.noAvailableDevices
        }
        return ["device_id": id]
    }

    private func request<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> T {
        try await JSONDecoder().decode(T.self, from: send(method: "GET", path: path, query: query))
    }

    @discardableResult
    private func send(method: String, path: String, query: [String: String] = [:],
                      body: [String: Any]? = nil, retried: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        var components = URLComponents(string: "https://api.spotify.com/v1\(path)")!
        components.queryItems = query.isEmpty ? nil : query.sorted(by: { $0.key < $1.key }).map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.validAccessToken(forceRefresh: false))", forHTTPHeaderField: "Authorization")
        try Task.checkCancellation()
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        let status = response.statusCode
        if (200..<300).contains(status) { return data }
        if status == 401 && !retried {
            _ = try await auth.validAccessToken(forceRefresh: true)
            return try await send(method: method, path: path, query: query, body: body, retried: true)
        }
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        if status == 429 && method == "GET" && !retried, let wait = retryAfter, (1...30).contains(wait) {
            try await Task.sleep(for: .seconds(wait))
            return try await send(method: method, path: path, query: query, body: body, retried: true)
        }
        AppLogger.spotify.error("Spotify request failed: \(method, privacy: .public) \(path, privacy: .public) status=\(status, privacy: .public)")
        switch status {
        case 401: throw SpotifyAPIError.unauthorized
        case 403 where path.hasPrefix("/me/player"):
            throw SpotifyAPIError.playbackRefused(path: path, reason: SpotifyPlaybackRefusal.decode(data))
        case 403: throw SpotifyAPIError.refused(path: path, message: "")
        case 404 where path.hasPrefix("/me/player"): throw SpotifyAPIError.noAvailableDevices
        case 429: throw SpotifyAPIError.rateLimited(retryAfter)
        default: throw SpotifyAPIError.requestFailed(status, path)
        }
    }
}

private extension SpotifyAction {
    var isQueue: Bool { if case .queueTrack = self { return true }; return false }
}
