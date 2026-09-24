import Foundation

/// A single persisted value makes the transition from uncertain creation to a known
/// playlist atomic. Records survive sign-out and remain isolated by Spotify account.
@MainActor
final class PlaylistRecoveryStore {
    static let storageKey = "playlistRecoveryByAccount"

    enum Record: Codable, Equatable {
        case creating(PlaylistCreationAttempt)
        case populating(PlaylistDraft)

        var attempt: PlaylistCreationAttempt? {
            if case .creating(let attempt) = self { return attempt }
            return nil
        }
        var draft: PlaylistDraft? {
            if case .populating(let draft) = self { return draft }
            return nil
        }
        fileprivate var accountID: String {
            switch self {
            case .creating(let attempt): attempt.accountID
            case .populating(let draft): draft.accountID
            }
        }
        fileprivate var createdAt: Date {
            switch self {
            case .creating(let attempt): attempt.createdAt
            case .populating(let draft): draft.createdAt
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(accountID: String) throws -> Record? {
        try records()[accountID]
    }

    func saveAttempt(_ attempt: PlaylistCreationAttempt) throws {
        try save(.creating(attempt))
    }

    func saveDraft(_ draft: PlaylistDraft) throws {
        try save(.populating(draft))
    }

    func clear(accountID: String) throws {
        var values = try records()
        values.removeValue(forKey: accountID)
        try persist(values)
    }

    private func save(_ record: Record) throws {
        guard !record.accountID.isEmpty else { throw unreadableRecord() }
        var values = try records()
        values[record.accountID] = record
        try persist(values)
    }

    private func records() throws -> [String: Record] {
        if let data = defaults.data(forKey: Self.storageKey) {
            guard let values = try? JSONDecoder().decode([String: Record].self, from: data),
                  values.allSatisfy({ !$0.key.isEmpty && $0.key == $0.value.accountID }) else {
                // Never erase an unreadable journal and silently allow a fresh create.
                throw unreadableRecord()
            }
            return values
        }
        if defaults.object(forKey: Self.storageKey) != nil { throw unreadableRecord() }

        var values: [String: Record] = [:]
        if let data = defaults.data(forKey: "pendingPlaylistCreation") {
            guard let attempt = try? JSONDecoder().decode(PlaylistCreationAttempt.self, from: data),
                  !attempt.accountID.isEmpty else { throw unreadableRecord() }
            values[attempt.accountID] = .creating(attempt)
        } else if defaults.object(forKey: "pendingPlaylistCreation") != nil {
            throw unreadableRecord()
        }
        if let data = defaults.data(forKey: "unfinishedPlaylist") {
            guard let draft = try? JSONDecoder().decode(PlaylistDraft.self, from: data),
                  !draft.accountID.isEmpty else { throw unreadableRecord() }
            // A saved draft normally follows its creation attempt. If the legacy keys
            // contain separate requests, keep the newest one for that account.
            if values[draft.accountID].map({ $0.createdAt <= draft.createdAt }) ?? true {
                values[draft.accountID] = .populating(draft)
            }
        } else if defaults.object(forKey: "unfinishedPlaylist") != nil {
            throw unreadableRecord()
        }
        // Even an empty archive records completed migration. Stale legacy keys after
        // an interrupted cleanup must never resurrect an explicitly cleared record.
        try persist(values)
        defaults.removeObject(forKey: "pendingPlaylistCreation")
        defaults.removeObject(forKey: "unfinishedPlaylist")
        _ = defaults.synchronize()
        return values
    }

    private func persist(_ values: [String: Record]) throws {
        let data = try JSONEncoder().encode(values)
        let previous = defaults.object(forKey: Self.storageKey)
        defaults.set(data, forKey: Self.storageKey)
        guard defaults.synchronize() else {
            if let previous { defaults.set(previous, forKey: Self.storageKey) }
            else { defaults.removeObject(forKey: Self.storageKey) }
            _ = defaults.synchronize()
            throw UserFacingError("The playlist recovery record couldn't be saved. Keep this request and try again before making another playlist.")
        }
    }

    private func unreadableRecord() -> UserFacingError {
        UserFacingError("The saved playlist recovery record couldn't be read. Check your Spotify library before starting another playlist.")
    }
}
