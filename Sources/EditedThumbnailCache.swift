import AppKit
import Foundation

actor EditedThumbnailCache {
    static let shared = EditedThumbnailCache()

    private struct CacheKey: Hashable {
        let assetPath: String
        let settings: AdjustmentSettings
    }

    private var storage: [CacheKey: NSImage] = [:]
    private var access: [CacheKey: Int] = [:]
    private var accessTick = 0
    private var maxEntries = 256

    func thumbnail(for assetPath: String, baseImage: NSImage, settings: AdjustmentSettings) async -> NSImage? {
        guard settings != .default else {
            return baseImage
        }

        let key = CacheKey(assetPath: assetPath, settings: settings)
        if let cached = storage[key] {
            touch(key)
            return cached
        }

        guard let edited = await AdjustmentEngine.shared.apply(settings, to: baseImage) else {
            return baseImage
        }

        storage[key] = edited
        touch(key)
        evictIfNeeded()
        return edited
    }

    func invalidate(assetPath: String) {
        let keys = storage.keys.filter { $0.assetPath == assetPath }
        for key in keys {
            storage.removeValue(forKey: key)
            access.removeValue(forKey: key)
        }
    }

    func configure(maxEntries: Int) {
        self.maxEntries = max(64, maxEntries)
        evictIfNeeded()
    }

    func clear() {
        storage.removeAll(keepingCapacity: false)
        access.removeAll(keepingCapacity: false)
        accessTick = 0
    }

    private func touch(_ key: CacheKey) {
        accessTick += 1
        access[key] = accessTick
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
