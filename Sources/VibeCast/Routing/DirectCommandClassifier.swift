import Foundation

struct DirectCommandClassifier {
    func action(for prompt: String) -> SpotifyAction? {
        let normalized = prompt.normalizedCommand

        switch normalized {
        case "pause", "pause playback", "stop", "stop playback", "hold up":
            return .pause
        case "resume", "play", "continue", "continue playback", "start playback", "unpause":
            return .resume
        case "skip", "next", "next song", "skip song", "skip this", "skip this song":
            return .next
        case "previous", "back", "last song", "previous song", "go back", "go back a song":
            return .previous
        case "shuffle on", "turn shuffle on", "enable shuffle":
            return .shuffle(true)
        case "shuffle off", "turn shuffle off", "disable shuffle":
            return .shuffle(false)
        case "repeat off", "turn repeat off", "disable repeat":
            return .repeatMode(.off)
        case "repeat on", "turn repeat on", "enable repeat":
            return .repeatMode(.context)
        case "repeat current song", "repeat the current song", "repeat track", "loop this song", "loop current song":
            return .repeatMode(.track)
        default:
            break
        }

        if let query = parseTrackCommand(normalized, verbs: ["play", "start", "put on"]) {
            return .playTrack(query: query)
        }

        if let query = parseTrackCommand(normalized, verbs: ["queue", "add to queue"]) {
            return .queueTrack(query: query)
        }

        if let deviceName = parseDeviceCommand(normalized) {
            return .transferPlayback(deviceName: deviceName)
        }

        return nil
    }

    private func parseTrackCommand(_ normalized: String, verbs: [String]) -> TrackQuery? {
        guard let verb = verbs.first(where: { normalized.hasPrefix("\($0) ") }) else { return nil }
        let prefix = "\(verb) "
        var remainder = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }

        if remainder.hasPrefix("song ") {
            remainder = String(remainder.dropFirst("song ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = remainder.range(of: " by ") {
            let title = String(remainder[..<range.lowerBound]).trimmedTitle
            let artist = String(remainder[range.upperBound...]).trimmedTitle
            guard !Self.isGenericArtistPlaylistRequest(title) else { return nil }
            guard !title.isEmpty, !artist.isEmpty else { return nil }
            return TrackQuery(title: title, artist: artist)
        }

        return nil
    }

    private static func isGenericArtistPlaylistRequest(_ title: String) -> Bool {
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.range(of: #"^(some |me some |me |a few )?(song|songs|music|tracks|playlist)$"#, options: .regularExpression) != nil
    }

    private func parseDeviceCommand(_ normalized: String) -> String? {
        let prefixes = [
            "change speaker to ",
            "switch speaker to ",
            "change output to ",
            "switch output to ",
            "play on ",
            "transfer playback to "
        ]

        for prefix in prefixes where normalized.hasPrefix(prefix) {
            let device = String(normalized.dropFirst(prefix.count)).trimmedTitle
            return device.isEmpty ? nil : device
        }

        return nil
    }
}

private extension String {
    var normalizedCommand: String {
        lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var trimmedTitle: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                guard let first = lower.first else { return "" }
                return first.uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
