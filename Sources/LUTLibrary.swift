import Foundation
import simd

struct LUTRecord: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let dimension: Int
    let path: String
    let checksum: String
    let domainMin: [Float]
    let domainMax: [Float]
    let createdAt: Date
}

struct LUTPayload {
    let id: String
    let dimension: Int
    let domainMin: SIMD3<Float>
    let domainMax: SIMD3<Float>
    let data: Data
}

actor LUTLibrary {
    static let shared = LUTLibrary()
    private static let bundledDefaultLUTFolder = "LUT/gfx100rf-3d-lut-v100"

    private let libraryManager: LibraryManager
    private var loaded = false
    private var records: [LUTRecord] = []
    private var recordsURL: URL?
    private var lutsFolderURL: URL?

    init(libraryManager: LibraryManager = .shared) {
        self.libraryManager = libraryManager
    }

    func allLUTs() async -> [LUTRecord] {
        await ensureLoaded()
        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func lutPayload(for id: String) async -> LUTPayload? {
        await ensureLoaded()
        guard let record = records.first(where: { $0.id == id }) else { return nil }
        let fileURL = URL(fileURLWithPath: record.path, isDirectory: false)
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let cube = try? CubeLUTParser.parse(text) else {
            return nil
        }
        return LUTPayload(
            id: record.id,
            dimension: cube.dimension,
            domainMin: cube.domainMin,
            domainMax: cube.domainMax,
            data: cube.data
        )
    }

    func importCube(from sourceURL: URL) async throws -> LUTRecord {
        await ensureLoaded()
        guard let lutsFolderURL else { throw CubeLUTParseError.missingSize }

        let sourceData = try Data(contentsOf: sourceURL)
        guard let sourceText = String(data: sourceData, encoding: .utf8) else {
            throw CubeLUTParseError.invalidEntry("File could not be decoded as UTF-8 text.")
        }
        let parsed = try CubeLUTParser.parse(sourceText)
        let checksum = CubeLUTParser.checksumSHA256Hex(sourceData)

        if let existing = records.first(where: { $0.checksum == checksum }) {
            return existing
        }

        let id = UUID().uuidString.lowercased()
        let filename = "\(id).cube"
        let destinationURL = lutsFolderURL.appending(path: filename, directoryHint: .notDirectory)
        try sourceData.write(to: destinationURL, options: [.atomic])

        let displayName = parsed.title?.isEmpty == false
            ? parsed.title!
            : sourceURL.deletingPathExtension().lastPathComponent
        let record = LUTRecord(
            id: id,
            name: displayName,
            dimension: parsed.dimension,
            path: destinationURL.path,
            checksum: checksum,
            domainMin: [parsed.domainMin.x, parsed.domainMin.y, parsed.domainMin.z],
            domainMax: [parsed.domainMax.x, parsed.domainMax.y, parsed.domainMax.z],
            createdAt: Date()
        )
        records.append(record)
        persistRecords()
        return record
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        let paths = try? await libraryManager.bootstrapIfNeeded()
        let manifestsRoot = paths?.manifestsRoot
            ?? FileManager.default.temporaryDirectory.appending(path: "DarkroomFallbackManifests", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: manifestsRoot, withIntermediateDirectories: true)

        let lutsFolderURL = manifestsRoot.appending(path: "LUTs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: lutsFolderURL, withIntermediateDirectories: true)
        let recordsURL = manifestsRoot.appending(path: "luts.json", directoryHint: .notDirectory)

        self.lutsFolderURL = lutsFolderURL
        self.recordsURL = recordsURL
        if let data = try? Data(contentsOf: recordsURL),
           let decoded = try? JSONDecoder().decode([LUTRecord].self, from: data) {
            records = decoded
        }
        loaded = true
        await importBundledDefaultsIfNeeded()
    }

    private func persistRecords() {
        guard let recordsURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: recordsURL, options: .atomic)
        }
    }

    private func importBundledDefaultsIfNeeded() async {
        guard let rootURL = bundledDefaultLUTRootURL() else { return }
        let cubeURLs = Self.cubeFileURLs(in: rootURL)
        for cubeURL in cubeURLs {
            _ = try? await importCube(from: cubeURL)
        }
    }

    private func bundledDefaultLUTRootURL() -> URL? {
        #if SWIFT_PACKAGE
        let base = Bundle.module.resourceURL
        #else
        let base = Bundle.main.resourceURL
        #endif
        return base?.appending(path: Self.bundledDefaultLUTFolder, directoryHint: .isDirectory)
    }

    private static func cubeFileURLs(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "cube" else { continue }
            urls.append(fileURL)
        }
        return urls.sorted { $0.path < $1.path }
    }
}
