import CoreGraphics
import Foundation
import ImageIO

struct ArtworkTint: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

// Decode a thumbnail off the main actor, not a full-resolution cover every render.
actor ArtworkPalette {
    static let shared = ArtworkPalette()
    private var cache: [URL: ArtworkTint] = [:]
    private var order: [URL] = []

    func tint(for url: URL) async -> ArtworkTint? {
        guard url.scheme == "https" else { return nil }
        if let cached = cache[url] { return cached }
        do {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 5_000_000, let tint = Self.extract(from: data) else { return nil }
            if cache[url] == nil { order.append(url) }
            cache[url] = tint
            if order.count > 16 { cache.removeValue(forKey: order.removeFirst()) }
            return tint
        } catch { return nil }
    }

    nonisolated static func extract(from data: Data) -> ArtworkTint? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32,
                                          bitsPerComponent: 8, bytesPerRow: 128,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        guard drawn else { return nil }
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let saturation = max(r, g, b) - min(r, g, b)
            let w = 0.15 + saturation
            red += r * w; green += g * w; blue += b * w; weight += w
        }
        guard weight > 0 else { return nil }
        return ArtworkTint(red: red / weight, green: green / weight, blue: blue / weight)
    }
}
