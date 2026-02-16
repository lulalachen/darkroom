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

struct ImportFailure: Error {
    let message: String
}

