import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import darkroom

final class ExportManagerTests: XCTestCase {
    func testRunQueueExportsFilesToResolvedFolder() async throws {
        let sandbox = try makeSandbox(name: "export-queue-basic")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        let file = sourceRoot.appending(path: "photo.jpg", directoryHint: .notDirectory)
        try Data("pixels".utf8).write(to: file)

        let item = ExportQueueItem(
            id: UUID(),
            asset: asset(file),
            state: .queued,
            destinationPath: nil,
            errorMessage: nil,
            warningMessage: nil,
            startedAt: nil,
            completedAt: nil,
            bytesWritten: nil
        )
        let destination = ExportDestinationOptions(
            basePath: sandbox.appending(path: "exports", directoryHint: .isDirectory).path,
            subfolderTemplate: "{date}-{shoot}",
            shootName: "Wedding"
        )
        let manager = ExportManager()

        let summary = try await manager.runQueue(
            items: [item],
            preset: ExportPreset(name: "Test", fileFormat: .original, longEdgePixels: 0, quality: 1.0),
            destination: destination
        )

        XCTAssertEqual(summary.queuedCount, 1)
        XCTAssertEqual(summary.exportedCount, 1)
        XCTAssertEqual(summary.failedCount, 0)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expectedFolder = sandbox
            .appending(path: "exports", directoryHint: .isDirectory)
            .appending(path: "\(formatter.string(from: Date()))-Wedding", directoryHint: .isDirectory)
        let exported = try contentsRecursively(at: expectedFolder)
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported.first?.lastPathComponent, "photo.jpg")
    }

    func testRunQueueAddsNumericSuffixOnCollision() async throws {
        let sandbox = try makeSandbox(name: "export-queue-collision")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        let first = sourceRoot.appending(path: "photo.jpg", directoryHint: .notDirectory)
        let secondFolder = sourceRoot.appending(path: "alt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let second = secondFolder.appending(path: "photo.jpg", directoryHint: .notDirectory)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let items = [
            ExportQueueItem(id: UUID(), asset: asset(first), state: .queued, destinationPath: nil, errorMessage: nil, warningMessage: nil, startedAt: nil, completedAt: nil, bytesWritten: nil),
            ExportQueueItem(id: UUID(), asset: asset(second), state: .queued, destinationPath: nil, errorMessage: nil, warningMessage: nil, startedAt: nil, completedAt: nil, bytesWritten: nil)
        ]
        let destination = ExportDestinationOptions(
            basePath: sandbox.appending(path: "exports", directoryHint: .isDirectory).path,
            subfolderTemplate: "delivery",
            shootName: "unused"
        )
        let manager = ExportManager()

        let summary = try await manager.runQueue(
            items: items,
            preset: ExportPreset(name: "Test", fileFormat: .original, longEdgePixels: 0, quality: 1.0),
            destination: destination
        )

        XCTAssertEqual(summary.exportedCount, 2)
        let exported = try contentsRecursively(
            at: sandbox
                .appending(path: "exports", directoryHint: .isDirectory)
                .appending(path: "delivery", directoryHint: .isDirectory)
        ).map(\.lastPathComponent).sorted()
        XCTAssertEqual(exported, ["photo-1.jpg", "photo.jpg"])
    }

    func testRunQueueEmitsWarningWhenTargetSizeCannotBeMet() async throws {
        let sandbox = try makeSandbox(name: "export-queue-size-warning")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        let file = sourceRoot.appending(path: "photo.jpg", directoryHint: .notDirectory)
        try makeJPEG(width: 2600, height: 1800).write(to: file)

        let item = ExportQueueItem(
            id: UUID(),
            asset: asset(file),
            state: .queued,
            destinationPath: nil,
            errorMessage: nil,
            warningMessage: nil,
            startedAt: nil,
            completedAt: nil,
            bytesWritten: nil
        )
        let destination = ExportDestinationOptions(
            basePath: sandbox.appending(path: "exports", directoryHint: .isDirectory).path,
            subfolderTemplate: "delivery",
            shootName: "unused"
        )
        let manager = ExportManager()
        let collector = WarningCollector()

        _ = try await manager.runQueue(
            items: [item],
            preset: ExportPreset(name: "Small", fileFormat: .jpeg, longEdgePixels: 0, quality: 0.95, maxFileSizeKB: 20),
            destination: destination
        ) { snapshot in
            if let warning = snapshot.warningMessage {
                Task { await collector.append(warning) }
            }
        }

        let messages = await collector.messages()
        XCTAssertFalse(messages.isEmpty)
    }

    func testRunQueuePreservesExifMetadataByDefault() async throws {
        let sandbox = try makeSandbox(name: "export-queue-metadata-preserve")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        let file = sourceRoot.appending(path: "photo.jpg", directoryHint: .notDirectory)
        try makeJPEGWithMetadata(
            width: 1800,
            height: 1200,
            lensModel: "XF35mmF1.4 R",
            dateTimeOriginal: "2026:02:16 09:10:11"
        ).write(to: file)

        let item = ExportQueueItem(
            id: UUID(),
            asset: asset(file),
            state: .queued,
            destinationPath: nil,
            errorMessage: nil,
            warningMessage: nil,
            startedAt: nil,
            completedAt: nil,
            bytesWritten: nil
        )
        let destination = ExportDestinationOptions(
            basePath: sandbox.appending(path: "exports", directoryHint: .isDirectory).path,
            subfolderTemplate: "delivery",
            shootName: "meta"
        )
        let manager = ExportManager()

        _ = try await manager.runQueue(
            items: [item],
            preset: ExportPreset(name: "Meta", fileFormat: .jpeg, longEdgePixels: 0, quality: 0.9),
            destination: destination
        )

        let outputDir = sandbox
            .appending(path: "exports", directoryHint: .isDirectory)
            .appending(path: "delivery", directoryHint: .isDirectory)
        let exported = try contentsRecursively(at: outputDir)
        XCTAssertEqual(exported.count, 1)

        let exif = try exifMetadata(for: exported[0])
        XCTAssertEqual(exif[kCGImagePropertyExifLensModel as String] as? String, "XF35mmF1.4 R")
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2026:02:16 09:10:11")
    }

    func testRunQueueStripsExifMetadataWhenRequested() async throws {
        let sandbox = try makeSandbox(name: "export-queue-metadata-strip")
        let sourceRoot = sandbox.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        let file = sourceRoot.appending(path: "photo.jpg", directoryHint: .notDirectory)
        try makeJPEGWithMetadata(
            width: 1800,
            height: 1200,
            lensModel: "XF23mmF2 R WR",
            dateTimeOriginal: "2026:02:16 10:11:12"
        ).write(to: file)

        let item = ExportQueueItem(
            id: UUID(),
            asset: asset(file),
            state: .queued,
            destinationPath: nil,
            errorMessage: nil,
            warningMessage: nil,
            startedAt: nil,
            completedAt: nil,
            bytesWritten: nil
        )
        let destination = ExportDestinationOptions(
            basePath: sandbox.appending(path: "exports", directoryHint: .isDirectory).path,
            subfolderTemplate: "delivery",
            shootName: "meta"
        )
        let manager = ExportManager()

        _ = try await manager.runQueue(
            items: [item],
            preset: ExportPreset(name: "Meta Stripped", fileFormat: .jpeg, longEdgePixels: 0, quality: 0.9, stripMetadata: true),
            destination: destination
        )

        let outputDir = sandbox
            .appending(path: "exports", directoryHint: .isDirectory)
            .appending(path: "delivery", directoryHint: .isDirectory)
        let exported = try contentsRecursively(at: outputDir)
        XCTAssertEqual(exported.count, 1)

        let exif = try exifMetadata(for: exported[0])
        XCTAssertNil(exif[kCGImagePropertyExifLensModel as String])
        XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal as String])
    }

    private func asset(_ url: URL) -> PhotoAsset {
        PhotoAsset(
            url: url,
            filename: url.lastPathComponent,
            captureDate: nil,
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

    private func makeJPEG(width: Int, height: Int) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: width, y: height))
        path.lineWidth = 20
        path.stroke()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 1.0]) else {
            throw NSError(domain: "ExportManagerTests", code: 1)
        }
        return jpeg
    }

    private func makeJPEGWithMetadata(width: Int, height: Int, lensModel: String, dateTimeOriginal: String) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "ExportManagerTests", code: 2)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "ExportManagerTests", code: 3)
        }
        let exif: [CFString: Any] = [
            kCGImagePropertyExifLensModel: lensModel,
            kCGImagePropertyExifDateTimeOriginal: dateTimeOriginal
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ExportManagerTests", code: 4)
        }
        return data as Data
    }

    private func exifMetadata(for url: URL) throws -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw NSError(domain: "ExportManagerTests", code: 5)
        }
        return (properties[kCGImagePropertyExifDictionary as String] as? [String: Any]) ?? [:]
    }
}

private actor WarningCollector {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func messages() -> [String] { values }
}
