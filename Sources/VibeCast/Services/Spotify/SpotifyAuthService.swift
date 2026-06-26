import CryptoKit
import Foundation

enum SpotifyAuthError: LocalizedError {
    case invalidAuthorizeURL
    case invalidCallback
    case stateMismatch
    case missingCodeVerifier
    case missingRefreshToken
    case spotifyDenied(String)
    case tokenExchangeFailed(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            "Could not build Spotify login URL."
        case .invalidCallback:
            "Spotify login callback was invalid."
        case .stateMismatch:
            "Spotify login state did not match. Please try logging in again."
        case .missingCodeVerifier:
            "Spotify login state expired. Please try logging in again."
        case .missingRefreshToken:
            "Spotify refresh token is missing. Please log in again."
        case .spotifyDenied(let message):
            "Spotify login was denied: \(message)"
        case .tokenExchangeFailed(let message):
            "Spotify token exchange failed: \(message)"
        case .keychain(let status):
            "Keychain error: \(status)"
        }
    }
}

@MainActor
final class SpotifyAuthService {
    static let shared = SpotifyAuthService()

    private let tokenStore = SpotifyTokenStore()
    private let defaults: UserDefaults
    private let verifierKey = "vibecast.spotify.pkce.verifier"
    private let stateKey = "vibecast.spotify.pkce.state"
    private var cachedToken: SpotifyToken?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentToken() throws -> SpotifyToken? {
        if let cachedToken {
            return cachedToken
        }

        let token = try tokenStore.load()
        cachedToken = token
        return token
    }

    func authorizationURL() throws -> URL {
        let verifier = Self.randomCodeVerifier()
        let state = UUID().uuidString
        defaults.set(verifier, forKey: verifierKey)
        defaults.set(state, forKey: stateKey)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.spotifyClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AppConfig.spotifyRedirectURI),
            URLQueryItem(name: "scope", value: AppConfig.spotifyScopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier))
        ]

        guard let authURL = components?.url else {
            throw SpotifyAuthError.invalidAuthorizeURL
        }

        return authURL
    }

    func handleRedirectURL(_ url: URL) async throws {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == AppConfig.spotifyCallbackScheme,
            components.host == "spotify-auth-callback"
        else {
            throw SpotifyAuthError.invalidCallback
        }

        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw SpotifyAuthError.spotifyDenied(error)
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAuthError.invalidCallback
        }

        guard
            let returnedState = items.first(where: { $0.name == "state" })?.value,
            let expectedState = defaults.string(forKey: stateKey),
            returnedState == expectedState
        else {
            throw SpotifyAuthError.stateMismatch
        }

        guard let verifier = defaults.string(forKey: verifierKey) else {
            throw SpotifyAuthError.missingCodeVerifier
        }

        let token = try await exchangeCode(code, verifier: verifier)
        try tokenStore.save(token)
        cachedToken = token
        defaults.removeObject(forKey: verifierKey)
        defaults.removeObject(forKey: stateKey)
    }

    func validAccessToken() async throws -> String {
        guard let token = try currentToken() else {
            throw SpotifyAuthError.missingRefreshToken
        }

        if !token.isExpired {
            return token.accessToken
        }

        let refreshed = try await refresh(token)
        try tokenStore.save(refreshed)
        cachedToken = refreshed
        return refreshed.accessToken
    }

    func logout() throws {
        defaults.removeObject(forKey: verifierKey)
        defaults.removeObject(forKey: stateKey)
        cachedToken = nil
        try tokenStore.clear()
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> SpotifyToken {
        let body = [
            "client_id": AppConfig.spotifyClientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppConfig.spotifyRedirectURI,
            "code_verifier": verifier
        ]

        let response: SpotifyTokenResponse = try await Self.postToken(body: body)
        return response.token()
    }

    private func refresh(_ token: SpotifyToken) async throws -> SpotifyToken {
        guard let refreshToken = token.refreshToken else {
            throw SpotifyAuthError.missingRefreshToken
        }

        let body = [
            "client_id": AppConfig.spotifyClientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]

        let response: SpotifyTokenResponse = try await Self.postToken(body: body)
        return response.token(replacingRefreshToken: refreshToken)
    }

    private static func postToken<T: Decodable>(body: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown token error"
            throw SpotifyAuthError.tokenExchangeFailed(message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func randomCodeVerifier() -> String {
        let allowed = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).compactMap { _ in allowed.randomElement() })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
