import AppKit
import QuickLookThumbnailing

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var storage: [URL: NSImage] = [:]
    private var access: [URL: Int] = [:]
    private var accessTick = 0
    private var maxEntries = 400
    private let generator = QLThumbnailGenerator.shared

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        if let cached = storage[url] {
            touch(url)
            return cached
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        guard let representation = try? await generateRepresentation(for: request) else {
            return nil
        }

        let nsImage = representation.nsImage
        storage[url] = nsImage
        touch(url)
        evictIfNeeded()
        return nsImage
    }

    func configure(maxEntries: Int) {
        self.maxEntries = max(32, maxEntries)
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


    private func generateRepresentation(for request: QLThumbnailGenerator.Request) async throws -> QLThumbnailRepresentation {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateBestRepresentation(for: request) { representation, error in
                if let representation {
                    continuation.resume(returning: representation)
                } else {
                    continuation.resume(throwing: error ?? ThumbnailError.failed)
                }
            }
        }
    }

    enum ThumbnailError: Error {
        case failed
    }
}
