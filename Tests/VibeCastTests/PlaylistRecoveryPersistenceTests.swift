import Foundation
import Testing
@testable import VibeCast

private final class FailingRecoveryDefaults: UserDefaults, @unchecked Sendable {
    var failsSynchronization = false
    override func synchronize() -> Bool { failsSynchronization ? false : super.synchronize() }
}

@MainActor
struct PlaylistRecoveryPersistenceTests {
    private let track = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000001", title: "Song", artist: "Artist")
    private let playlist = SpotifyResolvedPlaylist(uri: "spotify:playlist:created", name: "Night Drive", ownerName: nil, description: nil)

    private func attempt(account: String = "alice", at date: Date = Date()) -> PlaylistCreationAttempt {
        .init(accountID: account, name: "Night Drive", description: "For the road", tracks: [track], createdAt: date)
    }

    private func draft(account: String = "alice", at date: Date = Date()) -> PlaylistDraft {
        .init(accountID: account, playlist: playlist, tracks: [track], createdAt: date)
    }

    @Test func restartRetainsAccountIsolatedAttemptsAndAtomicDraftTransitions() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaylistRecoveryStore(defaults: defaults)
        let alice = attempt()
        let bob = attempt(account: "bob")
        try store.saveAttempt(alice)
        try store.saveAttempt(bob)

        let restarted = PlaylistRecoveryStore(defaults: UserDefaults(suiteName: suite)!)
        #expect(try restarted.load(accountID: "alice")?.attempt == alice)
        #expect(try restarted.load(accountID: "bob")?.attempt == bob)
        #expect(try restarted.load(accountID: "charlie") == nil)

        let known = draft()
        try restarted.saveDraft(known)
        let restored = try #require(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice"))
        #expect(restored.draft == known)
        #expect(restored.attempt == nil)
        #expect(try store.load(accountID: "bob")?.attempt == bob)
        try store.clear(accountID: "alice")
        #expect(try restarted.load(accountID: "alice") == nil)
        #expect(try restarted.load(accountID: "bob")?.attempt == bob)
    }

    @Test func migrationKeepsDifferentAccountsAndDoesNotExpireKnownPlaylists() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldDraft = draft(at: .distantPast)
        let otherAttempt = attempt(account: "bob", at: .distantPast)
        defaults.set(try JSONEncoder().encode(oldDraft), forKey: "unfinishedPlaylist")
        defaults.set(try JSONEncoder().encode(otherAttempt), forKey: "pendingPlaylistCreation")
        let store = PlaylistRecoveryStore(defaults: defaults)
        #expect(oldDraft.isRecoverable)
        #expect(try store.load(accountID: "alice")?.draft == oldDraft)
        #expect(try store.load(accountID: "bob")?.attempt == otherAttempt)
        #expect(defaults.object(forKey: "unfinishedPlaylist") == nil)
        #expect(defaults.object(forKey: "pendingPlaylistCreation") == nil)
    }

    @Test(arguments: [true, false])
    func migrationKeepsNewestLegacyRecordForSameAccount(draftIsNewest: Bool) throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)
        let known = draft(at: draftIsNewest ? recent : old)
        let unknown = attempt(at: draftIsNewest ? old : recent)
        defaults.set(try JSONEncoder().encode(known), forKey: "unfinishedPlaylist")
        defaults.set(try JSONEncoder().encode(unknown), forKey: "pendingPlaylistCreation")
        let record = try #require(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice"))
        #expect(record.draft == (draftIsNewest ? known : nil))
        #expect(record.attempt == (draftIsNewest ? nil : unknown))
    }

    @Test func staleLegacyKeysCannotResurrectExplicitlyClearedRecovery() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = attempt()
        let store = PlaylistRecoveryStore(defaults: defaults)
        try store.saveAttempt(original)
        try store.clear(accountID: "alice")
        // Simulate legacy-key cleanup interrupted after the new archive was durable.
        defaults.set(try JSONEncoder().encode(original), forKey: "pendingPlaylistCreation")
        #expect(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice") == nil)
    }

    @Test func failedDraftSaveRetainsTheCreationJournal() throws {
        let suite = UUID().uuidString
        let defaults = FailingRecoveryDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaylistRecoveryStore(defaults: defaults)
        let original = attempt()
        try store.saveAttempt(original)
        defaults.failsSynchronization = true
        #expect(throws: UserFacingError.self) { try store.saveDraft(draft()) }
        #expect(try store.load(accountID: "alice")?.attempt == original)
        #expect(throws: UserFacingError.self) { try store.clear(accountID: "alice") }
        #expect(try store.load(accountID: "alice")?.attempt == original)
    }

    @Test func unreadableArchiveIsNotErasedOrOverwritten() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let broken = Data("broken recovery record".utf8)
        defaults.set(broken, forKey: PlaylistRecoveryStore.storageKey)
        let store = PlaylistRecoveryStore(defaults: defaults)
        #expect(throws: UserFacingError.self) { try store.load(accountID: "alice") }
        #expect(throws: UserFacingError.self) { try store.saveAttempt(attempt()) }
        #expect(throws: UserFacingError.self) { try store.clear(accountID: "alice") }
        #expect(defaults.data(forKey: PlaylistRecoveryStore.storageKey) == broken)
    }

    @Test func failedMigrationPreservesLegacyEvidence() throws {
        let suite = UUID().uuidString
        let defaults = FailingRecoveryDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = attempt()
        let data = try JSONEncoder().encode(original)
        defaults.set(data, forKey: "pendingPlaylistCreation")
        defaults.failsSynchronization = true
        #expect(throws: UserFacingError.self) { try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice") }
        #expect(defaults.data(forKey: "pendingPlaylistCreation") == data)
        #expect(defaults.object(forKey: PlaylistRecoveryStore.storageKey) == nil)
    }
}
