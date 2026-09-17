import Foundation

enum SpotifyAction: Equatable {
    case pause
    case resume
    case next
    case previous
    case seek(positionMS: Int, trackURI: String)
    case advanceQueue(trackURI: String, deviceID: String)
    case rewindQueue(trackURI: String, deviceID: String)
    case shuffle(Bool)
    case repeatMode(SpotifyRepeatMode)
    case playTrack(query: TrackQuery)
    case queueTrack(query: TrackQuery)
    case playResolvedTrack(SpotifyResolvedTrack)
    case queueResolvedTrack(SpotifyResolvedTrack)
    case playResolvedPlaylist(SpotifyResolvedPlaylist)
    case transferPlayback(deviceName: String)
    case transferToDevice(SpotifyDevice)

    var notificationTitle: String {
        switch self {
        case .pause:
            "Paused playback"
        case .resume:
            "Resumed playback"
        case .next:
            "Skipped to next song"
        case .previous:
            "Went back to previous song"
        case .seek:
            "Moved to lyric"
        case .advanceQueue:
            "Moved forward in queue"
        case .rewindQueue:
            "Moved back in queue"
        case .shuffle(let enabled):
            enabled ? "Shuffle on" : "Shuffle off"
        case .repeatMode(let mode):
            "Repeat \(mode.displayName)"
        case .playTrack(let query):
            "Playing \(query.displayName)"
        case .queueTrack(let query):
            "Queued \(query.displayName)"
        case .playResolvedTrack(let track):
            "Playing \(track.displayName)"
        case .queueResolvedTrack(let track):
            "Queued \(track.displayName)"
        case .playResolvedPlaylist(let playlist):
            "Playing \(playlist.displayName)"
        case .transferPlayback(let deviceName):
            "Changed speaker to \(deviceName)"
        case .transferToDevice(let device):
            "Changed speaker to \(device.name)"
        }
    }

    var diagnosticName: String {
        switch self {
        case .pause:
            "Pause playback"
        case .resume:
            "Resume playback"
        case .next:
            "Skip to next song"
        case .previous:
            "Return to previous song"
        case .seek(let position, _):
            "Seek to \(position) ms"
        case .advanceQueue:
            "Advance existing Spotify queue"
        case .rewindQueue:
            "Rewind existing Spotify queue"
        case .shuffle(let enabled):
            enabled ? "Enable shuffle" : "Disable shuffle"
        case .repeatMode(let mode):
            "Set repeat \(mode.displayName)"
        case .playTrack(let query):
            "Play \(query.displayName)"
        case .queueTrack(let query):
            "Queue \(query.displayName)"
        case .playResolvedTrack(let track):
            "Play \(track.displayName)"
        case .queueResolvedTrack(let track):
            "Queue \(track.displayName)"
        case .playResolvedPlaylist(let playlist):
            "Play playlist \(playlist.displayName)"
        case .transferPlayback(let deviceName):
            "Transfer playback to \(deviceName)"
        case .transferToDevice(let device):
            "Transfer playback to \(device.name)"
        }
    }
}

enum SpotifyRepeatMode: String, Equatable {
    case off
    case context
    case track

    var displayName: String {
        switch self {
        case .off: "off"
        case .context: "on"
        case .track: "current song"
        }
    }
}

struct TrackQuery: Equatable {
    let title: String
    let artist: String?

    var displayName: String {
        artist.map { "\(title) by \($0)" } ?? title
    }
}

struct SpotifyResolvedTrack: Codable, Equatable, Identifiable, Sendable {
    let uri: String
    let title: String
    let artist: String
    var artworkURL: URL? = nil

    var id: String { uri }

    var displayName: String {
        "\(title) by \(artist)"
    }
}

struct SpotifyResolvedPlaylist: Codable, Equatable, Identifiable, Sendable {
    let uri: String
    let name: String
    let ownerName: String?
    let description: String?
    var artworkURL: URL? = nil

    var spotifyURL: URL? {
        guard uri.hasPrefix("spotify:playlist:") else { return nil }
        let id = String(uri.dropFirst("spotify:playlist:".count))
        guard id.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://open.spotify.com/playlist/\(id)")
    }

    var id: String { uri }

    var displayName: String {
        guard let ownerName, !ownerName.isEmpty else { return name }
        return "\(name) by \(ownerName)"
    }
}
