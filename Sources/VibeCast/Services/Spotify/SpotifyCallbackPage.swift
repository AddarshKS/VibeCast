import Foundation

enum SpotifyCallbackPage {
    enum State: String { case received, denied, expired }

    static let contentSecurityPolicy = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

    static func html(state: State) -> String {
        guard let template = AppResources.bundle.url(forResource: "SpotifyCallback", withExtension: "html"),
              let source = try? String(contentsOf: template, encoding: .utf8) else {
            return "<!doctype html><html lang=\"en\"><title>VibeCast</title><p>Return to VibeCast to check your Spotify connection.</p></html>"
        }
        let copy: (status: String, title: String, message: String, next: String)
        switch state {
        case .received:
            copy = ("SIGN-IN RECEIVED", "Back to the music.",
                    "VibeCast is finishing your Spotify connection. You can close this tab.",
                    "Open VibeCast from your menu bar to see your connection status.")
        case .denied:
            copy = ("ACCESS NOT GRANTED", "No rush. Your music can wait.",
                    "Spotify access wasn't granted. Your account has not been connected.",
                    "Return to VibeCast and choose Connect Spotify when you're ready.")
        case .expired:
            copy = ("LINK EXPIRED", "Let's try that again.",
                    "This sign-in link is no longer active. Nothing was changed.",
                    "Return to VibeCast and start a fresh Spotify connection.")
        }
        let values = ["STATE": state.rawValue, "STATUS": copy.status, "TITLE": copy.title,
                      "MESSAGE": copy.message, "NEXT": copy.next, "LOGO": logo]
        return values.reduce(source) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }

    private static let logo: String = {
        guard let url = AppResources.bundle.url(forResource: ResourceImage.brandLogoName, withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return "" }
        return data.base64EncodedString()
    }()
}
