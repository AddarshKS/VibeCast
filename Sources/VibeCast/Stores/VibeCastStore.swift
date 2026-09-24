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
    private let playlistRecovery: PlaylistRecoveryStore
    private var accountID: String?
    private var pending: [PendingPlaylistRecommendation]
    private var startupTask: Task<Void, Never>?
    private var subscriptionRestoreTask: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var operationID = UUID()
    private var accountGeneration = UUID()
    private var playbackRefreshID = UUID()
    // Request feedback remains visible while this suppresses competing player polls.
    private var isRequestPlayback = false
    private let controlConfirmationDelay: Duration
    private let accountRetryDelay: TimeInterval
    private var accountRestoreID: UUID?
    private var accountRetry: (after: Date, message: String)?
    private var lastSubmittedPrompt: String?
    private var activeRequest: (prompt: String, route: RequestRoute)?
    private var conversationContext: ConversationGuide.Context?
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
    @Published private(set) var pendingHistoryIndex: Int?
    var showsRequestProgress: Bool { isBusy && !isPlayerControl }
    @Published private(set) var progress = ""
    @Published private(set) var notificationNotice: String?
    @Published private(set) var playback: SpotifyPlayback? {
        didSet { playerDetails.observePlayback(playback) }
    }
    private(set) var playbackUpdatedAt = Date()
    @Published private(set) var playbackRefreshFailed = false
    @Published private(set) var lastRouteName: String?
    @Published private(set) var lastSpotifyAction: String?
    { didSet { if isBusy, let lastSpotifyAction { lastRequestStage = lastSpotifyAction } } }
    @Published private(set) var lastResolvedItem: String?
    @Published private(set) var lastRequestPrompt: String?
    @Published private(set) var lastRequestStage: String?
    @Published private(set) var lastRequestOutcome: String?
    @Published private(set) var requestHistory: [RequestHistoryItem] = []
    @Published private(set) var pendingPlaylistRecommendation: PendingPlaylistRecommendation?
    @Published private(set) var unfinishedPlaylist: PlaylistDraft?
    @Published private(set) var pendingPlaylistCreation: PlaylistCreationAttempt?
    var playlistRecoveryID: String? {
        if let attempt = pendingPlaylistCreation { return attempt.id.uuidString }
        if let draft = unfinishedPlaylist { return "\(draft.playlist.uri):\(draft.createdAt.timeIntervalSince1970)" }
        return nil
    }

    init(settings: AppSettings? = nil, secrets: (any SecretStoring)? = nil,
         spotify: (any SpotifyServing)? = nil, planner: (any PlaylistPlanning)? = nil,
         notifications: (any Notifying)? = nil, defaults: UserDefaults = .standard,
         startAutomatically: Bool = true, chatGPT: ChatGPTSession? = nil,
         controlConfirmationDelay: Duration = .milliseconds(500), lyrics: any LyricsServing = LyricsClient(),
         accountRetryDelay: TimeInterval = 30) {
        self.controlConfirmationDelay = controlConfirmationDelay
        self.accountRetryDelay = accountRetryDelay
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
        self.playerDetails = PlayerDetailsStore(spotify: spotify, lyrics: lyrics)
        self.planner = planner ?? PlaylistPlanner(settings: settings, auth: auth, secrets: secrets, subscription: chatGPT)
        self.notifications = notifications ?? NotificationService()
        self.playlistRecovery = PlaylistRecoveryStore(defaults: defaults)
        recommendations = RecommendationStore(defaults: defaults)
        pending = recommendations.load()
        if startAutomatically {
            NotificationActionRouter.shared.register(store: self)
            startupTask = Task { await refreshAuthState() }
            restoreSubscriptionIfNeeded()
        }
    }

    private func restoreSubscriptionIfNeeded() {
        guard settings.aiProvider == .chatGPT else { return }
        subscriptionRestoreTask = Task { [chatGPT] in await chatGPT.refresh() }
    }

    func refreshAuthState() async {
        guard accountRestoreID == nil else { return }
        let restoreID = UUID()
        accountRestoreID = restoreID
        defer { if accountRestoreID == restoreID { accountRestoreID = nil } }
        let generation = accountGeneration
        do {
            guard try auth.currentToken() != nil else { accountRetry = nil; authState = .loggedOut; return }
            let profile = try await spotify.profile()
            try Task.checkCancellation()
            guard accountGeneration == generation else { return }
            accountID = profile.id
            authState = .loggedIn(displayName: profile.displayName)
            if latestError == accountRetry?.message { latestError = nil }
            accountRetry = nil
            pending = pending.filter { $0.isActionable(accountID: profile.id) }
            recommendations.save(pending)
            pendingPlaylistRecommendation = pending.last
            do { try restorePlaylistRecovery(accountID: profile.id) }
            catch { fail(error) }
            await refreshPlayback()
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled,
                  accountGeneration == generation else { return }
            authState = .loggedOut
            let presentation = RequestErrorPresentation(error)
            latestError = presentation.message
            var retryDelay = accountRetryDelay
            if let apiError = error as? SpotifyAPIError, case .rateLimited(let seconds) = apiError {
                retryDelay = max(retryDelay, TimeInterval(seconds ?? 0))
            }
            accountRetry = Self.isTransientAccountFailure(error)
                ? (Date().addingTimeInterval(retryDelay), presentation.message) : nil
            diagnostics.record("Spotify", "Account restore: \(presentation.diagnostic)", isError: true)
        }
    }

    private static func isTransientAccountFailure(_ error: any Error) -> Bool {
        if let error = error as? URLError { return error.code != .cancelled }
        guard let error = error as? SpotifyAPIError else { return false }
        switch error {
        case .rateLimited: return true
        case .requestFailed(let status, _): return status >= 500
        default: return false
        }
    }

    func login() {
        guard !isBusy else { return }
        accountGeneration = UUID()
        startupTask?.cancel()
        accountRestoreID = nil
        accountRetry = nil
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
        accountRestoreID = nil
        accountRetry = nil
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
            // Recovery evidence belongs to the Spotify account. Hide it on sign-out,
            // but retain it for a permission reconnect or return to the same account.
            unfinishedPlaylist = nil
            pendingPlaylistCreation = nil
            notifications.clear()
            requestHistory = []
            diagnostics.clear()
            clear()
            prompt = ""
            lastRequestPrompt = nil
            lastRequestStage = nil
            lastRequestOutcome = nil
        } catch { fail(error) }
    }

    @discardableResult
    func saveSettings(_ draft: SettingsDraft, apiKey: String) -> Bool {
        guard !isBusy, !chatGPT.isBusy, draft.isValid else { return false }
        let value = draft.normalized
        if value.clientID != settings.spotifyClientID || value.serviceAddress != settings.serviceAddress {
            logout()
            guard latestError == nil, !authState.isLoggedIn else { return false }
        }
        do {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { try secrets.write(Data(key.utf8), account: "openai.api-key") }
            settings.spotifyClientID = value.clientID
            settings.serviceAddress = value.serviceAddress
            let providerChanged = settings.aiProvider != value.provider || settings.codexExecutable != value.codexExecutable
            settings.codexExecutable = value.codexExecutable
            settings.openAIModel = value.model
            settings.aiProvider = value.provider
            settings.subscriptionModel = value.subscriptionModel
            settings.aiConsent = value.aiConsent
            settings.notificationsEnabled = value.notificationsEnabled
            settings.lyricsEnabled = value.lyricsEnabled
            if providerChanged { restoreSubscriptionIfNeeded() }
            latestError = nil
            return true
        } catch { fail(error); return false }
    }

    func removeAPIKey() {
        do { try secrets.remove(account: "openai.api-key") }
        catch { fail(error) }
    }

    func clear() {
        guard !isBusy else { return }
        // A newer composer draft is unrelated to the feedback being dismissed.
        if prompt == lastSubmittedPrompt { prompt = "" }
        lastSubmittedPrompt = nil
        conversationContext = nil
        latestResult = nil
        latestError = nil
        notificationNotice = nil
        requestState = .idle
        noteInteraction()
    }

    func cancel() {
        if isBusy {
            if let activeRequest {
                appendHistory(activeRequest.prompt, route: activeRequest.route,
                              message: "Cancelled", status: .cancelled)
            }
            diagnostics.record("Request", "Cancelled at \(lastRequestStage ?? "Starting request")")
            lastRequestOutcome = "Cancelled"
        }
        activeRequest = nil
        operationID = UUID()
        work?.cancel()
        work = nil
        isBusy = false
        isPlayerControl = false
        isRequestPlayback = false
        pendingPlayerAction = nil
        pendingQueueIndex = nil
        pendingHistoryIndex = nil
        playbackRefreshID = UUID()
        progress = ""
        requestState = .idle
        conversationContext = nil
        noteInteraction()
        if authState == .authenticating { authState = .loggedOut }
    }

    func submitPrompt() {
        let request = VibeCastRequest(prompt: prompt)
        guard !request.prompt.isEmpty, !isBusy else { return }
        noteInteraction()
        lastRouteName = nil
        lastSpotifyAction = nil
        lastResolvedItem = nil
        lastRequestPrompt = request.prompt
        lastRequestStage = "Understanding request"
        lastSubmittedPrompt = prompt
        guard request.prompt.count <= AppConfig.maximumPromptLength else {
            fail(UserFacingError("Keep your request under \(AppConfig.maximumPromptLength) characters."))
            appendHistory(request.prompt, route: .conversation(prompt: request.prompt), message: latestError ?? "Request too long", status: .failure)
            return
        }
        let route = ConversationGuide.followUpRoute(for: request.prompt, context: conversationContext)
            ?? RequestRouter().route(request)
        lastRouteName = route.displayName
        if case .conversation = route {} else if !authState.isLoggedIn {
            fail(UserFacingError("Connect Spotify to get started."))
            appendHistory(request.prompt, route: route, message: latestError ?? "Connect Spotify", status: .failure)
            return
        }
        if case .conversation = route {} else { conversationContext = nil }
        run(prompt: request.prompt, route: route) { try await self.execute(route) }
    }

    func control(_ action: SpotifyAction) {
        guard authState.isLoggedIn, !isBusy else { return }
        let before = playback
        let baselineAge = max(0, Date().timeIntervalSince(playbackUpdatedAt))
        playbackRefreshID = UUID()
        pendingPlayerAction = action
        run(prompt: action.diagnosticName, route: .directSpotify(action), showFeedback: false) {
            try Task.checkCancellation()
            self.lastSpotifyAction = action.diagnosticName
            self.diagnostics.record("Player", "\(action.diagnosticName); shuffle=\(before?.shuffleState.description ?? "unknown"); previousRestricted=\(before?.actions?.disallows?["skipping_prev"]?.description ?? "unknown")")
            let commandStartedAt = ContinuousClock.now
            let result = try await self.spotify.execute(action, deviceID: before?.device?.id)
            try await self.confirmPlayback(action, before: before, commandStartedAt: commandStartedAt, baselineAge: baselineAge)
            return result
        }
    }

    func playQueueItem(at index: Int, in displayedItems: [SpotifyQueueItem]) {
        playListItem(at: index, in: displayedItems, list: .upcoming)
    }

    func playListItem(at index: Int, in displayedItems: [SpotifyQueueItem], list: PlayerList) {
        guard authState.isLoggedIn, !isBusy, displayedItems.indices.contains(index), index < 20,
              displayedItems[index].playableTrack != nil else { return }
        let requested = list == .upcoming ? Array(displayedItems.prefix(index + 1)) : Array(displayedItems[index...].reversed())
        let displayedCurrentURI = playback?.item?.uri
        if list == .history {
            guard displayedItems.map(\.uri) == playerDetails.recentlyPlayed.map(\.uri) else { return }
        }
        playbackRefreshID = UUID()
        if list == .upcoming { pendingQueueIndex = index } else { pendingHistoryIndex = index }
        run(prompt: "Play listed song: \(displayedItems[index].name)", route: .directSpotify(list == .upcoming ? .next : .previous), showFeedback: false) {
            do {
                try Task.checkCancellation()
                guard let initial = try await self.spotify.playback(), initial.isPlaying,
                      let initialURI = initial.item?.uri, let device = initial.device,
                      let deviceID = device.id, device.isRestricted != true else {
                    throw UserFacingError("Resume Spotify on your device before choosing a queued song.")
                }
                guard list == .upcoming || initialURI == displayedCurrentURI else {
                    throw UserFacingError("Spotify's song changed. Refresh the history and choose the song again.")
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
                    if list == .upcoming {
                        let currentQueue = try await self.spotify.queue()
                        guard Array(currentQueue.prefix(remaining.count).map(\.uri)) == remaining else {
                            throw UserFacingError("Spotify's queue or player changed. Refresh the queue and choose the song again.")
                        }
                    }
                    guard let current = try await self.spotify.playback(), current.isPlaying,
                          current.item?.uri == previousURI, current.device?.id == deviceID,
                          current.actions?.disallows?[list == .upcoming ? "skipping_next" : "skipping_prev"] != true else {
                        throw UserFacingError("Spotify's queue or player changed. Refresh the queue and choose the song again.")
                    }
                    try Task.checkCancellation()
                    let action: SpotifyAction = list == .upcoming
                        ? .advanceQueue(trackURI: requested[step].uri, deviceID: deviceID)
                        : .rewindQueue(trackURI: requested[step].uri, deviceID: deviceID)
                    self.pendingPlayerAction = action
                    self.lastSpotifyAction = "Queue step \(step + 1) of \(requested.count)"
                    let commandStartedAt = ContinuousClock.now
                    _ = try await self.spotify.execute(action)
                    try await self.confirmPlayback(action, before: current, commandStartedAt: commandStartedAt)
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

    private func confirmPlayback(_ action: SpotifyAction, before: SpotifyPlayback?,
                                 commandStartedAt: ContinuousClock.Instant, baselineAge: TimeInterval = 0,
                                 expectedDeviceID: String? = nil) async throws {
        let generation = accountGeneration
        var latest: SpotifyPlayback?
        for attempt in 0..<6 {
            if attempt > 0 { try await Task.sleep(for: controlConfirmationDelay) }
            try Task.checkCancellation()
            let readStartedAt = ContinuousClock.now
            do { latest = try await spotify.playback() }
            catch {
                try Task.checkCancellation()
                if isRequestPlayback {
                    diagnostics.record("Playback", "Confirmation read failed: \(Self.playbackErrorSummary(error))", isError: true)
                    playbackRefreshFailed = true
                }
                throw PlaybackConfirmationFailure.unavailable
            }
            try Task.checkCancellation()
            guard accountGeneration == generation else { throw CancellationError() }
            let elapsed = commandStartedAt.duration(to: .now).components
            let beforeRead = commandStartedAt.duration(to: readStartedAt).components
            if PlaybackConfirmation.matches(action, before: before, after: latest,
                                            elapsedSinceCommand: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                                            baselineAge: baselineAge,
                                            elapsedBeforeRead: Double(beforeRead.seconds) + Double(beforeRead.attoseconds) / 1e18,
                                            expectedDeviceID: expectedDeviceID) {
                playbackUpdatedAt = Date()
                playbackRefreshFailed = false
                playback = latest
                if case .playResolvedTrack = action { await playerDetails.refreshQueue() }
                return
            }
        }
        playbackUpdatedAt = Date()
        playback = latest
        if isRequestPlayback { diagnostics.record("Playback", "Not confirmed after 6 player checks", isError: true) }
        throw PlaybackConfirmationFailure.notObserved
    }

    func noteInteraction(at date: Date = Date()) { lastInteractionAt = date }

    @discardableResult
    func returnToSuggestionsIfIdle(at date: Date = Date()) -> Bool {
        guard date.timeIntervalSince(lastInteractionAt) >= 60, !isBusy,
              requestState != .idle || latestResult != nil,
              latestError == nil, notificationNotice == nil,
              pendingPlaylistRecommendation == nil, unfinishedPlaylist == nil, pendingPlaylistCreation == nil,
              prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt == lastSubmittedPrompt else { return false }
        restoreSuggestions()
        return true
    }

    private func restoreSuggestions() {
        latestResult = nil
        requestState = .idle
        if prompt == lastSubmittedPrompt { prompt = "" }
        lastSubmittedPrompt = nil
        conversationContext = nil
    }

    func refreshPlayback() async {
        if !authState.isLoggedIn, !isBusy, let retry = accountRetry, Date() >= retry.after {
            await refreshAuthState()
            return
        }
        guard authState.isLoggedIn, !isPlayerControl, !isRequestPlayback else { return }
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
            do { return try await self.executeRequestAction(.playResolvedPlaylist(recommendation.playlist)) }
            catch {
                if !Task.isCancelled, !(error is PlaybackConfirmationFailure),
                   let index = self.pending.firstIndex(where: { $0.id == id }) {
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
        run(prompt: recommendation.originalPrompt, route: .makePlaylist(prompt: recommendation.originalPrompt)) {
            try await self.makePlaylist(recommendation.originalPrompt, recommendationID: id)
        }
    }

    func dismissRecommendation() {
        guard let item = pendingPlaylistRecommendation else { return }
        pending.removeAll { $0.id == item.id }
        notifications.remove(item.id)
        persistPending()
        // Dismissing an old card must not erase a newer reply or interrupt work.
        if !isBusy, latestError == nil, latestResult?.source == .findPlaylist,
           latestResult?.playlist?.uri == item.playlist.uri {
            notificationNotice = nil
            restoreSuggestions()
        }
    }

    func finishPlaylist() {
        guard !isBusy, let draft = unfinishedPlaylist, draft.accountID == accountID else { return }
        let generation = accountGeneration
        run(prompt: "Finish playlist", route: .makePlaylist(prompt: draft.playlist.name)) {
            try await self.populatePlaylist(draft, generation: generation)
        }
    }

    func waitUntilIdle() async { await work?.value }

    private func run(prompt: String, route: RequestRoute, showFeedback: Bool = true,
                     operation: @escaping @MainActor () async throws -> VibeCastResult) {
        guard !isBusy else { return }
        noteInteraction()
        let id = UUID()
        operationID = id
        activeRequest = (prompt, route)
        lastRequestPrompt = prompt
        lastRequestStage = "Starting request"
        lastRequestOutcome = "Running"
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
                    self.isRequestPlayback = false
                    self.pendingPlayerAction = nil
                    self.pendingQueueIndex = nil
                    self.pendingHistoryIndex = nil
                    self.activeRequest = nil
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
                self.lastRequestOutcome = "Completed"
                self.appendHistory(prompt, route: route, message: result.title, status: .success)
                self.diagnostics.record("Request", "Completed: \(result.title)")
                await self.refreshPlayback()
            } catch {
                guard self.operationID == id, !Task.isCancelled else { return }
                if self.authState == .authenticating { self.authState = .loggedOut }
                self.fail(error)
                self.appendHistory(prompt, route: route, message: self.latestError ?? "Request failed", status: .failure)
            }
        }
    }

    private func execute(_ route: RequestRoute) async throws -> VibeCastResult {
        switch route {
        case .directSpotify(let action):
            return try await executeRequestAction(action)
        case .track(let prompt):
            let phrase = MusicSearch.trackQuery(prompt)
            let queue = MusicSearch.isQueueRequest(prompt)
            lastSpotifyAction = "Search track: \(phrase)"
            let candidates = try await spotify.searchTrackCandidates(query: phrase, limit: 8)
            try Task.checkCancellation()
            guard let track = MusicSearch.matchTrack(title: phrase, artist: nil, candidates: candidates) else {
                let reply = ConversationGuide.unresolvedTrackReply(title: phrase, queue: queue)
                conversationContext = reply.context
                throw UserFacingError("\(reply.title) \(reply.detail)")
            }
            return try await executeRequestAction(queue ? .queueResolvedTrack(track) : .playResolvedTrack(track))
        case .findPlaylist(let prompt):
            let requestID = operationID
            let generation = accountGeneration
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
                do {
                    try await notifications.recommend(recommendation)
                    try Task.checkCancellation()
                    guard operationID == requestID, accountGeneration == generation else { throw CancellationError() }
                }
                catch {
                    guard !Task.isCancelled, operationID == requestID, accountGeneration == generation else {
                        notifications.remove(recommendation.id)
                        throw CancellationError()
                    }
                    notificationNotice = "Your playlist is ready here. The notification couldn't be shown."
                    diagnostics.record("Notification", error.localizedDescription, isError: true)
                }
            }
            return VibeCastResult(title: "A little something for you.", source: .findPlaylist,
                                  resolvedItem: playlist.name, playlist: playlist)
        case .makePlaylist(let prompt): return try await makePlaylist(prompt)
        case .conversation(let prompt):
            lastSpotifyAction = "Clarifying request"
            let reply = ConversationGuide.reply(to: prompt, context: conversationContext)
            conversationContext = reply.context
            return VibeCastResult(title: reply.title, detail: reply.detail, source: .conversation)
        }
    }

    private func executeRequestAction(_ requested: SpotifyAction) async throws -> VibeCastResult {
        try Task.checkCancellation()
        let action: SpotifyAction
        switch requested {
        case .playTrack(let query), .queueTrack(let query):
            requestPlaybackStage("Resolving song", action: requested)
            let track = try await spotify.resolveTrack(query)
            if case .queueTrack = requested { action = .queueResolvedTrack(track) }
            else { action = .playResolvedTrack(track) }
        default: action = requested
        }
        try Task.checkCancellation()
        switch action {
        case .playResolvedTrack(let track), .queueResolvedTrack(let track): lastResolvedItem = track.displayName
        case .playResolvedPlaylist(let playlist): lastResolvedItem = playlist.name
        default: break
        }
        // Queue acknowledgement does not mean the song is currently playing.
        if case .queueResolvedTrack = action {
            requestPlaybackStage("Adding to queue", action: action)
            do { return try await spotify.execute(action) }
            catch {
                try Task.checkCancellation()
                diagnostics.record("Queue", "Command failed: \(Self.playbackErrorSummary(error))", isError: true)
                if let apiError = error as? SpotifyAPIError {
                    switch apiError {
                    case .requestFailed(let status, _) where status >= 500 || status == 408: break
                    default: throw error
                    }
                }
                throw UserFacingError("Spotify may have added the song. Check your queue before trying again to avoid adding it twice.")
            }
        }

        isRequestPlayback = true
        playbackRefreshID = UUID()
        requestPlaybackStage("Checking player", action: action)
        let before: SpotifyPlayback?
        do { before = try await spotify.playback() }
        catch {
            try Task.checkCancellation()
            diagnostics.record("Playback", "Preflight read failed: \(Self.playbackErrorSummary(error))", isError: true)
            if error is SpotifyAPIError { throw error }
            throw UserFacingError("Spotify's player couldn't be checked. No playback command was sent. Try again.")
        }
        try Task.checkCancellation()
        let observedAt = ContinuousClock.now
        let target: SpotifyDevice
        if case .transferPlayback(let name) = action {
            let devices = try await spotify.devices()
            try Task.checkCancellation()
            guard let device = devices.first(where: {
                $0.id?.isEmpty == false && $0.isRestricted != true && $0.name.localizedCaseInsensitiveContains(name)
            }) else { throw SpotifyAPIError.missingDevice }
            target = device
            lastResolvedItem = device.name
        } else if let device = before?.device, device.id?.isEmpty == false {
            guard device.isRestricted != true else { throw SpotifyAPIError.missingDevice }
            target = device
        } else {
            let devices = try await spotify.devices()
            try Task.checkCancellation()
            let available = devices.filter { $0.id?.isEmpty == false && $0.isRestricted != true }
            guard let device = available.first(where: \.isActive) ?? available.first else {
                throw SpotifyAPIError.noAvailableDevices
            }
            target = device
        }
        if action == .next || action == .previous, before?.item == nil {
            throw UserFacingError("Open Spotify and start a song before skipping or going back.")
        }
        try Task.checkCancellation()
        requestPlaybackStage("Sending command", action: action)
        let commandStartedAt = ContinuousClock.now
        let age = observedAt.duration(to: commandStartedAt).components
        let result: VibeCastResult
        do { result = try await spotify.execute(action, deviceID: target.id) }
        catch {
            try Task.checkCancellation()
            diagnostics.record("Playback", "Command failed: \(Self.playbackErrorSummary(error))", isError: true)
            if let apiError = error as? SpotifyAPIError {
                switch apiError {
                case .requestFailed(let status, _) where status >= 500 || status == 408: break
                default: throw error
                }
            }
            throw PlaybackConfirmationFailure.uncertainCommand
        }
        try Task.checkCancellation()
        requestPlaybackStage("Confirming playback", action: action)
        try await confirmPlayback(action, before: before, commandStartedAt: commandStartedAt,
                                  baselineAge: Double(age.seconds) + Double(age.attoseconds) / 1e18,
                                  expectedDeviceID: target.id)
        try Task.checkCancellation()
        requestPlaybackStage("Confirmed", action: action)
        return result
    }

    private func requestPlaybackStage(_ stage: String, action: SpotifyAction) {
        let message = "\(stage): \(action.diagnosticName)"
        lastSpotifyAction = message
        progress = stage == "Confirmed" ? "" : "\(stage)..."
        diagnostics.record("Playback", message)
    }

    private static func playbackErrorSummary(_ error: Error) -> String {
        if let error = error as? URLError { return "network error \(error.code.rawValue)" }
        if let error = error as? SpotifyAPIError {
            switch error {
            case .requestFailed(let status, let path): return "HTTP \(status) \(path)"
            case .playbackRefused(let path, let reason): return "HTTP 403 \(path); reason=\(reason.rawValue)"
            case .refused(let path, _): return "HTTP 403 \(path)"
            default: return error.localizedDescription
            }
        }
        // Do not copy raw transport/provider errors or URLs into the activity log.
        return "Unexpected playback error"
    }

    private func makePlaylist(_ prompt: String, recommendationID: UUID? = nil) async throws -> VibeCastResult {
        let generation = accountGeneration
        let requestID = operationID
        // Reload before any new create so persistence failures never silently permit a duplicate.
        if let accountID { try restorePlaylistRecovery(accountID: accountID) }
        guard settings.aiConsent else {
            throw UserFacingError("Enable Cast Magic in Settings before sharing your request with the AI service.")
        }
        guard unfinishedPlaylist == nil else {
            throw UserFacingError("Your last playlist is waiting to be finished. Resume it before making another.")
        }
        guard pendingPlaylistCreation == nil else {
            throw UserFacingError("Spotify may already have created your last playlist. Check Spotify below before making another.")
        }
        guard let accountID else { throw UserFacingError("Connect Spotify to make a playlist.") }
        try requirePlaylistPermissions()
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
        guard accountGeneration == generation, operationID == requestID else { throw CancellationError() }
        progress = "Creating your private playlist..."
        lastSpotifyAction = "Create private playlist"
        diagnostics.record("Spotify", "Verified \(tracks.count) tracks; creating private playlist")
        let attempt = PlaylistCreationAttempt(accountID: accountID, name: plan.name,
                                              description: plan.description, tracks: tracks)
        // Save the correlation marker before the non-idempotent POST. Unknown outcomes
        // are recovered by lookup only; neither a timeout nor cancellation sends it again.
        try saveCreationAttempt(attempt)
        if let recommendationID, let index = pending.firstIndex(where: { $0.id == recommendationID }) {
            pending[index].status = .superseded
            persistPending()
            notifications.remove(recommendationID)
        }
        let playlist: SpotifyResolvedPlaylist
        do {
            playlist = try await spotify.createPlaylist(name: attempt.name, description: attempt.spotifyDescription)
        } catch {
            guard accountGeneration == generation, operationID == requestID else { throw CancellationError() }
            if Self.isDefiniteCreationRejection(error) {
                try clearPlaylistRecovery()
                if let recommendationID, let index = pending.firstIndex(where: { $0.id == recommendationID }) {
                    pending[index].status = .pending
                    persistPending()
                }
                throw error
            }
            diagnostics.record("Playlist", "Creation outcome unknown: \(RequestErrorPresentation(error).diagnostic)", isError: true)
            throw UserFacingError("Spotify may have created your playlist. Use Check Spotify below to recover it without creating another.")
        }
        try Task.checkCancellation()
        guard accountGeneration == generation, operationID == requestID else { throw CancellationError() }
        let draft = PlaylistDraft(accountID: accountID, playlist: playlist, tracks: tracks)
        try saveDraft(draft)
        return try await populatePlaylist(draft, generation: generation)
    }

    private func populatePlaylist(_ draft: PlaylistDraft, generation: UUID) async throws -> VibeCastResult {
        let requestID = operationID
        try requirePlaylistPermissions()
        try Task.checkCancellation()
        progress = "Adding \(draft.tracks.count) songs..."
        lastSpotifyAction = "Populate private playlist"
        try await spotify.setPlaylistTracks(draft.playlist, tracks: draft.tracks)
        try Task.checkCancellation()
        guard accountGeneration == generation, operationID == requestID else { throw CancellationError() }
        progress = "Checking your playlist..."
        lastSpotifyAction = "Verify private playlist and song order"
        try await spotify.verifyPlaylist(draft.playlist, tracks: draft.tracks, accountID: draft.accountID)
        try Task.checkCancellation()
        guard accountGeneration == generation, operationID == requestID else { throw CancellationError() }
        try clearPlaylistRecovery()
        return createdResult(draft.playlist, count: draft.tracks.count)
    }

    func recoverPlaylistCreation() {
        guard !isBusy, let attempt = pendingPlaylistCreation, attempt.accountID == accountID else { return }
        let generation = accountGeneration
        run(prompt: "Recover \(attempt.name)", route: .makePlaylist(prompt: attempt.name)) {
            let requestID = self.operationID
            try self.requirePlaylistPermissions()
            self.progress = "Checking Spotify for your playlist..."
            self.lastSpotifyAction = "Locate previous playlist creation"
            let playlist = try await self.spotify.findCreatedPlaylist(for: attempt)
            try Task.checkCancellation()
            guard self.accountGeneration == generation, self.operationID == requestID,
                  self.pendingPlaylistCreation?.id == attempt.id else { throw CancellationError() }
            guard let playlist else {
                throw UserFacingError("That playlist hasn't appeared in Spotify yet. Check again shortly, or stop recovery after checking your Spotify library.")
            }
            let draft = PlaylistDraft(accountID: attempt.accountID, playlist: playlist, tracks: attempt.tracks)
            try self.saveDraft(draft)
            return try await self.populatePlaylist(draft, generation: generation)
        }
    }

    // Called only after the recovery UI explains that this leaves Spotify unchanged.
    func abandonPlaylistRecovery(id: String) {
        guard !isBusy, playlistRecoveryID == id else { return }
        do {
            try clearPlaylistRecovery()
            diagnostics.record("Playlist", "Recovery stopped by user; Spotify playlists retained")
            clear()
        } catch { fail(error) }
    }

    private func requirePlaylistPermissions() throws {
        guard try auth.currentToken()?.hasScopes(["playlist-modify-private", "playlist-read-private"]) == true else {
            throw UserFacingError("Reconnect Spotify in Settings to allow private playlist creation and recovery.")
        }
    }

    private func saveCreationAttempt(_ attempt: PlaylistCreationAttempt) throws {
        try playlistRecovery.saveAttempt(attempt)
        pendingPlaylistCreation = attempt
    }

    private func clearPlaylistRecovery() throws {
        guard let accountID else { throw SpotifyAPIError.unauthorized }
        try playlistRecovery.clear(accountID: accountID)
        pendingPlaylistCreation = nil
        unfinishedPlaylist = nil
    }

    private func restorePlaylistRecovery(accountID: String) throws {
        let record = try playlistRecovery.load(accountID: accountID)
        unfinishedPlaylist = record?.draft
        pendingPlaylistCreation = record?.attempt
    }

    private static func isDefiniteCreationRejection(_ error: any Error) -> Bool {
        guard let error = error as? SpotifyAPIError else { return false }
        switch error {
        case .unauthorized, .missingPlaylistScopes, .refused, .rateLimited: return true
        case .requestFailed(let status, _): return (400..<500).contains(status) && status != 408
        default: return false
        }
    }

    private func createdResult(_ playlist: SpotifyResolvedPlaylist, count: Int) -> VibeCastResult {
        VibeCastResult(title: playlist.name, detail: "\(count) songs. Made for you. Private on Spotify.",
                       source: .makePlaylist, resolvedItem: playlist.name, playlist: playlist)
    }

    private func saveDraft(_ draft: PlaylistDraft) throws {
        try playlistRecovery.saveDraft(draft)
        unfinishedPlaylist = draft
        pendingPlaylistCreation = nil
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
        if let apiError = error as? SpotifyAPIError, case .playbackRefused(let path, let reason) = apiError {
            diagnostics.record("Spotify", "HTTP 403 \(path); reason=\(reason.rawValue)", isError: true)
        }
        let presentation = RequestErrorPresentation(error)
        diagnostics.record("Request", "\(lastRequestStage ?? "Request"): \(presentation.diagnostic)", isError: true)
        latestResult = nil
        latestError = presentation.message
        lastRequestOutcome = "Failed"
        requestState = .failed(presentation.message)
    }

    private func appendHistory(_ prompt: String, route: RequestRoute, message: String, status: RequestHistoryItem.Status) {
        requestHistory.insert(RequestHistoryItem(prompt: DiagnosticLog.redacted(prompt), routeName: route.displayName,
                                                message: DiagnosticLog.redacted(message), status: status,
                                                stage: lastRequestStage.map(DiagnosticLog.redacted)), at: 0)
        requestHistory = Array(requestHistory.prefix(8))
    }
}
