import Foundation
import CryptoKit

enum ImportError: Error {
    case noMarkedPhotos
}

actor ImportManager {
    private let fileManager = FileManager.default
    private let libraryManager: LibraryManager
    private let previewGenerator: PreviewGenerator
    private let generatesPreviews: Bool
    private var cachedLibraryPaths: LibraryPaths?
    private var importStore: ImportStore?

    init(
        libraryManager: LibraryManager = .shared,
        previewGenerator: PreviewGenerator = .shared,
        generatesPreviews: Bool = true
    ) {
        self.libraryManager = libraryManager
        self.previewGenerator = previewGenerator
        self.generatesPreviews = generatesPreviews
    }

    func importAssets(
        _ assets: [PhotoAsset],
        sourceVolume: Volume?,
        libraryRootOverride: URL? = nil,
        progress: (@Sendable (ImportProgressSnapshot) -> Void)? = nil
    ) async throws -> ImportRunResult {
        guard !assets.isEmpty else {
            throw ImportError.noMarkedPhotos
        }

        let (paths, store) = try await bootstrapStore(overrideRoot: libraryRootOverride)
        let sourceRoot = sourceVolume?.importRoot ?? sourceVolume?.url ?? commonAncestor(for: assets.map(\.url))
        let sourceVolumePath = sourceVolume?.url.path ?? sourceRoot.path
        let sourceVolumeName = sourceVolume?.displayName ?? sourceRoot.lastPathComponent

        let sessionID = try await store.createSession(
            sourceVolumePath: sourceVolumePath,
            sourceVolumeName: sourceVolumeName,
            requestedCount: assets.count
        )
        try await store.enqueueItems(sessionID: sessionID, assets: assets, sourceRoot: sourceRoot)
        try await processSession(sessionID: sessionID, paths: paths, progress: progress)
        let summary = try await store.completeSessionIfFinished(sessionID: sessionID)
        return ImportRunResult(session: summary, destinationRoot: paths.originalsRoot)
    }

    func resumeIncompleteImports(
        libraryRootOverride: URL? = nil,
        progress: (@Sendable (ImportProgressSnapshot) -> Void)? = nil
    ) async throws -> [ImportRunResult] {
        let (paths, store) = try await bootstrapStore(overrideRoot: libraryRootOverride)
        let incomplete = try await store.incompleteSessions()
        var results: [ImportRunResult] = []
        for session in incomplete {
            try await processSession(sessionID: session.id, paths: paths, progress: progress)
            let summary = try await store.completeSessionIfFinished(sessionID: session.id)
            results.append(ImportRunResult(session: summary, destinationRoot: paths.originalsRoot))
        }
        return results
    }

    func recentSessions(limit: Int = 20) async throws -> [ImportSessionSummary] {
        let (_, store) = try await bootstrapStore()
        return try await store.recentSessions(limit: limit)
    }

    func sessionItems(sessionID: Int64) async throws -> [ImportQueueItem] {
        let (_, store) = try await bootstrapStore()
        return try await store.items(for: sessionID)
    }

    private func processSession(
        sessionID: Int64,
        paths: LibraryPaths,
        progress: (@Sendable (ImportProgressSnapshot) -> Void)?
    ) async throws {
        guard let store = importStore else {
            throw ImportFailure(message: "Import store unavailable.")
        }
        let items = try await store.pendingItems(for: sessionID)
        let destinationRoot = datedImportFolder(root: paths.originalsRoot)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true, attributes: nil)

        for item in items {
            do {
                try await store.markItemState(itemID: item.id, state: .hashing, errorMessage: nil)
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.hashing)))
                let sourceURL = URL(fileURLWithPath: item.sourcePath)
                let sourceHash = try sha256(of: sourceURL)
                let sourceFingerprint = try fingerprint(for: sourceURL, relativePath: item.sourceRelativePath)

                if try await store.hasAsset(contentHash: sourceHash, sourceFingerprint: sourceFingerprint) {
                    try await store.markItemState(itemID: item.id, state: .skippedDuplicate, contentHash: sourceHash)
                    try await store.updateSessionCounters(sessionID: sessionID, duplicateDelta: 1)
                    progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.skippedDuplicate, hash: sourceHash)))
                    continue
                }

                try await store.markItemState(itemID: item.id, state: .copying, contentHash: sourceHash)
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.copying, hash: sourceHash)))

                let destinationURL = uniqueDestination(for: item.filename, in: destinationRoot)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)

                try await store.markItemState(itemID: item.id, state: .verifying, destinationPath: destinationURL.path)
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.verifying, destinationPath: destinationURL.path, hash: sourceHash)))

                let destinationHash = try sha256(of: destinationURL)
                guard destinationHash == sourceHash else {
                    throw ImportFailure(message: "Checksum mismatch after copy.")
                }

                try await store.recordImportedAsset(
                    sourceFingerprint: sourceFingerprint,
                    contentHash: sourceHash,
                    originalPath: destinationURL.path,
                    filename: item.filename,
                    sessionID: sessionID
                )
                try await store.markItemState(itemID: item.id, state: .done, destinationPath: destinationURL.path, contentHash: sourceHash)
                try await store.updateSessionCounters(sessionID: sessionID, importedDelta: 1)
                if generatesPreviews {
                    await previewGenerator.generatePreviews(
                        for: destinationURL,
                        contentHash: sourceHash,
                        destinationRoot: paths.previewsRoot
                    )
                }
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.done, destinationPath: destinationURL.path, hash: sourceHash)))
            } catch {
                try await store.markItemState(
                    itemID: item.id,
                    state: .failed,
                    errorMessage: (error as? ImportFailure)?.message ?? error.localizedDescription
                )
                try await store.updateSessionCounters(sessionID: sessionID, failedDelta: 1)
                progress?(
                    ImportProgressSnapshot(
                        sessionID: sessionID,
                        item: item.withState(.failed, errorMessage: (error as? ImportFailure)?.message ?? error.localizedDescription)
                    )
                )
            }
        }
    }

    private func bootstrapStore(overrideRoot: URL? = nil) async throws -> (LibraryPaths, ImportStore) {
        if let overrideRoot {
            return try await bootstrapStoreForOverrideRoot(overrideRoot)
        }
        if let cachedLibraryPaths, let importStore {
            return (cachedLibraryPaths, importStore)
        }
        let paths = try await libraryManager.bootstrapIfNeeded()
        let store = ImportStore(databaseURL: paths.importDatabaseURL)
        try await store.prepareSchema()
        cachedLibraryPaths = paths
        importStore = store
        return (paths, store)
    }

    private func bootstrapStoreForOverrideRoot(_ root: URL) async throws -> (LibraryPaths, ImportStore) {
        let originalsRoot = root.appending(path: "Originals", directoryHint: .isDirectory)
        let previewsRoot = root.appending(path: "Previews", directoryHint: .isDirectory)
        let manifestsRoot = root.appending(path: "Manifests", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: originalsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: previewsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: manifestsRoot, withIntermediateDirectories: true)

        let paths = LibraryPaths(
            root: root,
            originalsRoot: originalsRoot,
            previewsRoot: previewsRoot,
            manifestsRoot: manifestsRoot,
            importDatabaseURL: manifestsRoot.appending(path: "imports.sqlite3", directoryHint: .notDirectory)
        )
        let store = ImportStore(databaseURL: paths.importDatabaseURL)
        try await store.prepareSchema()
        cachedLibraryPaths = paths
        importStore = store
        return (paths, store)
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

    private func sha256(of url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ImportFailure(message: "Could not read source file.")
        }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fingerprint(for url: URL, relativePath: String) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values.fileSize ?? 0)
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(relativePath)|\(size)|\(Int64(modified))"
    }

    private func commonAncestor(for urls: [URL]) -> URL {
        let directoryURLs = urls.map { $0.deletingLastPathComponent() }
        guard var prefix = directoryURLs.first?.standardizedFileURL.pathComponents else {
            return URL(fileURLWithPath: "/")
        }
        for url in directoryURLs.dropFirst() {
            let comps = url.standardizedFileURL.pathComponents
            var i = 0
            while i < prefix.count && i < comps.count && prefix[i] == comps[i] {
                i += 1
            }
            prefix = Array(prefix.prefix(i))
            if prefix.isEmpty {
                return URL(fileURLWithPath: "/")
            }
        }
        let path = NSString.path(withComponents: prefix)
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

private extension ImportQueueItem {
    func withState(
        _ newState: ImportItemState,
        destinationPath: String? = nil,
        hash: String? = nil,
        errorMessage: String? = nil
    ) -> ImportQueueItem {
        ImportQueueItem(
            id: id,
            sessionID: sessionID,
            sourcePath: sourcePath,
            sourceRelativePath: sourceRelativePath,
            filename: filename,
            state: newState,
            destinationPath: destinationPath ?? self.destinationPath,
            contentHash: hash ?? contentHash,
            errorMessage: errorMessage ?? self.errorMessage,
            updatedAt: Date()
        )
    }
}
