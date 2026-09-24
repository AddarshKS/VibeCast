import AppKit
import Foundation

struct ChatGPTAccount: Decodable, Equatable, Sendable {
    let type: String
    let email: String?
    let planType: String?
    var displayName: String { [email, planType?.capitalized].compactMap { $0 }.joined(separator: " - ") }
}

struct ChatGPTModel: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let isDefault: Bool
    let hidden: Bool
    let defaultReasoningEffort: String
}

struct ChatGPTUsage: Decodable, Sendable {
    struct Window: Decodable, Sendable { let usedPercent: Double }
    struct Limit: Decodable, Sendable {
        let primary: Window?
        let secondary: Window?
        let rateLimitReachedType: String?
        var remaining: Int? {
            let windows = [primary, secondary].compactMap { $0 }
            guard !windows.isEmpty else { return nil }
            return max(0, min(100, Int(100 - windows.map(\.usedPercent).max()!)))
        }
    }
    let rateLimits: Limit?
    let rateLimitsByLimitId: [String: Limit]?
    var core: Limit? { rateLimitsByLimitId?["codex"] ?? rateLimits }

    func requireIncludedUsage() throws {
        guard let core, let remaining = core.remaining else {
            throw UserFacingError("Your included ChatGPT allowance couldn't be checked. Try again shortly; no paid API request was made.")
        }
        guard core.rateLimitReachedType == nil, remaining > 0 else {
            throw UserFacingError("Your included ChatGPT allowance is used up. Wait for it to reset. VibeCast won't switch to paid API credits.")
        }
    }
}

@MainActor
final class ChatGPTSession: ObservableObject, PlaylistPlanning {
    let diagnostics = DiagnosticLog()
    @Published private(set) var account: ChatGPTAccount?
    @Published private(set) var hasCheckedAccount = false
    @Published private(set) var models: [ChatGPTModel] = []
    @Published private(set) var usage: ChatGPTUsage?
    @Published private(set) var isBusy = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var error: String?

    private let settings: AppSettings
    private let rpc: any CodexRPC
    private let workspace: () throws -> URL
    private let openBrowser: (URL) -> Bool
    private let operationTimeout: TimeInterval
    private var initialized = false
    private var connectionTask: Task<Void, Never>?
    private var loginID: String?
    private var loginWaiter: CheckedContinuation<Void, Error>?
    private var timer: Task<Void, Never>?
    private var threadID: String?
    private var turnID: String?
    private var turnWaiter: CheckedContinuation<String, Error>?
    private var completedTurns: [String: Turn] = [:]
    private var finalMessages: [String: String] = [:]
    private var eventError: Error?

