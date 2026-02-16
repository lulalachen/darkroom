import AppKit
import Foundation
import XCTest
@testable import darkroom

@MainActor
final class BrowserViewModelExportWorkflowTests: XCTestCase {
    func testGreenTagAutoQueuesAndIsIdempotent() async throws {
        let fixture = try makeFixture(name: "green-auto-queue", photoCount: 1)
        let viewModel = BrowserViewModel(mockVolumes: [fixture.volume])
        try await waitForAssets(in: viewModel, expectedCount: 1)
        clearQueue(in: viewModel)

        guard let asset = viewModel.photoAssets.first else {
            XCTFail("Missing loaded asset")
            return
        }

        viewModel.select(asset)
        viewModel.tagSelectedAsKeep()
        XCTAssertEqual(viewModel.exportQueue.count, 1)

        viewModel.tagSelectedAsKeep()
        XCTAssertEqual(viewModel.exportQueue.count, 1)
    }

    func testClearAndRejectRemoveQueuedItem() async throws {
        let fixture = try makeFixture(name: "clear-removes-queued", photoCount: 1)
        let viewModel = BrowserViewModel(mockVolumes: [fixture.volume])
        try await waitForAssets(in: viewModel, expectedCount: 1)
        clearQueue(in: viewModel)

        guard let asset = viewModel.photoAssets.first else {
            XCTFail("Missing loaded asset")
            return
        }

        viewModel.select(asset)
        viewModel.tagSelectedAsKeep()
        XCTAssertEqual(viewModel.exportQueue.count, 1)

        viewModel.clearSelectedTag()
        XCTAssertEqual(viewModel.exportQueue.count, 0)

        viewModel.tagSelectedAsKeep()
        XCTAssertEqual(viewModel.exportQueue.count, 1)

        viewModel.tagSelectedAsReject()
        XCTAssertEqual(viewModel.exportQueue.count, 0)
    }

    func testStartExportRequiresDestination() async throws {
        let fixture = try makeFixture(name: "start-needs-destination", photoCount: 1)
        let viewModel = BrowserViewModel(mockVolumes: [fixture.volume])
        try await waitForAssets(in: viewModel, expectedCount: 1)
        clearQueue(in: viewModel)

        guard let asset = viewModel.photoAssets.first else {
            XCTFail("Missing loaded asset")
            return
        }

        viewModel.select(asset)
        viewModel.tagSelectedAsKeep()
        viewModel.setExportBasePath("")
        viewModel.startExportQueue()

        XCTAssertEqual(viewModel.exportStatus, "Choose export path and preset first.")
    }

    private func clearQueue(in viewModel: BrowserViewModel) {
        for item in viewModel.exportQueue {
            viewModel.removeExportItem(id: item.id)
        }
    }

    private func waitForAssets(in viewModel: BrowserViewModel, expectedCount: Int) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if viewModel.photoAssets.count == expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for assets. Found \(viewModel.photoAssets.count), expected \(expectedCount)")
    }

    private func makeFixture(name: String, photoCount: Int) throws -> (root: URL, volume: Volume) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "darkroom-viewmodel-tests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dcim = root.appending(path: "DCIM", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dcim, withIntermediateDirectories: true)

        for index in 0..<photoCount {
            let file = dcim.appending(path: "photo-\(index).jpg", directoryHint: .notDirectory)
            try makeJPEG(width: 1000, height: 700).write(to: file)
        }

        let volume = Volume(
            url: root,
            name: "TEST_CARD",
            isRemovable: true,
            isInternal: false,
            capacity: nil
        )
        return (root, volume)
    }

    private func makeJPEG(width: Int, height: Int) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.gray.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw NSError(domain: "BrowserViewModelExportWorkflowTests", code: 1)
        }
        return jpeg
    }
}
