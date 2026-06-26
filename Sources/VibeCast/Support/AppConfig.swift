import Foundation

enum AppConfig {
    static let appName = "VibeCast"
    static let bundleID = "com.addarsh.vibecast"
    static let spotifyClientID = "fbd46b7a08a44ffe9646089ee7bff9e1"
    static let spotifyCallbackScheme = "vibecast-milestone2"
    static let spotifyRedirectURI = "\(spotifyCallbackScheme)://spotify-auth-callback"

    static let spotifyScopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing"
    ]
}
