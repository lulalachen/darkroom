import Foundation

struct LibraryPaths {
    let root: URL
    let originalsRoot: URL
    let previewsRoot: URL
    let manifestsRoot: URL
    let importDatabaseURL: URL
}

struct LibraryManifest: Codable {
    let version: Int
    let createdAt: Date
}

actor LibraryManager {
    static let shared = LibraryManager()

    private let fileManager = FileManager.default
    private let schemaVersion = 1

    func bootstrapIfNeeded() throws -> LibraryPaths {
        let paths = defaultPaths()

        try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.originalsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.previewsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.manifestsRoot, withIntermediateDirectories: true)
        try ensureManifest(in: paths.manifestsRoot)

        return paths
    }

    private func defaultPaths() -> LibraryPaths {
        let picturesDirectory = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Pictures", directoryHint: .isDirectory)
        let root = picturesDirectory.appending(path: "DarkroomLibrary.darkroom", directoryHint: .isDirectory)
        return LibraryPaths(
            root: root,
            originalsRoot: root.appending(path: "Originals", directoryHint: .isDirectory),
            previewsRoot: root.appending(path: "Previews", directoryHint: .isDirectory),
            manifestsRoot: root.appending(path: "Manifests", directoryHint: .isDirectory),
            importDatabaseURL: root
                .appending(path: "Manifests", directoryHint: .isDirectory)
                .appending(path: "imports.sqlite3", directoryHint: .notDirectory)
        )
    }

    private func ensureManifest(in manifestsRoot: URL) throws {
        let manifestURL = manifestsRoot.appending(path: "library.json", directoryHint: .notDirectory)
        guard !fileManager.fileExists(atPath: manifestURL.path) else {
            return
        }

        let manifest = LibraryManifest(version: schemaVersion, createdAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
    }
}
