import Foundation

struct PendingPlaylistRecommendation: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case pending, accepted, superseded }
    var id = UUID()
    let accountID: String
    let originalPrompt: String
    let playlist: SpotifyResolvedPlaylist
    let searchPhrase: String
    var createdAt = Date()
    var status: Status = .pending

    func isActionable(accountID: String, now: Date = .now) -> Bool {
        self.accountID == accountID && status == .pending && now >= createdAt
            && now.timeIntervalSince(createdAt) < AppConfig.recommendationLifetime
    }
}

@MainActor
final class RecommendationStore {
    private let defaults: UserDefaults
    private let key = "pendingRecommendations.v2"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [PendingPlaylistRecommendation] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([PendingPlaylistRecommendation].self, from: data) else {
            clear()
            return []
        }
        let now = Date()
        let current = Array(values.filter {
            now >= $0.createdAt && now.timeIntervalSince($0.createdAt) < AppConfig.recommendationLifetime
        }.suffix(10))
        save(current)
        return current
    }
    func save(_ values: [PendingPlaylistRecommendation]) {
        guard !values.isEmpty else { clear(); return }
        if let data = try? JSONEncoder().encode(Array(values.suffix(10))) { defaults.set(data, forKey: key) }
    }
    func clear() { defaults.removeObject(forKey: key) }
}
