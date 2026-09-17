import Foundation

enum Lyrics: Equatable, Sendable {
    case synced(TimedLyrics), text(String), instrumental, unavailable
}

protocol LyricsServing: Sendable {
    func lyrics(for track: SpotifyTrack) async throws -> Lyrics
}

struct LyricsClient: LyricsServing {
    var transport: any HTTPTransport = URLSessionTransport()

    func lyrics(for track: SpotifyTrack) async throws -> Lyrics {
        guard track.uri.hasPrefix("spotify:track:"), let artist = track.artists.first?.name,
              let duration = track.durationMS, duration > 0 else { return .unavailable }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: track.name),
                          URLQueryItem(name: "artist_name", value: artist),
                          URLQueryItem(name: "duration", value: String(Double(duration) / 1000))]
        if let album = track.album?.name { url.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 15
        request.setValue("VibeCast/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Never attach Spotify authorization, cookies, account IDs, or AI credentials.
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 404 { return .unavailable }
        guard response.statusCode == 200 else {
            throw UserFacingError("Lyrics couldn't be loaded. Try again in a moment.")
        }
        struct Record: Decodable { let instrumental: Bool; let plainLyrics: String?; let syncedLyrics: String? }
        let record = try JSONDecoder().decode(Record.self, from: data)
        if record.instrumental { return .instrumental }
        if let lrc = record.syncedLyrics, let timed = TimedLyrics(lrc: lrc) { return .synced(timed) }
        guard let text = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .unavailable
        }
        return .text(text)
    }
}
