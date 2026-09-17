import Foundation

@MainActor
final class NotificationActionRouter {
    static let shared = NotificationActionRouter()
    private weak var store: VibeCastStore?
    private var queued: [(String, UUID)] = []

    func register(store: VibeCastStore) {
        self.store = store
        let pending = queued
        queued = []
        for (action, id) in pending { handle(actionIdentifier: action, recommendationID: id) }
    }

    func handle(actionIdentifier: String, recommendationID: UUID) {
        guard actionIdentifier == NotificationService.playAction || actionIdentifier == NotificationService.magicAction else { return }
        guard let store else {
            queued.append((actionIdentifier, recommendationID))
            return
        }
        Task { await store.handleNotification(actionIdentifier, id: recommendationID) }
    }
}
