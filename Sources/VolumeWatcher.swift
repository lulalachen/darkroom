import AppKit
import Combine
import Foundation

@MainActor
final class VolumeWatcher: ObservableObject {
    @Published private(set) var volumes: [Volume] = []

    private var observers: [NSObjectProtocol] = []

    init() {
        startObserving()
        refresh()
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func refresh() {
        volumes = Volume.fetchMountedVolumes()
    }

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        let queue = OperationQueue.main
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: queue) { [weak self] _ in
            Task { await self?.refresh() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: queue) { [weak self] _ in
            Task { await self?.refresh() }
        })
    }
}
