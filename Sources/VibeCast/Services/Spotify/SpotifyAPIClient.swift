import Foundation

enum SpotifyAPIError: LocalizedError {
    case missingTrack
    case missingDevice
    case noAvailableDevices
    case noActiveDevice([SpotifyDevice])
    case unauthorized
    case forbidden(String)
    case rateLimited(String?)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingTrack:
            return "I could not find that track on Spotify."
        case .missingDevice:
            return "I could not find that Spotify speaker/device."
        case .noAvailableDevices:
            return "Spotify does not see an available playback device. Open Spotify on your Mac, phone, or speaker, then try again."
        case .noActiveDevice(let devices):
            let names = devices.map(\.name).joined(separator: ", ")
            if names.isEmpty {
                return "Spotify does not have an active playback device. Start Spotify on a device, then try again."
            }
            return "Spotify sees \(names), but none is active. Start playback there once, then try again."
        case .unauthorized:
            return "Your Spotify session expired. Log out and log back in."
        case .forbidden(let message):
            return message.isEmpty ? "Spotify refused that request. Check Premium status and app permissions." : message
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Spotify is rate limiting requests. Try again in \(retryAfter) seconds."
            } else {
                return "Spotify is rate limiting requests. Try again shortly."
            }
        case .requestFailed(let status, let message):
            return "Spotify API error \(status): \(message)"
        }
    }
}

@MainActor
final class SpotifyAPIClient {
    private let authService: SpotifyAuthService
    private let decoder = JSONDecoder()

    init(authService: SpotifyAuthService = .shared) {
        self.authService = authService
    }

    func execute(_ action: SpotifyAction) async throws -> VibeCastResult {
        switch action {
        case .pause:
            _ = try await requireActiveDevice()
            try await send(method: "PUT", path: "/me/player/pause")
            return VibeCastResult(title: action.notificationTitle, detail: nil, source: .spotifyAPI)
        case .resume:
            let device = try await preferredPlaybackDevice()
            try await send(method: "PUT", path: "/me/player/play", query: device.id.map { ["device_id": $0] } ?? [:])
            return VibeCastResult(title: action.notificationTitle, detail: nil, source: .spotifyAPI)
        case .next:
            _ = try await requireActiveDevice()
            try await send(method: "POST", path: "/me/player/next")
            return VibeCastResult(title: action.notificationTitle, detail: nil, source: .spotifyAPI)
        case .previous:
            _ = try await requireActiveDevice()
            try await send(method: "POST", path: "/me/player/previous")
            return VibeCastResult(title: action.notificationTitle, detail: nil, source: .spotifyAPI)
        case .shuffle(let enabled):
            _ = try await requireActiveDevice()
            try await send(method: "PUT", path: "/me/player/shuffle", query: ["state": enabled ? "true" : "false"])
            return VibeCastResult(title: action.notificationTitle, detail: nil, source: .spotifyAPI)
        case .repeatMode(let mode):
            _ = try await requireActiveDevice()
            try await send(method: "PUT", path: "/me/player/repeat", query: ["state": mode.rawValue])
            return VibeCastResult(title: action.notificationTitle, detail: nil, source: .spotifyAPI)
        case .playTrack(let query):
            let track = try await searchTrack(query)
            let device = try await preferredPlaybackDevice()
            let body = ["uris": [track.uri]]
            try await send(method: "PUT", path: "/me/player/play", query: device.id.map { ["device_id": $0] } ?? [:], jsonBody: body)
            return VibeCastResult(title: "Playing \(track.displayName)", detail: "Resolved track: \(track.displayName)", source: .spotifyAPI, resolvedItem: track.displayName)
        case .queueTrack(let query):
            let track = try await searchTrack(query)
            try await send(method: "POST", path: "/me/player/queue", query: ["uri": track.uri])
            return VibeCastResult(title: "Queued \(track.displayName)", detail: "Resolved track: \(track.displayName)", source: .spotifyAPI, resolvedItem: track.displayName)
        case .playResolvedTrack(let track):
            let device = try await preferredPlaybackDevice()
            let body = ["uris": [track.uri]]
            try await send(method: "PUT", path: "/me/player/play", query: device.id.map { ["device_id": $0] } ?? [:], jsonBody: body)
            return VibeCastResult(title: "Playing \(track.displayName)", detail: "Resolved track: \(track.displayName)", source: .spotifyAPI, resolvedItem: track.displayName)
        case .queueResolvedTrack(let track):
            try await send(method: "POST", path: "/me/player/queue", query: ["uri": track.uri])
            return VibeCastResult(title: "Queued \(track.displayName)", detail: "Resolved track: \(track.displayName)", source: .spotifyAPI, resolvedItem: track.displayName)
        case .transferPlayback(let deviceName):
            let device = try await findDevice(named: deviceName)
            let body = ["device_ids": [device.id ?? ""], "play": true] as [String: Any]
            try await send(method: "PUT", path: "/me/player", jsonAnyBody: body)
            return VibeCastResult(title: "Changed speaker to \(device.name)", detail: "Resolved device: \(device.name)", source: .spotifyAPI, resolvedItem: device.name)
        }
    }

