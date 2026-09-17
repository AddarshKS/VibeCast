import AppKit
import Foundation
import Network

@MainActor
protocol SpotifyLoginReceiving {
    func receiveCallback(open authorizationURL: URL, state: String) async throws -> URL
    func cancel()
}

@MainActor
final class LoopbackLogin: SpotifyLoginReceiving {
    private var listener: NWListener?
    private var ready: CheckedContinuation<Void, Error>?
    private var callback: CheckedContinuation<URL, Error>?
    private var timeout: Task<Void, Never>?
    private var expectedState = ""
    private var generation = UUID()

    func receiveCallback(open authorizationURL: URL, state: String) async throws -> URL {
        cancel()
        let generation = self.generation
        expectedState = state
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 43821)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection, buffer: Data(), generation: generation) }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled, self?.generation == generation else { return }
            self?.finish(throwing: UserFacingError("Spotify sign-in timed out. Please try again."))
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.generation == generation else { return }
                        switch state {
                        case .ready:
                            self.ready?.resume()
                            self.ready = nil
                        case .failed:
                            self.finish(throwing: UserFacingError("VibeCast couldn't open the Spotify sign-in callback. Close other VibeCast copies and try again."))
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
            }
        } onCancel: { Task { @MainActor in self.cancel(generation: generation) } }
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                callback = continuation
                if !NSWorkspace.shared.open(authorizationURL) {
                    finish(throwing: UserFacingError("Your browser couldn't open Spotify sign-in."))
                }
            }
        } onCancel: { Task { @MainActor in self.cancel(generation: generation) } }
    }

    func cancel() { finish(throwing: CancellationError()) }

    private func cancel(generation: UUID) {
        if self.generation == generation { cancel() }
    }

    private func finish(throwing error: Error) {
        generation = UUID()
        ready?.resume(throwing: error)
        ready = nil
        callback?.resume(throwing: error)
        callback = nil
        listener?.cancel()
        listener = nil
        timeout?.cancel()
        timeout = nil
    }

    private func receive(_ connection: NWConnection, buffer: Data, generation: UUID) {
        guard self.generation == generation else { connection.cancel(); return }
        if buffer.isEmpty {
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { connection.cancel(); return }
                var bytes = buffer
                if let data { bytes.append(data) }
                guard bytes.count <= 8_192, error == nil else { connection.cancel(); return }
                let header = String(decoding: bytes, as: UTF8.self)
                guard header.contains("\r\n\r\n") else {
                    if complete { connection.cancel() }
                    else { self.receive(connection, buffer: bytes, generation: generation) }
                    return
                }
                let url = Self.callbackURL(header: header, state: self.expectedState)
                let success = url != nil && self.callback != nil
                let denied = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                    .queryItems?.contains(where: { $0.name == "error" }) == true
                let body = SpotifyCallbackPage.html(state: success ? (denied ? .denied : .received) : .expired)
                let response = "HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: \(SpotifyCallbackPage.contentSecurityPolicy)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                if success, let url {
                    self.generation = UUID()
                    self.callback?.resume(returning: url)
                    self.callback = nil
                    self.listener?.cancel()
                    self.listener = nil
                    self.timeout?.cancel()
                    self.timeout = nil
                }
            }
        }
    }

    nonisolated static func callbackURL(header: String, state: String) -> URL? {
        let lines = header.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").split(separator: " ")
        guard request.count == 3, request[0] == "GET", request[2] == "HTTP/1.1",
              lines.contains(where: { $0.lowercased() == "host: 127.0.0.1:43821" }),
              request[1].hasPrefix("/callback?"),
              let url = URL(string: "http://127.0.0.1:43821\(request[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == "/callback" else { return nil }
        let states = (components.queryItems ?? []).filter { $0.name == "state" }
        guard states.count == 1, states.first?.value == state else { return nil }
        return url
    }
}
