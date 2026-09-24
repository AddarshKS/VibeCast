import Foundation

enum PlaybackConfirmation {
    static func matches(_ action: SpotifyAction, before: SpotifyPlayback?, after: SpotifyPlayback?,
                        elapsedSinceCommand: TimeInterval = 0, baselineAge: TimeInterval = 0,
                        elapsedBeforeRead: TimeInterval? = nil, expectedDeviceID: String? = nil) -> Bool {
        guard let after else { return false }
        if let expectedDeviceID, after.device?.id != expectedDeviceID { return false }
        let readEnd = max(0, elapsedSinceCommand) * 1000
        let readStart = min(readEnd, max(0, elapsedBeforeRead ?? elapsedSinceCommand) * 1000)
        // A player response may describe any instant during the read, not its receipt time.
        let continuing: ClosedRange<Double>? = before?.progressMS.map { position in
            let age = max(0, baselineAge) * 1000
            let lower = Double(position) + (before?.isPlaying == true ? age + readStart : 0)
            let upper = Double(position) + (before?.isPlaying == true ? age + readEnd : 0)
            return (lower - 500)...(upper + 500)
        }
        switch action {
        case .transferToDevice, .transferPlayback: break
        default:
            if expectedDeviceID == nil, let deviceID = before?.device?.id, after.device?.id != deviceID { return false }
        }
        switch action {
        case .shuffle(let enabled): return after.shuffleState == enabled
        case .repeatMode(let mode): return after.repeatState == mode.rawValue
        case .pause: return !after.isPlaying
        case .resume: return after.isPlaying
        case .seek(let position, let uri):
            guard after.item?.uri == uri, let progress = after.progressMS else { return false }
            if before?.item?.uri == uri, before?.progressMS == progress, abs(Double(progress) - Double(position)) > 250 {
                return false
            }
            if before?.item?.uri == uri, let continuing, continuing.contains(Double(progress)),
               abs(Double(before?.progressMS ?? 0) - Double(position)) > 250 { return false }
            let elapsed = after.isPlaying ? readEnd : 0
            return Double(progress) >= Double(position) - 500 && Double(progress) <= Double(position) + elapsed + 1500
        case .advanceQueue(let uri, let id), .rewindQueue(let uri, let id):
            return after.isPlaying && after.item?.uri == uri && before?.item?.uri != uri && after.device?.id == id
        case .playResolvedTrack(let track): return after.isPlaying && after.item?.uri == track.uri
        case .playResolvedPlaylist(let playlist):
            return after.isPlaying && after.context?.type == "playlist" && after.context?.uri == playlist.uri
        case .next, .previous:
            guard let uri = after.item?.uri else { return false }
            if uri != before?.item?.uri { return true }
            // Accept early or delayed restarts only outside the unmodified timeline.
            guard let before, let oldPosition = before.progressMS, let position = after.progressMS,
                  oldPosition != position, let continuing else { return false }
            let restartWindow = (after.isPlaying ? readEnd : 0) + 1500
            return position >= 0 && Double(position) <= restartWindow && Double(position) < continuing.lowerBound
        case .transferToDevice(let device): return after.device?.id == device.id && device.id != nil
        case .transferPlayback(let name):
            return after.isPlaying && (expectedDeviceID != nil || after.device?.name.localizedCaseInsensitiveContains(name) == true)
        default: return false
        }
    }
}

// These outcomes must not re-arm a consumed recommendation: Spotify may already
// have applied the command. Confirmation retries only read the player.
enum PlaybackConfirmationFailure: LocalizedError {
    case uncertainCommand, unavailable, notObserved

    var errorDescription: String? {
        switch self {
        case .uncertainCommand:
            "Spotify may have received the command, but its outcome is uncertain. Check Spotify before trying again."
        case .unavailable:
            "The command was sent, but Spotify's player couldn't be checked. Check Spotify before trying again."
        case .notObserved:
            "Spotify hasn't confirmed the player change yet. Check Spotify before trying again."
        }
    }
}
