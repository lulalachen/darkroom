import Foundation
import CryptoKit

enum ImportError: Error {
    case noMarkedPhotos
}

actor ImportManager {
    private let fileManager = FileManager.default
    private let libraryManager: LibraryManager
    private let previewGenerator: PreviewGenerator
    private let metadataWriter: MetadataWriter
    private let generatesPreviews: Bool
    private var cachedLibraryPaths: LibraryPaths?
    private var importStore: ImportStore?

    init(
        libraryManager: LibraryManager = .shared,
        previewGenerator: PreviewGenerator = .shared,
        metadataWriter: MetadataWriter = .shared,
        generatesPreviews: Bool = true
    ) {
        self.libraryManager = libraryManager
        self.previewGenerator = previewGenerator
        self.metadataWriter = metadataWriter
        self.generatesPreviews = generatesPreviews
    }

    func importAssets(
        _ assets: [PhotoAsset],
        sourceVolume: Volume?,
        options: ImportOptions = .default,
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
            requestedCount: assets.count,
            options: options
        )
        try await store.enqueueItems(sessionID: sessionID, assets: assets, sourceRoot: sourceRoot)
        try await processSession(sessionID: sessionID, paths: paths, options: options, progress: progress)
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
            let options = ImportOptions(
                renameTemplate: ImportRenameTemplate(rawValue: session.renameTemplate) ?? .original,
                customPrefix: session.customPrefix,
                destinationCollection: "",
                exportBasePath: "",
                exportFolderName: session.destinationCollection,
                metadata: ImportMetadataTweaks(creator: "", keywords: "", note: session.metadataNote)
            )
            try await processSession(sessionID: session.id, paths: paths, options: options, progress: progress)
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

    func importedAssetSourcePaths(for assets: [PhotoAsset], sourceRoot: URL) async throws -> Set<String> {
        let (_, store) = try await bootstrapStore()
        let fingerprints = try assets.map { try fingerprint(for: $0.url, relativePath: relativePath(for: $0.url, root: sourceRoot)) }
        let matched = try await store.sourcePathsAlreadyImported(for: fingerprints)
        var imported: Set<String> = []
        for asset in assets {
            let fp = try fingerprint(for: asset.url, relativePath: relativePath(for: asset.url, root: sourceRoot))
            if matched.contains(fp) {
                imported.insert(asset.url.path)
            }
        }
        return imported
    }

    func retryFailedItems(from sessionID: Int64, libraryRootOverride: URL? = nil) async throws -> ImportRunResult {
        let (_, store) = try await bootstrapStore(overrideRoot: libraryRootOverride)
        let failedItems = try await store.failedItems(for: sessionID)
        let session = try await store.sessionSummary(sessionID: sessionID)
        let assets = failedItems
            .map { PhotoAsset(url: URL(fileURLWithPath: $0.sourcePath), filename: $0.filename, captureDate: nil, fileSize: nil) }
        let sourceVolume = Volume(url: URL(fileURLWithPath: session.sourceVolumePath), name: session.sourceVolumeName, isRemovable: true, isInternal: false, capacity: nil)
        let options = ImportOptions(
            renameTemplate: ImportRenameTemplate(rawValue: session.renameTemplate) ?? .original,
            customPrefix: session.customPrefix,
            destinationCollection: "",
            exportBasePath: "",
            exportFolderName: session.destinationCollection,
            metadata: ImportMetadataTweaks(creator: "", keywords: "", note: session.metadataNote)
        )
        return try await importAssets(assets, sourceVolume: sourceVolume, options: options)
    }

    private func processSession(
        sessionID: Int64,
        paths: LibraryPaths,
        options: ImportOptions = .default,
        progress: (@Sendable (ImportProgressSnapshot) -> Void)?
    ) async throws {
        guard let store = importStore else {
            throw ImportFailure(message: "Import store unavailable.")
        }
        let items = try await store.pendingItems(for: sessionID)
        let destinationRoot = datedImportFolder(root: exportRoot(for: options, defaultRoot: paths.originalsRoot))
        var didCreateDestinationDirectory = false

        for (index, item) in items.enumerated() {
            do {
                try await store.markItemState(itemID: item.id, state: .hashing, errorMessage: nil)
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.hashing)))
                let sourceURL = URL(fileURLWithPath: item.sourcePath)
                let sourceHash = try sha256(of: sourceURL)
                let sourceFingerprint = try fingerprint(for: sourceURL, relativePath: item.sourceRelativePath)

                if try await store.hasAsset(contentHash: sourceHash, sourceFingerprint: sourceFingerprint) {
                    try await store.recordDuplicateItem(sessionID: sessionID, itemID: item.id, contentHash: sourceHash)
                    progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.skippedDuplicate, hash: sourceHash)))
                    continue
                }

                try await store.markItemState(itemID: item.id, state: .copying, contentHash: sourceHash)
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.copying, hash: sourceHash)))

                let destinationFilename = resolvedFilename(
                    originalFilename: item.filename,
                    options: options,
                    sequenceIndex: index + 1
                )
                if !didCreateDestinationDirectory {
                    try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true, attributes: nil)
                    didCreateDestinationDirectory = true
                }
                let destinationURL = uniqueDestination(for: destinationFilename, in: destinationRoot)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)

                try await store.markItemState(itemID: item.id, state: .verifying, destinationPath: destinationURL.path)
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.verifying, destinationPath: destinationURL.path, hash: sourceHash)))

                let destinationHash = try sha256(of: destinationURL)
                guard destinationHash == sourceHash else {
                    throw ImportFailure(message: "Checksum mismatch after copy.")
                }

                try await store.recordSuccessfulImport(
                    sessionID: sessionID,
                    itemID: item.id,
                    sourceFingerprint: sourceFingerprint,
                    contentHash: sourceHash,
                    originalPath: destinationURL.path,
                    filename: item.filename
                )
                _ = try await metadataWriter.applyTweaks(
                    options.metadata,
                    destinationURL: destinationURL,
                    contentHash: sourceHash,
                    manifestsRoot: paths.manifestsRoot
                )
                if generatesPreviews {
                    await previewGenerator.generatePreviews(
                        for: destinationURL,
                        contentHash: sourceHash,
                        destinationRoot: paths.previewsRoot
                    )
                }
                progress?(ImportProgressSnapshot(sessionID: sessionID, item: item.withState(.done, destinationPath: destinationURL.path, hash: sourceHash)))
            } catch {
                let message = (error as? ImportFailure)?.message ?? error.localizedDescription
                try await store.recordFailedItem(sessionID: sessionID, itemID: item.id, message: message)
                progress?(
                    ImportProgressSnapshot(
                        sessionID: sessionID,
                        item: item.withState(.failed, errorMessage: message)
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
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        return root.appending(path: day, directoryHint: .isDirectory)
    }

    private func exportRoot(for options: ImportOptions, defaultRoot: URL) -> URL {
        let basePath = options.exportBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = options.exportFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !basePath.isEmpty, !folderName.isEmpty else {
            return defaultRoot
        }
        return URL(fileURLWithPath: basePath, isDirectory: true)
            .appending(path: sanitizedPathComponent(folderName), directoryHint: .isDirectory)
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

    private func resolvedFilename(originalFilename: String, options: ImportOptions, sequenceIndex: Int) -> String {
        let ext = (originalFilename as NSString).pathExtension
        let base = (originalFilename as NSString).deletingPathExtension
        let stamp = dateStamp()

        let resolvedBase: String
        switch options.renameTemplate {
        case .original:
            resolvedBase = base
        case .dateSequence:
            resolvedBase = "\(stamp)-\(String(format: "%04d", sequenceIndex))"
        case .customPrefix:
            let prefix = options.customPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.isEmpty {
                resolvedBase = base
            } else {
                resolvedBase = "\(sanitizedPathComponent(prefix))-\(String(format: "%04d", sequenceIndex))"
            }
        }

        if ext.isEmpty {
            return resolvedBase
        }
        return "\(resolvedBase).\(ext)"
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private func sanitizedPathComponent(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = raw.components(separatedBy: invalid).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-")
        return joined.isEmpty ? "Untitled" : joined
    }

    private func fingerprint(for url: URL, relativePath: String) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values.fileSize ?? 0)
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(relativePath)|\(size)|\(Int64(modified))"
    }

    private func relativePath(for fileURL: URL, root: URL) -> String {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        if fileComponents.starts(with: rootComponents) {
            return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
        }
        return fileURL.lastPathComponent
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
