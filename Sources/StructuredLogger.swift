import Foundation

actor StructuredLogger {
    static let shared = StructuredLogger()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func log(event: String, metadata: [String: String]) {
        guard UserDefaults.standard.bool(forKey: darkroomPrefTelemetryEnabledKey) else { return }
        let entry = LogEntry(createdAt: Date(), event: event, metadata: metadata)
        guard let data = try? encoder.encode(entry) else { return }
        let url = logURL()
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            var line = data
            line.append(0x0a)
            try? line.write(to: url, options: [.atomic])
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0a]))
        } catch {
            return
        }
    }

    private func logURL() -> URL {
        let logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: "Darkroom", directoryHint: .isDirectory)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Logs/Darkroom", directoryHint: .isDirectory)
        return logsDirectory.appending(path: "app-events.jsonl", directoryHint: .notDirectory)
    }
}

private struct LogEntry: Codable {
    let createdAt: Date
    let event: String
    let metadata: [String: String]
}
