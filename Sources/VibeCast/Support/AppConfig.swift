import Foundation

enum AppConfig {
    static let appName = "VibeCast"
    static let bundleID = Bundle.main.bundleIdentifier ?? "app.vibecast.mac.development"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
    static let spotifyRedirectURI = "http://127.0.0.1:43821/callback"
    static let spotifyScopes = [
        "user-read-playback-state", "user-modify-playback-state", "playlist-modify-private", "playlist-read-private"
    ]
    static let maximumPromptLength = 600
    static let recommendationLifetime: TimeInterval = 3_600

    static func setting(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func serviceURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        if url.scheme == "http", host == "127.0.0.1" { return url }
        #endif
        return nil
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var spotifyClientID: String { didSet { defaults.set(spotifyClientID, forKey: "spotifyClientID") } }
    @Published var serviceAddress: String { didSet { defaults.set(serviceAddress, forKey: "serviceAddress") } }
    @Published var aiProvider: AIProvider { didSet { defaults.set(aiProvider.rawValue, forKey: "aiProvider") } }
    @Published var codexExecutable: String { didSet { defaults.set(codexExecutable, forKey: "codexExecutable") } }
    @Published var subscriptionModel: String { didSet { defaults.set(subscriptionModel, forKey: "subscriptionModel") } }
    @Published var aiConsent: Bool { didSet { defaults.set(aiConsent, forKey: "aiConsent") } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var lyricsEnabled: Bool { didSet { defaults.set(lyricsEnabled, forKey: "lyricsEnabled") } }
    @Published var openAIModel: String { didSet { defaults.set(openAIModel, forKey: "openAIModel") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spotifyClientID = defaults.string(forKey: "spotifyClientID") ?? AppConfig.setting("VibeCastSpotifyClientID")
        let service = defaults.string(forKey: "serviceAddress") ?? AppConfig.setting("VibeCastServiceURL")
        serviceAddress = service
        aiProvider = defaults.string(forKey: "aiProvider").flatMap(AIProvider.init(rawValue:))
            ?? (defaults.bool(forKey: "usePersonalAI") ? .personalAPI
                : (AIProvider(rawValue: AppConfig.setting("VibeCastAIProvider"))
                   ?? (service.isEmpty ? .chatGPT : .hosted)))
        codexExecutable = defaults.string(forKey: "codexExecutable") ?? ""
        subscriptionModel = defaults.string(forKey: "subscriptionModel") ?? ""
        aiConsent = defaults.bool(forKey: "aiConsent")
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        lyricsEnabled = defaults.bool(forKey: "lyricsEnabled")
        defaults.removeObject(forKey: "miniplayerStyle")
        openAIModel = defaults.string(forKey: "openAIModel") ?? "gpt-4.1-mini"
    }

    var hasSpotifyConfiguration: Bool {
        spotifyClientID.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil
    }
    var serviceURL: URL? { AppConfig.serviceURL(serviceAddress) }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case chatGPT, hosted, personalAPI
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chatGPT: "ChatGPT subscription"
        case .hosted: "VibeCast service"
        case .personalAPI: "OpenAI API key"
        }
    }
}
