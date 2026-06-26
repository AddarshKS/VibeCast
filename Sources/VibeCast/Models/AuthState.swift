import Foundation

enum AuthState: Equatable {
    case unknown
    case authenticating
    case loggedOut
    case loggedIn(displayName: String?)

    var isLoggedIn: Bool {
        if case .loggedIn = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .unknown, .authenticating:
            true
        case .loggedOut, .loggedIn:
            false
        }
    }

    var displayText: String {
        switch self {
        case .unknown:
            "Checking Spotify..."
        case .authenticating:
            "Logging in to Spotify..."
        case .loggedOut:
            "Spotify disconnected"
        case .loggedIn(let displayName):
            displayName.map { "Spotify connected: \($0)" } ?? "Spotify connected"
        }
    }
}
