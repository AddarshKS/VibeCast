import Foundation

@MainActor
final class SpotifyCallbackRouter {
    static let shared = SpotifyCallbackRouter()

    private var store: VibeCastStore?
    private var pendingURL: URL?

    private init() {}

    func register(store: VibeCastStore) {
        self.store = store
        if let pendingURL {
            self.pendingURL = nil
            handle(url: pendingURL)
        }
    }

    func handle(url: URL) {
        guard let store else {
            pendingURL = url
            return
        }

        Task {
            await store.handleSpotifyCallback(url)
        }
    }
}
