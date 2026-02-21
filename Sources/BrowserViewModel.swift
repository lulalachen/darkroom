import AppKit
import Combine
import Foundation
import UserNotifications

let darkroomShortcutExportRequestDefaultsKey = "darkroom.shortcut.export.request"

@MainActor
final class BrowserViewModel: ObservableObject {
    private static let lastExportPathDefaultsKey = "darkroom.lastExportPath"
    private static let exportPresetsDefaultsKey = "darkroom.exportPresets.v1"
    private static let selectedExportPresetDefaultsKey = "darkroom.selectedExportPresetID"
    private static let exportSubfolderTemplateDefaultsKey = "darkroom.exportSubfolderTemplate"
    private static let exportShootNameDefaultsKey = "darkroom.exportShootName"
    private static let exportRecentDestinationsDefaultsKey = "darkroom.exportRecentDestinations.v1"
    private static let exportQueueCacheFilename = "export-queue-cache.json"
    private static let ratingsDefaultsKey = "darkroom.asset.ratings.v1"
    private static let userLibraryPathsDefaultsKey = "darkroom.userLibraryPaths.v1"
    private static let starterPresetRestoreOnceDefaultsKey = "darkroom.exportStarterPresetRestoreOnce.v1"
    private static let uiTestFixturePathMarker = "/darkroom-viewmodel-tests-"

