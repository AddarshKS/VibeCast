import AppKit
import Foundation

@MainActor
final class VibeCastStore: ObservableObject {
    let settings: AppSettings
    let chatGPT: ChatGPTSession
    let playerDetails: PlayerDetailsStore
    var diagnostics: DiagnosticLog { chatGPT.diagnostics }
    private let secrets: any SecretStoring
    private let auth: SpotifyAuthService
    private let spotify: any SpotifyServing
    private let planner: any PlaylistPlanning
    private let notifications: any Notifying
    private let recommendations: RecommendationStore
    private let defaults: UserDefaults
    private var accountID: String?
    private var pending: [PendingPlaylistRecommendation]
    private var startupTask: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var operationID = UUID()
    private var accountGeneration = UUID()
    private var playbackRefreshID = UUID()
    private let controlConfirmationDelay: Duration
    private var lastSubmittedPrompt: String?
    private(set) var lastInteractionAt = Date()

    @Published var prompt = ""
    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var requestState: RequestState = .idle
    @Published private(set) var latestResult: VibeCastResult?
    @Published private(set) var latestError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isPlayerControl = false
    @Published private(set) var pendingPlayerAction: SpotifyAction?
    @Published private(set) var pendingQueueIndex: Int?
    var showsRequestProgress: Bool { isBusy && !isPlayerControl }
    @Published private(set) var progress = ""
    @Published private(set) var notificationNotice: String?
    @Published private(set) var playback: SpotifyPlayback?
    private(set) var playbackUpdatedAt = Date()
    @Published private(set) var playbackRefreshFailed = false
    @Published private(set) var lastRouteName: String?
    @Published private(set) var lastSpotifyAction: String?
    @Published private(set) var lastResolvedItem: String?
    @Published private(set) var requestHistory: [RequestHistoryItem] = []
    @Published private(set) var pendingPlaylistRecommendation: PendingPlaylistRecommendation?
    @Published private(set) var unfinishedPlaylist: PlaylistDraft?

    init(settings: AppSettings? = nil, secrets: (any SecretStoring)? = nil,
         spotify: (any SpotifyServing)? = nil, planner: (any PlaylistPlanning)? = nil,
         notifications: (any Notifying)? = nil, defaults: UserDefaults = .standard,
         startAutomatically: Bool = true, chatGPT: ChatGPTSession? = nil,
         controlConfirmationDelay: Duration = .milliseconds(500)) {
        self.controlConfirmationDelay = controlConfirmationDelay
        let settings = settings ?? AppSettings(defaults: defaults)
        let secrets = secrets ?? KeychainStore()
        let auth = SpotifyAuthService(settings: settings, secrets: secrets)
        self.settings = settings
        let chatGPT = chatGPT ?? ChatGPTSession(settings: settings)
        self.chatGPT = chatGPT
        self.secrets = secrets
        self.auth = auth
        let spotify = spotify ?? SpotifyAPIClient(auth: auth)
        self.spotify = spotify
        self.playerDetails = PlayerDetailsStore(spotify: spotify)
        self.planner = planner ?? PlaylistPlanner(settings: settings, auth: auth, secrets: secrets, subscription: chatGPT)
        self.notifications = notifications ?? NotificationService()
        self.defaults = defaults
        recommendations = RecommendationStore(defaults: defaults)
        pending = recommendations.load()
        if let data = defaults.data(forKey: "unfinishedPlaylist") {
            let draft = try? JSONDecoder().decode(PlaylistDraft.self, from: data)
            if draft?.isRecoverable != true {
                defaults.removeObject(forKey: "unfinishedPlaylist")
            }
        }
        if startAutomatically {
            NotificationActionRouter.shared.register(store: self)
            startupTask = Task { await refreshAuthState() }
        }
    }

