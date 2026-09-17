import SwiftUI

struct PlayerArtwork<Content: View>: View {
    let url: URL?
    var cache: PlayerArtworkCache = .shared
    @ViewBuilder var content: (Image?) -> Content
    @State private var loaded: (url: URL, image: NSImage)?

    var body: some View {
        let image = url.flatMap { url in
            loaded?.url == url ? loaded?.image : cache.cachedImage(for: url)
        }
        // Consult the decoded cache during the first render, not in an async task
        // after a placeholder has already flashed inside the ripple.
        content(image.map { Image(nsImage: $0) })
            .task(id: url) {
                guard let url, let image = await cache.image(for: url), !Task.isCancelled else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { loaded = (url, image) }
            }
    }
}
