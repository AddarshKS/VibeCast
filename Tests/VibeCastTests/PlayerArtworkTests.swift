import AppKit
import ImageIO
import SwiftUI
import Testing
@testable import VibeCast

@MainActor
@Suite(.serialized)
struct PlayerArtworkTests {
    private func fixture() -> (PlayerArtworkCache, URLSession, URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlayerArtworkProtocol.self]
        let session = URLSession(configuration: configuration)
        return (PlayerArtworkCache(session: session), session,
                URL(string: "https://artwork-cache.vibecast.test/\(UUID().uuidString)")!)
    }

    @Test func overlappingScreensShareOneFetchAndDecodedImage() async throws {
        let (cache, session, url) = fixture()
        defer { session.invalidateAndCancel() }
        #expect(cache.cachedImage(for: url) == nil)
        let first = Task { await cache.image(for: url) }
        let second = Task { await cache.image(for: url) }
        let image = try #require(await first.value)
        #expect(await second.value === image)
        #expect(cache.cachedImage(for: url) === image)
        #expect(await cache.image(for: url) === image)
        #expect(PlayerArtworkProtocol.readCount(url) == 1)
    }

    @Test func disappearingScreenDoesNotCancelDestinationArtwork() async throws {
        let (cache, session, url) = fixture()
        defer { session.invalidateAndCancel() }
        let outgoing = Task { await cache.image(for: url) }
        await Task.yield()
        outgoing.cancel()
        let incoming = try #require(await cache.image(for: url))
        #expect(await outgoing.value === incoming)
        #expect(PlayerArtworkProtocol.readCount(url) == 1)
    }

    @Test func failedImagesAreNotCachedAndOtherURLsNeverReuseOldArtwork() async {
        let (cache, session, url) = fixture()
        defer { session.invalidateAndCancel() }
        for suffix in ["forbidden", "invalid"] {
            let failed = url.appendingPathComponent(suffix)
            #expect(await cache.image(for: failed) == nil)
            #expect(cache.cachedImage(for: failed) == nil)
            #expect(await cache.image(for: failed) == nil)
            #expect(PlayerArtworkProtocol.readCount(failed) == 2)
        }
        _ = await cache.image(for: url)
        #expect(cache.cachedImage(for: url.appendingPathComponent("different-song")) == nil)
        let insecure = URL(string: "http://artwork-cache.vibecast.test/cover")!
        #expect(await cache.image(for: insecure) == nil)
        #expect(PlayerArtworkProtocol.readCount(insecure) == 0)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func firstFrameOfNewArtworkViewsNeverShowsAWarmCachePlaceholder() async throws {
        _ = NSApplication.shared
        let (cache, session, url) = fixture()
        defer { session.invalidateAndCancel() }
        _ = try #require(await cache.image(for: url))
        for _ in 0..<4 {
            let host = NSHostingView(rootView: PlayerArtwork(url: url, cache: cache) { image in
                if let image { image.resizable() } else { Color.red }
            }.frame(width: 64, height: 64))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 64, height: 64),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            // No sleep or asynchronous load before checking the first displayed frame.
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let pixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            #expect(pixel.blueComponent > 0.8 && pixel.redComponent < 0.2)
        }
        #expect(PlayerArtworkProtocol.readCount(url) == 1)
    }
}

private final class PlayerArtworkProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var reads: [URL: Int] = [:]

    static func readCount(_ url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return reads[url, default: 0]
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "artwork-cache.vibecast.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.reads[url, default: 0] += 1
        Self.lock.unlock()
        let data = NSMutableData()
        if url.lastPathComponent != "invalid",
           let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            if let image = context.makeImage(),
               let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url,
            statusCode: url.lastPathComponent == "forbidden" ? 403 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "image/png"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data as Data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