    func refreshAuthState() async {
        let generation = accountGeneration
        do {
            guard try auth.currentToken() != nil else { authState = .loggedOut; return }
            let profile = try await spotify.profile()
            try Task.checkCancellation()
            guard accountGeneration == generation else { return }
            accountID = profile.id
            authState = .loggedIn(displayName: profile.displayName)
            pending = pending.filter { $0.isActionable(accountID: profile.id) }
            recommendations.save(pending)
            pendingPlaylistRecommendation = pending.last
            if let data = defaults.data(forKey: "unfinishedPlaylist"),
               let draft = try? JSONDecoder().decode(PlaylistDraft.self, from: data),
               draft.accountID == profile.id, draft.isRecoverable {
                unfinishedPlaylist = draft
            } else { setDraft(nil) }
            await refreshPlayback()
        } catch is CancellationError { return }
        catch {
            guard accountGeneration == generation else { return }
            authState = .loggedOut
            latestError = error.localizedDescription
            diagnostics.record("Spotify", "Account restore: \(error.localizedDescription)", isError: true)
        }
    }

    func login() {
        guard !isBusy else { return }
        accountGeneration = UUID()
        authState = .authenticating
        run(prompt: "", route: .conversation(prompt: "")) {
            self.diagnostics.record("Spotify", "Starting browser sign-in")
            try await self.auth.login()
            self.diagnostics.record("Spotify", "OAuth token saved; loading account")
            await self.refreshAuthState()
            guard self.authState.isLoggedIn else {
                throw UserFacingError(self.latestError ?? "Spotify connected, but your account couldn't be loaded.")
            }
            return VibeCastResult(title: "You're connected.", source: .local)
        }
    }

    func logout() {
        accountGeneration = UUID()
        cancel()
        startupTask?.cancel()
        do {
            try auth.logout()
            authState = .loggedOut
            accountID = nil
            playback = nil
            playbackRefreshFailed = false
            playerDetails.reset()
            pending = []
            recommendations.clear()
            pendingPlaylistRecommendation = nil
            setDraft(nil)
            notifications.clear()
            requestHistory = []
            diagnostics.clear()
            clear()
        } catch { fail(error) }
    }

    func saveConnections(clientID: String, serviceAddress: String, apiKey: String, model: String, codexExecutable: String) {
        guard !isBusy, !chatGPT.isBusy else { return }
        if clientID != settings.spotifyClientID || serviceAddress != settings.serviceAddress {
            logout()
            guard !authState.isLoggedIn else { return }
        }
        do {
            if !apiKey.isEmpty { try secrets.write(Data(apiKey.utf8), account: "openai.api-key") }
            settings.spotifyClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.serviceAddress = serviceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.codexExecutable = codexExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.openAIModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            latestError = nil
        } catch { fail(error) }
    }

    func removeAPIKey() {
        do { try secrets.remove(account: "openai.api-key") }
        catch { fail(error) }
    }

    func clear() {
        guard !isBusy else { return }
        prompt = ""
        latestResult = nil
        latestError = nil
        notificationNotice = nil
        lastRouteName = nil
        lastSpotifyAction = nil
        lastResolvedItem = nil
        requestState = .idle
    }

    func cancel() {
        if isBusy { diagnostics.record("Request", "Cancelled") }
        operationID = UUID()
        work?.cancel()
        work = nil
        isBusy = false
        isPlayerControl = false
        pendingPlayerAction = nil
        pendingQueueIndex = nil
        playbackRefreshID = UUID()
        progress = ""
        requestState = .idle
        if authState == .authenticating { authState = .loggedOut }
    }

    func submitPrompt() {
        let request = VibeCastRequest(prompt: prompt)
        guard !request.prompt.isEmpty, !isBusy else { return }
        noteInteraction()
        lastRouteName = nil
        lastSpotifyAction = nil
        lastResolvedItem = nil
        guard request.prompt.count <= AppConfig.maximumPromptLength else {
            fail(UserFacingError("Keep your request under \(AppConfig.maximumPromptLength) characters."))
            return
        }
        let route = RequestRouter().route(request)
        lastRouteName = route.displayName
        if case .conversation = route {} else if !authState.isLoggedIn {
            fail(UserFacingError("Connect Spotify to get started."))
            return
        }
        lastSubmittedPrompt = prompt
        run(prompt: request.prompt, route: route) { try await self.execute(route) }
    }

