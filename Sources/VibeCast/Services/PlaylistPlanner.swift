import Foundation

struct TrackIntent: Codable, Equatable, Sendable {
    let title: String
    let artist: String
    var searchQuery: String {
        let cleanTitle = title.replacingOccurrences(of: "\"", with: "")
        let cleanArtist = artist.replacingOccurrences(of: "\"", with: "")
        return "track:\"\(cleanTitle)\" artist:\"\(cleanArtist)\""
    }
}

struct PlaylistPlan: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let tracks: [TrackIntent]

    func validated() throws -> PlaylistPlan {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              description.count <= 280, (12...20).contains(tracks.count),
              tracks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !$0.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.title.count <= 150 && $0.artist.count <= 150 }) else {
            throw UserFacingError("Cast Magic returned an incomplete song list. Try a more specific request.")
        }
        return self
    }
}

@MainActor
protocol PlaylistPlanning {
    func plan(for prompt: String) async throws -> PlaylistPlan
}

@MainActor
final class PlaylistPlanner: PlaylistPlanning {
    private let settings: AppSettings
    private let auth: SpotifyAuthService
    private let secrets: any SecretStoring
    private let transport: any HTTPTransport
    private let subscription: any PlaylistPlanning

    init(settings: AppSettings, auth: SpotifyAuthService, secrets: any SecretStoring,
         transport: any HTTPTransport = URLSessionTransport(), subscription: any PlaylistPlanning) {
        self.settings = settings
        self.auth = auth
        self.secrets = secrets
        self.transport = transport
        self.subscription = subscription
    }

    func plan(for prompt: String) async throws -> PlaylistPlan {
        guard settings.aiConsent else {
            throw UserFacingError("Enable Cast Magic in Settings to share your musical request with the AI service.")
        }
        guard !prompt.isEmpty, prompt.count <= AppConfig.maximumPromptLength else {
            throw UserFacingError("Keep your request under \(AppConfig.maximumPromptLength) characters.")
        }
        // Subscription failures never fall through to either paid API path.
        let provider = settings.aiProvider
        if provider == .chatGPT { return try await subscription.plan(for: prompt).validated() }
        var request: URLRequest
        if provider == .personalAPI {
            guard let keyData = try secrets.read(account: "openai.api-key"),
                  let key = String(data: keyData, encoding: .utf8), !key.isEmpty else {
                throw UserFacingError("Add your OpenAI API key in Settings to use personal Cast Magic.")
            }
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try Self.openAIRequest(prompt: prompt, model: settings.openAIModel)
        } else {
            guard let url = settings.serviceURL else {
                throw UserFacingError("Cast Magic isn't connected to a service yet. Configure it in Settings, or use your own API key.")
            }
            request = URLRequest(url: url.appendingPathComponent("v1/plan"))
            request.setValue("Bearer \(try await auth.serviceSession())", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(["prompt": prompt])
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            switch response.statusCode {
            case 401:
                throw UserFacingError(provider == .personalAPI ? "Your OpenAI API key wasn't accepted. Update it in Settings."
                                      : "Your Cast Magic session expired. Reconnect Spotify.")
            case 403: throw UserFacingError("Cast Magic isn't enabled for this account. Contact the beta organizer.")
            case 429: throw UserFacingError("You've reached the Cast Magic limit for now. Try again later.")
            default: throw UserFacingError("Cast Magic couldn't finish (\(response.statusCode)). Your Spotify library hasn't changed.")
            }
        }
        let plan: PlaylistPlan
        if provider == .personalAPI { plan = try Self.decodeOpenAIResponse(data) }
        else { plan = try JSONDecoder().decode(PlaylistPlan.self, from: data) }
        return try plan.validated()
    }

    static func openAIRequest(prompt: String, model: String) throws -> Data {
        guard let schemaURL = AppResources.bundle.url(forResource: "PlaylistPlan.schema", withExtension: "json"),
              let instructionsURL = AppResources.bundle.url(forResource: "PlaylistPlanner", withExtension: "txt") else {
            throw UserFacingError("The Cast Magic resources are missing. Reinstall VibeCast.")
        }
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
        let instructions = try String(contentsOf: instructionsURL, encoding: .utf8)
        return try JSONSerialization.data(withJSONObject: [
            "model": model, "store": false, "max_output_tokens": 4000,
            "instructions": instructions, "input": prompt,
            "text": ["format": ["type": "json_schema", "name": "playlist_plan", "strict": true, "schema": schema]]
        ])
    }

    static func decodeOpenAIResponse(_ data: Data) throws -> PlaylistPlan {
        struct Response: Decodable {
            struct Output: Decodable {
                struct Content: Decodable { let type: String; let text: String? }
                let type: String
                let content: [Content]?
            }
            let status: String
            let output: [Output]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status == "completed",
              let text = response.output.filter({ $0.type == "message" }).flatMap({ $0.content ?? [] })
                .first(where: { $0.type == "output_text" })?.text else {
            throw UserFacingError("Cast Magic couldn't produce a complete playlist for that request.")
        }
        return try JSONDecoder().decode(PlaylistPlan.self, from: Data(text.utf8)).validated()
    }
}
