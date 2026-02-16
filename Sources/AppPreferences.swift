import Foundation
import Combine

let darkroomPrefCacheSizeMBKey = "darkroom.preferences.cacheSizeMB"
let darkroomPrefFullImageCacheCountKey = "darkroom.preferences.fullImageCacheCount"
let darkroomPrefTelemetryEnabledKey = "darkroom.preferences.telemetryEnabled"
let darkroomPrefShortcutProfileKey = "darkroom.preferences.shortcutProfile"
let darkroomPrefDefaultLibraryPathKey = "darkroom.preferences.defaultLibraryPath"

enum KeyboardShortcutProfile: String, Codable, CaseIterable, Identifiable {
    case classicZXC
    case numeric120

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classicZXC: return "Classic (Z/X/C)"
        case .numeric120: return "Numeric (1/2/0)"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var cacheSizeMB: Int {
        didSet {
            cacheSizeMB = min(max(cacheSizeMB, 128), 4096)
            UserDefaults.standard.set(cacheSizeMB, forKey: darkroomPrefCacheSizeMBKey)
            notifyChanged()
        }
    }

    @Published var fullImageCacheCount: Int {
        didSet {
            fullImageCacheCount = min(max(fullImageCacheCount, 16), 1000)
            UserDefaults.standard.set(fullImageCacheCount, forKey: darkroomPrefFullImageCacheCountKey)
            notifyChanged()
        }
    }

    @Published var telemetryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(telemetryEnabled, forKey: darkroomPrefTelemetryEnabledKey)
            notifyChanged()
        }
    }

    @Published var shortcutProfile: KeyboardShortcutProfile {
        didSet {
            UserDefaults.standard.set(shortcutProfile.rawValue, forKey: darkroomPrefShortcutProfileKey)
            notifyChanged()
        }
    }

    @Published var defaultLibraryPath: String {
        didSet {
            UserDefaults.standard.set(defaultLibraryPath, forKey: darkroomPrefDefaultLibraryPathKey)
            notifyChanged()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedProfile = KeyboardShortcutProfile(rawValue: defaults.string(forKey: darkroomPrefShortcutProfileKey) ?? "")
        self.cacheSizeMB = defaults.integer(forKey: darkroomPrefCacheSizeMBKey) == 0 ? 512 : defaults.integer(forKey: darkroomPrefCacheSizeMBKey)
        self.fullImageCacheCount = defaults.integer(forKey: darkroomPrefFullImageCacheCountKey) == 0 ? 120 : defaults.integer(forKey: darkroomPrefFullImageCacheCountKey)
        self.telemetryEnabled = defaults.bool(forKey: darkroomPrefTelemetryEnabledKey)
        self.shortcutProfile = storedProfile ?? .classicZXC
        self.defaultLibraryPath = defaults.string(forKey: darkroomPrefDefaultLibraryPathKey) ?? ""
    }

    var thumbnailCacheEntryLimit: Int {
        // Approximate 300 KB per thumbnail entry.
        max(64, (cacheSizeMB * 1024) / 300)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .darkroomPreferencesChanged, object: nil)
    }
}

extension Notification.Name {
    static let darkroomPreferencesChanged = Notification.Name("darkroom.preferences.changed")
}
