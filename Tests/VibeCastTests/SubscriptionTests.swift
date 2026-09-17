import Foundation
import Testing
@testable import VibeCast

@MainActor
final class FakeCodexRPC: CodexRPC {
    var onNotification: ((String, Data) -> Void)?
    var onTermination: (() -> Void)?
    var requests: [(method: String, params: [String: Any])] = []
    var notifications: [String] = []
    var starts = 0
    var stops = 0
    var signedIn = true
    var accountType = "chatgpt"
    var usedPercent = 20
    var unknownUsage = false
    var holdTurn = false
    var badPlan = false
    var failedTurn = false
    var denyTool = false
    var repeatModelCursor = false
    var authURL = "https://auth.openai.com/authorize?state=test"
    var failMethod: String?

    func start() throws { starts += 1 }
    func stop() { stops += 1 }
    func notify(_ method: String) throws { notifications.append(method) }
    func emit(_ method: String, _ params: [String: Any]) throws {
        onNotification?(method, try JSONSerialization.data(withJSONObject: params))
    }
    func request(_ method: String, params: Data, timeout: TimeInterval) async throws -> Data {
        requests.append((method, try JSONSerialization.jsonObject(with: params) as! [String: Any]))
        if method == failMethod { throw UserFacingError("Connection unavailable") }
        let result: [String: Any]
        switch method {
        case "initialize": result = ["userAgent": "fake"]
        case "account/read":
            result = ["account": signedIn ? ["type": accountType, "email": "tester@example.com", "planType": "pro"] : NSNull()]
        case "account/login/start": result = ["type": "chatgpt", "loginId": "login", "authUrl": authURL]
        case "account/logout": signedIn = false; result = [:]
        case "model/list":
            result = ["data": [["id": "model-id", "model": "account-model", "displayName": "Account Model",
                                  "hidden": false, "isDefault": true, "defaultReasoningEffort": "medium"]],
                      "nextCursor": repeatModelCursor ? "repeat" : NSNull()]
        case "account/rateLimits/read":
            result = ["rateLimits": ["primary": unknownUsage ? NSNull() as Any : ["usedPercent": usedPercent],
                                     "secondary": NSNull(), "rateLimitReachedType": NSNull()]]
        case "thread/start": result = ["thread": ["id": "own-thread"]]
        case "turn/start":
            result = ["turn": ["id": "own-turn"]]
            if denyTool { try emit("vibecast/toolDenied", ["method": "item/tool/call"]) }
            else if !holdTurn {
                let plan = PlaylistPlan(name: "Night Drive", description: "A late-night mix", tracks: (1...12).map {
                    TrackIntent(title: "Song \($0)", artist: "Artist")
                })
                let text = badPlan ? "not JSON" : String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
                try emit("item/completed", ["threadId": "other-thread", "turnId": "own-turn",
                                            "item": ["type": "agentMessage", "text": "untrusted", "phase": "final_answer"]])
                try emit("item/completed", ["threadId": "own-thread", "turnId": "own-turn",
                                            "item": ["type": "agentMessage", "text": "Thinking", "phase": "commentary"]])
                try emit("item/completed", ["threadId": "own-thread", "turnId": "own-turn",
                                            "item": ["type": "agentMessage", "text": text, "phase": "final_answer"]])
                // Completion can beat the turn/start response on the stdio pipe.
                try emit("turn/completed", ["threadId": "own-thread",
                                            "turn": ["id": "own-turn", "status": failedTurn ? "failed" : "completed", "items": []]])
            }
        default: throw UserFacingError("Unexpected test method: \(method)")
        }
        return try JSONSerialization.data(withJSONObject: result)
    }
}

@MainActor
struct SubscriptionTests {
    @Test func appRestoresSubscriptionWithoutOpeningSettingsOrRequiringSpotify() async throws {
        let (session, rpc, settings) = fixture()
        let store = VibeCastStore(settings: settings, secrets: MemorySecrets(), spotify: FakeSpotify(),
                                 planner: FakePlanner(), notifications: FakeNotifications(), chatGPT: session)
        for _ in 0..<100 where !session.hasCheckedAccount { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.hasCheckedAccount)
        #expect(session.account?.type == "chatgpt")
        #expect(rpc.requests.contains { $0.method == "account/read" })
        #expect(!store.authState.isLoggedIn)
    }

    @Test func otherProvidersDoNotStartSubscriptionRestore() async throws {
        for provider in [AIProvider.hosted, .personalAPI] {
            let (session, rpc, settings) = fixture()
            settings.aiProvider = provider
            let store = VibeCastStore(settings: settings, secrets: MemorySecrets(), spotify: FakeSpotify(),
                                     planner: FakePlanner(), notifications: FakeNotifications(), chatGPT: session)
            try await Task.sleep(for: .milliseconds(30))
            #expect(rpc.starts == 0)
            #expect(!session.hasCheckedAccount)
            #expect(!store.authState.isLoggedIn)
        }
    }