    enum AssetFilter: String, CaseIterable, Identifiable {
        case all
        case keep
        case reject
        case untagged

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .keep: return "Selected"
            case .reject: return "Rejected"
            case .untagged: return "Untagged"
            }
        }
    }

    private struct TagEditCommand {
        let assetIDs: [PhotoAsset.ID]
        let previousTags: [PhotoAsset.ID: PhotoTag]
        let updatedTag: PhotoTag?
    }

    @Published private(set) var volumes: [Volume] = []
    @Published private(set) var libraryVolume: Volume?
    @Published private(set) var userLibraryVolumes: [Volume] = []
    @Published var selectedVolume: Volume? {
        didSet {
            guard selectedVolume != oldValue else { return }
            loadAssetsForSelection()
        }
    }
    @Published private(set) var photoAssets: [PhotoAsset] = []
    @Published var selectedAssetID: PhotoAsset.ID?
    @Published private(set) var selectedAssetIDs: Set<PhotoAsset.ID> = []
    @Published private(set) var tags: [PhotoAsset.ID: PhotoTag] = [:]
    @Published private(set) var ratings: [PhotoAsset.ID: Int] = [:]
    @Published var assetFilter: AssetFilter = .all {
        didSet {
            ensureSelectedAssetVisible()
        }
    }
    @Published var isLoadingAssets: Bool = false
    @Published private(set) var gridColumnCount: Int = 1
    @Published private(set) var shortcutProfile: KeyboardShortcutProfile = .classicZXC
    @Published private(set) var isExporting: Bool = false
    @Published private(set) var exportStatus: String?
    @Published private(set) var exportCompletionBanner: ExportCompletionBanner?
    @Published private(set) var exportQueue: [ExportQueueItem] = [] {
        didSet { Self.persistExportQueue(exportQueue) }
    }
    @Published private(set) var recentExportDestinations: [String] = []
    @Published var exportPresets: [ExportPreset] = ExportPreset.starterPresets {
        didSet { persistExportPresets() }
    }
    @Published var selectedExportPresetID: ExportPreset.ID? {
        didSet {
            UserDefaults.standard.set(selectedExportPresetID?.uuidString, forKey: Self.selectedExportPresetDefaultsKey)
            recentExportDestinations = loadRecentDestinations(for: selectedExportPresetID)
        }
    }
    @Published var exportDestination: ExportDestinationOptions = .default {
        didSet {
            UserDefaults.standard.set(exportDestination.subfolderTemplate, forKey: Self.exportSubfolderTemplateDefaultsKey)
            UserDefaults.standard.set(exportDestination.shootName, forKey: Self.exportShootNameDefaultsKey)
        }
    }

    var filteredVolumes: [Volume] {
        volumes.filter { $0.isRemovable }
    }

    var allLibraryVolumes: [Volume] {
        var items: [Volume] = []
        if let libraryVolume {
            items.append(libraryVolume)
        }
        let builtInPath = libraryVolume?.url.standardizedFileURL.path
        let user = userLibraryVolumes.filter { $0.url.standardizedFileURL.path != builtInPath }
        items.append(contentsOf: user)
        return items
    }

    private let volumeWatcher: VolumeWatcher
    private let enumerator = PhotoEnumerator()
    private let libraryManager: LibraryManager
    private let exportManager = ExportManager()
    private let finderTagManager = FinderTagManager()
    private var shortcutObserver: NSObjectProtocol?
    private var preferenceObserver: NSObjectProtocol?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var cancellables: Set<AnyCancellable> = []
    private var selectionAnchorAssetID: PhotoAsset.ID?
    private var tagUndoStack: [TagEditCommand] = []
    private var tagRedoStack: [TagEditCommand] = []
    private let maxTagHistory = 100

    var selectedAsset: PhotoAsset? {
        guard let selectedAssetID else { return nil }
        return visiblePhotoAssets.first(where: { $0.id == selectedAssetID })
    }

    var keepCount: Int {
        tags.values.filter { $0 == .keep }.count
    }

    var rejectCount: Int {
        tags.values.filter { $0 == .reject }.count
    }

    var shortcutLegend: String {
        switch shortcutProfile {
        case .classicZXC:
            return "Shortcuts: Z = Selected, X = Rejected, C = Clear, R = Cycle rating"
        case .numeric120:
            return "Shortcuts: 1 = Selected, 2 = Rejected, 0 = Clear, R = Cycle rating"
        }
    }

    var visiblePhotoAssets: [PhotoAsset] {
        switch assetFilter {
        case .all:
            return photoAssets
        case .keep:
            return photoAssets.filter { tags[$0.id] == .keep }
        case .reject:
            return photoAssets.filter { tags[$0.id] == .reject }
        case .untagged:
            return photoAssets.filter { tags[$0.id] == nil }
        }
    }

    var greenTaggedAssets: [PhotoAsset] {
        photoAssets.filter { tags[$0.id] == .keep }
    }

    var canUndoTagEdit: Bool { !tagUndoStack.isEmpty }
    var canRedoTagEdit: Bool { !tagRedoStack.isEmpty }

    init(volumeWatcher: VolumeWatcher? = nil, libraryManager: LibraryManager = .shared, mockVolumes: [Volume]? = nil) {
        let watcher = volumeWatcher ?? VolumeWatcher()
        self.volumeWatcher = watcher
        self.libraryManager = libraryManager

        let exportPath = UserDefaults.standard.string(forKey: Self.lastExportPathDefaultsKey) ?? ""
        self.exportDestination.basePath = exportPath
        self.exportDestination.subfolderTemplate = Self.loadPersistedSubfolderTemplate()
        self.exportDestination.shootName = UserDefaults.standard.string(forKey: Self.exportShootNameDefaultsKey) ?? ""
        self.exportPresets = Self.loadPersistedExportPresets() ?? ExportPreset.starterPresets
        self.restoreMissingStarterPresetsOnceIfNeeded()
        if let selectedPresetRaw = UserDefaults.standard.string(forKey: Self.selectedExportPresetDefaultsKey),
           let selectedPresetID = UUID(uuidString: selectedPresetRaw),
           self.exportPresets.contains(where: { $0.id == selectedPresetID }) {
            self.selectedExportPresetID = selectedPresetID
        } else {
            self.selectedExportPresetID = self.exportPresets.first?.id
        }
        self.recentExportDestinations = self.loadRecentDestinations(for: self.selectedExportPresetID)
        self.exportQueue = Self.loadPersistedExportQueue().map { item in
            var mutable = item
            if mutable.state == .rendering || mutable.state == .writing {
                mutable.state = .queued
                mutable.errorMessage = "Recovered after app relaunch."
            }
            return mutable
        }

        if let mockVolumes {
            self.volumes = mockVolumes
            self.selectedVolume = mockVolumes.first
        } else {
            self.userLibraryVolumes = Self.loadPersistedUserLibraries()
            bindVolumeUpdates()
            watcher.refresh()
        }
        applyRuntimePreferences()
        installPreferenceObserver()
        installMemoryPressureHandler()
        installShortcutObserver()
    }

    deinit {
        if let shortcutObserver {
            DistributedNotificationCenter.default().removeObserver(shortcutObserver)
        }
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
        memoryPressureSource?.cancel()
    }

    func bootstrapForExportWorkflow() async {
        do {
            let paths = try await libraryManager.bootstrapIfNeeded()
            libraryVolume = Volume(
                url: paths.originalsRoot,
                name: "Darkroom Library",
                isRemovable: false,
                isInternal: true,
                capacity: nil,
                isBuiltInLibrary: true,
                isUserLibrary: false
            )
            if userLibraryVolumes.contains(where: { $0.url.standardizedFileURL.path == paths.originalsRoot.standardizedFileURL.path }) {
                userLibraryVolumes.removeAll { $0.url.standardizedFileURL.path == paths.originalsRoot.standardizedFileURL.path }
                persistUserLibraries()
            }
            if selectedVolume == nil {
                selectedVolume = preferredAutoSelectedVolume(from: volumes)
            }
            resumePendingExportsIfNeeded()
        } catch {
            exportStatus = "Could not initialize library: \(error.localizedDescription)"
        }
    }

    func refreshVolumes() {
        volumeWatcher.refresh()
        loadAssetsForSelection()
    }

    func addUserLibraryFolder(_ folderURL: URL) {
        let standardized = folderURL.standardizedFileURL
        guard Self.isDirectory(at: standardized) else {
            exportStatus = "Selected path is not a folder."
            return
        }
        if let libraryVolume,
           libraryVolume.url.standardizedFileURL.path == standardized.path {
            selectedVolume = libraryVolume
            return
        }
        if let existing = userLibraryVolumes.first(where: { $0.url.standardizedFileURL.path == standardized.path }) {
            selectedVolume = existing
            return
        }

        let newVolume = Volume(
            url: standardized,
            name: standardized.lastPathComponent,
            isRemovable: false,
            isInternal: true,
            capacity: nil,
            isBuiltInLibrary: false,
            isUserLibrary: true
        )
        userLibraryVolumes.append(newVolume)
        userLibraryVolumes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        persistUserLibraries()
        selectedVolume = newVolume
    }

    func addUserLibraryFolders(_ folderURLs: [URL]) {
        var lastAddedOrExisting: Volume?
        for folderURL in folderURLs {
            let standardized = folderURL.standardizedFileURL
            guard Self.isDirectory(at: standardized) else {
                continue
            }
            if let libraryVolume,
               libraryVolume.url.standardizedFileURL.path == standardized.path {
                lastAddedOrExisting = libraryVolume
                continue
            }
            if let existing = userLibraryVolumes.first(where: { $0.url.standardizedFileURL.path == standardized.path }) {
                lastAddedOrExisting = existing
                continue
            }

            let newVolume = Volume(
                url: standardized,
                name: standardized.lastPathComponent,
                isRemovable: false,
                isInternal: true,
                capacity: nil,
                isBuiltInLibrary: false,
                isUserLibrary: true
            )
            userLibraryVolumes.append(newVolume)
            lastAddedOrExisting = newVolume
        }

        userLibraryVolumes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        persistUserLibraries()
        if let lastAddedOrExisting {
            selectedVolume = lastAddedOrExisting
        }
    }

    func removeUserLibrary(_ volume: Volume) {
        guard volume.isUserLibrary else { return }
        userLibraryVolumes.removeAll { $0.url.standardizedFileURL.path == volume.url.standardizedFileURL.path }
        persistUserLibraries()
        if selectedVolume?.url.standardizedFileURL.path == volume.url.standardizedFileURL.path {
            selectedVolume = preferredAutoSelectedVolume(from: volumes)
        }
    }

    func select(_ asset: PhotoAsset) {
        selectSingleAsset(asset.id)
    }

    func selectRange(to asset: PhotoAsset) {
        let visible = visiblePhotoAssets
        guard let targetIndex = visible.firstIndex(where: { $0.id == asset.id }) else { return }

        let anchorID = selectionAnchorAssetID ?? selectedAssetID ?? selectedAssetIDs.first
        guard let anchorID,
              let anchorIndex = visible.firstIndex(where: { $0.id == anchorID }) else {
            selectSingleAsset(asset.id)
            return
        }

        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        let rangeIDs = Set(visible[lower...upper].map(\.id))
        selectedAssetIDs = rangeIDs
        selectedAssetID = asset.id
    }

    func selectAllVisibleAssets() {
        let visible = visiblePhotoAssets
        guard !visible.isEmpty else {
            selectedAssetID = nil
            selectedAssetIDs = []
            selectionAnchorAssetID = nil
            return
        }

        let allIDs = Set(visible.map(\.id))
        selectedAssetIDs = allIDs
        if let selectedAssetID, allIDs.contains(selectedAssetID) {
            selectionAnchorAssetID = selectedAssetID
            return
        }
        if let firstID = visible.first?.id {
            selectedAssetID = firstID
            selectionAnchorAssetID = firstID
        }
    }

    func tagSelectedAsKeep() {
        applyTagChange(.keep, to: targetAssetIDsForTagging())
    }

    func tagSelectedAsReject() {
        applyTagChange(.reject, to: targetAssetIDsForTagging())
    }

    func tag(for asset: PhotoAsset) -> PhotoTag? {
        tags[asset.id]
    }

    func rating(for asset: PhotoAsset) -> Int {
        ratings[asset.id] ?? 0
    }

    func setExportBasePath(_ path: String) {
        exportDestination.basePath = path
        UserDefaults.standard.set(path, forKey: Self.lastExportPathDefaultsKey)
    }

    func applyRuntimePreferences() {
        shortcutProfile = AppPreferences.shared.shortcutProfile
        Task {
            await ThumbnailCache.shared.configure(maxEntries: AppPreferences.shared.thumbnailCacheEntryLimit)
            await FullImageLoader.shared.configure(maxEntries: AppPreferences.shared.fullImageCacheCount)
            await EditedThumbnailCache.shared.configure(maxEntries: max(64, AppPreferences.shared.thumbnailCacheEntryLimit / 2))
        }
    }

    var selectedExportPreset: ExportPreset? {
        guard let selectedExportPresetID else { return exportPresets.first }
        return exportPresets.first(where: { $0.id == selectedExportPresetID }) ?? exportPresets.first
    }

    var hasValidExportDestination: Bool {
        let path = exportDestination.basePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !path.isEmpty && selectedExportPreset != nil
    }

    var estimatedExportRemaining: TimeInterval? {
        let completed = exportQueue.filter { $0.state == .done && $0.startedAt != nil && $0.completedAt != nil }
        guard !completed.isEmpty else { return nil }
        let average = completed
            .map { ($0.completedAt ?? Date()).timeIntervalSince($0.startedAt ?? Date()) }
            .reduce(0, +) / Double(completed.count)
        let pending = exportQueue.filter { $0.state == .queued || $0.state == .rendering || $0.state == .writing }.count
        guard pending > 0 else { return nil }
        return average * Double(pending)
    }

    var exportQueueCounts: (queued: Int, done: Int, failed: Int, cancelled: Int) {
        var queued = 0
        var done = 0
        var failed = 0
        var cancelled = 0
        for item in exportQueue {
            switch item.state {
            case .queued, .rendering, .writing:
                queued += 1
            case .done:
                done += 1
            case .failed:
                failed += 1
            case .cancelled:
                cancelled += 1
            }
        }
        return (queued, done, failed, cancelled)
    }

    func enqueueGreenTaggedForExport() {
        enqueueForExport(assets: greenTaggedAssets, statusPrefix: "Queued")
    }

    func enqueueSelectedForExport() {
        guard let selectedAsset else {
            exportStatus = "Select a photo to queue for export."
            return
        }
        enqueueForExport(assets: [selectedAsset], statusPrefix: "Queued")
    }

    func startExportQueue() {
        guard !isExporting else { return }
        guard !exportDestination.shootName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            exportStatus = "Enter folder name first."
            return
        }
        guard hasValidExportDestination else {
            exportStatus = "Choose export path and preset first."
            return
        }
        guard let preset = selectedExportPreset else {
            exportStatus = "No export preset selected."
            return
        }
        let currentSourceIDs = Set(photoAssets.map(\.id))
        let queueSnapshot = exportQueue.filter { item in
            !item.state.isTerminal && currentSourceIDs.contains(item.asset.id)
        }
        guard !queueSnapshot.isEmpty else {
            exportStatus = "No pending exports for current source."
            return
        }

        isExporting = true
        exportCompletionBanner = nil
        exportStatus = "Export queue running..."
        rememberRecentDestination(exportDestination.basePath, for: preset.id)
        requestNotificationPermissionIfNeeded()
        let destination = exportDestination

        Task {
            do {
                let summary = try await exportManager.runQueue(
                    items: queueSnapshot,
                    preset: preset,
                    destination: destination
                ) { [weak self] snapshot in
                    Task { @MainActor in
                        self?.applyExportSnapshot(snapshot)
                    }
                }
                await MainActor.run {
                    self.isExporting = false
                    self.exportStatus = "Exported \(summary.exportedCount), failed \(summary.failedCount), cancelled \(summary.cancelledCount)."
                    if let folderPath = self.latestCompletedExportFolderPath(), summary.exportedCount > 0 {
                        self.exportCompletionBanner = ExportCompletionBanner(
                            folderPath: folderPath,
                            exportedCount: summary.exportedCount
                        )
                    }
                    self.postExportCompletionNotification(summary: summary)
                }
                await StructuredLogger.shared.log(
                    event: "export_queue_completed",
                    metadata: [
                        "exported": "\(summary.exportedCount)",
                        "failed": "\(summary.failedCount)",
                        "cancelled": "\(summary.cancelledCount)"
                    ]
                )
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportStatus = "Export failed: \(error.localizedDescription)"
                }
                await StructuredLogger.shared.log(
                    event: "export_queue_failed",
                    metadata: [
                        "error": error.localizedDescription
                    ]
                )
            }
        }
    }

    func cancelExportQueue() {
        guard isExporting else { return }
        Task { await exportManager.cancel() }
        exportStatus = "Cancelling export queue..."
    }

    func retryFailedExports() {
        var retried = 0
        for index in exportQueue.indices where exportQueue[index].state == .failed {
            exportQueue[index].state = .queued
            exportQueue[index].errorMessage = nil
            exportQueue[index].warningMessage = nil
            exportQueue[index].destinationPath = nil
            exportQueue[index].startedAt = nil
            exportQueue[index].completedAt = nil
            exportQueue[index].bytesWritten = nil
            retried += 1
        }
        exportStatus = retried > 0 ? "Re-queued \(retried) failed export(s)." : "No failed exports to retry."
    }

    func clearCompletedExports() {
        exportQueue.removeAll { $0.state == .done || $0.state == .cancelled }
    }

    func removeExportItem(id: ExportQueueItem.ID) {
        exportQueue.removeAll { $0.id == id }
    }

    func revealExportedItem(_ item: ExportQueueItem) {
        guard let destinationPath = item.destinationPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: destinationPath)])
    }

    func openExportCompletionFolder() {
        guard let folderPath = exportCompletionBanner?.folderPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: folderPath, isDirectory: true))
    }

    func dismissExportCompletionBanner() {
        exportCompletionBanner = nil
    }

    func useRecentExportDestination(_ path: String) {
        setExportBasePath(path)
    }

    func addExportPreset(_ preset: ExportPreset) {
        exportPresets.append(preset)
        selectedExportPresetID = preset.id
    }

    func updateSelectedExportPreset(_ updated: ExportPreset) {
        guard let index = exportPresets.firstIndex(where: { $0.id == updated.id }) else { return }
        exportPresets[index] = updated
    }

    func deleteSelectedExportPreset() {
        guard let selectedExportPresetID, exportPresets.count > 1 else { return }
        exportPresets.removeAll { $0.id == selectedExportPresetID }
        self.selectedExportPresetID = exportPresets.first?.id
    }

    func selectNextAsset() {
        moveSelection(by: 1)
    }

    func selectPreviousAsset() {
        moveSelection(by: -1)
    }

    func selectLeftAsset() {
        moveSelection(by: -1)
    }

    func selectRightAsset() {
        moveSelection(by: 1)
    }

    func selectUpAsset() {
        moveSelectionVertically(direction: -1)
    }

    func selectDownAsset() {
        moveSelectionVertically(direction: 1)
    }

    func setGridColumnCount(_ count: Int) {
        gridColumnCount = max(1, count)
    }

    func clearSelectedTag() {
        applyTagChange(nil, to: targetAssetIDsForTagging())
    }

    func undoTagEdit() {
        guard let command = tagUndoStack.popLast() else { return }
        for assetID in command.assetIDs {
            applyTag(command.previousTags[assetID], to: assetID)
        }
        tagRedoStack.append(command)
        ensureSelectedAssetVisible()
    }

    func redoTagEdit() {
        guard let command = tagRedoStack.popLast() else { return }
        applyTagChange(command.updatedTag, to: command.assetIDs, recordHistory: false)
        tagUndoStack.append(command)
    }

    func setSelectedRating(_ value: Int) {
        guard let selectedAssetID else { return }
        setRating(value, for: selectedAssetID)
    }

    func clearSelectedRating() {
        guard let selectedAssetID else { return }
        ratings[selectedAssetID] = nil
        persistRatingsForVisibleAssets()
    }

    func isTagHotkey(_ characters: String?) -> Bool {
        guard let key = characters?.lowercased() else { return false }
        switch shortcutProfile {
        case .classicZXC:
            return key == "z" || key == "x" || key == "c" || key == "r"
        case .numeric120:
            return key == "1" || key == "2" || key == "0" || key == "r"
        }
    }

    func handleTagHotkey(_ characters: String?) -> Bool {
        guard let key = characters?.lowercased() else { return false }
        switch shortcutProfile {
        case .classicZXC:
            switch key {
            case "z":
                tagSelectedAsKeep()
                return true
            case "x":
                tagSelectedAsReject()
                return true
            case "c":
                clearSelectedTag()
                return true
            case "r":
                cycleSelectedRating()
                return true
            default:
                return false
            }
        case .numeric120:
            switch key {
            case "1":
                tagSelectedAsKeep()
                return true
            case "2":
                tagSelectedAsReject()
                return true
            case "0":
                clearSelectedTag()
                return true
            case "r":
                cycleSelectedRating()
                return true
            default:
                return false
            }
        }
    }

    private func bindVolumeUpdates() {
        volumeWatcher.$volumes
            .receive(on: RunLoop.main)
            .sink { [weak self] newVolumes in
                guard let self = self else { return }
                self.volumes = newVolumes
                if let currentlySelected = self.selectedVolume {
                    if currentlySelected.isBuiltInLibrary || currentlySelected.isUserLibrary {
                        // Keep explicit library selections; don't override them from removable volume updates.
                        return
                    }
                    if currentlySelected.isRemovable, newVolumes.contains(currentlySelected) {
                        return
                    }
                }
                self.selectedVolume = self.preferredAutoSelectedVolume(from: newVolumes)
            }
            .store(in: &cancellables)
    }

    private func installShortcutObserver() {
        shortcutObserver = DistributedNotificationCenter.default().addObserver(
            forName: .darkroomShortcutExportRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleShortcutExportRequest()
            }
        }
    }

    private func installPreferenceObserver() {
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .darkroomPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyRuntimePreferences()
            }
        }
    }

    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await ThumbnailCache.shared.clear()
                await FullImageLoader.shared.clear()
                await EditedThumbnailCache.shared.clear()
                await StructuredLogger.shared.log(
                    event: "memory_pressure_cache_clear",
                    metadata: ["state": "\(source.data.rawValue)"]
                )
                await MainActor.run {
                    self.exportStatus = "Cache cleared due to memory pressure."
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleShortcutExportRequest() {
        guard let payload = UserDefaults.standard.dictionary(forKey: darkroomShortcutExportRequestDefaultsKey) else {
            return
        }
        if let presetName = payload["presetName"] as? String,
           let preset = exportPresets.first(where: { $0.name.caseInsensitiveCompare(presetName) == .orderedSame }) {
            selectedExportPresetID = preset.id
        }
        if let destinationPath = payload["destinationPath"] as? String {
            setExportBasePath(destinationPath)
        }
        if let shootName = payload["shootName"] as? String {
            exportDestination.shootName = shootName
        }
        if let selectedAsset {
            enqueueForExport(assets: [selectedAsset], statusPrefix: "Queued")
        } else {
            enqueueGreenTaggedForExport()
        }
        startExportQueue()
    }

    private func loadAssetsForSelection() {
        guard let volume = selectedVolume, let root = volume.browsingRoot else {
            photoAssets = []
            selectedAssetID = nil
            selectedAssetIDs = []
            selectionAnchorAssetID = nil
            tags = [:]
            ratings = [:]
            tagUndoStack = []
            tagRedoStack = []
            return
        }

        isLoadingAssets = true
        Task {
            let assets = await enumerator.assets(at: root)
            let loadedTags = await finderTagManager.tagMap(for: assets)
            let loadedRatings = self.loadRatings(for: assets)
            await MainActor.run {
                self.photoAssets = assets
                self.tags = loadedTags
                self.ratings = loadedRatings
                self.tagUndoStack = []
                self.tagRedoStack = []
                self.ensureSelectedAssetVisible(defaultToFirst: true)
                self.isLoadingAssets = false
                self.syncQueueWithGreenTags()
            }
        }
    }

    private func syncQueueWithGreenTags() {
        let greenIDs = Set(photoAssets.compactMap { tags[$0.id] == .keep ? $0.id : nil })
        exportQueue.removeAll { item in
            guard item.state == .queued else { return false }
            return photoAssets.contains(where: { $0.id == item.asset.id }) && !greenIDs.contains(item.asset.id)
        }
        for asset in photoAssets where tags[asset.id] == .keep {
            ensureQueuedForExport(asset)
        }
    }

    private func enqueueForExport(assets: [PhotoAsset], statusPrefix: String) {
        guard !assets.isEmpty else {
            exportStatus = "No photos available to queue."
            return
        }
        var appended = 0
        for asset in assets {
            if ensureQueuedForExport(asset) {
                appended += 1
            }
        }
        if appended == 0 {
            exportStatus = "Selected photos are already queued."
        } else {
            exportStatus = "\(statusPrefix) \(appended) photo(s) for export."
        }
    }

    @discardableResult
    private func ensureQueuedForExport(_ asset: PhotoAsset) -> Bool {
        if exportQueue.contains(where: { $0.asset.id == asset.id && !$0.state.isTerminal }) {
            return false
        }
        exportQueue.append(
            ExportQueueItem(
                id: UUID(),
                asset: asset,
                state: .queued,
                destinationPath: nil,
                errorMessage: nil,
                warningMessage: nil,
                startedAt: nil,
                completedAt: nil,
                bytesWritten: nil
            )
        )
        return true
    }

    private func removePendingQueueEntry(for assetID: PhotoAsset.ID) {
        exportQueue.removeAll { $0.asset.id == assetID && $0.state == .queued }
    }

    private func applyExportSnapshot(_ snapshot: ExportProgressSnapshot) {
        guard let index = exportQueue.firstIndex(where: { $0.asset.url.path == snapshot.sourcePath }) else {
            return
        }
        if exportQueue[index].startedAt == nil && (snapshot.state == .rendering || snapshot.state == .writing) {
            exportQueue[index].startedAt = Date()
        }
        exportQueue[index].state = snapshot.state
        exportQueue[index].destinationPath = snapshot.destinationPath ?? exportQueue[index].destinationPath
        exportQueue[index].errorMessage = snapshot.errorMessage
        exportQueue[index].warningMessage = snapshot.warningMessage
        exportQueue[index].bytesWritten = snapshot.bytesWritten ?? exportQueue[index].bytesWritten
        if snapshot.state.isTerminal {
            exportQueue[index].completedAt = Date()
        }
    }

    private func latestCompletedExportFolderPath() -> String? {
        let latestDone = exportQueue
            .filter { $0.state == .done && $0.destinationPath != nil }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .last

        guard let destinationPath = latestDone?.destinationPath else { return nil }
        return URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
    }

    private func persistExportPresets() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(exportPresets) else { return }
        UserDefaults.standard.set(data, forKey: Self.exportPresetsDefaultsKey)
    }

    private static func loadPersistedExportPresets() -> [ExportPreset]? {
        guard let data = UserDefaults.standard.data(forKey: exportPresetsDefaultsKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode([ExportPreset].self, from: data)
    }

    private static func persistExportQueue(_ queue: [ExportQueueItem]) {
        guard !isRunningTests else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(queue.map { ExportQueueRecord(item: $0) }) else { return }
        let url = exportQueueCacheURL()
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    private static func loadPersistedExportQueue() -> [ExportQueueItem] {
        guard !isRunningTests else { return [] }
        let url = exportQueueCacheURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        guard let records = try? decoder.decode([ExportQueueRecord].self, from: data) else { return [] }
        return records
            .map(\.asQueueItem)
            .filter { !isTestFixtureAssetPath($0.asset.url.path) }
    }

    private static func exportQueueCacheURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return appSupport
            .appending(path: "Darkroom", directoryHint: .isDirectory)
            .appending(path: exportQueueCacheFilename, directoryHint: .notDirectory)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func isTestFixtureAssetPath(_ path: String) -> Bool {
        path.contains(uiTestFixturePathMarker)
    }

    private func loadRecentDestinations(for presetID: ExportPreset.ID?) -> [String] {
        guard let presetID else { return [] }
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.exportRecentDestinationsDefaultsKey) as? [String: [String]] else {
            return []
        }
        return raw[presetID.uuidString] ?? []
    }

    private func rememberRecentDestination(_ path: String, for presetID: ExportPreset.ID) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var raw = UserDefaults.standard.dictionary(forKey: Self.exportRecentDestinationsDefaultsKey) as? [String: [String]] ?? [:]
        var paths = raw[presetID.uuidString] ?? []
        paths.removeAll { $0 == trimmed }
        paths.insert(trimmed, at: 0)
        if paths.count > 5 {
            paths.removeLast(paths.count - 5)
        }
        raw[presetID.uuidString] = paths
        UserDefaults.standard.set(raw, forKey: Self.exportRecentDestinationsDefaultsKey)
        if selectedExportPresetID == presetID {
            recentExportDestinations = paths
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postExportCompletionNotification(summary: ExportRunSummary) {
        let content = UNMutableNotificationContent()
        content.title = "Export Queue Complete"
        content.body = "Exported \(summary.exportedCount), failed \(summary.failedCount), cancelled \(summary.cancelledCount)."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func resumePendingExportsIfNeeded() {
        guard exportQueue.contains(where: { $0.state == .queued }) else { return }
        exportStatus = "Recovered pending exports. Open Export Config to start manually."
    }

    private func preferredAutoSelectedVolume(from volumes: [Volume]) -> Volume? {
        volumes.first { $0.isLikelyCameraCard } ?? volumes.first { $0.isRemovable }
    }

    private static func isDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func persistUserLibraries() {
        let paths = userLibraryVolumes.map { $0.url.standardizedFileURL.path }
        UserDefaults.standard.set(paths, forKey: Self.userLibraryPathsDefaultsKey)
    }

    private static func loadPersistedUserLibraries() -> [Volume] {
        let paths = UserDefaults.standard.array(forKey: userLibraryPathsDefaultsKey) as? [String] ?? []
        var items: [Volume] = []
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard isDirectory(at: url) else { continue }
            items.append(
                Volume(
                    url: url,
                    name: url.lastPathComponent,
                    isRemovable: false,
                    isInternal: true,
                    capacity: nil,
                    isBuiltInLibrary: false,
                    isUserLibrary: true
                )
            )
        }
        return items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func restoreMissingStarterPresetsOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.starterPresetRestoreOnceDefaultsKey) == false else { return }

        let existingNames = Set(exportPresets.map { $0.name.lowercased() })
        let missing = ExportPreset.starterPresets.filter { !existingNames.contains($0.name.lowercased()) }
        if !missing.isEmpty {
            exportPresets.append(contentsOf: missing)
        }
        defaults.set(true, forKey: Self.starterPresetRestoreOnceDefaultsKey)
    }

    private func applyTagChange(_ tag: PhotoTag?, to assetIDs: [PhotoAsset.ID], recordHistory: Bool = true) {
        let uniqueIDs = Array(Set(assetIDs))
        guard !uniqueIDs.isEmpty else { return }

        var previousTags: [PhotoAsset.ID: PhotoTag] = [:]
        var changedIDs: [PhotoAsset.ID] = []
        for assetID in uniqueIDs {
            let previous = tags[assetID]
            if previous != tag {
                if let previous {
                    previousTags[assetID] = previous
                }
                changedIDs.append(assetID)
            }
        }
        guard !changedIDs.isEmpty else { return }

        for assetID in changedIDs {
            applyTag(tag, to: assetID)
        }
        ensureSelectedAssetVisible()

        if recordHistory {
            let command = TagEditCommand(assetIDs: changedIDs, previousTags: previousTags, updatedTag: tag)
            tagUndoStack.append(command)
            if tagUndoStack.count > maxTagHistory {
                tagUndoStack.removeFirst(tagUndoStack.count - maxTagHistory)
            }
            tagRedoStack = []
        }
    }

    private func applyTag(_ tag: PhotoTag?, to assetID: PhotoAsset.ID) {
        guard photoAssets.contains(where: { $0.id == assetID }) else { return }
        if let tag {
            tags[assetID] = tag
            applyFinderTag(tag, to: assetID)
            if tag == .keep, let asset = photoAssets.first(where: { $0.id == assetID }) {
                _ = ensureQueuedForExport(asset)
            } else {
                removePendingQueueEntry(for: assetID)
            }
        } else {
            tags[assetID] = nil
            clearFinderColorTags(for: assetID)
            removePendingQueueEntry(for: assetID)
        }
    }

    private func applyFinderTag(_ tag: PhotoTag, to assetID: PhotoAsset.ID) {
        guard let selectedAsset = photoAssets.first(where: { $0.id == assetID }) else {
            return
        }

        Task {
            do {
                try await finderTagManager.applyTag(for: tag, to: selectedAsset.url)
            } catch {
                await MainActor.run {
                    self.exportStatus = "Could not set Finder tag for \(selectedAsset.filename)."
                }
            }
        }
    }

    private func clearFinderColorTags(for assetID: PhotoAsset.ID) {
        guard let selectedAsset = photoAssets.first(where: { $0.id == assetID }) else {
            return
        }

        Task {
            do {
                try await finderTagManager.clearColorTags(for: selectedAsset.url)
            } catch {
                await MainActor.run {
                    self.exportStatus = "Could not clear Finder tags for \(selectedAsset.filename)."
                }
            }
        }
    }

    private func moveSelection(by offset: Int) {
        let visible = visiblePhotoAssets
        guard !visible.isEmpty else {
            selectedAssetID = nil
            selectedAssetIDs = []
            selectionAnchorAssetID = nil
            return
        }

        guard let selectedAssetID,
              let currentIndex = visible.firstIndex(where: { $0.id == selectedAssetID }) else {
            if let firstID = visible.first?.id {
                selectSingleAsset(firstID)
            }
            return
        }

        let targetIndex = max(0, min(visible.count - 1, currentIndex + offset))
        selectSingleAsset(visible[targetIndex].id)
    }

    private func moveSelectionVertically(direction: Int) {
        let sections = visibleSections()
        guard !sections.isEmpty else {
            selectedAssetID = nil
            selectedAssetIDs = []
            selectionAnchorAssetID = nil
            return
        }

        guard let selectedAssetID,
              let current = locateAsset(selectedAssetID, in: sections) else {
            if let firstID = sections.first?.assets.first?.id {
                selectSingleAsset(firstID)
            }
            return
        }

        let columns = max(1, gridColumnCount)
        let column = current.assetIndex % columns
        let sameSectionTarget = current.assetIndex + (direction * columns)
        if sameSectionTarget >= 0 && sameSectionTarget < current.section.assets.count {
            selectSingleAsset(current.section.assets[sameSectionTarget].id)
            return
        }

        let adjacentSectionIndex = current.sectionIndex + direction
        guard adjacentSectionIndex >= 0, adjacentSectionIndex < sections.count else {
            return
        }
        let adjacentSectionAssets = sections[adjacentSectionIndex].assets
        guard !adjacentSectionAssets.isEmpty else { return }

        if direction > 0 {
            let targetIndex = min(column, adjacentSectionAssets.count - 1)
            selectSingleAsset(adjacentSectionAssets[targetIndex].id)
            return
        }

        let lastRowStart = ((adjacentSectionAssets.count - 1) / columns) * columns
        let targetIndex = min(lastRowStart + column, adjacentSectionAssets.count - 1)
        selectSingleAsset(adjacentSectionAssets[targetIndex].id)
    }

    private func visibleSections() -> [VisibleSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visiblePhotoAssets) { asset in
            asset.captureDate.map { calendar.startOfDay(for: $0) }
        }

        let orderedDates = grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (left?, right?):
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return false
            }
        }

        return orderedDates.map { date in
            let assets = (grouped[date] ?? []).sorted { lhs, rhs in
                switch (lhs.captureDate, rhs.captureDate) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate < rightDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
                }
            }
            return VisibleSection(date: date, assets: assets)
        }
    }

    private func locateAsset(_ id: PhotoAsset.ID, in sections: [VisibleSection]) -> (sectionIndex: Int, assetIndex: Int, section: VisibleSection)? {
        for (sectionIndex, section) in sections.enumerated() {
            if let assetIndex = section.assets.firstIndex(where: { $0.id == id }) {
                return (sectionIndex, assetIndex, section)
            }
        }
        return nil
    }

    private func ensureSelectedAssetVisible(defaultToFirst: Bool = false) {
        let visible = visiblePhotoAssets
        guard !visible.isEmpty else {
            selectedAssetID = nil
            selectedAssetIDs = []
            selectionAnchorAssetID = nil
            return
        }

        let visibleIDs = Set(visible.map(\.id))
        selectedAssetIDs = selectedAssetIDs.intersection(visibleIDs)
        if selectedAssetIDs.isEmpty, let selectedAssetID, visibleIDs.contains(selectedAssetID) {
            selectedAssetIDs = [selectedAssetID]
        }

        if let selectedAssetID, visibleIDs.contains(selectedAssetID) {
            selectedAssetIDs.insert(selectedAssetID)
            return
        }

        if defaultToFirst || selectedAssetID == nil {
            if let firstID = visible.first?.id {
                selectedAssetID = firstID
                selectedAssetIDs = [firstID]
                selectionAnchorAssetID = firstID
            }
        } else {
            if let firstID = visible.first?.id {
                selectedAssetID = firstID
                selectedAssetIDs = [firstID]
                selectionAnchorAssetID = firstID
            }
        }
    }

    private func cycleSelectedRating() {
        guard let selectedAssetID else { return }
        let current = ratings[selectedAssetID] ?? 0
        let next = current >= 5 ? 0 : current + 1
        setRating(next, for: selectedAssetID)
    }

    private func targetAssetIDsForTagging() -> [PhotoAsset.ID] {
        if !selectedAssetIDs.isEmpty {
            let selected = selectedAssetIDs
            return visiblePhotoAssets.map(\.id).filter { selected.contains($0) }
        }
        if let selectedAssetID {
            return [selectedAssetID]
        }
        return []
    }

    private func selectSingleAsset(_ assetID: PhotoAsset.ID) {
        selectedAssetID = assetID
        selectedAssetIDs = [assetID]
        selectionAnchorAssetID = assetID
    }

    private func setRating(_ value: Int, for assetID: PhotoAsset.ID) {
        let clamped = min(max(value, 0), 5)
        if clamped == 0 {
            ratings[assetID] = nil
        } else {
            ratings[assetID] = clamped
        }
        persistRatingsForVisibleAssets()
    }

    private func loadRatings(for assets: [PhotoAsset]) -> [PhotoAsset.ID: Int] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.ratingsDefaultsKey) as? [String: Int] else {
            return [:]
        }
        var mapped: [PhotoAsset.ID: Int] = [:]
        for asset in assets {
            if let value = raw[asset.url.path], value > 0 {
                mapped[asset.id] = min(max(value, 1), 5)
            }
        }
        return mapped
    }

    private func persistRatingsForVisibleAssets() {
        var raw = UserDefaults.standard.dictionary(forKey: Self.ratingsDefaultsKey) as? [String: Int] ?? [:]
        for asset in photoAssets {
            let rating = ratings[asset.id] ?? 0
            if rating > 0 {
                raw[asset.url.path] = rating
            } else {
                raw.removeValue(forKey: asset.url.path)
            }
        }
        UserDefaults.standard.set(raw, forKey: Self.ratingsDefaultsKey)
    }
}