    func control(_ action: SpotifyAction) {
        guard authState.isLoggedIn, !isBusy else { return }
        var before = playback
        if before?.progressMS != nil, before?.item?.durationMS != nil {
            before?.progressMS = playback?.elapsedMS(observedAt: playbackUpdatedAt, now: Date())
        }
        playbackRefreshID = UUID()
        pendingPlayerAction = action
        run(prompt: action.diagnosticName, route: .directSpotify(action), showFeedback: false) {
            try Task.checkCancellation()
            self.lastSpotifyAction = action.diagnosticName
            let result = try await self.spotify.execute(action)
            try await self.confirmPlayback(action, before: before)
            return result
        }
    }

    func playQueueItem(at index: Int, in displayedItems: [SpotifyQueueItem]) {
        guard authState.isLoggedIn, !isBusy, displayedItems.indices.contains(index), index < 20,
              displayedItems[index].playableTrack != nil else { return }
        let requested = Array(displayedItems.prefix(index + 1))
        playbackRefreshID = UUID()
        pendingQueueIndex = index
        run(prompt: "Play queued song: \(displayedItems[index].name)", route: .directSpotify(.next), showFeedback: false) {
            do {
                try Task.checkCancellation()
                guard let initial = try await self.spotify.playback(), initial.isPlaying,
                      let initialURI = initial.item?.uri, let device = initial.device,
                      let deviceID = device.id, device.isRestricted != true else {
                    throw UserFacingError("Resume Spotify on your device before choosing a queued song.")
                }
                let path = [initialURI] + requested.map(\.uri)
                guard requested.allSatisfy({ $0.playableTrack != nil }),
                      zip(path, path.dropFirst()).allSatisfy({ $0 != $1 }) else {
                    throw UserFacingError("Choose this item in Spotify. This queue includes an episode or repeated song that can't be advanced reliably here.")
                }
                var previousURI = initialURI
                for step in requested.indices {
                    if step > 0 { try await Task.sleep(for: self.controlConfirmationDelay) }
                    try Task.checkCancellation()
                    let remaining = requested.dropFirst(step).map(\.uri)
                    let currentQueue = try await self.spotify.queue()
                    guard Array(currentQueue.prefix(remaining.count).map(\.uri)) == remaining,
                          let current = try await self.spotify.playback(), current.isPlaying,
                          current.item?.uri == previousURI, current.device?.id == deviceID,
                          current.actions?.disallows?["skipping_next"] != true else {
                        throw UserFacingError("Spotify's queue or player changed. Refresh the queue and choose the song again.")
                    }
                    try Task.checkCancellation()
                    let action = SpotifyAction.advanceQueue(trackURI: requested[step].uri, deviceID: deviceID)
                    self.pendingPlayerAction = action
                    self.lastSpotifyAction = "Queue step \(step + 1) of \(requested.count)"
                    _ = try await self.spotify.execute(action)
                    try await self.confirmPlayback(action, before: current)
                    previousURI = requested[step].uri
                }
                await self.playerDetails.refreshQueue()
                return VibeCastResult(title: "Playing \(displayedItems[index].name)", source: .spotifyAPI,
                                      resolvedItem: displayedItems[index].name)
            } catch {
                if !Task.isCancelled { await self.playerDetails.refreshQueue() }
                throw error
            }
        }
    }

    private func confirmPlayback(_ action: SpotifyAction, before: SpotifyPlayback?) async throws {
        let generation = accountGeneration
        var latest: SpotifyPlayback?
        for attempt in 0..<6 {
            if attempt > 0 { try await Task.sleep(for: controlConfirmationDelay) }
            try Task.checkCancellation()
            do { latest = try await spotify.playback() }
            catch {
                try Task.checkCancellation()
                throw UserFacingError("The command was sent, but Spotify's player couldn't be checked. Check Spotify before trying again.")
            }
            try Task.checkCancellation()
            guard accountGeneration == generation else { throw CancellationError() }
            if PlaybackConfirmation.matches(action, before: before, after: latest) {
                playbackUpdatedAt = Date()
                playbackRefreshFailed = false
                playback = latest
                if case .playResolvedTrack = action { await playerDetails.refreshQueue() }
                return
            }
        }
        playbackUpdatedAt = Date()
        playback = latest
        throw UserFacingError("Spotify hasn't confirmed the player change yet. Check Spotify before trying again.")
    }

    func noteInteraction(at date: Date = Date()) { lastInteractionAt = date }

