import Foundation

struct PlaybackScrub {
    let trackURI: String
    let durationMS: Int
    var positionMS: Int

    static func position(x: CGFloat, width: CGFloat, durationMS: Int) -> Int? {
        guard x.isFinite, width.isFinite, width > 0, durationMS > 0 else { return nil }
        let fraction = min(1, max(0, x / width))
        // Seeking exactly to the end can advance the queue instead of seeking.
        return Int((fraction * Double(durationMS - 1)).rounded(.down))
    }

    func action(currentURI: String?, canSeek: Bool) -> SpotifyAction? {
        guard canSeek, currentURI == trackURI, positionMS >= 0, positionMS < durationMS else { return nil }
        return .seek(positionMS: positionMS, trackURI: trackURI)
    }
}
