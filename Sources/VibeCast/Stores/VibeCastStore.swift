import AppKit
import Foundation

@MainActor
final class VibeCastStore: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var requestState: RequestState = .idle
    @Published private(set) var latestResult: VibeCastResult?
    @Published private(set) var latestError: String?
    @Published private(set) var lastRouteName: String?
    @Published private(set) var lastSpotifyAction: String?
    @Published private(set) var lastResolvedItem: String?
    @Published private(set) var requestHistory: [RequestHistoryItem] = []

    private let router = RequestRouter()
    private let spotifyClient = SpotifyAPIClient()
    private let authService = SpotifyAuthService.shared
    private let interpreterClient = CodexInterpreterClient()
    private let chatClient = CodexChatClient()
    private let fallbackClient = CodexComputerFallbackClient()
    private let notificationService = NotificationService()

    init() {
        Task {
            await refreshAuthState()
        }
    }

    func refreshAuthState() async {
        do {
            guard try authService.currentToken() != nil else {
                authState = .loggedOut
                return
            }

            let displayName = try await spotifyClient.fetchCurrentUserDisplayName()
            authState = .loggedIn(displayName: displayName)
        } catch {
            AppLogger.spotify.error("Auth refresh failed: \(error.localizedDescription)")
            authState = .loggedOut
        }
    }

    func login() {
        authState = .authenticating
        requestState = .idle
        latestError = nil
        do {
            let url = try authService.authorizationURL()
            NSWorkspace.shared.open(url)
        } catch {
            latestError = error.localizedDescription
            authState = .loggedOut
            requestState = .failed(error.localizedDescription)
        }
    }

    func handleSpotifyCallback(_ url: URL) async {
        authState = .authenticating
        latestError = nil

        do {
            try await authService.handleRedirectURL(url)
            await refreshAuthState()
            let result = VibeCastResult(title: "Spotify connected", detail: nil, source: .local)
            latestResult = result
            requestState = .completed(result)
        } catch {
            latestError = error.localizedDescription
            authState = .loggedOut
            requestState = .failed(error.localizedDescription)
        }
    }

    func logout() {
        do {
            try authService.logout()
            authState = .loggedOut
            latestResult = VibeCastResult(title: "Logged out of Spotify", detail: nil, source: .local)
        } catch {
            latestError = error.localizedDescription
            requestState = .failed(error.localizedDescription)
        }
    }

    func clear() {
        prompt = ""
        requestState = .idle
        latestResult = nil
        latestError = nil
        lastRouteName = nil
        lastSpotifyAction = nil
        lastResolvedItem = nil
    }

    func submitPrompt() {
        let request = VibeCastRequest(prompt: prompt)
        guard !request.prompt.isEmpty else { return }

        requestState = .routing
        latestError = nil

        Task {
            do {
                let route = router.route(request)
                recordDiagnostics(for: route)
                requestState = .executing(route)
                let result = try await execute(route)
                latestResult = result
                lastResolvedItem = result.resolvedItem
                requestState = .completed(result)
                appendHistory(
                    prompt: request.prompt,
                    routeName: route.displayName,
                    message: result.title,
                    status: .success
                )
                notificationService.send(result: result)
            } catch {
                latestError = error.localizedDescription
                requestState = .failed(error.localizedDescription)
                appendHistory(
                    prompt: request.prompt,
                    routeName: lastRouteName ?? "Unknown route",
                    message: error.localizedDescription,
                    status: .failure
                )
            }
        }
    }

    private func recordDiagnostics(for route: RequestRoute) {
        lastRouteName = route.displayName
        lastResolvedItem = nil

        if case .directSpotify(let action) = route {
            lastSpotifyAction = action.diagnosticName
        } else {
            lastSpotifyAction = nil
        }
    }

    private func appendHistory(
        prompt: String,
        routeName: String,
        message: String,
        status: RequestHistoryItem.Status
    ) {
        let item = RequestHistoryItem(
            prompt: prompt,
            routeName: routeName,
            message: message,
            status: status
        )
        requestHistory.insert(item, at: 0)
        requestHistory = Array(requestHistory.prefix(3))
    }

    private func execute(_ route: RequestRoute) async throws -> VibeCastResult {
        switch route {
        case .directSpotify(let action):
            return try await spotifyClient.execute(action)
        case .codexInterpreter(let prompt):
            let phrase = try interpreterClient.searchPhrase(from: prompt)
            let candidates = try await spotifyClient.searchTrackCandidates(query: phrase, limit: 8)
            let resolution = try await interpreterClient.resolve(prompt: prompt, candidates: candidates)
            lastSpotifyAction = "Interpreted: \(resolution.action.diagnosticName)"
            let result = try await spotifyClient.execute(resolution.action)
            return VibeCastResult(
                title: result.title,
                detail: interpreterDetail(prompt: prompt, resolution: resolution, spotifyDetail: result.detail),
                source: .codexInterpreter,
                resolvedItem: result.resolvedItem
            )
        case .codexChat(let prompt):
            return await chatClient.respond(to: prompt)
        case .codexComputerFallback(let prompt):
            return await fallbackClient.handle(prompt)
        }
    }

    private func interpreterDetail(
        prompt: String,
        resolution: CodexResolvedTrackAction,
        spotifyDetail: String?
    ) -> String {
        let percent = Int((resolution.confidence * 100).rounded())
        let base = "Resolved \"\(prompt)\" to \(resolution.track.displayName) via \(resolution.method) selection (\(percent)%). \(resolution.reason)"
        guard let spotifyDetail, !spotifyDetail.isEmpty else {
            return base
        }
        return "\(base) \(spotifyDetail)"
    }
}