    @discardableResult
    func returnToSuggestionsIfIdle(at date: Date = Date()) -> Bool {
        guard date.timeIntervalSince(lastInteractionAt) >= 60, !isBusy,
              requestState != .idle || latestResult != nil,
              latestError == nil, notificationNotice == nil,
              pendingPlaylistRecommendation == nil, unfinishedPlaylist == nil,
              prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt == lastSubmittedPrompt else { return false }
        latestResult = nil
        requestState = .idle
        if prompt == lastSubmittedPrompt { prompt = "" }
        lastSubmittedPrompt = nil
        return true
    }

    func refreshPlayback() async {
        guard authState.isLoggedIn, !isPlayerControl else { return }
        let generation = accountGeneration
        let refreshID = UUID()
        playbackRefreshID = refreshID
        let began = Date()
        do {
            let value = try await spotify.playback()
            try Task.checkCancellation()
            guard authState.isLoggedIn, accountGeneration == generation, playbackRefreshID == refreshID else { return }
            let received = Date()
            // Bound latency compensation so a rate-limit retry cannot advance lyrics by seconds.
            playbackUpdatedAt = received.addingTimeInterval(-min(0.5, received.timeIntervalSince(began) / 2))
            playbackRefreshFailed = false
            playback = value
        } catch {
            guard !Task.isCancelled, accountGeneration == generation, playbackRefreshID == refreshID else { return }
            // Keep request errors separate, but stop claiming lyric sync with stale playback.
            playbackRefreshFailed = true
        }
    }

    func handleNotification(_ action: String, id: UUID) async {
        await startupTask?.value
        if action == NotificationService.playAction { acceptPlaylistRecommendation(id: id) }
        else if action == NotificationService.magicAction { castMagic(from: id) }
    }

    func acceptPlaylistRecommendation(id: UUID) {
        guard !isBusy else {
            notificationNotice = "Finish the current request, then choose your playlist here."
            return
        }
        guard let index = actionableIndex(id) else { expiredRecommendation(); return }
        let recommendation = pending[index]
        pending[index].status = .accepted
        persistPending()
        notifications.remove(id)
        run(prompt: recommendation.originalPrompt, route: .findPlaylist(prompt: recommendation.originalPrompt)) {
            self.lastSpotifyAction = "Play confirmed playlist: \(recommendation.playlist.name)"
            do { return try await self.spotify.execute(.playResolvedPlaylist(recommendation.playlist)) }
            catch {
                if !Task.isCancelled, let index = self.pending.firstIndex(where: { $0.id == id }) {
                    self.pending[index].status = .pending
                    self.persistPending()
                }
                throw error
            }
        }
    }

    func castMagic(from id: UUID) {
        guard !isBusy else {
            notificationNotice = "Finish the current request, then choose Cast Magic here."
            return
        }
        guard let index = actionableIndex(id) else { expiredRecommendation(); return }
        let recommendation = pending[index]
        pending[index].status = .superseded
        persistPending()
        notifications.remove(id)
        run(prompt: recommendation.originalPrompt, route: .makePlaylist(prompt: recommendation.originalPrompt)) {
            try await self.makePlaylist(recommendation.originalPrompt)
        }
    }

    func dismissRecommendation() {
        guard let item = pendingPlaylistRecommendation else { return }
        pending.removeAll { $0.id == item.id }
        notifications.remove(item.id)
        persistPending()
    }

    func finishPlaylist() {
        guard !isBusy, let draft = unfinishedPlaylist, draft.accountID == accountID else { return }
        guard draft.isRecoverable else {
            setDraft(nil)
            fail(UserFacingError("That recovery request has expired. The playlist is still in Spotify; try a new request here."))
            return
        }
        let generation = accountGeneration
        run(prompt: "Finish playlist", route: .makePlaylist(prompt: draft.playlist.name)) {
            try await self.spotify.setPlaylistTracks(draft.playlist, tracks: draft.tracks)
            guard self.accountGeneration == generation else { throw CancellationError() }
            self.setDraft(nil)
            return self.createdResult(draft.playlist, count: draft.tracks.count)
        }
    }

    func waitUntilIdle() async { await work?.value }

