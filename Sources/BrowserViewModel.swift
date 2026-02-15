import Combine
import Foundation

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published private(set) var volumes: [Volume] = []
    @Published var selectedVolume: Volume? {
        didSet {
            guard selectedVolume != oldValue else { return }
            loadAssetsForSelection()
        }
    }
    @Published private(set) var photoAssets: [PhotoAsset] = []
    @Published var isLoadingAssets: Bool = false

    var filteredVolumes: [Volume] {
        volumes.filter { $0.isRemovable }
    }

    private let volumeWatcher: VolumeWatcher
    private let enumerator = PhotoEnumerator()
    private var cancellables: Set<AnyCancellable> = []

    init(volumeWatcher: VolumeWatcher? = nil, mockVolumes: [Volume]? = nil) {
        let watcher = volumeWatcher ?? VolumeWatcher()
        self.volumeWatcher = watcher
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
            return
        }
        isLoadingAssets = true
        Task {
            let assets = await enumerator.assets(at: root)
            await MainActor.run {
                self.photoAssets = assets
                self.isLoadingAssets = false
            }
        }
    }
}
