import Foundation
import UniformTypeIdentifiers

actor PhotoEnumerator {
    private let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "arw", "cr2", "cr3", "nef", "raf", "rw2", "dng"
    ]
    private let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .typeIdentifierKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    func assets(at root: URL) -> [PhotoAsset] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }

        var assets: [PhotoAsset] = []
        for case let fileURL as URL in enumerator {
            guard shouldInclude(url: fileURL) else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)), values.isRegularFile == true else {
                continue
            }
            let asset = PhotoAsset(
                url: fileURL,
                filename: fileURL.lastPathComponent,
                captureDate: values.contentModificationDate,
                fileSize: values.fileSize.flatMap { Int64($0) }
            )
            assets.append(asset)
        }

        return assets.sorted { (lhs, rhs) in
            let leftDate = lhs.captureDate ?? .distantPast
            let rightDate = rhs.captureDate ?? .distantPast
            return leftDate > rightDate
        }
    }

    private func shouldInclude(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if allowedExtensions.contains(ext) {
            return true
        }
        if let identifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let type = UTType(identifier),
           type.conforms(to: .image) {
            return true
        }
        return false
    }
}