    private func run(prompt: String, route: RequestRoute, showFeedback: Bool = true,
                     operation: @escaping @MainActor () async throws -> VibeCastResult) {
        guard !isBusy else { return }
        noteInteraction()
        let id = UUID()
        operationID = id
        diagnostics.record("Request", "Started: \(route.displayName)")
        isBusy = true
        isPlayerControl = !showFeedback
        latestError = nil
        if showFeedback {
            latestResult = nil
            notificationNotice = nil
            requestState = .executing(route)
        } else if case .failed = requestState {
            requestState = .idle
        }
        lastRouteName = route.displayName
        lastSpotifyAction = nil
        lastResolvedItem = nil
        progress = showFeedback ? (route.displayName == "Cast Magic" ? "Finding your sound..." : "One moment...") : ""
        work = Task {
            defer {
                if self.operationID == id {
                    self.isBusy = false; self.isPlayerControl = false; self.progress = ""; self.work = nil
                    self.pendingPlayerAction = nil
                    self.pendingQueueIndex = nil
                    self.noteInteraction()
                }
            }
            do {
                let result = try await operation()
                try Task.checkCancellation()
                guard self.operationID == id else { return }
                if showFeedback {
                    self.latestResult = result
                    self.requestState = .completed(result)
                }
                self.lastResolvedItem = result.resolvedItem
                self.appendHistory(prompt, route: route, message: result.title, status: .success)
                self.diagnostics.record("Request", "Completed: \(result.title)")
                await self.refreshPlayback()
            } catch {
                guard self.operationID == id, !Task.isCancelled else { return }
                if self.authState == .authenticating { self.authState = .loggedOut }
                self.fail(error)
                self.appendHistory(prompt, route: route, message: error.localizedDescription, status: .failure)
            }
        }
    }