    func fetchCurrentUserDisplayName() async throws -> String? {
        let profile: SpotifyUserProfile = try await request(method: "GET", path: "/me")
        return profile.displayName
    }

    func searchTrackCandidates(query: String, limit: Int = 8) async throws -> [SpotifyResolvedTrack] {
        let cleanedQuery = query.cleanedSearchQuery
        guard !cleanedQuery.isEmpty else { return [] }

        var deduped: [String: SpotifyResolvedTrack] = [:]
        var ordered: [SpotifyResolvedTrack] = []

        for variant in searchVariants(for: cleanedQuery) {
            let response: SpotifySearchResponse = try await request(
                method: "GET",
                path: "/search",
                query: ["type": "track", "limit": "\(limit)", "q": variant]
            )

            for track in response.tracks.items {
                guard deduped[track.uri] == nil else { continue }
                let resolved = track.resolvedTrack
                deduped[track.uri] = resolved
                ordered.append(resolved)
            }
        }

        return Array(ordered.prefix(limit))
    }

    private func searchTrack(_ query: TrackQuery) async throws -> SpotifyTrack {
        var search = "track:\(query.title)"
        if let artist = query.artist {
            search += " artist:\(artist)"
        }

        let response: SpotifySearchResponse = try await request(
            method: "GET",
            path: "/search",
            query: ["type": "track", "limit": "1", "q": search]
        )

        guard let track = response.tracks.items.first else {
            throw SpotifyAPIError.missingTrack
        }

        return track
    }

    private func searchVariants(for query: String) -> [String] {
        var variants = [query]
        let withoutParentheticals = query.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .cleanedSearchQuery
        if !withoutParentheticals.isEmpty, withoutParentheticals != query {
            variants.append(withoutParentheticals)
        }
        return variants
    }

    private func findDevice(named deviceName: String) async throws -> SpotifyDevice {
        let response: SpotifyDevicesResponse = try await request(method: "GET", path: "/me/player/devices")
        let normalized = deviceName.lowercased()
        guard let device = response.devices.first(where: { $0.name.lowercased().contains(normalized) }),
              device.id != nil else {
            throw SpotifyAPIError.missingDevice
        }
        return device
    }

    private func fetchDevices() async throws -> [SpotifyDevice] {
        let response: SpotifyDevicesResponse = try await request(method: "GET", path: "/me/player/devices")
        return response.devices
    }

    private func requireActiveDevice() async throws -> SpotifyDevice {
        let devices = try await fetchDevices()
        guard !devices.isEmpty else {
            throw SpotifyAPIError.noAvailableDevices
        }

        guard let active = devices.first(where: \.isActive) else {
            throw SpotifyAPIError.noActiveDevice(devices)
        }

        return active
    }

    private func preferredPlaybackDevice() async throws -> SpotifyDevice {
        let devices = try await fetchDevices()
        guard !devices.isEmpty else {
            throw SpotifyAPIError.noAvailableDevices
        }

        return devices.first(where: \.isActive) ?? devices[0]
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        query: [String: String] = [:]
    ) async throws -> T {
        let data = try await send(method: method, path: path, query: query)
        return try decoder.decode(T.self, from: data)
    }

    @discardableResult
    private func send(
        method: String,
        path: String,
        query: [String: String] = [:],
        jsonBody: Encodable? = nil,
        jsonAnyBody: [String: Any]? = nil
    ) async throws -> Data {
        var components = URLComponents(string: "https://api.spotify.com/v1\(path)")!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await authService.validAccessToken())", forHTTPHeaderField: "Authorization")

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(jsonBody))
        } else if let jsonAnyBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonAnyBody)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLogger.spotify.error("Spotify request failed: method=\(method, privacy: .public) path=\(path, privacy: .public) status=\(status, privacy: .public)")
            throw mapFailure(status: status, data: data, response: response)
        }

        return data
    }

    private func mapFailure(status: Int, data: Data, response: URLResponse) -> SpotifyAPIError {
        let message = spotifyErrorMessage(from: data)
        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message)
        case 404:
            return .noAvailableDevices
        case 429:
            let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            return .rateLimited(retryAfter)
        default:
            return .requestFailed(status, message.isEmpty ? "Unknown response" : message)
        }
    }

    private func spotifyErrorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable {
            struct Body: Decodable {
                let message: String?
                let reason: String?
            }

            let error: Body?
        }

        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message ?? envelope.error?.reason {
            return message
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension SpotifyTrack {
    var resolvedTrack: SpotifyResolvedTrack {
        SpotifyResolvedTrack(
            uri: uri,
            title: name,
            artist: artists.first?.name ?? "Unknown Artist"
        )
    }
}

private extension String {
    var cleanedSearchQuery: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

private struct AnyEncodable: Encodable {
    let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
