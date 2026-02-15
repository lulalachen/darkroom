import AppKit
import QuickLookThumbnailing

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var storage: [URL: NSImage] = [:]
    private let generator = QLThumbnailGenerator.shared

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        if let cached = storage[url] {
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
        return nsImage
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
