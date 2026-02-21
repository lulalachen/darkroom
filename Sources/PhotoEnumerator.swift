import Foundation
import ImageIO
import UniformTypeIdentifiers

actor PhotoEnumerator {
    private let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "arw", "cr2", "cr3", "nef", "raf", "rw2", "dng"
    ]
    private let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .typeIdentifierKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey
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
                captureDate: preferredCaptureDate(for: fileURL, values: values),
                fileSize: values.fileSize.flatMap { Int64($0) }
            )
            assets.append(asset)
        }

        let calendar = Calendar.current
        return assets.sorted { lhs, rhs in
            switch (lhs.captureDate, rhs.captureDate) {
            case let (leftDate?, rightDate?):
                let leftDay = calendar.startOfDay(for: leftDate)
                let rightDay = calendar.startOfDay(for: rightDate)
                if leftDay != rightDay {
                    // Newer dates first.
                    return leftDay > rightDay
                }
                if leftDate != rightDate {
                    // Chronological order within each day.
                    return leftDate < rightDate
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
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

    private func preferredCaptureDate(for url: URL, values: URLResourceValues) -> Date? {
        if let metadataDate = metadataCaptureDate(for: url) {
            return metadataDate
        }
        return values.creationDate
    }

    private func metadataCaptureDate(for url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let date = parseMetadataDate(exif[kCGImagePropertyExifDateTimeOriginal]) {
                return date
            }
            if let date = parseMetadataDate(exif[kCGImagePropertyExifDateTimeDigitized]) {
                return date
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let date = parseMetadataDate(tiff[kCGImagePropertyTIFFDateTime]) {
            return date
        }
        return nil
    }

    private func parseMetadataDate(_ raw: Any?) -> Date? {
        if let date = raw as? Date {
            return date
        }
        guard let string = raw as? String else {
            return nil
        }

        for formatter in Self.metadataDateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        if #available(macOS 10.12, *) {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private static let metadataDateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy:MM:dd HH:mm:ss",
            "yyyy:MM:dd HH:mm:ssXXX",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssXXX"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            return formatter
        }
    }()
}
