import Foundation
import XCTest
@testable import darkroom

final class ImportManagerTests: XCTestCase {
    func testImportHandlesFilenameCollisions() async throws {
        let sandbox = try makeSandbox(name: "collision")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        let folderA = sourceRoot.appending(path: "A", directoryHint: .isDirectory)
        let folderB = sourceRoot.appending(path: "B", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

        let fileA = folderA.appending(path: "image.jpg", directoryHint: .notDirectory)
        let fileB = folderB.appending(path: "image.jpg", directoryHint: .notDirectory)
        try Data("one".utf8).write(to: fileA)
        try Data("two".utf8).write(to: fileB)

        let assets = [asset(fileA), asset(fileB)]
        let libraryRoot = sandbox.appending(path: "library", directoryHint: .isDirectory)
        let manager = ImportManager(generatesPreviews: false)

        let result = try await manager.importAssets(assets, sourceVolume: nil, libraryRootOverride: libraryRoot)

        XCTAssertEqual(result.session.importedCount, 2)
        let originals = try contentsRecursively(at: libraryRoot.appending(path: "Originals", directoryHint: .isDirectory))
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertTrue(originals.contains("image.jpg"))
        XCTAssertTrue(originals.contains("image-1.jpg"))
    }

    func testImportSkipsDuplicatesByContentHash() async throws {
        let sandbox = try makeSandbox(name: "duplicates")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let file = sourceRoot.appending(path: "same.raw", directoryHint: .notDirectory)
        try Data("raw-content".utf8).write(to: file)

        let libraryRoot = sandbox.appending(path: "library", directoryHint: .isDirectory)
        let manager = ImportManager(generatesPreviews: false)
        let first = try await manager.importAssets([asset(file)], sourceVolume: nil, libraryRootOverride: libraryRoot)
        let second = try await manager.importAssets([asset(file)], sourceVolume: nil, libraryRootOverride: libraryRoot)

        XCTAssertEqual(first.session.importedCount, 1)
        XCTAssertEqual(second.session.importedCount, 0)
        XCTAssertEqual(second.session.duplicateCount, 1)

        let originals = try contentsRecursively(at: libraryRoot.appending(path: "Originals", directoryHint: .isDirectory))
        XCTAssertEqual(originals.count, 1)
    }

    func testResumeProcessesQueuedItemsFromIncompleteSession() async throws {
        let sandbox = try makeSandbox(name: "resume")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let file = sourceRoot.appending(path: "queued.jpg", directoryHint: .notDirectory)
        try Data("queued-content".utf8).write(to: file)

        let libraryRoot = sandbox.appending(path: "library", directoryHint: .isDirectory)
        let manifestsRoot = libraryRoot.appending(path: "Manifests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: manifestsRoot, withIntermediateDirectories: true)
        let store = ImportStore(databaseURL: manifestsRoot.appending(path: "imports.sqlite3", directoryHint: .notDirectory))
        try await store.prepareSchema()
        let sessionID = try await store.createSession(sourceVolumePath: sourceRoot.path, sourceVolumeName: "TestVolume", requestedCount: 1)
        try await store.enqueueItems(sessionID: sessionID, assets: [asset(file)], sourceRoot: sourceRoot)

        let manager = ImportManager(generatesPreviews: false)
        let resumed = try await manager.resumeIncompleteImports(libraryRootOverride: libraryRoot)

        XCTAssertEqual(resumed.count, 1)
        XCTAssertEqual(resumed[0].session.id, sessionID)
        XCTAssertEqual(resumed[0].session.importedCount, 1)
        XCTAssertTrue(resumed[0].session.isCompleted)
    }

    private func asset(_ url: URL) -> PhotoAsset {
        PhotoAsset(
            url: url,
            filename: url.lastPathComponent,
            captureDate: Date(),
            fileSize: Int64((try? Data(contentsOf: url).count) ?? 0)
        )
    }

    private func makeSandbox(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "darkroom-tests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func contentsRecursively(at root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}