    init(settings: AppSettings, rpc: (any CodexRPC)? = nil,
         workspace: (() throws -> URL)? = nil,
         openBrowser: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
         operationTimeout: TimeInterval = 180) {
        self.settings = settings
        let configuration = { try CodexLaunchConfiguration.resolve(executable: settings.codexExecutable) }
        self.rpc = rpc ?? CodexProcess(configuration: configuration)
        self.workspace = workspace ?? { try configuration().workspace }
        self.openBrowser = openBrowser
        self.operationTimeout = operationTimeout
        self.rpc.onNotification = { [weak self] method, params in self?.receive(method, params: params) }
        self.rpc.onTermination = { [weak self] in
            self?.failWaiters(UserFacingError("The ChatGPT connection closed. Please reconnect in Settings."))
            self?.initialized = false
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { close(); isBusy = false }
        do {
            try await connect()
            try await loadAccount()
            error = nil
        } catch is CancellationError { return }
        catch { present(error) }
    }

    func signIn() {
        guard !isBusy else { return }
        isBusy = true
        isSigningIn = true
        error = nil
        connectionTask = Task {
            defer { close(); isBusy = false; isSigningIn = false; connectionTask = nil }
            do {
                try await connect()
                let response: Login = try await call("account/login/start", ["type": "chatgpt"])
                guard response.type == "chatgpt", Self.isTrustedLoginURL(response.authUrl) else {
                    throw UserFacingError("Codex returned an unexpected sign-in address. Update Codex and try again.")
                }
                loginID = response.loginId
                startTimer("ChatGPT sign-in timed out. Please try again.")
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        loginWaiter = continuation
                        if !openBrowser(response.authUrl) {
                            failWaiters(UserFacingError("Your browser couldn't open ChatGPT sign-in."))
                        }
                    }
                } onCancel: { Task { @MainActor in self.failWaiters(CancellationError()) } }
                timer?.cancel()
                try Task.checkCancellation()
                try await loadAccount()
                guard account != nil else { throw UserFacingError("ChatGPT sign-in didn't finish. Please try again.") }
            } catch is CancellationError { return }
            catch { present(error) }
        }
    }

    func cancelSignIn() {
        guard isSigningIn else { return }
        connectionTask?.cancel()
        failWaiters(CancellationError())
        close()
    }

    func signOut() {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        connectionTask = Task {
            defer { close(); isBusy = false; connectionTask = nil }
            do {
                try await connect()
                let _: Empty = try await call("account/logout")
                account = nil
                hasCheckedAccount = true
                usage = nil
                models = []
            } catch { present(error) }
        }
    }

    func shutdown() {
        connectionTask?.cancel()
        failWaiters(CancellationError())
        close()
    }

    func waitForConnection() async { await connectionTask?.value }

    func plan(for prompt: String) async throws -> PlaylistPlan {
        guard settings.aiConsent else { throw UserFacingError("Enable Cast Magic in Settings first." ) }
        guard !isBusy else { throw UserFacingError("Finish connecting ChatGPT before casting magic.") }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.count <= AppConfig.maximumPromptLength else { throw UserFacingError("Keep your musical request under 600 characters.") }
        isBusy = true
        error = nil
        defer { close(); isBusy = false }
        do {
            try await connect()
            try await loadAccount()
            guard account?.type == "chatgpt" else { throw UserFacingError("Connect your ChatGPT subscription in Settings to use Cast Magic.") }
            let freshUsage: ChatGPTUsage = try await call("account/rateLimits/read")
            usage = freshUsage
            try freshUsage.requireIncludedUsage()
            guard let model = settings.subscriptionModel.isEmpty
                ? (models.first(where: \.isDefault) ?? models.first)
                : models.first(where: { $0.model == settings.subscriptionModel }) else {
                throw UserFacingError("That model isn't available on your ChatGPT connection. Choose another in Settings.")
            }
            let directory = try workspace()
            let instructions = try Self.instructions()
            let started: ThreadStarted = try await call("thread/start", [
                "cwd": directory.path, "ephemeral": true, "model": model.model, "modelProvider": "openai",
                "approvalPolicy": "never", "sandbox": "read-only", "personality": "none",
                "baseInstructions": instructions, "developerInstructions": "Return only the playlist JSON. Do not use tools or access files, browsers, accounts, or computer controls."
            ])
            threadID = started.thread.id
            startTimer("Cast Magic took too long. Try a simpler request; no playlist was created.")
            let startedTurn: TurnStarted = try await call("turn/start", [
                "threadId": started.thread.id, "input": [["type": "text", "text": prompt]],
                "model": model.model, "effort": model.defaultReasoningEffort, "summary": "none",
                "approvalPolicy": "never", "sandboxPolicy": ["type": "readOnly", "networkAccess": false],
                "outputSchema": Self.schema()
            ])
            turnID = startedTurn.turn.id
            let text = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    turnWaiter = continuation
                    completeTurnIfReady()
                }
            } onCancel: { Task { @MainActor in self.failWaiters(CancellationError()) } }
            try Task.checkCancellation()
            return try JSONDecoder().decode(PlaylistPlan.self, from: Data(text.utf8)).validated()
        } catch {
            if !(error is CancellationError) { present(error) }
            throw error
        }
    }

    private func present(_ error: Error) {
        let feedback = RequestErrorPresentation(error, source: .chatGPT)
        diagnostics.record("ChatGPT", feedback.diagnostic, isError: true)
        self.error = feedback.message
    }

    static func isTrustedLoginURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil &&
            ["auth.openai.com", "auth.chatgpt.com", "chatgpt.com"].contains(url.host ?? "")
    }

    private func connect() async throws {
        guard !initialized else { return }
        try Task.checkCancellation()
        try rpc.start()
        let _: Empty = try await call("initialize", ["clientInfo": ["name": "vibecast", "title": "VibeCast", "version": AppConfig.version]])
        try rpc.notify("initialized")
        initialized = true
    }

    private func loadAccount() async throws {
        let result: AccountResponse = try await call("account/read", ["refreshToken": true])
        hasCheckedAccount = true
        guard result.account == nil || result.account?.type == "chatgpt" else {
            account = nil
            models = []
            usage = nil
            throw UserFacingError("This connection isn't using a ChatGPT subscription. Disconnect and sign in with ChatGPT; API-key accounts are not accepted in subscription mode.")
        }
        account = result.account
        guard account != nil else { models = []; usage = nil; return }
        models = []
        var cursor: String?
        var visitedCursors = Set<String>()
        var pages = 0
        repeat {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let page: Models = try await call("model/list", params)
            pages += 1
            let existing = Set(models.map(\.model))
            models.append(contentsOf: page.data.filter { !$0.hidden && !existing.contains($0.model) })
            cursor = page.nextCursor
            if let cursor, !visitedCursors.insert(cursor).inserted { break }
        } while cursor != nil && pages < 4
        usage = try? await call("account/rateLimits/read")
    }

    private func call<T: Decodable>(_ method: String, _ params: [String: Any] = [:]) async throws -> T {
        diagnostics.record("ChatGPT", method)
        do {
            let data = try JSONSerialization.data(withJSONObject: params)
            let response = try await rpc.request(method, params: data, timeout: 30)
            try Task.checkCancellation()
            let value = try JSONDecoder().decode(T.self, from: response)
            diagnostics.record("ChatGPT", "\(method) completed")
            return value
        } catch {
            diagnostics.record("ChatGPT", "\(method): \(error.localizedDescription)", isError: true)
            throw error
        }
    }

    private func receive(_ method: String, params: Data) {
        do {
            switch method {
            case "account/login/completed":
                let event = try JSONDecoder().decode(LoginCompleted.self, from: params)
                guard event.loginId == loginID else { return }
                diagnostics.record("ChatGPT", event.success ? "Browser sign-in completed" : Self.loginFailure(event.error), isError: !event.success)
                let waiter = loginWaiter
                loginWaiter = nil
                if event.success { waiter?.resume() }
                else { waiter?.resume(throwing: UserFacingError(Self.loginFailure(event.error))) }
            case "item/completed":
                let event = try JSONDecoder().decode(ItemCompleted.self, from: params)
                guard event.threadId == threadID else { return }
                if let text = event.item.finalText {
                    guard text.utf8.count <= 65_536 else { throw UserFacingError("Cast Magic returned too much text.") }
                    finalMessages[event.turnId] = text
                }
            case "turn/completed":
                let event = try JSONDecoder().decode(TurnCompleted.self, from: params)
                guard event.threadId == threadID else { return }
                completedTurns[event.turn.id] = event.turn
                completeTurnIfReady()
            case "vibecast/toolDenied":
                failWaiters(UserFacingError("Cast Magic requested an unavailable tool. No permission was granted; try a new request."))
            default: break
            }
        } catch { failWaiters(error) }
    }

    private func completeTurnIfReady() {
        if let eventError { failWaiters(eventError); return }
        guard let turnID, let turn = completedTurns[turnID], let waiter = turnWaiter else { return }
        turnWaiter = nil
        guard turn.status == "completed" else {
            waiter.resume(throwing: UserFacingError("ChatGPT couldn't finish this playlist. Check your subscription limits and try again. No API fallback was used."))
            return
        }
        guard let text = turn.items?.compactMap(\.finalText).last ?? finalMessages[turnID], !text.isEmpty,
              text.utf8.count <= 65_536 else {
            waiter.resume(throwing: UserFacingError("ChatGPT didn't return a complete song list. Try again."))
            return
        }
        waiter.resume(returning: text)
    }

    private func startTimer(_ message: String) {
        timer?.cancel()
        timer = Task { [weak self, operationTimeout] in
            do { try await Task.sleep(for: .seconds(operationTimeout)) } catch { return }
            self?.failWaiters(UserFacingError(message))
        }
    }

    private func failWaiters(_ error: Error) {
        eventError = error
        loginWaiter?.resume(throwing: error)
        loginWaiter = nil
        turnWaiter?.resume(throwing: error)
        turnWaiter = nil
    }

    private func close() {
        timer?.cancel()
        timer = nil
        rpc.stop()
        initialized = false
        loginID = nil
        threadID = nil
        turnID = nil
        finalMessages = [:]
        completedTurns = [:]
        eventError = nil
    }

    private static func instructions() throws -> String {
        guard let url = AppResources.bundle.url(forResource: "PlaylistPlanner", withExtension: "txt") else {
            throw UserFacingError("Cast Magic resources are missing. Reinstall VibeCast.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func schema() throws -> Any {
        guard let url = AppResources.bundle.url(forResource: "PlaylistPlan.schema", withExtension: "json") else {
            throw UserFacingError("Cast Magic resources are missing. Reinstall VibeCast.")
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private struct Empty: Decodable {}
    private struct AccountResponse: Decodable { let account: ChatGPTAccount? }
    private struct Models: Decodable { let data: [ChatGPTModel]; let nextCursor: String? }
    private struct Login: Decodable { let type: String; let loginId: String; let authUrl: URL }
    static func loginFailure(_ message: String?) -> String {
        let text = message?.lowercased() ?? ""
        if text.contains("keyring") || text.contains("keychain") || text.contains("persist") {
            return "ChatGPT approved sign-in, but macOS couldn't save it in your login Keychain. Unlock the login Keychain and retry. No API fallback was used."
        }
        return "ChatGPT sign-in wasn't completed. Please try again."
    }

    private struct LoginCompleted: Decodable { let loginId: String; let success: Bool; let error: String? }
    private struct Identifier: Decodable { let id: String }
    private struct ThreadStarted: Decodable { let thread: Identifier }
    private struct TurnStarted: Decodable { let turn: Identifier }
    private struct Item: Decodable {
        let type: String
        let text: String?
        let phase: String?
        var finalText: String? { type == "agentMessage" && (phase == nil || phase == "final_answer") ? text : nil }
    }
    private struct Turn: Decodable { let id: String; let status: String; let items: [Item]? }
    private struct ItemCompleted: Decodable { let threadId: String; let turnId: String; let item: Item }
    private struct TurnCompleted: Decodable { let threadId: String; let turn: Turn }
}
