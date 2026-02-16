import Combine
import Foundation

@MainActor
final class BrowserViewModel: ObservableObject {
    enum AssetFilter: String, CaseIterable, Identifiable {
        case all
        case keep
        case reject
        case untagged

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .keep:
                return "Green"
            case .reject:
                return "Red"
            case .untagged:
                return "Untagged"
            }
        }
    }

    @Published private(set) var volumes: [Volume] = []
    @Published var selectedVolume: Volume? {
        didSet {
            guard selectedVolume != oldValue else { return }
            loadAssetsForSelection()
        }
    }
    @Published private(set) var photoAssets: [PhotoAsset] = []
    @Published var selectedAssetID: PhotoAsset.ID?
    @Published private(set) var tags: [PhotoAsset.ID: PhotoTag] = [:]
    @Published var assetFilter: AssetFilter = .all {
        didSet {
            ensureSelectedAssetVisible()
        }
    }
    @Published var isLoadingAssets: Bool = false
    @Published private(set) var isImporting: Bool = false
    @Published private(set) var importStatus: String?
    @Published private(set) var gridColumnCount: Int = 1
    @Published private(set) var importItemStates: [PhotoAsset.ID: ImportItemState] = [:]
    @Published private(set) var recentImportSessions: [ImportSessionSummary] = []
    @Published private(set) var selectedSessionItems: [ImportQueueItem] = []
    @Published var selectedImportSessionID: Int64? {
        didSet {
            guard selectedImportSessionID != oldValue else { return }
            loadSelectedSessionItems()
        }
    }

    var filteredVolumes: [Volume] {
        volumes.filter { $0.isRemovable }
    }

    private let volumeWatcher: VolumeWatcher
    private let enumerator = PhotoEnumerator()
    private let libraryManager: LibraryManager
    private let importManager: ImportManager
    private let finderTagManager = FinderTagManager()
    private var cancellables: Set<AnyCancellable> = []

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

    init(volumeWatcher: VolumeWatcher? = nil, libraryManager: LibraryManager = .shared, mockVolumes: [Volume]? = nil) {
        let watcher = volumeWatcher ?? VolumeWatcher()
        self.volumeWatcher = watcher
        self.libraryManager = libraryManager
        self.importManager = ImportManager(libraryManager: libraryManager)
        if let mockVolumes {
            self.volumes = mockVolumes
            self.selectedVolume = mockVolumes.first
        } else {
            bindVolumeUpdates()
            watcher.refresh()
        }
    }

    func refreshVolumes() {
        volumeWatcher.refresh()
    }

    func select(_ asset: PhotoAsset) {
        selectedAssetID = asset.id
    }

    func tagSelectedAsKeep() {
        setSelectedTag(.keep)
    }

    func tagSelectedAsReject() {
        setSelectedTag(.reject)
    }

    func tag(for asset: PhotoAsset) -> PhotoTag? {
        tags[asset.id]
    }

    func importMarkedPhotos() {
        guard !isImporting else { return }
        let marked = photoAssets.filter { tags[$0.id] == .keep }
        let currentVolume = selectedVolume
        guard !marked.isEmpty else {
            importStatus = "No photos tagged Green yet."
            return
        }

        isImporting = true
        importStatus = "Importing \(marked.count) photo(s)..."

        Task {
            do {
                let result = try await importManager.importAssets(marked, sourceVolume: currentVolume) { [weak self] snapshot in
                    Task { @MainActor in
                        self?.setImportState(forSourcePath: snapshot.item.sourcePath, state: snapshot.item.state)
                    }
                }
                await MainActor.run {
                    let summary = result.session
                    self.importStatus = "Imported \(summary.importedCount), skipped \(summary.duplicateCount), failed \(summary.failedCount)."
                    self.isImporting = false
                    self.refreshImportHistory()
                }
            } catch {
                await MainActor.run {
                    self.importStatus = "Import failed: \(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }

    func prepareLibraryIfNeeded() async {
        do {
            _ = try await libraryManager.bootstrapIfNeeded()
            _ = try await importManager.resumeIncompleteImports { [weak self] snapshot in
                Task { @MainActor in
                    self?.setImportState(forSourcePath: snapshot.item.sourcePath, state: snapshot.item.state)
                }
            }
            refreshImportHistory()
        } catch {
            importStatus = "Could not initialize library: \(error.localizedDescription)"
        }
    }

    func refreshImportHistory() {
        Task {
            do {
                let sessions = try await importManager.recentSessions(limit: 20)
                await MainActor.run {
                    self.recentImportSessions = sessions
                    if self.selectedImportSessionID == nil {
                        self.selectedImportSessionID = sessions.first?.id
                    } else {
                        self.loadSelectedSessionItems()
                    }
                }
            } catch {
                await MainActor.run {
                    self.importStatus = "Could not load import history: \(error.localizedDescription)"
                }
            }
        }
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
        moveSelection(by: -gridColumnCount)
    }

    func selectDownAsset() {
        moveSelection(by: gridColumnCount)
    }

    func setGridColumnCount(_ count: Int) {
        gridColumnCount = max(1, count)
    }

    func clearSelectedTag() {
        guard let selectedAssetID else { return }
        tags[selectedAssetID] = nil
        clearFinderColorTags(for: selectedAssetID)
        ensureSelectedAssetVisible()
    }

    private func bindVolumeUpdates() {
        volumeWatcher.$volumes
            .receive(on: RunLoop.main)
            .sink { [weak self] newVolumes in
                guard let self = self else { return }
                self.volumes = newVolumes
                if let currentlySelected = self.selectedVolume,
                   !newVolumes.contains(currentlySelected) {
                    self.selectedVolume = newVolumes.first { $0.isLikelyCameraCard } ?? newVolumes.first
                } else if self.selectedVolume == nil {
                    self.selectedVolume = newVolumes.first { $0.isLikelyCameraCard } ?? newVolumes.first
                }
            }
            .store(in: &cancellables)
    }

    private func loadAssetsForSelection() {
        guard let volume = selectedVolume, let root = volume.importRoot else {
            photoAssets = []
            selectedAssetID = nil
            tags = [:]
            importItemStates = [:]
            return
        }
        isLoadingAssets = true
        importStatus = nil
        Task {
            let assets = await enumerator.assets(at: root)
            let loadedTags = await finderTagManager.tagMap(for: assets)
            await MainActor.run {
                self.photoAssets = assets
                self.tags = loadedTags
                self.importItemStates = [:]
                self.ensureSelectedAssetVisible(defaultToFirst: true)
                self.isLoadingAssets = false
            }
        }
    }

    private func loadSelectedSessionItems() {
        guard let selectedImportSessionID else {
            selectedSessionItems = []
            return
        }
        Task {
            do {
                let items = try await importManager.sessionItems(sessionID: selectedImportSessionID)
                await MainActor.run {
                    self.selectedSessionItems = items
                }
            } catch {
                await MainActor.run {
                    self.importStatus = "Could not load session items: \(error.localizedDescription)"
                }
            }
        }
    }

    private func setImportState(forSourcePath sourcePath: String, state: ImportItemState) {
        guard let matchingAsset = photoAssets.first(where: { $0.url.path == sourcePath }) else {
            return
        }
        importItemStates[matchingAsset.id] = state
    }

    private func setSelectedTag(_ tag: PhotoTag) {
        guard let selectedAssetID else { return }
        tags[selectedAssetID] = tag
        applyFinderTag(tag, to: selectedAssetID)
        ensureSelectedAssetVisible()
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
                    self.importStatus = "Could not set Finder tag for \(selectedAsset.filename)."
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
                    self.importStatus = "Could not clear Finder tags for \(selectedAsset.filename)."
                }
            }
        }
    }

    private func moveSelection(by offset: Int) {
        let visible = visiblePhotoAssets
        guard !visible.isEmpty else {
            selectedAssetID = nil
            return
        }

        guard let selectedAssetID,
              let currentIndex = visible.firstIndex(where: { $0.id == selectedAssetID }) else {
            self.selectedAssetID = visible.first?.id
            return
        }

        let targetIndex = max(0, min(visible.count - 1, currentIndex + offset))
        self.selectedAssetID = visible[targetIndex].id
    }

    private func ensureSelectedAssetVisible(defaultToFirst: Bool = false) {
        let visible = visiblePhotoAssets
        guard !visible.isEmpty else {
            selectedAssetID = nil
            return
        }

        if let selectedAssetID, visible.contains(where: { $0.id == selectedAssetID }) {
            return
        }

        if defaultToFirst || selectedAssetID == nil {
            selectedAssetID = visible.first?.id
        } else {
            selectedAssetID = visible.first?.id
        }
    }
}
