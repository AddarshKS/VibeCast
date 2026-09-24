import Foundation

struct DirectCommandClassifier {
    func action(for prompt: String) -> SpotifyAction? {
        let normalized = RequestLanguage.command(prompt)

        switch normalized {
        case "pause", "pause playback", "pause the music", "pause music", "stop", "stop playback", "stop the music", "hold up":
            return .pause
        case "resume", "play", "continue", "continue playback", "start playback", "resume playback", "resume the music", "unpause":
            return .resume
        case "skip", "next", "next song", "next track", "skip song", "skip track", "skip this", "skip this song", "skip this track":
            return .next
        case "previous", "back", "last song", "previous song", "previous track", "go back", "go back a song":
            return .previous
        case "shuffle on", "turn shuffle on", "turn on shuffle", "enable shuffle":
            return .shuffle(true)
        case "shuffle off", "turn shuffle off", "turn off shuffle", "disable shuffle":
            return .shuffle(false)
        case "repeat off", "turn repeat off", "turn off repeat", "disable repeat":
            return .repeatMode(.off)
        case "repeat on", "turn repeat on", "turn on repeat", "enable repeat":
            return .repeatMode(.context)
        case "repeat current song", "repeat the current song", "repeat track", "repeat this song", "loop this song", "loop current song":
            return .repeatMode(.track)
        default:
            break
        }

        if let query = parseTrackCommand(normalized, verbs: ["play", "start", "put on", "listen to"]) {
            return .playTrack(query: query)
        }
        if let query = parseTrackCommand(normalized, verbs: ["queue", "add to queue", "add to my queue"]) {
            return .queueTrack(query: query)
        }
        if let deviceName = parseDeviceCommand(normalized) {
            return .transferPlayback(deviceName: deviceName)
        }
        return nil
    }

    private func parseTrackCommand(_ normalized: String, verbs: [String]) -> TrackQuery? {
        guard let verb = verbs.first(where: { normalized.hasPrefix("\($0) ") }),
              RequestLanguage.artistPreference(normalized) == nil else { return nil }
        var remainder = String(normalized.dropFirst(verb.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        remainder = remainder.replacingOccurrences(of: #"^(?:the )?(?:song|track)\s+"#, with: "", options: .regularExpression)
        guard !remainder.isEmpty else { return nil }

        // Use the last separator, and don't treat "by" inside a quoted title as an artist.
        if let range = remainder.range(of: " by ", options: .backwards) {
            let titlePart = String(remainder[..<range.lowerBound])
            let openQuotes = titlePart.filter { $0 == "\"" || $0 == "\u{201C}" || $0 == "\u{201D}" }.count
            guard openQuotes.isMultiple(of: 2) else { return nil }
            let title = RequestLanguage.unquoted(titlePart).displayCapitalized
            let artist = RequestLanguage.unquoted(String(remainder[range.upperBound...])).displayCapitalized
            guard !title.isEmpty, !artist.isEmpty else { return nil }
            return TrackQuery(title: title, artist: artist)
        }
        return nil
    }

    private func parseDeviceCommand(_ normalized: String) -> String? {
        let prefixes = ["change speaker to ", "switch speaker to ", "change output to ", "switch output to ",
                        "play on ", "transfer playback to "]
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            let device = String(normalized.dropFirst(prefix.count)).displayCapitalized
            return device.isEmpty ? nil : device
        }
        return nil
    }
}

private extension String {
    var displayCapitalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }.joined(separator: " ")
    }
}
