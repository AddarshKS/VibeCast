import AppKit

enum AppResources {
    static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("VibeCast_VibeCast.bundle")) {
            return bundle
        }
        return Bundle.module
    }()
}

enum ResourceImage {
    static let brandLogoName = "MenuBarAppIcon"

    static let menuBarSymbol: NSImage = {
        guard let source = named(brandLogoName),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let mask = templateMask(cg) else {
            return NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "VibeCast")!
        }
        let size = NSSize(width: (18 * Double(mask.width) / Double(mask.height)).rounded(), height: 18)
        let image = NSImage(size: size)
        for scale in [1, 2] {
            guard let bitmap = menuBarBitmap(mask, size: size, scale: scale) else { continue }
            image.addRepresentation(bitmap)
        }
        guard !image.representations.isEmpty else {
            return NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "VibeCast")!
        }
        image.isTemplate = true
        return image
    }()

    // Strengthen coverage after downsampling, where the fine rings would otherwise
    // become translucent. Separate 1x/2x rasters avoid a second lossy scaling pass.
    private static func menuBarBitmap(_ mask: CGImage, size: NSSize, scale: Int) -> NSBitmapImageRep? {
        let width = Int(size.width) * scale, height = Int(size.height) * scale
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            for i in stride(from: 3, to: data.count, by: 4) {
                data[i] = UInt8(min(255, Int(data[i]) * 2))
            }
            guard let raster = context.makeImage() else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: raster)
            bitmap.size = size
            return bitmap
        }
    }

    // The supplied artwork has a black background, not transparency. Turn its
    // monochrome ink into an alpha mask and trim padding without stretching it.
    static func templateMask(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            var minX = width, minY = height, maxX = 0, maxY = 0
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let luminance = (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / 3
                    let alpha = UInt8(max(0, min(255, (luminance - 40) * 255 / 215)))
                    data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = alpha
                    if alpha > 32 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
                }
            }
            guard minX < maxX, minY < maxY, let mask = context.makeImage() else { return nil }
            return mask.cropping(to: CGRect(x: max(0, minX - 8), y: max(0, minY - 8),
                                            width: min(width - max(0, minX - 8), maxX - minX + 17),
                                            height: min(height - max(0, minY - 8), maxY - minY + 17)))
        }
    }

    static func named(_ name: String, extension fileExtension: String = "png") -> NSImage? {
        guard let url = AppResources.bundle.url(forResource: name, withExtension: fileExtension) else { return nil }
        return NSImage(contentsOf: url)
    }
}
