import CryptoKit
import Foundation

@MainActor
protocol SpotifyAuthorizing: AnyObject {
    func validAccessToken(forceRefresh: Bool) async throws -> String
    func currentToken() throws -> SpotifyToken?
}

@MainActor
final class SpotifyAuthService: SpotifyAuthorizing {
    private let settings: AppSettings
    private let secrets: any SecretStoring
    private let transport: any HTTPTransport
    private let loginReceiver = LoopbackLogin()
    private var cachedToken: SpotifyToken?
    private var refreshTask: Task<String, Error>?
    private var generation = UUID()
    private var account: String { "spotify.\(settings.spotifyClientID).\(settings.serviceAddress)" }

    init(settings: AppSettings, secrets: any SecretStoring, transport: any HTTPTransport = URLSessionTransport()) {
        self.settings = settings
        self.secrets = secrets
        self.transport = transport
    }

    func currentToken() throws -> SpotifyToken? {
        if let cachedToken { return cachedToken }
        guard let data = try secrets.read(account: account) else { return nil }
        let token = try JSONDecoder().decode(SpotifyToken.self, from: data)
        cachedToken = token
        return token
    }

    func login() async throws {
        guard settings.hasSpotifyConfiguration else {
            throw UserFacingError("Spotify isn't configured for this build. Open Settings to finish setup.")
        }
        let nonce = generation
        let verifier = UUID().uuidString + UUID().uuidString
        let state = UUID().uuidString
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: settings.spotifyClientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: AppConfig.spotifyRedirectURI),
            .init(name: "scope", value: AppConfig.spotifyScopes.joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "show_dialog", value: "true")
        ]
        let url = try await loginReceiver.receiveCallback(open: components.url!, state: state)
        let code = try Self.authorizationCode(url: url, expectedState: state)
        let response = try await tokenRequest([
            "grant_type": "authorization_code", "code": code,
            "code_verifier": verifier, "redirect_uri": AppConfig.spotifyRedirectURI
        ])
        try Task.checkCancellation()
        guard generation == nonce else { throw CancellationError() }
        try save(response.token())
    }

    static func authorizationCode(url: URL, expectedState: String) throws -> String {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "http", c.host == "127.0.0.1", c.port == 43821, c.path == "/callback" else {
            throw UserFacingError("That Spotify sign-in link isn't valid.")
        }
        let items = c.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw UserFacingError("Spotify sign-in expired. Please try again.")
        }
        if items.contains(where: { $0.name == "error" }) {
            throw UserFacingError("Spotify access wasn't granted. You can reconnect whenever you're ready.")
        }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty else {
            throw UserFacingError("Spotify didn't return a sign-in code. Please try again.")
        }
        return code
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let token = try currentToken() else { throw UserFacingError("Connect Spotify to continue.") }
        if !forceRefresh && !token.isExpired { return token.accessToken }
        guard let refreshToken = token.refreshToken else {
            throw UserFacingError("Your Spotify session expired. Reconnect in Settings.")
        }
        let nonce = generation
        let task = Task { @MainActor in
            let response = try await self.tokenRequest(["grant_type": "refresh_token", "refresh_token": refreshToken])
            try Task.checkCancellation()
            guard self.generation == nonce else { throw CancellationError() }
            let refreshed = response.token(replacingRefreshToken: refreshToken, replacingScope: token.scope)
            try self.save(refreshed)
            return refreshed.accessToken
        }
        refreshTask = task
        defer { if generation == nonce { refreshTask = nil } }
        return try await task.value
    }

    func serviceSession() async throws -> String {
        _ = try await validAccessToken()
        guard let session = try currentToken()?.serviceSession else {
            throw UserFacingError("Reconnect Spotify to activate Cast Magic on this service.")
        }
        return session
    }

    func logout() throws {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        loginReceiver.cancel()
        let token = cachedToken
        try secrets.remove(account: account)
        cachedToken = nil
        if let session = token?.serviceSession, let base = settings.serviceURL {
            let transport = transport
            Task {
                var request = URLRequest(url: base.appendingPathComponent("v1/logout"))
                request.httpMethod = "POST"
                request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
                _ = try? await transport.data(for: request)
            }
        }
    }

    private func save(_ token: SpotifyToken) throws {
        try secrets.write(JSONEncoder().encode(token), account: account)
        cachedToken = token
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> SpotifyTokenResponse {
        var fields = fields
        fields["client_id"] = settings.spotifyClientID
        let useGateway = !settings.serviceAddress.isEmpty
        if useGateway && settings.serviceURL == nil {
            throw UserFacingError("The VibeCast service address must be a valid HTTPS address.")
        }
        let url = useGateway ? settings.serviceURL!.appendingPathComponent("v1/token")
            : URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if useGateway {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(fields)
        } else {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            request.httpBody = Data(fields.sorted(by: { $0.key < $1.key }).map {
                "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
            }.joined(separator: "&").utf8)
        }
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 400 || response.statusCode == 401 {
                throw UserFacingError("Spotify sign-in expired or the app configuration changed. Reconnect Spotify.")
            }
            if response.statusCode == 403 {
                throw UserFacingError("This Spotify account doesn't have access to this VibeCast beta. Ask the publisher to add you as a tester.")
            }
            throw UserFacingError("Spotify sign-in couldn't finish (\(response.statusCode)). Try again shortly.")
        }
        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }
}
