import Foundation

enum SpotifyAction: Equatable {
    case pause
    case resume
    case next
    case previous
    case shuffle(Bool)
    case repeatMode(SpotifyRepeatMode)
    case playTrack(query: TrackQuery)
    case queueTrack(query: TrackQuery)
    case playResolvedTrack(SpotifyResolvedTrack)
    case queueResolvedTrack(SpotifyResolvedTrack)
    case transferPlayback(deviceName: String)

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
        case .transferPlayback(let deviceName):
            "Changed speaker to \(deviceName)"
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
        case .transferPlayback(let deviceName):
            "Transfer playback to \(deviceName)"
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

struct SpotifyResolvedTrack: Equatable, Identifiable {
    let uri: String
    let title: String
    let artist: String

    var id: String { uri }

    var displayName: String {
        "\(title) by \(artist)"
    }
}
