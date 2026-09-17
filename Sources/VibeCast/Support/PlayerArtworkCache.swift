import AppKit
import ImageIO

@MainActor
final class PlayerArtworkCache {
    static let shared = PlayerArtworkCache()
    private let images = NSCache<NSURL, NSImage>()
    private var requests: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        images.countLimit = 20
        images.totalCostLimit = 40 * 1024 * 1024
    }

    func cachedImage(for url: URL) -> NSImage? { images.object(forKey: url as NSURL) }

    func image(for url: URL) async -> NSImage? {
        guard url.scheme == "https" else { return nil }
        if let image = cachedImage(for: url) { return image }
        if let request = requests[url] { return await request.value }
        let request = Task { [session] () -> NSImage? in
            // A screen disappearing must not cancel a fetch needed by the screen
            // being revealed. All player surfaces share the decoded cover.
            let decoded = await Task.detached(priority: .utility) {
                await Self.download(url, session: session)
            }.value
            guard let decoded else { return nil }
            let image = NSImage(cgImage: decoded, size: .zero)
            images.setObject(image, forKey: url as NSURL, cost: decoded.width * decoded.height * 4)
            return image
        }
        requests[url] = request
        let image = await request.value
        requests[url] = nil
        return image
    }

    private nonisolated static func download(_ url: URL, session: URLSession) async -> CGImage? {
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 5_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        } catch { return nil }
    }
}
