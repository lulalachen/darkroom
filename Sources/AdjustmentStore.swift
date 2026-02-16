import Foundation

actor AdjustmentStore {
    static let shared = AdjustmentStore()

    private let libraryManager: LibraryManager
    private var loaded = false
    private var adjustments: [String: AdjustmentSettings] = [:]
    private var bookmarks: [String: [AdjustmentBookmark]] = [:]
    private var derivedMetadata: [String: DerivedAdjustmentMetadata] = [:]
    private var userPresets: [AdjustmentPreset] = []
    private var adjustmentsURL: URL?
    private var bookmarksURL: URL?
    private var derivedMetadataURL: URL?
    private var presetsURL: URL?

    init(libraryManager: LibraryManager = .shared) {
        self.libraryManager = libraryManager
    }

    func adjustment(for assetPath: String) async -> AdjustmentSettings {
        await ensureLoaded()
        return adjustments[assetPath] ?? .default
    }

    func saveAdjustment(_ settings: AdjustmentSettings, for assetPath: String) async {
        await ensureLoaded()
        adjustments[assetPath] = settings
        persistAdjustments()
    }

    func presets() async -> [AdjustmentPreset] {
        await ensureLoaded()
        return AdjustmentPreset.builtIns + userPresets
    }

    func bookmarks(for assetPath: String) async -> [AdjustmentBookmark] {
        await ensureLoaded()
        return bookmarks[assetPath] ?? []
    }

    func saveBookmark(name: String, settings: AdjustmentSettings, for assetPath: String) async {
        await ensureLoaded()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let bookmark = AdjustmentBookmark(name: trimmed, settings: settings, updatedAt: Date())
        var assetBookmarks = bookmarks[assetPath] ?? []
        assetBookmarks.removeAll { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        assetBookmarks.append(bookmark)
        bookmarks[assetPath] = assetBookmarks.sorted { $0.updatedAt > $1.updatedAt }
        persistBookmarks()
    }

    func bookmark(named name: String, for assetPath: String) async -> AdjustmentBookmark? {
        await ensureLoaded()
        return bookmarks[assetPath]?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func syncDerivedMetadata(for assetPath: String, sourceSize: CGSize, settings: AdjustmentSettings) async {
        await ensureLoaded()
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }

        let hasAdjustments = settings != .default
        let scale = max(0.4, min(1.0, settings.cropScale))
        let width = Int((sourceSize.width * scale).rounded())
        let height = Int((sourceSize.height * scale).rounded())
        let rotation = settings.rotateDegrees + settings.straightenDegrees

        derivedMetadata[assetPath] = DerivedAdjustmentMetadata(
            assetPath: assetPath,
            updatedAt: Date(),
            hasAdjustments: hasAdjustments,
            rotationDegrees: rotation,
            cropScale: scale,
            estimatedOutputWidth: max(1, width),
            estimatedOutputHeight: max(1, height)
        )
        persistDerivedMetadata()
    }

    func syncDerivedMetadataFromRendered(
        for assetPath: String,
        renderedSize: CGSize,
        settings: AdjustmentSettings
    ) async {
        await ensureLoaded()
        guard renderedSize.width > 0, renderedSize.height > 0 else { return }
        let rotation = settings.rotateDegrees + settings.straightenDegrees
        derivedMetadata[assetPath] = DerivedAdjustmentMetadata(
            assetPath: assetPath,
            updatedAt: Date(),
            hasAdjustments: settings != .default,
            rotationDegrees: rotation,
            cropScale: max(0.4, min(1.0, settings.cropScale)),
            estimatedOutputWidth: Int(renderedSize.width.rounded()),
            estimatedOutputHeight: Int(renderedSize.height.rounded())
        )
        persistDerivedMetadata()
    }

    func savePreset(name: String, settings: AdjustmentSettings) async {
        await ensureLoaded()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = AdjustmentPreset(id: UUID(), name: trimmed, settings: settings, isBuiltIn: false)
        userPresets.append(preset)
        persistPresets()
    }

    func deleteUserPreset(id: UUID) async {
        await ensureLoaded()
        userPresets.removeAll { $0.id == id }
        persistPresets()
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        let paths = try? await libraryManager.bootstrapIfNeeded()
        let manifestsRoot = paths?.manifestsRoot
            ?? FileManager.default.temporaryDirectory.appending(path: "DarkroomFallbackManifests", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: manifestsRoot, withIntermediateDirectories: true)

        let adjustmentsURL = manifestsRoot.appending(path: "adjustments.json", directoryHint: .notDirectory)
        let bookmarksURL = manifestsRoot.appending(path: "adjustment-bookmarks.json", directoryHint: .notDirectory)
        let derivedMetadataURL = manifestsRoot.appending(path: "adjustment-derived-metadata.json", directoryHint: .notDirectory)
        let presetsURL = manifestsRoot.appending(path: "presets.json", directoryHint: .notDirectory)
        self.adjustmentsURL = adjustmentsURL
        self.bookmarksURL = bookmarksURL
        self.derivedMetadataURL = derivedMetadataURL
        self.presetsURL = presetsURL

        if let data = try? Data(contentsOf: adjustmentsURL),
           let decoded = try? JSONDecoder().decode([String: AdjustmentSettings].self, from: data) {
            adjustments = decoded
        }
        if let data = try? Data(contentsOf: bookmarksURL),
           let decoded = try? JSONDecoder().decode([String: [AdjustmentBookmark]].self, from: data) {
            bookmarks = decoded
        }
        if let data = try? Data(contentsOf: derivedMetadataURL),
           let decoded = try? JSONDecoder().decode([String: DerivedAdjustmentMetadata].self, from: data) {
            derivedMetadata = decoded
        }
        if let data = try? Data(contentsOf: presetsURL),
           let decoded = try? JSONDecoder().decode([AdjustmentPreset].self, from: data) {
            userPresets = decoded
        }
        loaded = true
    }

    private func persistAdjustments() {
        guard let url = adjustmentsURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(adjustments) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistPresets() {
        guard let url = presetsURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(userPresets) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistBookmarks() {
        guard let url = bookmarksURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(bookmarks) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistDerivedMetadata() {
        guard let url = derivedMetadataURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(derivedMetadata) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
