import Foundation

enum PlaybackConfirmation {
    static func matches(_ action: SpotifyAction, before: SpotifyPlayback?, after: SpotifyPlayback?) -> Bool {
        guard let after else { return false }
        switch action {
        case .shuffle(let enabled): return after.shuffleState == enabled
        case .repeatMode(let mode): return after.repeatState == mode.rawValue
        case .pause: return !after.isPlaying
        case .resume: return after.isPlaying
        case .seek(let position, let uri):
            guard after.item?.uri == uri, let progress = after.progressMS else { return false }
            return abs(Double(progress) - Double(position)) <= 3000
        case .advanceQueue(let uri, let id), .rewindQueue(let uri, let id):
            return after.isPlaying && after.item?.uri == uri && before?.item?.uri != uri && after.device?.id == id
        case .playResolvedTrack(let track): return after.isPlaying && after.item?.uri == track.uri
        case .next, .previous:
            guard let uri = after.item?.uri else { return false }
            if uri != before?.item?.uri { return true }
            // Previous may restart the same song; a queue may also repeat a URI.
            return (before?.progressMS ?? 0) > 3000 && (after.progressMS ?? Int.max) < 1500
        case .transferToDevice(let device): return after.device?.id == device.id && device.id != nil
        case .transferPlayback(let name): return after.device?.name.localizedCaseInsensitiveContains(name) == true
        default: return false
        }
    }
}
