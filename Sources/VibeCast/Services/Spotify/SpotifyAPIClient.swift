import Foundation

enum SpotifyAPIError: LocalizedError {
    case missingTrack, missingDevice, noAvailableDevices, unauthorized, missingPlaylistScopes
    case refused(path: String, message: String)
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
        let age = Date().timeIntervalSince(createdAt)
        return age >= 0 && age < 86_400
    }
}

@MainActor
protocol SpotifyServing {
    func execute(_ action: SpotifyAction) async throws -> VibeCastResult
    func profile() async throws -> SpotifyUserProfile
    func playback() async throws -> SpotifyPlayback?
    func queue() async throws -> [SpotifyQueueItem]
    func devices() async throws -> [SpotifyDevice]
    func searchTrackCandidates(query: String, limit: Int) async throws -> [SpotifyResolvedTrack]
    func searchPlaylistCandidates(query: String, limit: Int) async throws -> [SpotifyResolvedPlaylist]
    func createPlaylist(name: String, description: String) async throws -> SpotifyResolvedPlaylist
    func setPlaylistTracks(_ playlist: SpotifyResolvedPlaylist, tracks: [SpotifyResolvedTrack]) async throws
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

    func execute(_ action: SpotifyAction) async throws -> VibeCastResult {
        var resolved: String?
        var playlist: SpotifyResolvedPlaylist?
        switch action {
        case .pause: try await send(method: "PUT", path: "/me/player/pause")
        case .resume:
            try await send(method: "PUT", path: "/me/player/play", query: deviceQuery())
        case .next: try await send(method: "POST", path: "/me/player/next")
        case .previous: try await send(method: "POST", path: "/me/player/previous")
        case .advanceQueue(_, let id):
            try await send(method: "POST", path: "/me/player/next", query: ["device_id": id])
        case .rewindQueue(_, let id):
            try await send(method: "POST", path: "/me/player/previous", query: ["device_id": id])
        case .seek(let position, let uri):
            guard let current = try await playback(), current.item?.uri == uri,
                  let duration = current.item?.durationMS, position >= 0, position < duration,
                  let device = current.device, device.isRestricted != true, let id = device.id,
                  !id.isEmpty, current.actions?.disallows?["seeking"] != true else {
                throw UserFacingError("The song or Spotify device changed, or seeking isn't available. Refresh the player and try again.")
            }
            try await send(method: "PUT", path: "/me/player/seek", query: ["position_ms": String(position), "device_id": id])
        case .shuffle(let enabled):
            try await send(method: "PUT", path: "/me/player/shuffle", query: ["state": String(enabled)])
        case .repeatMode(let mode):
            try await send(method: "PUT", path: "/me/player/repeat", query: ["state": mode.rawValue])
        case .playTrack(let query), .queueTrack(let query):
            let candidates = try await searchTrackCandidates(query: "track:\"\(query.title)\" artist:\"\(query.artist ?? "")\"", limit: 8)
            guard let track = MusicSearch.matchTrack(title: query.title, artist: query.artist, candidates: candidates) else {
                throw SpotifyAPIError.missingTrack
            }
            return try await execute(action.isQueue ? .queueResolvedTrack(track) : .playResolvedTrack(track))
        case .playResolvedTrack(let track):
            try await send(method: "PUT", path: "/me/player/play", query: deviceQuery(), body: ["uris": [track.uri]])
            resolved = track.displayName
        case .queueResolvedTrack(let track):
            try await send(method: "POST", path: "/me/player/queue", query: ["uri": track.uri])
            resolved = track.displayName
        case .playResolvedPlaylist(let value):
            try await send(method: "PUT", path: "/me/player/play", query: deviceQuery(), body: ["context_uri": value.uri])
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
                $0.id != nil && $0.isRestricted != true && $0.name.localizedCaseInsensitiveContains(name)
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

    private func deviceQuery() async throws -> [String: String] {
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
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await transport.data(for: request)
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