    private func fixture(timeout: TimeInterval = 2) -> (ChatGPTSession, FakeCodexRPC, AppSettings) {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.aiProvider = .chatGPT
        settings.aiConsent = true
        let rpc = FakeCodexRPC()
        let session = ChatGPTSession(settings: settings, rpc: rpc,
                                     workspace: { URL(fileURLWithPath: "/test/isolated") },
                                     openBrowser: { _ in false }, operationTimeout: timeout)
        return (session, rpc, settings)
    }

    @Test func subscriptionGeneratesOnlyStructuredMusicWithAccountModel() async throws {
        let (session, rpc, _) = fixture()
        let plan = try await session.plan(for: "Soft rock for a night drive")
        #expect(plan.tracks.count == 12)
        #expect(session.account?.type == "chatgpt")
        #expect(session.usage?.core?.remaining == 80)
        #expect(!session.isBusy)
        #expect(rpc.starts == 1 && rpc.stops == 1)
        #expect(rpc.notifications == ["initialized"])
        let thread = try #require(rpc.requests.first { $0.method == "thread/start" }?.params)
        #expect(thread["ephemeral"] as? Bool == true)
        #expect(thread["approvalPolicy"] as? String == "never")
        #expect(thread["sandbox"] as? String == "read-only")
        let turn = try #require(rpc.requests.first { $0.method == "turn/start" }?.params)
        #expect(turn["model"] as? String == "account-model")
        #expect(turn["effort"] as? String == "medium")
        #expect((turn["input"] as? [[String: String]])?.first?["text"] == "Soft rock for a night drive")
        #expect(turn["outputSchema"] != nil)
        #expect(turn["tools"] == nil)
    }

    @Test func accountAndUsageFailuresNeverStartGeneration() async {
        for scenario in 0..<5 {
            let (session, rpc, _) = fixture()
            switch scenario {
            case 0: rpc.accountType = "apiKey"
            case 1: rpc.signedIn = false
            case 2: rpc.usedPercent = 100
            case 3: rpc.unknownUsage = true
            default: rpc.failMethod = "account/rateLimits/read"
            }
            await #expect(throws: (any Error).self) { try await session.plan(for: "Night drive") }
            #expect(!rpc.requests.contains { $0.method == "thread/start" })
            #expect(!session.isBusy)
            #expect(rpc.stops == 1)
        }
    }

    @Test func failureCannotFallThroughToPaidAPI() async {
        let (session, rpc, settings) = fixture()
        rpc.usedPercent = 100
        let transport = StubTransport([])
        let secrets = MemorySecrets()
        secrets.values["openai.api-key"] = Data("should-never-be-read".utf8)
        settings.serviceAddress = "https://service.example.com"
        let auth = SpotifyAuthService(settings: settings, secrets: secrets, transport: transport)
        let planner = PlaylistPlanner(settings: settings, auth: auth, secrets: secrets,
                                      transport: transport, subscription: session)
        await #expect(throws: (any Error).self) { try await planner.plan(for: "Night drive") }
        #expect(await transport.requests.isEmpty)
    }

    @Test func consentAndUnavailableModelBlockRequests() async {
        let (session, rpc, settings) = fixture()
        settings.aiConsent = false
        await #expect(throws: (any Error).self) { try await session.plan(for: "Night drive") }
        #expect(rpc.starts == 0)
        settings.aiConsent = true
        settings.subscriptionModel = "not-on-account"
        await #expect(throws: (any Error).self) { try await session.plan(for: "Night drive") }
        #expect(!rpc.requests.contains { $0.method == "thread/start" })
    }

    @Test func failedInvalidAndToolUsingTurnsAreRejected() async {
        for scenario in 0..<3 {
            let (session, rpc, _) = fixture()
            if scenario == 0 { rpc.badPlan = true }
            if scenario == 1 { rpc.failedTurn = true }
            if scenario == 2 { rpc.denyTool = true }
            await #expect(throws: (any Error).self) { try await session.plan(for: "Night drive") }
            #expect(!session.isBusy)
            #expect(rpc.stops == 1)
        }
    }

    @Test func cancellationStopsLocalRuntimeAndAllowsNextRequest() async throws {
        let (session, rpc, _) = fixture()
        rpc.holdTurn = true
        let task = Task { try await session.plan(for: "Night drive") }
        while !rpc.requests.contains(where: { $0.method == "turn/start" }) { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!session.isBusy)
        #expect(rpc.stops == 1)
        rpc.holdTurn = false
        _ = try await session.plan(for: "Try again")
        #expect(rpc.stops == 2)
    }

    @Test func lostCompletionTimesOutAndStopsRuntime() async {
        let (session, rpc, _) = fixture(timeout: 0.02)
        rpc.holdTurn = true
        await #expect(throws: (any Error).self) { try await session.plan(for: "Night drive") }
        #expect(session.error?.contains("too long") == true)
        #expect(!session.isBusy)
        #expect(rpc.stops == 1)
    }

    @Test func crashedRuntimeFailsPendingTurn() async {
        let (session, rpc, _) = fixture()
        rpc.holdTurn = true
        let task = Task { try await session.plan(for: "Night drive") }
        while !rpc.requests.contains(where: { $0.method == "turn/start" }) { await Task.yield() }
        rpc.onTermination?()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(!session.isBusy)
    }

