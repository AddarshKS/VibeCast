import Foundation

struct SettingsDraft: Equatable {
    var clientID: String
    var serviceAddress: String
    var codexExecutable: String
    var model: String
    var provider: AIProvider
    var subscriptionModel: String
    var aiConsent: Bool
    var notificationsEnabled: Bool
    var lyricsEnabled: Bool

    @MainActor init(settings: AppSettings) {
        clientID = settings.spotifyClientID
        serviceAddress = settings.serviceAddress
        codexExecutable = settings.codexExecutable
        model = settings.openAIModel
        provider = settings.aiProvider
        subscriptionModel = settings.subscriptionModel
        aiConsent = settings.aiConsent
        notificationsEnabled = settings.notificationsEnabled
        lyricsEnabled = settings.lyricsEnabled
    }

    var normalized: Self {
        var copy = self
        copy.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.serviceAddress = serviceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.codexExecutable = codexExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    var isValid: Bool {
        let value = normalized
        return (value.clientID.isEmpty || value.clientID.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil) &&
            (value.serviceAddress.isEmpty || AppConfig.serviceURL(value.serviceAddress) != nil) &&
            (value.provider != .personalAPI || !value.model.isEmpty)
    }

    @MainActor func hasChanges(from settings: AppSettings, apiKey: String) -> Bool {
        normalized != SettingsDraft(settings: settings).normalized ||
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
