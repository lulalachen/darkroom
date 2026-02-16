import Foundation

enum ExportFileFormat: String, Codable, CaseIterable, Identifiable {
    case original
    case jpeg
    case heif
    case tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .jpeg: return "JPEG"
        case .heif: return "HEIF"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String? {
        switch self {
        case .original: return nil
        case .jpeg: return "jpg"
        case .heif: return "heic"
        case .tiff: return "tiff"
        }
    }
}

enum ExportColorSpace: String, Codable, CaseIterable, Identifiable {
    case sRGB
    case displayP3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sRGB: return "sRGB"
        case .displayP3: return "Display P3"
        }
    }
}

struct ExportPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var fileFormat: ExportFileFormat
    var longEdgePixels: Int
    var quality: Double
    var maxFileSizeKB: Int
    var colorSpace: ExportColorSpace
    var stripMetadata: Bool
    var watermarkEnabled: Bool
    var watermarkText: String

    init(
        id: UUID = UUID(),
        name: String,
        fileFormat: ExportFileFormat,
        longEdgePixels: Int,
        quality: Double,
        maxFileSizeKB: Int = 0,
        colorSpace: ExportColorSpace = .sRGB,
        stripMetadata: Bool = false,
        watermarkEnabled: Bool = false,
        watermarkText: String = "Darkroom"
    ) {
        self.id = id
        self.name = name
        self.fileFormat = fileFormat
        self.longEdgePixels = longEdgePixels
        self.quality = quality
        self.maxFileSizeKB = maxFileSizeKB
        self.colorSpace = colorSpace
        self.stripMetadata = stripMetadata
        self.watermarkEnabled = watermarkEnabled
        self.watermarkText = watermarkText
    }

    static let starterPresets: [ExportPreset] = [
        ExportPreset(name: "Social 2048", fileFormat: .jpeg, longEdgePixels: 2_048, quality: 0.82, maxFileSizeKB: 700, stripMetadata: true),
        ExportPreset(name: "Client High", fileFormat: .jpeg, longEdgePixels: 4_000, quality: 0.92, maxFileSizeKB: 4_500),
        ExportPreset(name: "Archive TIFF", fileFormat: .tiff, longEdgePixels: 0, quality: 1.0, colorSpace: .displayP3)
    ]
}

enum ExportItemState: String, Codable {
    case queued
    case rendering
    case writing
    case done
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .done, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

struct ExportQueueItem: Identifiable, Hashable {
    let id: UUID
    let asset: PhotoAsset
    var state: ExportItemState
    var destinationPath: String? = nil
    var errorMessage: String? = nil
    var warningMessage: String? = nil
    var startedAt: Date? = nil
    var completedAt: Date? = nil
    var bytesWritten: Int64? = nil
}

struct ExportDestinationOptions: Codable, Hashable {
    var basePath: String
    var subfolderTemplate: String
    var shootName: String

    static let `default` = ExportDestinationOptions(
        basePath: "",
        subfolderTemplate: "{date}-{shoot}",
        shootName: "Session"
    )
}

struct ExportProgressSnapshot {
    let sourcePath: String
    let state: ExportItemState
    let destinationPath: String?
    let errorMessage: String?
    let warningMessage: String?
    let bytesWritten: Int64?
}

struct ExportRunSummary {
    let queuedCount: Int
    let exportedCount: Int
    let failedCount: Int
    let cancelledCount: Int
}
