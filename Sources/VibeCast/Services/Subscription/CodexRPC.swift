import Darwin
import Foundation

@MainActor
protocol CodexRPC: AnyObject {
    var onNotification: ((String, Data) -> Void)? { get set }
    var onTermination: (() -> Void)? { get set }
    func start() throws
    func request(_ method: String, params: Data, timeout: TimeInterval) async throws -> Data
    func notify(_ method: String) throws
    func stop()
}

struct CodexLaunchConfiguration {
    let executable: URL
    let home: URL
    var workspace: URL { home.appendingPathComponent("workspace", isDirectory: true) }

    static func resolve(executable override: String = "", home: URL? = nil) throws -> Self {
        let user = FileManager.default.homeDirectoryForCurrentUser
        let candidates = override.isEmpty ? [
            user.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ] : [override]
        guard let path = candidates.first(where: {
            $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw UserFacingError("Install the Codex CLI to use your ChatGPT subscription, or select its executable in Advanced settings.")
        }
        let base = home ?? user.appendingPathComponent("Library/Application Support/\(AppConfig.bundleID)/Codex", isDirectory: true)
        return Self(executable: URL(fileURLWithPath: path).resolvingSymlinksInPath(), home: base)
    }

    var environment: [String: String] {
        // Do not inherit API keys, auth tokens, provider overrides, or the user's CODEX_HOME.
        // macOS resolves the login Keychain through HOME. Only CODEX_HOME is isolated.
        ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
         "PATH": executable.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin",
         "CODEX_HOME": home.path, "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8"]
    }

    static let disabledFeatures = [
        "shell_tool", "unified_exec", "shell_snapshot", "apps", "plugins", "hooks",
        "browser_use", "browser_use_external", "in_app_browser", "computer_use",
        "image_generation", "multi_agent", "memories", "workspace_dependencies",
        "skill_mcp_dependency_install", "code_mode", "code_mode_only", "goals", "tool_suggest",
        "multi_agent_v2", "remote_plugin", "imagegenext", "artifact", "chronicle", "fast_mode"
    ]

    var arguments: [String] {
        let overrides = [
            "forced_login_method=\"chatgpt\"", "cli_auth_credentials_store=\"keyring\"",
            "model_provider=\"openai\"", "approval_policy=\"never\"", "sandbox_mode=\"read-only\"",
            "web_search=\"disabled\"", "history.persistence=\"none\"", "project_doc_max_bytes=0",
            "check_for_update_on_startup=false", "analytics.enabled=false", "feedback.enabled=false",
            "mcp_servers={}"
        ] + Self.disabledFeatures.map { "features.\($0)=false" }
        return ["app-server", "--listen", "stdio://", "--strict-config"] + overrides.flatMap { ["-c", $0] }
    }

    func prepare() throws {
        for directory in [home, workspace] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
    }
}

struct JSONLineBuffer {
    private var data = Data()
    static let maximumBytes = 1_048_576

    mutating func append(_ chunk: Data) throws -> [Data] {
        data.append(chunk)
        var lines: [Data] = []
        while let newline = data.firstIndex(of: 10) {
            let line = Data(data[..<newline])
            guard line.count <= Self.maximumBytes else { throw UserFacingError("The ChatGPT connection returned too much data.") }
            data.removeSubrange(...newline)
            if !line.isEmpty { lines.append(line) }
        }
        guard data.count <= Self.maximumBytes else { throw UserFacingError("The ChatGPT connection returned too much data.") }
        return lines
    }
}

@MainActor
final class CodexProcess: CodexRPC {
    var onNotification: ((String, Data) -> Void)?
    var onTermination: (() -> Void)?
    private let configuration: () throws -> CodexLaunchConfiguration
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var lines = JSONLineBuffer()
    private var nextID = 0
    private var epoch = UUID()
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]

    init(configuration: @escaping () throws -> CodexLaunchConfiguration) {
        self.configuration = configuration
    }

    func start() throws {
        guard process == nil else { return }
        let config = try configuration()
        try config.prepare()
        let child = Process()
        child.executableURL = config.executable
        child.arguments = config.arguments
        child.environment = config.environment
        child.currentDirectoryURL = config.workspace
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        let epoch = UUID()
        self.epoch = epoch
        lines = JSONLineBuffer()
        input = stdin.fileHandleForWriting
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        output = stdout.fileHandleForReading
        errors = stderr.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(bytes, epoch: epoch) }
        }
        // Always drain stderr, but never log auth URLs, tokens, or raw provider errors.
        errors?.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.unexpectedExit(epoch: epoch) }
        }
        process = child
        do { try child.run() }
        catch {
            stop()
            throw UserFacingError("Codex couldn't start. Check the executable in Advanced settings.")
        }
    }

    func request(_ method: String, params: Data, timeout: TimeInterval = 30) async throws -> Data {
        try Task.checkCancellation()
        guard process?.isRunning == true else { throw UserFacingError("The ChatGPT connection isn't running. Reconnect in Settings.") }
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    self?.finish(id, result: .failure(UserFacingError("The ChatGPT connection timed out. Please try again.")))
                }
                do {
                    try send(["id": id, "method": method, "params": JSONSerialization.jsonObject(with: params)])
                } catch { finish(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(id, result: .failure(CancellationError())) }
        }
    }

    func notify(_ method: String) throws { try send(["method": method]) }

    func stop() {
        epoch = UUID()
        let child = process
        process = nil
        input.map { try? $0.close() }
        output?.readabilityHandler = nil
        errors?.readabilityHandler = nil
        input = nil
        output = nil
        errors = nil
        for id in Array(pending.keys) { finish(id, result: .failure(CancellationError())) }
        if let child, child.isRunning {
            child.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw UserFacingError("The ChatGPT connection closed. Please try again.") }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        data.append(10)
        try input.write(contentsOf: data)
    }

    private func receive(_ bytes: Data, epoch: UUID) {
        guard self.epoch == epoch else { return }
        if bytes.isEmpty { return } // Process termination reports the error after queued output is handled.
        do {
            for line in try lines.append(bytes) {
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw UserFacingError("Codex returned an invalid response. Update Codex and try again.")
                }
                if let method = message["method"] as? String {
                    if let id = message["id"] {
                        // This integration grants no tool approvals or dynamic tool execution.
                        try send(["id": id, "error": ["code": -32601, "message": "Tools are unavailable in VibeCast."]])
                        let data = try JSONSerialization.data(withJSONObject: ["method": method])
                        onNotification?("vibecast/toolDenied", data)
                    } else {
                        let data = try JSONSerialization.data(withJSONObject: message["params"] ?? [:])
                        onNotification?(method, data)
                    }
                } else if let id = message["id"] as? Int {
                    if message["error"] != nil {
                        finish(id, result: .failure(UserFacingError("Codex couldn't complete this request. Check your subscription connection or update Codex. No API fallback was used.")))
                    } else if let result = message["result"] {
                        finish(id, result: .success(try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])))
                    } else {
                        finish(id, result: .failure(UserFacingError("Codex returned an invalid response.")))
                    }
                }
            }
        } catch {
            for id in Array(pending.keys) { finish(id, result: .failure(error)) }
            stop()
            onTermination?()
        }
    }

    private func finish(_ id: Int, result: Result<Data, Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func unexpectedExit(epoch: UUID) {
        guard self.epoch == epoch else { return }
        for id in Array(pending.keys) {
            finish(id, result: .failure(UserFacingError("Codex stopped unexpectedly. Update Codex or reconnect in Settings.")))
        }
        stop()
        onTermination?()
    }
}
