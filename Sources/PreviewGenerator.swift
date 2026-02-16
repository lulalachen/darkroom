import AppKit
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

actor PreviewGenerator {
    static let shared = PreviewGenerator()
    private let generator = QLThumbnailGenerator.shared

    func generatePreviews(for sourceURL: URL, contentHash: String, destinationRoot: URL) async {
        let sizes: [CGFloat] = [512, 2048]
        for size in sizes {
            let request = QLThumbnailGenerator.Request(
                fileAt: sourceURL,
                size: CGSize(width: size, height: size),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            guard let representation = try? await bestRepresentation(for: request) else {
                continue
            }
            let outputURL = destinationRoot
                .appending(path: "\(contentHash)-\(Int(size)).jpg", directoryHint: .notDirectory)
            _ = writeJPEG(image: representation.nsImage, to: outputURL)
        }
    }

    private func bestRepresentation(for request: QLThumbnailGenerator.Request) async throws -> QLThumbnailRepresentation {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateBestRepresentation(for: request) { representation, error in
                if let representation {
                    continuation.resume(returning: representation)
                } else {
                    continuation.resume(throwing: error ?? ImportFailure(message: "Thumbnail generation failed."))
                }
            }
        }
    }

    private func writeJPEG(image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}

