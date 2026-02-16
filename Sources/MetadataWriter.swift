import Foundation
import ImageIO

enum MetadataWriteOutcome {
    case skipped
    case embedded
    case sidecar
}

struct MetadataTweaks: Codable, Hashable {
    var creator: String
    var keywords: String
    var note: String

    static let empty = MetadataTweaks(creator: "", keywords: "", note: "")
}

struct MetadataSidecarRecord: Codable {
    let createdAt: Date
    let destinationPath: String
    let contentHash: String
    let creator: String
    let keywords: [String]
    let note: String
    let embeddedWriteApplied: Bool
}

actor MetadataWriter {
    static let shared = MetadataWriter()

    private let fileManager = FileManager.default

    func applyTweaks(
        _ tweaks: MetadataTweaks,
        destinationURL: URL,
        contentHash: String,
        manifestsRoot: URL
    ) throws -> MetadataWriteOutcome {
        guard hasTweaks(tweaks) else {
            return .skipped
        }

        if try writeEmbeddedMetadata(tweaks, to: destinationURL) {
            return .embedded
        }

        try writeSidecarMetadata(tweaks, destinationURL: destinationURL, contentHash: contentHash, manifestsRoot: manifestsRoot)
        return .sidecar
    }

    private func hasTweaks(_ tweaks: MetadataTweaks) -> Bool {
        !tweaks.creator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !tweaks.keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !tweaks.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func writeEmbeddedMetadata(_ tweaks: MetadataTweaks, to url: URL) throws -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else {
            return false
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            return false
        }

        let tempURL = url.deletingPathExtension().appendingPathExtension("metadata-temp-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, sourceType, frameCount, nil) else {
            return false
        }

        for index in 0..<frameCount {
            let original = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let merged = mergedMetadata(original: original, tweaks: tweaks)
            CGImageDestinationAddImageFromSource(destination, source, index, merged as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            return false
        }

        try fileManager.removeItem(at: url)
        try fileManager.moveItem(at: tempURL, to: url)
        return true
    }

    private func mergedMetadata(original: [CFString: Any], tweaks: MetadataTweaks) -> [CFString: Any] {
        var result = original
        var iptc = (result[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) ?? [:]
        var exif = (result[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]

        let creator = tweaks.creator.trimmingCharacters(in: .whitespacesAndNewlines)
        if !creator.isEmpty {
            iptc[kCGImagePropertyIPTCByline] = creator
        }

        let keywords = tweaks.keywords
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !keywords.isEmpty {
            iptc[kCGImagePropertyIPTCKeywords] = keywords
        }

        let note = tweaks.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            iptc[kCGImagePropertyIPTCCaptionAbstract] = note
            exif[kCGImagePropertyExifUserComment] = note
        }

        result[kCGImagePropertyIPTCDictionary] = iptc
        result[kCGImagePropertyExifDictionary] = exif
        return result
    }

    private func writeSidecarMetadata(
        _ tweaks: MetadataTweaks,
        destinationURL: URL,
        contentHash: String,
        manifestsRoot: URL
    ) throws {
        let metadataRoot = manifestsRoot.appending(path: "Metadata", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: metadataRoot, withIntermediateDirectories: true)

        let record = MetadataSidecarRecord(
            createdAt: Date(),
            destinationPath: destinationURL.path,
            contentHash: contentHash,
            creator: tweaks.creator,
            keywords: tweaks.keywords
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            note: tweaks.note,
            embeddedWriteApplied: false
        )

        let outputURL = metadataRoot.appending(path: "\(contentHash).json", directoryHint: .notDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: outputURL, options: .atomic)
    }
}
