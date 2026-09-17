import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import VibeCast

struct ArtworkPaletteTests {
    @Test func invalidArtworkFallsBackWithoutAnAccent() {
        #expect(ArtworkPalette.extract(from: Data("invalid".utf8)) == nil)
    }

    @Test func extractionKeepsTheCoversDominantColor() throws {
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let color = try #require(ArtworkPalette.extract(from: data as Data))
        #expect(color.red > 0.7 && color.green < 0.3 && color.blue < 0.2)
        #expect(ArtworkPalette.extract(from: data as Data) == color)
    }
}