    @Test func browserLoginUsesOwnAccountAndDisconnectLogsOut() async throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let rpc = FakeCodexRPC()
        rpc.signedIn = false
        var opened: URL?
        let session = ChatGPTSession(settings: settings, rpc: rpc, openBrowser: { url in
            opened = url
            rpc.signedIn = true
            try? rpc.emit("account/login/completed", ["loginId": "another-login", "success": false])
            try? rpc.emit("account/login/completed", ["loginId": "login", "success": true])
            return true
        })
        session.signIn()
        await session.waitForConnection()
        #expect(opened?.host == "auth.openai.com")
        #expect(session.account?.email == "tester@example.com")
        #expect(session.error == nil)
        #expect(!session.isSigningIn)
        session.signOut()
        await session.waitForConnection()
        #expect(session.account == nil)
        #expect(rpc.requests.last?.method == "account/logout")
    }

    @Test func rejectedAndCancelledLoginsLeaveNoConnection() async {
        for scenario in 0..<3 {
            let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            let rpc = FakeCodexRPC()
            rpc.signedIn = false
            if scenario == 0 { rpc.authURL = "https://auth.openai.com.evil.example/login" }
            let session = ChatGPTSession(settings: settings, rpc: rpc, openBrowser: { _ in
                if scenario == 1 { try? rpc.emit("account/login/completed", ["loginId": "login", "success": false]) }
                return true
            }, operationTimeout: 0.05)
            session.signIn()
            if scenario == 2 {
                while !rpc.requests.contains(where: { $0.method == "account/login/start" }) { await Task.yield() }
                session.cancelSignIn()
            }
            await session.waitForConnection()
            #expect(session.account == nil)
            #expect(!session.isBusy && !session.isSigningIn)
            #expect(rpc.stops >= 1)
        }
    }

    @Test func repeatedPaginationIsBounded() async {
        let (session, rpc, _) = fixture()
        rpc.repeatModelCursor = true
        await session.refresh()
        #expect(rpc.requests.filter { $0.method == "model/list" }.count == 2)
        #expect(session.models.count == 1)
    }

    @Test func runtimeConfigurationDoesNotInheritAccountOrAPIEnvironment() throws {
        let config = CodexLaunchConfiguration(executable: URL(fileURLWithPath: "/opt/bin/codex"),
                                              home: URL(fileURLWithPath: "/isolated/codex"))
        #expect(config.environment["CODEX_HOME"] == "/isolated/codex")
        #expect(config.environment["HOME"] == FileManager.default.homeDirectoryForCurrentUser.path)
        #expect(Set(config.environment.keys) == Set(["HOME", "PATH", "CODEX_HOME", "TMPDIR", "LANG"]))
        #expect(config.arguments.contains("forced_login_method=\"chatgpt\""))
        #expect(config.arguments.contains("cli_auth_credentials_store=\"keyring\""))
        #expect(config.arguments.contains("features.shell_tool=false"))
        #expect(config.arguments.contains("features.plugins=false"))
        #expect(config.arguments.contains("mcp_servers={}"))
        #expect(!ChatGPTSession.isTrustedLoginURL(URL(string: "http://auth.openai.com")!))
        #expect(!ChatGPTSession.isTrustedLoginURL(URL(string: "https://user:pass@auth.openai.com")!))
    }

    @Test func lineFramingHandlesChunksAndRejectsOversizedMessages() throws {
        var buffer = JSONLineBuffer()
        #expect(try buffer.append(Data("{\"id\":".utf8)).isEmpty)
        #expect(try buffer.append(Data("1}\n\n{}\npar".utf8)) == [Data("{\"id\":1}".utf8), Data("{}".utf8)])
        #expect(try buffer.append(Data("tial\n".utf8)) == [Data("partial".utf8)])
        #expect(throws: (any Error).self) { try buffer.append(Data(repeating: 65, count: JSONLineBuffer.maximumBytes + 1)) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_CODEX"] == "1"))
    func installedRuntimeStartsWithIsolatedUnauthenticatedHome() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vibecast-codex-test-" + UUID().uuidString)
        let config = try CodexLaunchConfiguration.resolve(home: home)
        let keychain = Process()
        keychain.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        keychain.arguments = ["default-keychain", "-d", "user"]
        keychain.environment = config.environment
        keychain.standardOutput = Pipe()
        keychain.standardError = Pipe()
        try keychain.run()
        keychain.waitUntilExit()
        #expect(keychain.terminationStatus == 0, "The Codex child must be able to locate the macOS login Keychain.")
        let rpc = CodexProcess(configuration: { config })
        defer { rpc.stop(); try? FileManager.default.removeItem(at: home) }
        try rpc.start()
        let hello = try JSONSerialization.data(withJSONObject: ["clientInfo": ["name": "vibecast_test", "version": "1.0"]])
        _ = try await rpc.request("initialize", params: hello, timeout: 20)
        try rpc.notify("initialized")
        let response = try await rpc.request("account/read", params: Data(#"{"refreshToken":false}"#.utf8), timeout: 20)
        let account = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
        #expect(account["account"] is NSNull)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
    }
}
