import Foundation

enum RequestRoute: Equatable {
    case directSpotify(SpotifyAction)
    case codexInterpreter(prompt: String)
    case codexChat(prompt: String)
    case codexComputerFallback(prompt: String)

    var displayName: String {
        switch self {
        case .directSpotify:
            "Spotify API"
        case .codexInterpreter:
            "Codex interpreter"
        case .codexChat:
            "VibeCast chat"
        case .codexComputerFallback:
            "Codex computer fallback"
        }
    }
}