private extension BrowserViewModel {
    struct VisibleSection {
        let date: Date?
        let assets: [PhotoAsset]
    }
}

private extension BrowserViewModel {
    static func loadPersistedSubfolderTemplate() -> String {
        let defaults = UserDefaults.standard
        let key = exportSubfolderTemplateDefaultsKey

        guard let stored = defaults.string(forKey: key) else {
            return "{shoot}"
        }

        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "{date}-{shoot}" {
            defaults.set("{shoot}", forKey: key)
            return "{shoot}"
        }
        return stored
    }
}

private struct ExportQueueRecord: Codable {
    let id: UUID
    let sourcePath: String
    let filename: String
    let captureDate: Date?
    let fileSize: Int64?
    let state: ExportItemState
    let destinationPath: String?
    let errorMessage: String?
    let warningMessage: String?
    let startedAt: Date?
    let completedAt: Date?
    let bytesWritten: Int64?

    init(item: ExportQueueItem) {
        self.id = item.id
        self.sourcePath = item.asset.url.path
        self.filename = item.asset.filename
        self.captureDate = item.asset.captureDate
        self.fileSize = item.asset.fileSize
        self.state = item.state
        self.destinationPath = item.destinationPath
        self.errorMessage = item.errorMessage
        self.warningMessage = item.warningMessage
        self.startedAt = item.startedAt
        self.completedAt = item.completedAt
        self.bytesWritten = item.bytesWritten
    }

    var asQueueItem: ExportQueueItem {
        ExportQueueItem(
            id: id,
            asset: PhotoAsset(
                url: URL(fileURLWithPath: sourcePath),
                filename: filename,
                captureDate: captureDate,
                fileSize: fileSize
            ),
            state: state,
            destinationPath: destinationPath,
            errorMessage: errorMessage,
            warningMessage: warningMessage,
            startedAt: startedAt,
            completedAt: completedAt,
            bytesWritten: bytesWritten
        )
    }
}

struct ExportCompletionBanner: Identifiable, Equatable {
    let id = UUID()
    let folderPath: String
    let exportedCount: Int
}

extension Notification.Name {
    static let darkroomShortcutExportRequested = Notification.Name("darkroom.shortcut.export.requested")
}
