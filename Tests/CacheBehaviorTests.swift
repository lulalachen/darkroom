import AppKit
import Foundation
import XCTest
@testable import darkroom

final class CacheBehaviorTests: XCTestCase {
    func testFullImageLoaderEvictsLeastRecentlyUsedEntries() async throws {
        let sandbox = try makeSandbox(name: "full-image-loader-lru")
        let urls = try [
            createImage(at: sandbox.appending(path: "a.jpg", directoryHint: .notDirectory), shade: .red),
            createImage(at: sandbox.appending(path: "b.jpg", directoryHint: .notDirectory), shade: .green),
            createImage(at: sandbox.appending(path: "c.jpg", directoryHint: .notDirectory), shade: .blue)
        ]

        let loader = FullImageLoader()
        await loader.clear()
        await loader.configure(maxEntries: 2)
        _ = await loader.image(for: urls[0])
        _ = await loader.image(for: urls[1])
        let countAfterTwo = await loader.cachedCount()
        XCTAssertEqual(countAfterTwo, 2)

        _ = await loader.image(for: urls[2])
        let countAfterThree = await loader.cachedCount()
        XCTAssertEqual(countAfterThree, 2)
    }

    func testFullImageLoaderClearDropsAllEntries() async throws {
        let sandbox = try makeSandbox(name: "full-image-loader-clear")
        let url = try createImage(at: sandbox.appending(path: "sample.jpg", directoryHint: .notDirectory), shade: .orange)
        let loader = FullImageLoader()
        await loader.configure(maxEntries: 16)
        _ = await loader.image(for: url)
        let cachedBeforeClear = await loader.cachedCount()
        XCTAssertGreaterThan(cachedBeforeClear, 0)
        await loader.clear()
        let cachedAfterClear = await loader.cachedCount()
        XCTAssertEqual(cachedAfterClear, 0)
    }

    private func makeSandbox(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "darkroom-tests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func createImage(at url: URL, shade: NSColor) throws -> URL {
        let image = NSImage(size: NSSize(width: 200, height: 120))
        image.lockFocus()
        shade.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 120)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw NSError(domain: "CacheBehaviorTests", code: 1)
        }
        try jpeg.write(to: url, options: [.atomic])
        return url
    }
}
