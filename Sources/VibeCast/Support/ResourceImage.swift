import AppKit

enum ResourceImage {
    static func named(_ name: String, extension fileExtension: String = "png") -> NSImage? {
        if let image = NSImage(named: name) {
            return image
        }

        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}
