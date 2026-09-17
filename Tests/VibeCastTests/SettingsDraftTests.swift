import Foundation
import Testing
@testable import VibeCast

@MainActor
struct SettingsDraftTests {
    @Test func everyPreferenceIsTrackedAndRevertingClearsDirtyState() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let original = SettingsDraft(settings: settings)
        #expect(!original.hasChanges(from: settings, apiKey: ""))
        for key in [\SettingsDraft.clientID, \.serviceAddress, \.codexExecutable, \.model, \.subscriptionModel] {
            var draft = original
            draft[keyPath: key] += "changed"
            #expect(draft.hasChanges(from: settings, apiKey: ""))
            #expect(SettingsDraft(settings: settings) == original)
            draft[keyPath: key] = original[keyPath: key]
            #expect(!draft.hasChanges(from: settings, apiKey: ""))
        }
        for key in [\SettingsDraft.aiConsent, \.notificationsEnabled, \.lyricsEnabled] {
            var draft = original
            draft[keyPath: key].toggle()
            #expect(draft.hasChanges(from: settings, apiKey: ""))
            #expect(SettingsDraft(settings: settings) == original)
            draft[keyPath: key].toggle()
            #expect(!draft.hasChanges(from: settings, apiKey: ""))
        }
        var draft = original
        draft.provider = original.provider == .chatGPT ? .personalAPI : .chatGPT
        #expect(draft.hasChanges(from: settings, apiKey: ""))
        #expect(original.hasChanges(from: settings, apiKey: "test-key"))
        #expect(!original.hasChanges(from: settings, apiKey: " \n"))
        draft = original
        draft.model = "  \(original.model)\n"
        #expect(!draft.hasChanges(from: settings, apiKey: ""))
    }

    @Test func saveAppliesDraftAndBecomesCleanWhileInvalidDraftDoesNotPersist() async throws {
        let (store, _, _, _, defaults) = try await StoreTests().fixture()
        var draft = SettingsDraft(settings: store.settings)
        draft.lyricsEnabled.toggle()
        draft.notificationsEnabled.toggle()
        draft.aiConsent.toggle()
        draft.subscriptionModel = "test-model"
        #expect(draft.hasChanges(from: store.settings, apiKey: ""))
        #expect(store.saveSettings(draft, apiKey: ""))
        #expect(!draft.hasChanges(from: store.settings, apiKey: ""))
        #expect(SettingsDraft(settings: AppSettings(defaults: defaults)) == draft)
        draft.provider = .personalAPI
        draft.model = " "
        #expect(!draft.isValid)
        #expect(!store.saveSettings(draft, apiKey: ""))
        #expect(draft.hasChanges(from: store.settings, apiKey: ""))
        #expect(store.settings.openAIModel != " ")
    }

    @Test func failedKeychainWriteKeepsSettingsUnchangedAndRetryable() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        let secrets = RejectingSettingsSecrets()
        let store = VibeCastStore(settings: settings, secrets: secrets, defaults: defaults, startAutomatically: false)
        let original = SettingsDraft(settings: settings)
        var draft = original
        draft.lyricsEnabled.toggle()
        #expect(!store.saveSettings(draft, apiKey: "private-test-value"))
        #expect(SettingsDraft(settings: settings) == original)
        #expect(draft.hasChanges(from: settings, apiKey: "private-test-value"))
        #expect(store.latestError != nil)
        #expect(!store.diagnostics.text.contains("private-test-value"))
        secrets.rejectWrites = false
        #expect(store.saveSettings(draft, apiKey: "private-test-value"))
        #expect(!draft.hasChanges(from: settings, apiKey: ""))
    }
}

@MainActor
private final class RejectingSettingsSecrets: SecretStoring {
    var rejectWrites = true
    func read(account: String) throws -> Data? { nil }
    func remove(account: String) throws {}
    func write(_ data: Data, account: String) throws {
        if rejectWrites { throw UserFacingError("Keychain unavailable") }
    }
}
