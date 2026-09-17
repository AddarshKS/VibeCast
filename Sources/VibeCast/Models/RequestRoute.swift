import Foundation

enum RequestRoute: Equatable {
    case directSpotify(SpotifyAction)
    case track(prompt: String)
    case findPlaylist(prompt: String)
    case makePlaylist(prompt: String)
    case conversation(prompt: String)

    var displayName: String {
        switch self {
        case .directSpotify: "Playback"
        case .track: "Find song"
        case .findPlaylist: "Find playlist"
        case .makePlaylist: "Cast Magic"
        case .conversation: "Conversation"
        }
    }
}
