import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor ImportStore {
    private let databaseURL: URL
    private var db: OpaquePointer?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func prepareSchema() throws {
        try ensureOpen()
        try execute(
            """
            CREATE TABLE IF NOT EXISTS import_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at REAL NOT NULL,
                completed_at REAL,
                source_volume_path TEXT NOT NULL,
                source_volume_name TEXT NOT NULL,
                rename_template TEXT NOT NULL DEFAULT 'original',
                custom_prefix TEXT NOT NULL DEFAULT '',
                destination_collection TEXT NOT NULL DEFAULT '',
                metadata_note TEXT NOT NULL DEFAULT '',
                requested_count INTEGER NOT NULL,
                imported_count INTEGER NOT NULL DEFAULT 0,
                duplicate_count INTEGER NOT NULL DEFAULT 0,
                failed_count INTEGER NOT NULL DEFAULT 0,
                is_completed INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS import_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                source_path TEXT NOT NULL,
                source_relative_path TEXT NOT NULL,
                filename TEXT NOT NULL,
                state TEXT NOT NULL,
                destination_path TEXT,
                content_hash TEXT,
                error_message TEXT,
                updated_at REAL NOT NULL,
                UNIQUE(session_id, source_path),
                FOREIGN KEY(session_id) REFERENCES import_sessions(id)
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS assets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_fingerprint TEXT NOT NULL UNIQUE,
                content_hash TEXT NOT NULL UNIQUE,
                original_path TEXT NOT NULL,
                filename TEXT NOT NULL,
                rating INTEGER NOT NULL DEFAULT 0,
                edit_stack_pointer TEXT NOT NULL DEFAULT '',
                imported_at REAL NOT NULL,
                session_id INTEGER NOT NULL,
                FOREIGN KEY(session_id) REFERENCES import_sessions(id)
            );
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_items_session_state ON import_items(session_id, state);")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_updated ON import_items(updated_at);")
        try ensureSessionColumns()
        try ensureAssetColumns()
    }

    func createSession(sourceVolumePath: String, sourceVolumeName: String, requestedCount: Int, options: ImportOptions) throws -> Int64 {
        try ensureOpen()
        let sql = """
        INSERT INTO import_sessions (
            started_at, source_volume_path, source_volume_name, rename_template, custom_prefix, destination_collection, metadata_note, requested_count, is_completed
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 2, sourceVolumePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, sourceVolumeName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, options.renameTemplate.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, options.customPrefix, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, persistedCollection(from: options), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 7, metadataSummary(from: options), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 8, Int64(requestedCount))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
        return sqlite3_last_insert_rowid(db)
    }

    func enqueueItems(sessionID: Int64, assets: [PhotoAsset], sourceRoot: URL) throws {
        try ensureOpen()
        let sql = """
        INSERT OR IGNORE INTO import_items (
            session_id, source_path, source_relative_path, filename, state, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        for asset in assets {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, sessionID)
            sqlite3_bind_text(statement, 2, asset.url.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, relativePath(for: asset.url, root: sourceRoot), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, asset.filename, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, ImportItemState.queued.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw lastError()
            }
        }
    }

    func items(for sessionID: Int64) throws -> [ImportQueueItem] {
        try ensureOpen()
        let sql = """
        SELECT id, session_id, source_path, source_relative_path, filename, state, destination_path, content_hash, error_message, updated_at
        FROM import_items
        WHERE session_id = ?
        ORDER BY id ASC;
        """
        return try readItems(sql: sql, binder: { statement in
            sqlite3_bind_int64(statement, 1, sessionID)
        })
    }

    func pendingItems(for sessionID: Int64) throws -> [ImportQueueItem] {
        try ensureOpen()
        let sql = """
        SELECT id, session_id, source_path, source_relative_path, filename, state, destination_path, content_hash, error_message, updated_at
        FROM import_items
        WHERE session_id = ? AND state NOT IN (?, ?, ?)
        ORDER BY id ASC;
        """
        return try readItems(sql: sql, binder: { statement in
            sqlite3_bind_int64(statement, 1, sessionID)
            sqlite3_bind_text(statement, 2, ImportItemState.done.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, ImportItemState.skippedDuplicate.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, ImportItemState.failed.rawValue, -1, SQLITE_TRANSIENT)
        })
    }

    func markItemState(
        itemID: Int64,
        state: ImportItemState,
        destinationPath: String? = nil,
        contentHash: String? = nil,
        errorMessage: String? = nil
    ) throws {
        try ensureOpen()
        let sql = """
        UPDATE import_items
        SET state = ?, destination_path = COALESCE(?, destination_path), content_hash = COALESCE(?, content_hash), error_message = ?, updated_at = ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, state.rawValue, -1, SQLITE_TRANSIENT)
        if let destinationPath {
            sqlite3_bind_text(statement, 2, destinationPath, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        if let contentHash {
            sqlite3_bind_text(statement, 3, contentHash, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        if let errorMessage {
            sqlite3_bind_text(statement, 4, errorMessage, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 6, itemID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    func hasAsset(contentHash: String, sourceFingerprint: String) throws -> Bool {
        try ensureOpen()
        let sql = "SELECT 1 FROM assets WHERE content_hash = ? OR source_fingerprint = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, sourceFingerprint, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func recordImportedAsset(
        sourceFingerprint: String,
        contentHash: String,
        originalPath: String,
        filename: String,
        sessionID: Int64
    ) throws {
        try ensureOpen()
        let sql = """
        INSERT OR IGNORE INTO assets (
            source_fingerprint, content_hash, original_path, filename, imported_at, session_id
        ) VALUES (?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sourceFingerprint, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, originalPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, filename, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 6, sessionID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    func updateSessionCounters(sessionID: Int64, importedDelta: Int = 0, duplicateDelta: Int = 0, failedDelta: Int = 0) throws {
        try ensureOpen()
        let sql = """
        UPDATE import_sessions
        SET imported_count = imported_count + ?,
            duplicate_count = duplicate_count + ?,
            failed_count = failed_count + ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(importedDelta))
        sqlite3_bind_int64(statement, 2, Int64(duplicateDelta))
        sqlite3_bind_int64(statement, 3, Int64(failedDelta))
        sqlite3_bind_int64(statement, 4, sessionID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    func completeSessionIfFinished(sessionID: Int64) throws -> ImportSessionSummary {
        try ensureOpen()
        let sql = """
        SELECT
            SUM(CASE WHEN state = ? THEN 1 ELSE 0 END) AS queued_count,
            SUM(CASE WHEN state = ? THEN 1 ELSE 0 END) AS hashing_count,
            SUM(CASE WHEN state = ? THEN 1 ELSE 0 END) AS copying_count,
            SUM(CASE WHEN state = ? THEN 1 ELSE 0 END) AS verifying_count
        FROM import_items
        WHERE session_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, ImportItemState.queued.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, ImportItemState.hashing.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, ImportItemState.copying.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, ImportItemState.verifying.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 5, sessionID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw lastError()
        }

        let activeCount = sqlite3_column_int64(statement, 0)
            + sqlite3_column_int64(statement, 1)
            + sqlite3_column_int64(statement, 2)
            + sqlite3_column_int64(statement, 3)
        if activeCount == 0 {
            try execute(
                """
                UPDATE import_sessions
                SET is_completed = 1, completed_at = COALESCE(completed_at, ?)
                WHERE id = ?;
                """,
                binder: { statement in
                    sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
                    sqlite3_bind_int64(statement, 2, sessionID)
                }
            )
        }
        return try sessionSummary(sessionID: sessionID)
    }

    func sessionSummary(sessionID: Int64) throws -> ImportSessionSummary {
        try ensureOpen()
        let sql = """
        SELECT id, started_at, completed_at, source_volume_path, source_volume_name, rename_template, custom_prefix, destination_collection, metadata_note, requested_count, imported_count, duplicate_count, failed_count, is_completed
        FROM import_sessions
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, sessionID)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ImportFailure(message: "Import session \(sessionID) not found.")
        }
        return decodeSession(from: statement)
    }

    func recentSessions(limit: Int) throws -> [ImportSessionSummary] {
        try ensureOpen()
        let sql = """
        SELECT id, started_at, completed_at, source_volume_path, source_volume_name, rename_template, custom_prefix, destination_collection, metadata_note, requested_count, imported_count, duplicate_count, failed_count, is_completed
        FROM import_sessions
        ORDER BY started_at DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(limit))
        var rows: [ImportSessionSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(decodeSession(from: statement))
        }
        return rows
    }

    func incompleteSessions() throws -> [ImportSessionSummary] {
        try ensureOpen()
        let sql = """
        SELECT id, started_at, completed_at, source_volume_path, source_volume_name, rename_template, custom_prefix, destination_collection, metadata_note, requested_count, imported_count, duplicate_count, failed_count, is_completed
        FROM import_sessions
        WHERE is_completed = 0
        ORDER BY started_at ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        var rows: [ImportSessionSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(decodeSession(from: statement))
        }
        return rows
    }

    func failedItems(for sessionID: Int64) throws -> [ImportQueueItem] {
        try ensureOpen()
        let sql = """
        SELECT id, session_id, source_path, source_relative_path, filename, state, destination_path, content_hash, error_message, updated_at
        FROM import_items
        WHERE session_id = ? AND state = ?
        ORDER BY id ASC;
        """
        return try readItems(sql: sql, binder: { statement in
            sqlite3_bind_int64(statement, 1, sessionID)
            sqlite3_bind_text(statement, 2, ImportItemState.failed.rawValue, -1, SQLITE_TRANSIENT)
        })
    }

    func sourcePathsAlreadyImported(for fingerprints: [String]) throws -> Set<String> {
        try ensureOpen()
        guard !fingerprints.isEmpty else { return [] }
        let sql = "SELECT source_fingerprint FROM assets WHERE source_fingerprint = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        var matched = Set<String>()
        for fingerprint in fingerprints {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, fingerprint, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                matched.insert(fingerprint)
            }
        }
        return matched
    }

    func recordDuplicateItem(sessionID: Int64, itemID: Int64, contentHash: String) throws {
        try inTransaction {
            try execute(
                """
                UPDATE import_items
                SET state = ?, content_hash = ?, error_message = NULL, updated_at = ?
                WHERE id = ?;
                """,
                binder: { statement in
                    sqlite3_bind_text(statement, 1, ImportItemState.skippedDuplicate.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, contentHash, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
                    sqlite3_bind_int64(statement, 4, itemID)
                }
            )
            try execute(
                """
                UPDATE import_sessions
                SET duplicate_count = duplicate_count + 1
                WHERE id = ?;
                """,
                binder: { statement in
                    sqlite3_bind_int64(statement, 1, sessionID)
                }
            )
        }
    }

    func recordFailedItem(sessionID: Int64, itemID: Int64, message: String) throws {
        try inTransaction {
            try execute(
                """
                UPDATE import_items
                SET state = ?, error_message = ?, updated_at = ?
                WHERE id = ?;
                """,
                binder: { statement in
                    sqlite3_bind_text(statement, 1, ImportItemState.failed.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, message, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
                    sqlite3_bind_int64(statement, 4, itemID)
                }
            )
            try execute(
                """
                UPDATE import_sessions
                SET failed_count = failed_count + 1
                WHERE id = ?;
                """,
                binder: { statement in
                    sqlite3_bind_int64(statement, 1, sessionID)
                }
            )
        }
    }

    func recordSuccessfulImport(
        sessionID: Int64,
        itemID: Int64,
        sourceFingerprint: String,
        contentHash: String,
        originalPath: String,
        filename: String
    ) throws {
        try inTransaction {
            try execute(
                """
                INSERT OR IGNORE INTO assets (
                    source_fingerprint, content_hash, original_path, filename, imported_at, session_id
                ) VALUES (?, ?, ?, ?, ?, ?);
                """,
                binder: { statement in
                    sqlite3_bind_text(statement, 1, sourceFingerprint, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, contentHash, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, originalPath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 4, filename, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
                    sqlite3_bind_int64(statement, 6, sessionID)
                }
            )
            try execute(
                """
                UPDATE import_items
                SET state = ?, destination_path = ?, content_hash = ?, error_message = NULL, updated_at = ?
                WHERE id = ?;
                """,
                binder: { statement in
                    sqlite3_bind_text(statement, 1, ImportItemState.done.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, originalPath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, contentHash, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
                    sqlite3_bind_int64(statement, 5, itemID)
                }
            )
            try execute(
                """
                UPDATE import_sessions
                SET imported_count = imported_count + 1
                WHERE id = ?;
                """,
                binder: { statement in
                    sqlite3_bind_int64(statement, 1, sessionID)
                }
            )
        }
    }

    private func decodeSession(from statement: OpaquePointer) -> ImportSessionSummary {
        let completedAt: Date?
        if sqlite3_column_type(statement, 2) == SQLITE_NULL {
            completedAt = nil
        } else {
            completedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        }
        return ImportSessionSummary(
            id: sqlite3_column_int64(statement, 0),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            completedAt: completedAt,
            sourceVolumePath: stringColumn(statement, index: 3),
            sourceVolumeName: stringColumn(statement, index: 4),
            renameTemplate: stringColumn(statement, index: 5),
            customPrefix: stringColumn(statement, index: 6),
            destinationCollection: stringColumn(statement, index: 7),
            metadataNote: stringColumn(statement, index: 8),
            requestedCount: Int(sqlite3_column_int64(statement, 9)),
            importedCount: Int(sqlite3_column_int64(statement, 10)),
            duplicateCount: Int(sqlite3_column_int64(statement, 11)),
            failedCount: Int(sqlite3_column_int64(statement, 12)),
            isCompleted: sqlite3_column_int64(statement, 13) == 1
        )
    }

    private func readItems(sql: String, binder: (OpaquePointer) -> Void) throws -> [ImportQueueItem] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        binder(statement)
        var rows: [ImportQueueItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                ImportQueueItem(
                    id: sqlite3_column_int64(statement, 0),
                    sessionID: sqlite3_column_int64(statement, 1),
                    sourcePath: stringColumn(statement, index: 2),
                    sourceRelativePath: stringColumn(statement, index: 3),
                    filename: stringColumn(statement, index: 4),
                    state: ImportItemState(rawValue: stringColumn(statement, index: 5)) ?? .failed,
                    destinationPath: nullableStringColumn(statement, index: 6),
                    contentHash: nullableStringColumn(statement, index: 7),
                    errorMessage: nullableStringColumn(statement, index: 8),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
                )
            )
        }
        return rows
    }

    private func relativePath(for fileURL: URL, root: URL) -> String {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        if fileComponents.starts(with: rootComponents) {
            return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
        }
        return fileURL.lastPathComponent
    }

    private func execute(_ sql: String, binder: ((OpaquePointer) -> Void)? = nil) throws {
        try ensureOpen()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        binder?(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    private func ensureOpen() throws {
        if db != nil {
            return
        }
        let parent = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        if sqlite3_open(databaseURL.path, &handle) != SQLITE_OK {
            if let handle {
                sqlite3_close(handle)
            }
            throw ImportFailure(message: "Failed to open import database.")
        }
        db = handle
    }

    private func ensureSessionColumns() throws {
        try addSessionColumnIfMissing(name: "rename_template", definition: "TEXT NOT NULL DEFAULT 'original'")
        try addSessionColumnIfMissing(name: "custom_prefix", definition: "TEXT NOT NULL DEFAULT ''")
        try addSessionColumnIfMissing(name: "destination_collection", definition: "TEXT NOT NULL DEFAULT ''")
        try addSessionColumnIfMissing(name: "metadata_note", definition: "TEXT NOT NULL DEFAULT ''")
    }

    private func ensureAssetColumns() throws {
        try addAssetColumnIfMissing(name: "rating", definition: "INTEGER NOT NULL DEFAULT 0")
        try addAssetColumnIfMissing(name: "edit_stack_pointer", definition: "TEXT NOT NULL DEFAULT ''")
    }

    private func addSessionColumnIfMissing(name: String, definition: String) throws {
        guard !(try sessionColumns().contains(name)) else {
            return
        }
        try execute("ALTER TABLE import_sessions ADD COLUMN \(name) \(definition);")
    }

    private func addAssetColumnIfMissing(name: String, definition: String) throws {
        guard !(try assetColumns().contains(name)) else {
            return
        }
        try execute("ALTER TABLE assets ADD COLUMN \(name) \(definition);")
    }

    private func sessionColumns() throws -> Set<String> {
        let sql = "PRAGMA table_info(import_sessions);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            names.insert(stringColumn(statement, index: 1))
        }
        return names
    }

    private func assetColumns() throws -> Set<String> {
        let sql = "PRAGMA table_info(assets);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            names.insert(stringColumn(statement, index: 1))
        }
        return names
    }

    private func inTransaction(_ block: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try block()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func metadataSummary(from options: ImportOptions) -> String {
        var parts: [String] = []
        if !options.metadata.creator.isEmpty {
            parts.append("creator=\(options.metadata.creator)")
        }
        if !options.metadata.keywords.isEmpty {
            parts.append("keywords=\(options.metadata.keywords)")
        }
        if !options.metadata.note.isEmpty {
            parts.append("note=\(options.metadata.note)")
        }
        return parts.joined(separator: " | ")
    }

    private func persistedCollection(from options: ImportOptions) -> String {
        let folderName = options.exportFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !folderName.isEmpty {
            return folderName
        }
        return options.destinationCollection
    }

    private func lastError() -> ImportFailure {
        guard let db else {
            return ImportFailure(message: "SQLite database not initialized.")
        }
        let text = String(cString: sqlite3_errmsg(db))
        return ImportFailure(message: text)
    }

    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: cString)
    }

    private func nullableStringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
}
