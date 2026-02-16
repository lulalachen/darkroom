import Foundation

struct ImportResult {
    let copiedCount: Int
    let destination: URL
}

enum ImportError: Error {
    case noMarkedPhotos
}

actor ImportManager {
    private let fileManager = FileManager.default

    func importAssets(_ assets: [PhotoAsset], into libraryRoot: URL? = nil) throws -> ImportResult {
        guard !assets.isEmpty else {
            throw ImportError.noMarkedPhotos
        }

        let root = libraryRoot ?? defaultLibraryRoot()
        let destinationRoot = datedImportFolder(root: root)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true, attributes: nil)

        var copiedCount = 0
        for asset in assets {
            let destinationURL = uniqueDestination(for: asset.filename, in: destinationRoot)
            try fileManager.copyItem(at: asset.url, to: destinationURL)
            copiedCount += 1
        }

        return ImportResult(copiedCount: copiedCount, destination: destinationRoot)
    }

    private func defaultLibraryRoot() -> URL {
        let picturesDirectory = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Pictures", directoryHint: .isDirectory)
        return picturesDirectory
            .appending(path: "DarkroomLibrary.darkroom", directoryHint: .isDirectory)
            .appending(path: "Originals", directoryHint: .isDirectory)
    }

    private func datedImportFolder(root: URL) -> URL {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: date)
        formatter.dateFormat = "MM"
        let month = formatter.string(from: date)
        return root.appending(path: year, directoryHint: .isDirectory)
            .appending(path: month, directoryHint: .isDirectory)
    }

    private func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        var index = 0
        while true {
            let candidateName: String
            if index == 0 {
                candidateName = filename
            } else if ext.isEmpty {
                candidateName = "\(base)-\(index)"
            } else {
                candidateName = "\(base)-\(index).\(ext)"
            }

            let candidate = directory.appending(path: candidateName, directoryHint: .notDirectory)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            index += 1
        }
    }
}
