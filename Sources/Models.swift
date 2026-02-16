import AppKit
import Foundation

struct Volume: Identifiable, Hashable {
    let url: URL
    let name: String
    let isRemovable: Bool
    let isInternal: Bool
    let capacity: Int64?

    var id: String { url.path }

    var displayName: String {
        name.isEmpty ? url.lastPathComponent : name
    }

    var subtitle: String {
        let kind = isRemovable ? "Removable" : "Built-in"
        if let capacity {
            return "\(kind) • \(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file))"
        }
        return kind
    }

    var iconName: String {
        isRemovable ? "externaldrive" : "internaldrive"
    }

    var isLikelyCameraCard: Bool {
        isRemovable && url.path.hasPrefix("/Volumes/")
    }

    var importRoot: URL? {
        let dcim = url.appending(path: "DCIM", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: dcim.path, isDirectory: nil) {
            return dcim
        }
        return url
    }

    static func from(url: URL) -> Volume? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeTotalCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        return Volume(
            url: url,
            name: values.volumeName ?? url.lastPathComponent,
            isRemovable: values.volumeIsRemovable ?? false,
            isInternal: values.volumeIsInternal ?? false,
            capacity: values.volumeTotalCapacity.map { Int64($0) }
        )
    }

    static func fetchMountedVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeTotalCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(Volume.from)
    }

    #if DEBUG
    static let mockVolumes: [Volume] = [
        Volume(url: URL(fileURLWithPath: "/Volumes/SD_CARD"), name: "SD_CARD", isRemovable: true, isInternal: false, capacity: 256_000_000_000),
        Volume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", isRemovable: false, isInternal: true, capacity: 1_000_000_000_000)
    ]
    #endif
}

struct PhotoAsset: Identifiable, Hashable {
    let url: URL
    let filename: String
    let captureDate: Date?
    let fileSize: Int64?

    var id: String { url.path }
}

enum PhotoTag: String, Codable, CaseIterable {
    case keep
    case reject

    var title: String {
        switch self {
        case .keep:
            return "Green"
        case .reject:
            return "Red"
        }
    }

    var symbolName: String {
        switch self {
        case .keep:
            return "checkmark.circle.fill"
        case .reject:
            return "xmark.circle.fill"
        }
    }
}

extension NSImage: @unchecked Sendable {}
