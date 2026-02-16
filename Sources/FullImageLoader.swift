import AppKit
import Foundation

actor FullImageLoader {
    static let shared = FullImageLoader()

    private var storage: [URL: NSImage] = [:]

    func image(for url: URL) -> NSImage? {
        if let cached = storage[url] {
            return cached
        }

        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        storage[url] = image
        return image
    }
}
