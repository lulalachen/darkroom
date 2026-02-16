import AppKit
import Foundation

actor FullImageLoader {
    static let shared = FullImageLoader()

    private var storage: [URL: NSImage] = [:]
    private var access: [URL: Int] = [:]
    private var accessTick = 0
    private var maxEntries = 120

    func image(for url: URL) -> NSImage? {
        if let cached = storage[url] {
            touch(url)
            return cached
        }

        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        storage[url] = image
        touch(url)
        evictIfNeeded()
        return image
    }

    func configure(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
        evictIfNeeded()
    }

    func clear() {
        storage.removeAll(keepingCapacity: false)
        access.removeAll(keepingCapacity: false)
        accessTick = 0
    }

    func cachedCount() -> Int {
        storage.count
    }

    private func touch(_ url: URL) {
        accessTick += 1
        access[url] = accessTick
    }

    private func evictIfNeeded() {
        guard storage.count > maxEntries else { return }
        let overflow = storage.count - maxEntries
        let victims = access.sorted { $0.value < $1.value }.prefix(overflow).map(\.key)
        for key in victims {
            storage.removeValue(forKey: key)
            access.removeValue(forKey: key)
        }
    }
}
