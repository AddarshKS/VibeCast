import Foundation

enum SpotifyPlaybackRefusal: String {
    case restricted = "RESTRICTION_VIOLATED"
    case premiumRequired = "PREMIUM_REQUIRED"
    case insufficientScope = "INSUFFICIENT_SCOPE"
    case noActiveDevice = "NO_ACTIVE_DEVICE"
    case unspecified = "UNSPECIFIED"

    static func decode(_ data: Data) -> Self {
        struct Envelope: Decodable {
            struct Failure: Decodable { let reason: String?; let message: String? }
            let error: Failure
        }
        guard let failure = try? JSONDecoder().decode(Envelope.self, from: data).error else { return .unspecified }
        if let reason = failure.reason, let known = Self(rawValue: reason.uppercased()) { return known }
        // Spotify also sends reason=UNKNOWN with the restriction in its message.
        let message = failure.message?.lowercased() ?? ""
        if message.contains("restriction violated") { return .restricted }
        if message.contains("insufficient client scope") { return .insufficientScope }
        return .unspecified
    }

    func message(path: String) -> String {
        let action: String
        switch path {
        case "/me/player/previous": action = "Previous"
        case "/me/player/next": action = "Next"
        case "/me/player/shuffle": action = "Shuffle"
        case "/me/player/repeat": action = "Repeat"
        case "/me/player/seek": action = "Seeking"
        default: action = "This playback action"
        }
        switch self {
        case .restricted:
            return "Spotify isn't allowing \(action) in the current playback context. Try the same control in Spotify."
        case .premiumRequired:
            return "Spotify reported that this device's account requires Premium. Check which account is active in Spotify."
        case .insufficientScope:
            return "Spotify reported missing playback permission. Reconnect Spotify in Settings."
        case .noActiveDevice:
            return "Spotify has no active device. Open Spotify on your device and start playback."
        case .unspecified:
            return "Spotify declined \(action) (403) without a specific reason. Try the same control in Spotify; this alone doesn't mean your Premium account is missing."
        }
    }
}