    private func execute(_ route: RequestRoute) async throws -> VibeCastResult {
        switch route {
        case .directSpotify(let action):
            lastSpotifyAction = action.diagnosticName
            return try await spotify.execute(action)
        case .track(let prompt):
            let phrase = MusicSearch.trackQuery(prompt)
            lastSpotifyAction = "Search track: \(phrase)"
            let candidates = try await spotify.searchTrackCandidates(query: phrase, limit: 8)
            guard let track = MusicSearch.matchTrack(title: phrase, artist: nil, candidates: candidates) else {
                throw SpotifyAPIError.missingTrack
            }
            let queue = prompt.lowercased().matches(#"^(queue|add to queue)\b"#)
            return try await spotify.execute(queue ? .queueResolvedTrack(track) : .playResolvedTrack(track))
        case .findPlaylist(let prompt):
            let query = MusicSearch.playlistQuery(prompt)
            lastSpotifyAction = "Search playlists: \(query)"
            diagnostics.record("Spotify", "Searching playlists: \(query)")
            guard !query.isEmpty else { throw UserFacingError("Give me a mood, genre, or artist to find a playlist.") }
            let candidates = try await spotify.searchPlaylistCandidates(query: query, limit: 10)
            guard let playlist = MusicSearch.matchPlaylist(query: query, candidates: candidates), let accountID else {
                throw UserFacingError("No close playlist match yet. Try a genre, artist, or a more specific mood.")
            }
            try Task.checkCancellation()
            let recommendation = PendingPlaylistRecommendation(accountID: accountID, originalPrompt: prompt,
                                                              playlist: playlist, searchPhrase: query)
            pending.append(recommendation)
            persistPending()
            lastSpotifyAction = "Awaiting playlist confirmation"
            diagnostics.record("Playlist", "Selected \(playlist.name); waiting for Sure! or Cast Magic")
            if settings.notificationsEnabled {
                do { try await notifications.recommend(recommendation) }
                catch {
                    notificationNotice = "Your playlist is ready here. The notification couldn't be shown."
                    diagnostics.record("Notification", error.localizedDescription, isError: true)
                }
            }
            return VibeCastResult(title: "A little something for you.", source: .findPlaylist,
                                  resolvedItem: playlist.name, playlist: playlist)
        case .makePlaylist(let prompt): return try await makePlaylist(prompt)
        case .conversation(let prompt):
            let tired = prompt.lowercased().matches(#"\b(tired|stressed)\b"#)
            return VibeCastResult(title: tired ? "Something gentle, perhaps?" : "What are you in the mood for?",
                                  detail: tired ? "Try a quiet evening mix or your favorite artist."
                                                : "A mood, a memory, a genre. Where should we start?",
                                  source: .conversation)
        }
    }

    private func makePlaylist(_ prompt: String) async throws -> VibeCastResult {
        let generation = accountGeneration
        if unfinishedPlaylist?.isRecoverable == false { setDraft(nil) }
        guard settings.aiConsent else {
            throw UserFacingError("Enable Cast Magic in Settings before sharing your request with the AI service.")
        }
        guard unfinishedPlaylist == nil else {
            throw UserFacingError("Your last playlist is waiting to be finished. Resume it before making another.")
        }
        guard let accountID else { throw UserFacingError("Connect Spotify to make a playlist.") }
        progress = "Curating your playlist..."
        lastSpotifyAction = "Cast Magic: generating track intents"
        let plan = try await planner.plan(for: prompt).validated()
        diagnostics.record("Cast Magic", "Plan received: \(plan.tracks.count) track intents")
        var tracks: [SpotifyResolvedTrack] = []
        var seen = Set<String>()
        for (index, intent) in plan.tracks.enumerated() {
            try Task.checkCancellation()
            progress = "Finding songs \(index + 1) of \(plan.tracks.count)"
            let candidates = try await spotify.searchTrackCandidates(query: intent.searchQuery, limit: 5)
            if let track = MusicSearch.matchTrack(title: intent.title, artist: intent.artist, candidates: candidates),
               seen.insert(track.uri).inserted { tracks.append(track) }
        }
        guard tracks.count >= max(8, Int(ceil(Double(plan.tracks.count) * 0.6))) else {
            throw UserFacingError("Only \(tracks.count) songs could be verified. Try a more specific request; no playlist was created.")
        }
        try Task.checkCancellation()
        progress = "Creating your private playlist..."
        lastSpotifyAction = "Create private playlist"
        diagnostics.record("Spotify", "Verified \(tracks.count) tracks; creating private playlist")
        let playlist = try await spotify.createPlaylist(name: plan.name, description: plan.description)
        guard accountGeneration == generation else { throw CancellationError() }
        let draft = PlaylistDraft(accountID: accountID, playlist: playlist, tracks: tracks)
        setDraft(draft)
        try Task.checkCancellation()
        progress = "Adding \(tracks.count) songs..."
        lastSpotifyAction = "Populate private playlist"
        try await spotify.setPlaylistTracks(playlist, tracks: tracks)
        guard accountGeneration == generation else { throw CancellationError() }
        setDraft(nil)
        return createdResult(playlist, count: tracks.count)
    }

    private func createdResult(_ playlist: SpotifyResolvedPlaylist, count: Int) -> VibeCastResult {
        VibeCastResult(title: playlist.name, detail: "\(count) songs. Made for you. Private on Spotify.",
                       source: .makePlaylist, resolvedItem: playlist.name, playlist: playlist)
    }

    private func setDraft(_ draft: PlaylistDraft?) {
        unfinishedPlaylist = draft
        if let draft, let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: "unfinishedPlaylist") }
        else { defaults.removeObject(forKey: "unfinishedPlaylist") }
    }

    private func actionableIndex(_ id: UUID) -> Int? {
        guard let accountID else { return nil }
        return pending.firstIndex { $0.id == id && $0.isActionable(accountID: accountID) }
    }

    private func persistPending() {
        pending = Array(pending.suffix(10))
        recommendations.save(pending)
        pendingPlaylistRecommendation = pending.last(where: { $0.isActionable(accountID: accountID ?? "") })
    }

    private func expiredRecommendation() {
        fail(UserFacingError("That recommendation has expired or belongs to another session. Try the request again."))
    }

    private func fail(_ error: Error) {
        diagnostics.record("Request", error.localizedDescription, isError: true)
        latestResult = nil
        latestError = error.localizedDescription
        requestState = .failed(error.localizedDescription)
    }

    private func appendHistory(_ prompt: String, route: RequestRoute, message: String, status: RequestHistoryItem.Status) {
        requestHistory.insert(RequestHistoryItem(prompt: prompt, routeName: route.displayName, message: message, status: status), at: 0)
        requestHistory = Array(requestHistory.prefix(8))
    }
}
