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
        viewModel.exportDestination.shootName = "Test"
        viewModel.setExportBasePath("")
        viewModel.startExportQueue()

        XCTAssertEqual(viewModel.exportStatus, "Choose export path and preset first.")
    }

    func testMultiSelectTaggingAndUndoRedo() async throws {
        let fixture = try makeFixture(name: "multi-select-tagging", photoCount: 3)
        let viewModel = BrowserViewModel(mockVolumes: [fixture.volume])
        try await waitForAssets(in: viewModel, expectedCount: 3)
        clearQueue(in: viewModel)

        let visible = viewModel.visiblePhotoAssets
        guard let first = visible.first, let last = visible.last else {
            XCTFail("Missing loaded assets")
            return
        }

        viewModel.select(first)
        viewModel.selectRange(to: last)
        XCTAssertEqual(viewModel.selectedAssetIDs.count, 3)

        viewModel.tagSelectedAsKeep()
        XCTAssertEqual(visible.filter { viewModel.tag(for: $0) == .keep }.count, 3)
        XCTAssertEqual(viewModel.exportQueue.filter { !$0.state.isTerminal }.count, 3)

        viewModel.undoTagEdit()
        XCTAssertEqual(visible.filter { viewModel.tag(for: $0) == .keep }.count, 0)
        XCTAssertEqual(viewModel.exportQueue.filter { !$0.state.isTerminal }.count, 0)

        viewModel.redoTagEdit()
        XCTAssertEqual(visible.filter { viewModel.tag(for: $0) == .keep }.count, 3)
        XCTAssertEqual(viewModel.exportQueue.filter { !$0.state.isTerminal }.count, 3)

        viewModel.selectAllVisibleAssets()
        XCTAssertEqual(viewModel.selectedAssetIDs.count, visible.count)
    }

    func testVerticalNavigationUsesNearestTargetAcrossSectionBoundaries() async throws {
        let fixture = try makeFixture(name: "vertical-navigation-sections", photoCount: 5)
        let firstSectionDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 9)) ?? Date()
        let secondSectionDate = Calendar.current.date(from: DateComponents(year: 2025, month: 9, day: 28)) ?? Date.distantPast

        // First section: 3 items.
        for idx in 0...2 {
            let file = fixture.root.appending(path: "DCIM/photo-\(idx).jpg", directoryHint: .notDirectory)
            let date = firstSectionDate.addingTimeInterval(TimeInterval(idx * 60))
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: file.path)
        }
        // Second section: 2 items.
        for idx in 3...4 {
            let file = fixture.root.appending(path: "DCIM/photo-\(idx).jpg", directoryHint: .notDirectory)
            let date = secondSectionDate.addingTimeInterval(TimeInterval((idx - 3) * 60))
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: file.path)
        }

        let viewModel = BrowserViewModel(mockVolumes: [fixture.volume])
        try await waitForAssets(in: viewModel, expectedCount: 5)

        let visible = viewModel.visiblePhotoAssets
        XCTAssertEqual(visible.count, 5)

        // From section-1 col 0, move down should land on section-2 first item (not +gridColumnCount).
        viewModel.setGridColumnCount(4)
        viewModel.select(visible[0])
        viewModel.selectDownAsset()
        XCTAssertEqual(viewModel.selectedAssetID, visible[3].id)

        // From section-2 item in col 1, move up should land on nearest item in previous section.
        viewModel.select(visible[4])
        viewModel.selectUpAsset()
        XCTAssertEqual(viewModel.selectedAssetID, visible[1].id)
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
