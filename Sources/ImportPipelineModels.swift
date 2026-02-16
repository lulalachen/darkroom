import Foundation

enum ImportItemState: String, Codable, CaseIterable {
    case queued
    case hashing
    case copying
    case verifying
    case done
    case skippedDuplicate = "skipped_duplicate"
    case failed

    var isTerminal: Bool {
        switch self {
        case .done, .skippedDuplicate, .failed:
            return true
        default:
            return false
        }
    }
}

struct ImportQueueItem: Identifiable, Hashable {
    let id: Int64
    let sessionID: Int64
    let sourcePath: String
    let sourceRelativePath: String
    let filename: String
    let state: ImportItemState
    let destinationPath: String?
    let contentHash: String?
    let errorMessage: String?
    let updatedAt: Date

    var sourceURL: URL {
        URL(fileURLWithPath: sourcePath)
    }
}

struct ImportSessionSummary: Identifiable, Hashable {
    let id: Int64
    let startedAt: Date
    let completedAt: Date?
    let sourceVolumePath: String
    let sourceVolumeName: String
    let renameTemplate: String
    let customPrefix: String
    let destinationCollection: String
    let metadataNote: String
    let requestedCount: Int
    let importedCount: Int
    let duplicateCount: Int
    let failedCount: Int
    let isCompleted: Bool
}

struct ImportProgressSnapshot {
    let sessionID: Int64
    let item: ImportQueueItem
}

struct ImportRunResult {
    let session: ImportSessionSummary
    let destinationRoot: URL
}

enum ImportRenameTemplate: String, CaseIterable, Identifiable, Codable {
    case original
    case dateSequence
    case customPrefix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .dateSequence: return "Date + Sequence"
        case .customPrefix: return "Custom Prefix"
        }
    }
}

struct ImportMetadataTweaks: Codable, Hashable {
    var creator: String
    var keywords: String
    var note: String

    static let empty = ImportMetadataTweaks(creator: "", keywords: "", note: "")
}

struct ImportOptions: Codable, Hashable {
    var renameTemplate: ImportRenameTemplate
    var customPrefix: String
    var destinationCollection: String
    var exportBasePath: String
    var exportFolderName: String
    var metadata: ImportMetadataTweaks

    static let `default` = ImportOptions(
        renameTemplate: .original,
        customPrefix: "",
        destinationCollection: "",
        exportBasePath: "",
        exportFolderName: "",
        metadata: .empty
    )
}

struct ImportFailure: Error {
    let message: String
}

struct ImportActivityEntry: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let title: String
    let detail: String
    let sessionID: Int64?
    let isError: Bool
}
