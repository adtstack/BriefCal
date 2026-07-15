import CryptoKit
import Foundation
import GRDB

struct DatabaseBackupManifest: Codable, Equatable, Sendable {
    static let formatVersion = 1
    static let applicationIdentifier = "com.adtstack.kaoscal"
    static let databaseFilename = "kaoscal.sqlite"

    let backupFormatVersion: Int
    let applicationIdentifier: String
    let applicationVersion: String
    let schemaVersion: Int
    let schemaIdentifier: String
    let appliedMigrations: [String]
    let exportedAt: String
    let databaseFilename: String
    let databaseByteCount: Int
    let databaseSHA256: String
    let containsCompleteCalendarEvents: Bool
    let containsLinkedEventSnapshots: Bool
    let containsEventBriefs: Bool
    let isEncrypted: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case backupFormatVersion = "backup_format_version"
        case applicationIdentifier = "application_identifier"
        case applicationVersion = "application_version"
        case schemaVersion = "schema_version"
        case schemaIdentifier = "schema_identifier"
        case appliedMigrations = "applied_migrations"
        case exportedAt = "exported_at"
        case databaseFilename = "database_filename"
        case databaseByteCount = "database_byte_count"
        case databaseSHA256 = "database_sha256"
        case containsCompleteCalendarEvents = "contains_complete_calendar_events"
        case containsLinkedEventSnapshots = "contains_linked_event_snapshots"
        case containsEventBriefs = "contains_event_briefs"
        case isEncrypted = "is_encrypted"
    }
}

struct LocalDataExportResult: Equatable, Sendable {
    let archiveURL: URL
    let manifest: DatabaseBackupManifest
}

struct LocalDataBackupInspection: Equatable, Sendable {
    let archiveURL: URL
    let manifest: DatabaseBackupManifest
}

struct LocalDataImportResult: Equatable, Sendable {
    let manifest: DatabaseBackupManifest
    let automaticBackupURL: URL
}

struct BootstrapLocalDataRecoveryResult: Equatable, Sendable {
    let manifest: DatabaseBackupManifest
    let quarantinedDatabaseDirectory: URL
}

struct LocalDataDeletedRowCounts: Equatable, Sendable {
    let eventContexts: Int
    let eventLinks: Int
    let eventTasks: Int
    let personalTasks: Int
    let eventChangeLog: Int
    let calendarPreferences: Int
    let calendarUsagePreferences: Int
    let providerAccounts: Int
    let providerItems: Int
    let providerBindings: Int
    let providerDestinations: Int
    let providerSyncCursors: Int
    let providerPendingOperations: Int
    let contextReferences: Int

    var total: Int {
        eventContexts
            + eventLinks
            + eventTasks
            + personalTasks
            + eventChangeLog
            + calendarPreferences
            + calendarUsagePreferences
            + providerAccounts
            + providerItems
            + providerBindings
            + providerDestinations
            + providerSyncCursors
            + providerPendingOperations
            + contextReferences
    }
}

struct LocalDataResetResult: Equatable, Sendable {
    let automaticBackupURL: URL
    let deletedRowCounts: LocalDataDeletedRowCounts
}

enum LocalDataBackupError: Error, Equatable, LocalizedError, Sendable {
    case invalidArchive(String)
    case invalidManifest(String)
    case invalidDatabase(String)
    case incompatibleSchema(expected: [String], found: [String])
    case fileTooLarge(limit: Int)
    case unsafeDestination(String)
    case importFailed(reason: String, rollbackSucceeded: Bool)
    case resetFailed(reason: String, rollbackSucceeded: Bool)

    var errorDescription: String? {
        switch self {
        case let .invalidArchive(reason):
            "The backup archive is invalid: \(reason)"
        case let .invalidManifest(reason):
            "The backup manifest is invalid: \(reason)"
        case let .invalidDatabase(reason):
            "The backup database is invalid: \(reason)"
        case let .incompatibleSchema(expected, found):
            "The backup schema is incompatible. Expected \(expected.joined(separator: ", ")); found \(found.joined(separator: ", "))."
        case let .fileTooLarge(limit):
            "The backup exceeds the \(limit)-byte safety limit."
        case let .unsafeDestination(reason):
            "The backup destination is unsafe: \(reason)"
        case let .importFailed(reason, rollbackSucceeded):
            rollbackSucceeded
                ? "Import failed and the previous local data was restored: \(reason)"
                : "Import failed and the previous local data could not be restored: \(reason)"
        case let .resetFailed(reason, rollbackSucceeded):
            rollbackSucceeded
                ? "Reset failed and the previous local data was restored: \(reason)"
                : "Reset failed and the previous local data could not be restored: \(reason)"
        }
    }
}

/// Owns KaosCal-local data backup, restore, and reset. It never reads from or
/// writes to EventKit.
struct LocalDataBackupService: Sendable {
    static let maximumManifestByteCount = 64 * 1_024
    static let maximumDatabaseByteCount = 128 * 1_024 * 1_024
    static let maximumArchiveByteCount = maximumDatabaseByteCount + 1_024 * 1_024

    let database: AppDatabase
    let databaseURL: URL?

    init(database: AppDatabase, databaseURL: URL? = nil) {
        self.database = database
        self.databaseURL = (databaseURL ?? database.databaseURL)?.standardizedFileURL
    }

    func exportBackup(
        to archiveURL: URL,
        now: Date = Date(),
        appVersion: String
    ) throws -> LocalDataExportResult {
        try validateExportDestination(archiveURL)
        return try withTemporaryDirectory(prefix: "KaosCal-Export") { directory in
            let snapshotURL = directory.appendingPathComponent(
                DatabaseBackupManifest.databaseFilename
            )
            try database.writeSnapshot(to: snapshotURL)
            let inspection = try DatabaseSchemaValidator.validateDatabase(at: snapshotURL)
            let manifest = try makeArchive(
                snapshotURL: snapshotURL,
                databaseInspection: inspection,
                destinationURL: archiveURL,
                workingDirectory: directory,
                now: now,
                appVersion: appVersion
            )
            return LocalDataExportResult(
                archiveURL: archiveURL.standardizedFileURL,
                manifest: manifest
            )
        }
    }

    func inspectBackup(at archiveURL: URL) throws -> LocalDataBackupInspection {
        try withPreparedBackup(at: archiveURL) { manifest, _ in
            LocalDataBackupInspection(
                archiveURL: archiveURL.standardizedFileURL,
                manifest: manifest
            )
        }
    }

    /// Copies the validated current-schema SQLite snapshot from an archive to
    /// an app-private staging URL. Bootstrap recovery uses this while no live
    /// DatabaseWriter exists; the active database is never the destination.
    func copyValidatedDatabase(
        from archiveURL: URL,
        to destinationURL: URL
    ) throws -> DatabaseBackupManifest {
        try withPreparedBackup(at: archiveURL) { manifest, importedDatabaseURL in
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw LocalDataBackupError.unsafeDestination(
                    "the bootstrap staging destination already exists"
                )
            }
            try fileManager.copyItem(at: importedDatabaseURL, to: destinationURL)
            _ = try DatabaseSchemaValidator.validateDatabase(at: destinationURL)
            return manifest
        }
    }

    func importBackup(
        from archiveURL: URL,
        automaticBackupDirectory: URL,
        now: Date = Date(),
        appVersion: String
    ) throws -> LocalDataImportResult {
        try withPreparedBackup(at: archiveURL) { manifest, importedDatabaseURL in
            try withTemporaryDirectory(prefix: "KaosCal-Import-Rollback") { directory in
                let oldDatabaseURL = directory.appendingPathComponent("pre-import.sqlite")
                try database.writeSnapshot(to: oldDatabaseURL)
                let oldInspection = try DatabaseSchemaValidator.validateDatabase(
                    at: oldDatabaseURL
                )

                let automaticBackupURL = try makeAutomaticBackupURL(
                    in: automaticBackupDirectory,
                    now: now,
                    operation: "Pre-Import"
                )
                _ = try makeArchive(
                    snapshotURL: oldDatabaseURL,
                    databaseInspection: oldInspection,
                    destinationURL: automaticBackupURL,
                    workingDirectory: directory,
                    now: now,
                    appVersion: appVersion
                )

                do {
                    try database.restoreSnapshot(from: importedDatabaseURL)
                    _ = try DatabaseSchemaValidator.validateDatabase(database)
                } catch {
                    do {
                        try database.restoreSnapshot(from: oldDatabaseURL)
                        _ = try DatabaseSchemaValidator.validateDatabase(database)
                    } catch let rollbackError {
                        throw LocalDataBackupError.importFailed(
                            reason: "\(error); rollback error: \(rollbackError)",
                            rollbackSucceeded: false
                        )
                    }
                    throw LocalDataBackupError.importFailed(
                        reason: String(describing: error),
                        rollbackSucceeded: true
                    )
                }

                return LocalDataImportResult(
                    manifest: manifest,
                    automaticBackupURL: automaticBackupURL
                )
            }
        }
    }

    func resetLocalData(
        automaticBackupDirectory: URL,
        now: Date = Date(),
        appVersion: String
    ) throws -> LocalDataResetResult {
        try withTemporaryDirectory(prefix: "KaosCal-Reset-Rollback") { directory in
            let oldDatabaseURL = directory.appendingPathComponent("pre-reset.sqlite")
            try database.writeSnapshot(to: oldDatabaseURL)
            let oldInspection = try DatabaseSchemaValidator.validateDatabase(at: oldDatabaseURL)
            let automaticBackupURL = try makeAutomaticBackupURL(
                in: automaticBackupDirectory,
                now: now,
                operation: "Pre-Reset"
            )
            _ = try makeArchive(
                snapshotURL: oldDatabaseURL,
                databaseInspection: oldInspection,
                destinationURL: automaticBackupURL,
                workingDirectory: directory,
                now: now,
                appVersion: appVersion
            )

            do {
                let counts = try deleteAllLocalData()
                _ = try DatabaseSchemaValidator.validateDatabase(database)
                return LocalDataResetResult(
                    automaticBackupURL: automaticBackupURL,
                    deletedRowCounts: counts
                )
            } catch {
                do {
                    try database.restoreSnapshot(from: oldDatabaseURL)
                    _ = try DatabaseSchemaValidator.validateDatabase(database)
                } catch let rollbackError {
                    throw LocalDataBackupError.resetFailed(
                        reason: "\(error); rollback error: \(rollbackError)",
                        rollbackSucceeded: false
                    )
                }
                throw LocalDataBackupError.resetFailed(
                    reason: String(describing: error),
                    rollbackSucceeded: true
                )
            }
        }
    }

    private func deleteAllLocalData() throws -> LocalDataDeletedRowCounts {
        try database.write { db in
            let counts = try LocalDataDeletedRowCounts(
                eventContexts: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM event_contexts") ?? 0,
                eventLinks: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM event_links") ?? 0,
                eventTasks: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM event_tasks") ?? 0,
                personalTasks: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM personal_tasks") ?? 0,
                eventChangeLog: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM event_change_log") ?? 0,
                calendarPreferences: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM calendar_preferences"
                ) ?? 0,
                calendarUsagePreferences: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM calendar_usage_preferences"
                ) ?? 0,
                providerAccounts: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM provider_accounts"
                ) ?? 0,
                providerItems: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM provider_items"
                ) ?? 0,
                providerBindings: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM task_bindings"
                ) ?? 0,
                providerDestinations: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM calendar_task_destinations"
                ) ?? 0,
                providerSyncCursors: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM provider_sync_cursors"
                ) ?? 0,
                providerPendingOperations: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM provider_pending_operations"
                ) ?? 0,
                contextReferences: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM context_references"
                ) ?? 0
            )

            // Keep GRDB's migration ledger, and remove only KaosCal-owned user
            // data. Explicit child-first deletes make every reset target
            // auditable without relying solely on cascade behavior.
            try db.execute(sql: "DELETE FROM provider_pending_operations")
            try db.execute(sql: "DELETE FROM provider_sync_cursors")
            try db.execute(sql: "DELETE FROM task_bindings")
            try db.execute(sql: "DELETE FROM calendar_task_destinations")
            try db.execute(sql: "DELETE FROM provider_items")
            try db.execute(sql: "DELETE FROM provider_accounts")
            try db.execute(sql: "DELETE FROM context_references")
            try db.execute(sql: "DELETE FROM event_change_log")
            try db.execute(sql: "DELETE FROM event_tasks")
            try db.execute(sql: "DELETE FROM event_links")
            try db.execute(sql: "DELETE FROM event_contexts")
            try db.execute(sql: "DELETE FROM personal_tasks")
            try db.execute(sql: "DELETE FROM calendar_usage_preferences")
            try db.execute(sql: "DELETE FROM calendar_preferences")
            return counts
        }
    }

    private func validateExportDestination(_ archiveURL: URL) throws {
        guard archiveURL.isFileURL else {
            throw LocalDataBackupError.unsafeDestination(
                "the selected URL is not a local file"
            )
        }
        let destination = archiveURL.standardizedFileURL
        if try protectedDatabaseURLs().contains(where: {
            try fileURLsReferToSameDestination(destination, $0)
        }) {
            throw LocalDataBackupError.unsafeDestination(
                "the archive cannot replace the live SQLite database or a sidecar"
            )
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: destination.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            throw LocalDataBackupError.unsafeDestination(
                "the selected URL is a directory"
            )
        }
        if (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw LocalDataBackupError.unsafeDestination(
                "an existing symbolic link cannot be used as the destination"
            )
        }
    }

    private func makeArchive(
        snapshotURL: URL,
        databaseInspection: DatabaseSchemaInspection,
        destinationURL: URL,
        workingDirectory: URL,
        now: Date,
        appVersion: String
    ) throws -> DatabaseBackupManifest {
        let databaseData = try boundedFileData(
            at: snapshotURL,
            maximumByteCount: Self.maximumDatabaseByteCount
        )
        guard !databaseInspection.migrations.isEmpty,
              let schemaIdentifier = databaseInspection.migrations.last else {
            throw LocalDataBackupError.invalidDatabase("the migration ledger is empty")
        }

        let normalizedVersion = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVersion.isEmpty, normalizedVersion.utf8.count <= 128 else {
            throw LocalDataBackupError.invalidManifest(
                "the application version must contain 1...128 UTF-8 bytes"
            )
        }

        let manifest = DatabaseBackupManifest(
            backupFormatVersion: DatabaseBackupManifest.formatVersion,
            applicationIdentifier: DatabaseBackupManifest.applicationIdentifier,
            applicationVersion: normalizedVersion,
            schemaVersion: databaseInspection.migrations.count,
            schemaIdentifier: schemaIdentifier,
            appliedMigrations: databaseInspection.migrations,
            exportedAt: Self.timestampString(now),
            databaseFilename: DatabaseBackupManifest.databaseFilename,
            databaseByteCount: databaseData.count,
            databaseSHA256: Self.sha256(databaseData),
            containsCompleteCalendarEvents: false,
            containsLinkedEventSnapshots: true,
            containsEventBriefs: true,
            isEncrypted: false
        )
        let manifestData = try Self.encodeManifest(manifest)
        guard manifestData.count <= Self.maximumManifestByteCount else {
            throw LocalDataBackupError.fileTooLarge(
                limit: Self.maximumManifestByteCount
            )
        }

        let archiveData = try StrictZIPArchive.encode(entries: [
            .init(name: "manifest.json", data: manifestData),
            .init(name: DatabaseBackupManifest.databaseFilename, data: databaseData),
        ])
        guard archiveData.count <= Self.maximumArchiveByteCount else {
            throw LocalDataBackupError.fileTooLarge(
                limit: Self.maximumArchiveByteCount
            )
        }

        // Finish the archive in the app-private temporary directory before any
        // write to a user-selected security-scoped destination.
        let completedArchiveURL = workingDirectory.appendingPathComponent(
            "completed-\(UUID().uuidString).zip"
        )
        try archiveData.write(to: completedArchiveURL, options: .atomic)
        // Re-check after snapshot and archive construction. A save-panel URL
        // can point through a symbolic-link directory, and the destination may
        // have changed while a large snapshot was being prepared.
        try validateExportDestination(destinationURL)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try validateExportDestination(destinationURL)
        let completedData = try boundedFileData(
            at: completedArchiveURL,
            maximumByteCount: Self.maximumArchiveByteCount
        )
        try completedData.write(to: destinationURL, options: .atomic)
        return manifest
    }

    private func withPreparedBackup<T>(
        at archiveURL: URL,
        _ body: (DatabaseBackupManifest, URL) throws -> T
    ) throws -> T {
        let archiveData = try boundedFileData(
            at: archiveURL,
            maximumByteCount: Self.maximumArchiveByteCount
        )
        let entries = try StrictZIPArchive.decode(archiveData)
        guard entries.count == 2,
              let manifestData = entries["manifest.json"],
              let databaseData = entries[DatabaseBackupManifest.databaseFilename] else {
            throw LocalDataBackupError.invalidArchive(
                "exactly manifest.json and kaoscal.sqlite are required"
            )
        }
        guard manifestData.count <= Self.maximumManifestByteCount else {
            throw LocalDataBackupError.fileTooLarge(
                limit: Self.maximumManifestByteCount
            )
        }
        guard databaseData.count <= Self.maximumDatabaseByteCount else {
            throw LocalDataBackupError.fileTooLarge(
                limit: Self.maximumDatabaseByteCount
            )
        }

        let manifest = try Self.decodeAndValidateManifest(manifestData)
        guard manifest.databaseByteCount == databaseData.count else {
            throw LocalDataBackupError.invalidManifest(
                "database byte count does not match the archive entry"
            )
        }
        guard manifest.databaseSHA256 == Self.sha256(databaseData) else {
            throw LocalDataBackupError.invalidManifest(
                "database SHA-256 does not match the archive entry"
            )
        }

        return try withTemporaryDirectory(prefix: "KaosCal-Import-Preflight") { directory in
            let importedDatabaseURL = directory.appendingPathComponent(
                DatabaseBackupManifest.databaseFilename
            )
            try databaseData.write(to: importedDatabaseURL, options: [.atomic])
            let inspection = try DatabaseSchemaValidator.validateDatabase(
                at: importedDatabaseURL
            )
            guard manifest.appliedMigrations == inspection.migrations,
                  manifest.schemaVersion == inspection.migrations.count,
                  manifest.schemaIdentifier == inspection.migrations.last else {
                throw LocalDataBackupError.invalidManifest(
                    "schema metadata does not match the SQLite migration ledger"
                )
            }
            return try body(manifest, importedDatabaseURL)
        }
    }

    private func makeAutomaticBackupURL(
        in directory: URL,
        now: Date,
        operation: String
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            throw LocalDataBackupError.unsafeDestination(
                "the automatic backup location is not a directory"
            )
        }
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw LocalDataBackupError.unsafeDestination(
                "a symbolic link cannot be used as the automatic backup directory"
            )
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let token = UUID().uuidString.lowercased()
        let timestamp = Self.filenameTimestamp(now)
        return directory.appendingPathComponent(
            "KaosCal-\(operation)-\(timestamp)-\(token).zip"
        )
    }

    private func boundedFileData(
        at fileURL: URL,
        maximumByteCount: Int
    ) throws -> Data {
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LocalDataBackupError.invalidArchive("the selected URL is not a regular file")
        }
        if let fileSize = values.fileSize, fileSize > maximumByteCount {
            throw LocalDataBackupError.fileTooLarge(limit: maximumByteCount)
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard data.count <= maximumByteCount else {
            throw LocalDataBackupError.fileTooLarge(limit: maximumByteCount)
        }
        return data
    }

    private func protectedDatabaseURLs() -> [URL] {
        guard let databaseURL else { return [] }
        let canonicalDatabaseURL = canonicalFileURL(databaseURL)
        let baseURLs = Set([
            databaseURL.standardizedFileURL,
            canonicalDatabaseURL,
        ])
        return baseURLs.flatMap { baseURL in
            ["", "-wal", "-shm", "-journal"].map { suffix in
                URL(fileURLWithPath: baseURL.path + suffix).standardizedFileURL
            }
        }
    }

    private func fileURLsReferToSameDestination(
        _ lhs: URL,
        _ rhs: URL
    ) throws -> Bool {
        let lhsCanonical = canonicalFileURL(lhs)
        let rhsCanonical = canonicalFileURL(rhs)
        if lhsCanonical.path == rhsCanonical.path {
            return true
        }

        let lhsCaseSensitive = volumeSupportsCaseSensitiveNames(for: lhsCanonical)
        let rhsCaseSensitive = volumeSupportsCaseSensitiveNames(for: rhsCanonical)
        if lhsCaseSensitive == false,
           rhsCaseSensitive == false,
           lhsCanonical.path.compare(
               rhsCanonical.path,
               options: [.caseInsensitive, .literal]
           ) == .orderedSame {
            return true
        }

        guard let lhsIdentifier = try? lhs.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier,
        let rhsIdentifier = try? rhs.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier else {
            return false
        }
        return lhsIdentifier.isEqual(rhsIdentifier)
    }

    /// Resolves every existing ancestor before appending not-yet-created path
    /// components. `URL.resolvingSymlinksInPath()` alone does not resolve a
    /// symbolic-link parent when the final destination does not exist.
    private func canonicalFileURL(_ fileURL: URL) -> URL {
        let fileManager = FileManager.default
        var existingAncestor = fileURL.standardizedFileURL
        var missingComponents: [String] = []

        while !fileManager.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            missingComponents.append(existingAncestor.lastPathComponent)
            existingAncestor = parent
        }

        var canonical = existingAncestor
            .resolvingSymlinksInPath()
            .standardizedFileURL
        for component in missingComponents.reversed() {
            canonical.appendPathComponent(component)
        }
        return canonical.standardizedFileURL
    }

    private func volumeSupportsCaseSensitiveNames(for fileURL: URL) -> Bool? {
        let fileManager = FileManager.default
        var ancestor = fileURL.standardizedFileURL
        while !fileManager.fileExists(atPath: ancestor.path) {
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { return nil }
            ancestor = parent
        }
        return try? ancestor.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames
    }

    private func withTemporaryDirectory<T>(
        prefix: String,
        _ body: (URL) throws -> T
    ) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    private static func encodeManifest(_ manifest: DatabaseBackupManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    private static func decodeAndValidateManifest(
        _ data: Data
    ) throws -> DatabaseBackupManifest {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LocalDataBackupError.invalidManifest("manifest.json is not valid JSON")
        }
        guard let dictionary = object as? [String: Any] else {
            throw LocalDataBackupError.invalidManifest("the top level must be an object")
        }
        let expectedKeys = Set(DatabaseBackupManifest.CodingKeys.allCases.map(\.rawValue))
        guard Set(dictionary.keys) == expectedKeys else {
            throw LocalDataBackupError.invalidManifest(
                "manifest keys must exactly match backup format version 1"
            )
        }

        let manifest: DatabaseBackupManifest
        do {
            manifest = try JSONDecoder().decode(DatabaseBackupManifest.self, from: data)
        } catch {
            throw LocalDataBackupError.invalidManifest("manifest field types are invalid")
        }

        let expected = try DatabaseSchemaValidator.expectedInspection()
        guard manifest.backupFormatVersion == DatabaseBackupManifest.formatVersion else {
            throw LocalDataBackupError.invalidManifest("unsupported backup format version")
        }
        guard manifest.applicationIdentifier == DatabaseBackupManifest.applicationIdentifier else {
            throw LocalDataBackupError.invalidManifest("unexpected application identifier")
        }
        let normalizedVersion = manifest.applicationVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVersion.isEmpty,
              normalizedVersion == manifest.applicationVersion,
              normalizedVersion.utf8.count <= 128,
              !normalizedVersion.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
              ) else {
            throw LocalDataBackupError.invalidManifest("invalid application version")
        }
        guard manifest.databaseFilename == DatabaseBackupManifest.databaseFilename else {
            throw LocalDataBackupError.invalidManifest("unexpected database filename")
        }
        guard manifest.containsCompleteCalendarEvents == false,
              manifest.containsLinkedEventSnapshots,
              manifest.containsEventBriefs,
              manifest.isEncrypted == false else {
            throw LocalDataBackupError.invalidManifest(
                "privacy-content flags do not match backup format version 1"
            )
        }
        guard manifest.schemaVersion == expected.migrations.count,
              manifest.schemaIdentifier == expected.migrations.last,
              manifest.appliedMigrations == expected.migrations else {
            throw LocalDataBackupError.incompatibleSchema(
                expected: expected.migrations,
                found: manifest.appliedMigrations
            )
        }
        guard manifest.databaseByteCount > 0,
              manifest.databaseByteCount <= Self.maximumDatabaseByteCount else {
            throw LocalDataBackupError.invalidManifest("invalid database byte count")
        }
        let hashCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard manifest.databaseSHA256.utf8.count == 64,
              manifest.databaseSHA256.unicodeScalars.allSatisfy(hashCharacters.contains) else {
            throw LocalDataBackupError.invalidManifest("invalid database SHA-256")
        }
        guard let exportedDate = timestampDate(manifest.exportedAt),
              timestampString(exportedDate) == manifest.exportedAt else {
            throw LocalDataBackupError.invalidManifest("invalid export timestamp")
        }
        return manifest
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func timestampDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: string)
    }

    private static func filenameTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

enum BootstrapLocalDataRecoveryError: Error, Equatable, LocalizedError, Sendable {
    case recoveryFailed(reason: String, rollbackSucceeded: Bool)

    var errorDescription: String? {
        switch self {
        case let .recoveryFailed(reason, rollbackSucceeded):
            rollbackSucceeded
                ? "Recovery did not finish, and the original database files were restored: \(reason)"
                : "Recovery did not finish, and KaosCal could not put every original database file back: \(reason)"
        }
    }
}

/// Restores a strictly validated KaosCal backup when the normal application
/// database cannot be opened. The failed SQLite file family is moved together
/// into an app-private quarantine directory before the replacement is opened.
/// It never calls EventKit.
struct BootstrapLocalDataRecoveryService: Sendable {
    private static let databaseSidecarSuffixes = ["", "-wal", "-shm", "-journal"]

    let liveDatabaseURL: URL
    private let validateInstalledDatabase: @Sendable (URL) throws -> Void

    init(
        liveDatabaseURL: URL,
        validateInstalledDatabase: @escaping @Sendable (URL) throws -> Void = { url in
            let database = try AppDatabase.open(at: url)
            _ = try DatabaseSchemaValidator.validateDatabase(database)
        }
    ) {
        self.liveDatabaseURL = liveDatabaseURL.standardizedFileURL
        self.validateInstalledDatabase = validateInstalledDatabase
    }

    func recover(
        from archiveURL: URL,
        now: Date = Date()
    ) throws -> BootstrapLocalDataRecoveryResult {
        let fileManager = FileManager.default
        let parentDirectory = liveDatabaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stagingDirectory = parentDirectory.appendingPathComponent(
            ".Bootstrap-Recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let stagedDatabaseURL = stagingDirectory.appendingPathComponent(
            DatabaseBackupManifest.databaseFilename
        )
        let validatorDatabase = try AppDatabase.inMemory()
        let manifest = try LocalDataBackupService(database: validatorDatabase)
            .copyValidatedDatabase(from: archiveURL, to: stagedDatabaseURL)

        let quarantineRoot = parentDirectory.appendingPathComponent(
            "Recovery",
            isDirectory: true
        )
        var quarantineRootIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: quarantineRoot.path,
            isDirectory: &quarantineRootIsDirectory
        ) {
            guard quarantineRootIsDirectory.boolValue,
                  (try? quarantineRoot.resourceValues(
                      forKeys: [.isSymbolicLinkKey]
                  ).isSymbolicLink) != true else {
                throw LocalDataBackupError.unsafeDestination(
                    "the bootstrap Recovery location must be a private directory, not a file or symbolic link"
                )
            }
        }
        try fileManager.createDirectory(
            at: quarantineRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard (try? quarantineRoot.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true else {
            throw LocalDataBackupError.unsafeDestination(
                "the bootstrap Recovery location changed before quarantine"
            )
        }
        let quarantineDirectory = quarantineRoot.appendingPathComponent(
            "Failed-Bootstrap-\(Self.filenameTimestamp(now))-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: quarantineDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        var movedSuffixes: [String] = []
        var installedReplacement = false
        do {
            for suffix in Self.databaseSidecarSuffixes {
                let source = Self.databaseFamilyURL(base: liveDatabaseURL, suffix: suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = quarantineDirectory.appendingPathComponent(
                    source.lastPathComponent
                )
                try fileManager.moveItem(at: source, to: destination)
                movedSuffixes.append(suffix)
            }

            try fileManager.moveItem(at: stagedDatabaseURL, to: liveDatabaseURL)
            installedReplacement = true
            try validateInstalledDatabase(liveDatabaseURL)

            let note = """
                KaosCal preserved this SQLite file family after a failed application bootstrap.
                The files may contain private Event Brief text and linked calendar metadata.
                Keep them private; do not attach them to a public issue.
                Recovery source: \(archiveURL.lastPathComponent)
                """
            try Data(note.utf8).write(
                to: quarantineDirectory.appendingPathComponent("RECOVERY.txt"),
                options: .atomic
            )
            return BootstrapLocalDataRecoveryResult(
                manifest: manifest,
                quarantinedDatabaseDirectory: quarantineDirectory
            )
        } catch {
            var rollbackErrors: [String] = []
            if installedReplacement {
                for suffix in Self.databaseSidecarSuffixes {
                    let installedURL = Self.databaseFamilyURL(
                        base: liveDatabaseURL,
                        suffix: suffix
                    )
                    guard fileManager.fileExists(atPath: installedURL.path) else { continue }
                    do {
                        try fileManager.removeItem(at: installedURL)
                    } catch {
                        rollbackErrors.append("remove replacement \(suffix): \(error)")
                    }
                }
            }
            for suffix in movedSuffixes.reversed() {
                let quarantinedURL = quarantineDirectory.appendingPathComponent(
                    Self.databaseFamilyURL(base: liveDatabaseURL, suffix: suffix).lastPathComponent
                )
                let originalURL = Self.databaseFamilyURL(base: liveDatabaseURL, suffix: suffix)
                guard fileManager.fileExists(atPath: quarantinedURL.path) else { continue }
                do {
                    try fileManager.moveItem(at: quarantinedURL, to: originalURL)
                } catch {
                    rollbackErrors.append("restore original \(suffix): \(error)")
                }
            }
            if rollbackErrors.isEmpty {
                try? fileManager.removeItem(at: quarantineDirectory)
            }
            throw BootstrapLocalDataRecoveryError.recoveryFailed(
                reason: ([String(describing: error)] + rollbackErrors).joined(separator: "; "),
                rollbackSucceeded: rollbackErrors.isEmpty
            )
        }
    }

    private static func databaseFamilyURL(base: URL, suffix: String) -> URL {
        URL(fileURLWithPath: base.path + suffix).standardizedFileURL
    }

    private static func filenameTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private struct DatabaseSchemaInspection: Equatable {
    let migrations: [String]
    let schemaObjects: [DatabaseSchemaObject]
}

private struct DatabaseSchemaObject: Equatable {
    let type: String
    let name: String
    let tableName: String
    let sql: String?
}

private enum DatabaseSchemaValidator {
    static func expectedInspection() throws -> DatabaseSchemaInspection {
        let reference = try AppDatabase.inMemory()
        return try inspect(reference)
    }

    static func validateDatabase(_ database: AppDatabase) throws -> DatabaseSchemaInspection {
        let actual = try inspect(database)
        try requireCurrentSchema(actual)
        return actual
    }

    static func validateDatabase(at fileURL: URL) throws -> DatabaseSchemaInspection {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.label = "KaosCal Backup Preflight"
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: fileURL.path, configuration: configuration)
        } catch {
            throw LocalDataBackupError.invalidDatabase("SQLite could not open the snapshot")
        }
        let actual = try inspect(queue)
        try requireCurrentSchema(actual)
        return actual
    }

    private static func inspect(_ database: AppDatabase) throws -> DatabaseSchemaInspection {
        try database.read(inspectDatabase)
    }

    private static func inspect(_ queue: DatabaseQueue) throws -> DatabaseSchemaInspection {
        try queue.read(inspectDatabase)
    }

    private static func inspectDatabase(_ db: Database) throws -> DatabaseSchemaInspection {
        let integrity = try String.fetchOne(db, sql: "PRAGMA integrity_check(1)")
        guard integrity == "ok" else {
            throw LocalDataBackupError.invalidDatabase(
                "integrity_check failed: \(integrity ?? "no result")"
            )
        }
        let foreignKeyViolation = try Row.fetchOne(db, sql: "PRAGMA foreign_key_check")
        guard foreignKeyViolation == nil else {
            throw LocalDataBackupError.invalidDatabase(
                "foreign_key_check reported at least one violation"
            )
        }
        let migrations = try exactCurrentMigrations(in: db)
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT type, name, tbl_name, sql
                FROM sqlite_master
                ORDER BY type, name
                """
        )
        let objects = rows.map { row in
            DatabaseSchemaObject(
                type: row["type"],
                name: row["name"],
                tableName: row["tbl_name"],
                sql: row["sql"]
            )
        }
        return DatabaseSchemaInspection(
            migrations: migrations,
            schemaObjects: objects
        )
    }

    private static func exactCurrentMigrations(in db: Database) throws -> [String] {
        let expected = DatabaseMigrations.migrator.migrations
        let rowCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM grdb_migrations"
        ) ?? 0
        guard rowCount == expected.count else {
            throw LocalDataBackupError.incompatibleSchema(
                expected: expected,
                found: rowCount <= expected.count
                    ? try boundedMigrationIdentifiers(in: db, limit: expected.count + 1)
                    : ["\(rowCount) migration ledger entries"]
            )
        }
        guard !expected.isEmpty else { return [] }

        let placeholders = expected.map { _ in "?" }.joined(separator: ", ")
        let matchingCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM grdb_migrations
                WHERE typeof(identifier) = 'text'
                    AND identifier IN (\(placeholders))
                """,
            arguments: StatementArguments(expected)
        ) ?? 0
        guard matchingCount == expected.count else {
            throw LocalDataBackupError.incompatibleSchema(
                expected: expected,
                found: try boundedMigrationIdentifiers(
                    in: db,
                    limit: expected.count + 1
                )
            )
        }
        return expected
    }

    private static func boundedMigrationIdentifiers(
        in db: Database,
        limit: Int
    ) throws -> [String] {
        try String.fetchAll(
            db,
            sql: """
                SELECT CASE
                    WHEN typeof(identifier) = 'text'
                        THEN substr(identifier, 1, 128)
                    ELSE '<' || typeof(identifier) || ' identifier>'
                END
                FROM grdb_migrations
                LIMIT ?
                """,
            arguments: [limit]
        )
    }

    private static func requireCurrentSchema(
        _ actual: DatabaseSchemaInspection
    ) throws {
        let expected = try expectedInspection()
        guard actual.migrations == expected.migrations else {
            throw LocalDataBackupError.incompatibleSchema(
                expected: expected.migrations,
                found: actual.migrations
            )
        }
        guard actual.schemaObjects == expected.schemaObjects else {
            throw LocalDataBackupError.invalidDatabase(
                "sqlite_master does not exactly match the current KaosCal schema"
            )
        }
    }
}

private enum StrictZIPArchive {
    struct Entry {
        let name: String
        let data: Data
    }

    private struct CentralEntry {
        let name: String
        let flags: UInt16
        let method: UInt16
        let modificationTime: UInt16
        let modificationDate: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    static func encode(entries: [Entry]) throws -> Data {
        guard entries.map(\.name) == ["manifest.json", "kaoscal.sqlite"] else {
            throw LocalDataBackupError.invalidArchive("invalid export entry list")
        }
        var archive = Data()
        var centralEntries: [(Entry, UInt32, UInt32)] = []
        let flags: UInt16 = 0x0800

        for entry in entries {
            guard let nameData = entry.name.data(using: .utf8),
                  nameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw LocalDataBackupError.fileTooLarge(
                    limit: LocalDataBackupService.maximumArchiveByteCount
                )
            }
            let crc = CRC32.checksum(entry.data)
            let localOffset = UInt32(archive.count)
            archive.appendLittleEndian(UInt32(0x04034b50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(flags)
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0x0021))
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt16(nameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(nameData)
            archive.append(entry.data)
            centralEntries.append((entry, crc, localOffset))
        }

        guard archive.count <= Int(UInt32.max) else {
            throw LocalDataBackupError.fileTooLarge(
                limit: LocalDataBackupService.maximumArchiveByteCount
            )
        }
        let centralOffset = UInt32(archive.count)
        for (entry, crc, localOffset) in centralEntries {
            let nameData = Data(entry.name.utf8)
            archive.appendLittleEndian(UInt32(0x02014b50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(flags)
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0x0021))
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt16(nameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt32(0))
            archive.appendLittleEndian(localOffset)
            archive.append(nameData)
        }
        let centralSize = archive.count - Int(centralOffset)
        guard centralEntries.count <= Int(UInt16.max), centralSize <= Int(UInt32.max) else {
            throw LocalDataBackupError.fileTooLarge(
                limit: LocalDataBackupService.maximumArchiveByteCount
            )
        }
        archive.appendLittleEndian(UInt32(0x06054b50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(UInt32(centralSize))
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    static func decode(_ archive: Data) throws -> [String: Data] {
        guard archive.count >= 22 else {
            throw invalid("missing end-of-central-directory record")
        }
        let endOffset = archive.count - 22
        guard try archive.uint32(at: endOffset) == 0x06054b50 else {
            throw invalid("ZIP comments, trailing bytes, or a missing end record are not allowed")
        }
        guard try archive.uint16(at: endOffset + 4) == 0,
              try archive.uint16(at: endOffset + 6) == 0 else {
            throw invalid("multi-disk ZIP archives are not allowed")
        }
        let entriesOnDisk = Int(try archive.uint16(at: endOffset + 8))
        let entryCount = Int(try archive.uint16(at: endOffset + 10))
        guard entriesOnDisk == entryCount, entryCount == 2 else {
            throw invalid("exactly two central-directory entries are required")
        }
        guard try archive.uint16(at: endOffset + 20) == 0 else {
            throw invalid("ZIP comments are not allowed")
        }
        let centralSize = Int(try archive.uint32(at: endOffset + 12))
        let centralOffset = Int(try archive.uint32(at: endOffset + 16))
        guard let centralEnd = checkedEnd(
            offset: centralOffset,
            length: centralSize,
            limit: archive.count
        ), centralEnd == endOffset else {
            throw invalid("invalid central-directory bounds")
        }

        var cursor = centralOffset
        var centralEntries: [CentralEntry] = []
        var names = Set<String>()
        for _ in 0..<entryCount {
            guard let fixedEnd = checkedEnd(offset: cursor, length: 46, limit: centralEnd),
                  try archive.uint32(at: cursor) == 0x02014b50 else {
                throw invalid("invalid central-directory entry")
            }
            let madeByVersion = try archive.uint16(at: cursor + 4)
            let neededVersion = try archive.uint16(at: cursor + 6)
            let flags = try archive.uint16(at: cursor + 8)
            let method = try archive.uint16(at: cursor + 10)
            let modificationTime = try archive.uint16(at: cursor + 12)
            let modificationDate = try archive.uint16(at: cursor + 14)
            let crc = try archive.uint32(at: cursor + 16)
            let compressedSize = Int(try archive.uint32(at: cursor + 20))
            let uncompressedSize = Int(try archive.uint32(at: cursor + 24))
            let nameLength = Int(try archive.uint16(at: cursor + 28))
            let extraLength = Int(try archive.uint16(at: cursor + 30))
            let commentLength = Int(try archive.uint16(at: cursor + 32))
            let diskStart = try archive.uint16(at: cursor + 34)
            let internalAttributes = try archive.uint16(at: cursor + 36)
            let externalAttributes = try archive.uint32(at: cursor + 38)
            let localOffset = Int(try archive.uint32(at: cursor + 42))
            guard madeByVersion == 20,
                  neededVersion == 20,
                  flags & ~UInt16(0x0800) == 0,
                  flags & UInt16(0x0001) == 0,
                  flags & UInt16(0x0008) == 0,
                  method == 0,
                  modificationTime == 0,
                  modificationDate == 0x0021,
                  compressedSize == uncompressedSize,
                  extraLength == 0,
                  commentLength == 0,
                  diskStart == 0,
                  internalAttributes == 0,
                  externalAttributes == 0 else {
                throw invalid(
                    "encrypted, data-descriptor, compressed, ZIP64, attributed, or extended entries are not allowed"
                )
            }
            guard uncompressedSize <= LocalDataBackupService.maximumDatabaseByteCount else {
                throw LocalDataBackupError.fileTooLarge(
                    limit: LocalDataBackupService.maximumDatabaseByteCount
                )
            }
            guard let nameEnd = checkedEnd(
                offset: fixedEnd,
                length: nameLength,
                limit: centralEnd
            ) else {
                throw invalid("invalid central entry name bounds")
            }
            let nameData = archive.subdata(in: fixedEnd..<nameEnd)
            guard let name = String(data: nameData, encoding: .utf8),
                  isSafeEntryName(name) else {
                throw invalid("entry names must be plain UTF-8 filenames")
            }
            guard names.insert(name).inserted else {
                throw invalid("duplicate entry names are not allowed")
            }
            centralEntries.append(CentralEntry(
                name: name,
                flags: flags,
                method: method,
                modificationTime: modificationTime,
                modificationDate: modificationDate,
                crc32: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            cursor = nameEnd
        }
        guard cursor == centralEnd,
              names == Set(["manifest.json", DatabaseBackupManifest.databaseFilename]) else {
            throw invalid("unexpected, missing, or hidden entries are not allowed")
        }

        var result: [String: Data] = [:]
        var localCursor = 0
        for entry in centralEntries.sorted(by: { $0.localHeaderOffset < $1.localHeaderOffset }) {
            guard entry.localHeaderOffset == localCursor,
                  let fixedEnd = checkedEnd(
                    offset: entry.localHeaderOffset,
                    length: 30,
                    limit: centralOffset
                  ),
                  try archive.uint32(at: entry.localHeaderOffset) == 0x04034b50 else {
                throw invalid("overlapping, gapped, or invalid local entries are not allowed")
            }
            let localNeededVersion = try archive.uint16(at: entry.localHeaderOffset + 4)
            let localFlags = try archive.uint16(at: entry.localHeaderOffset + 6)
            let localMethod = try archive.uint16(at: entry.localHeaderOffset + 8)
            let localModificationTime = try archive.uint16(at: entry.localHeaderOffset + 10)
            let localModificationDate = try archive.uint16(at: entry.localHeaderOffset + 12)
            let localCRC = try archive.uint32(at: entry.localHeaderOffset + 14)
            let localCompressedSize = Int(try archive.uint32(at: entry.localHeaderOffset + 18))
            let localUncompressedSize = Int(try archive.uint32(at: entry.localHeaderOffset + 22))
            let nameLength = Int(try archive.uint16(at: entry.localHeaderOffset + 26))
            let extraLength = Int(try archive.uint16(at: entry.localHeaderOffset + 28))
            guard localNeededVersion == 20,
                  localFlags == entry.flags,
                  localMethod == entry.method,
                  localModificationTime == entry.modificationTime,
                  localModificationDate == entry.modificationDate,
                  localCRC == entry.crc32,
                  localCompressedSize == entry.compressedSize,
                  localUncompressedSize == entry.uncompressedSize,
                  extraLength == 0,
                  let nameEnd = checkedEnd(
                    offset: fixedEnd,
                    length: nameLength,
                    limit: centralOffset
                  ),
                  let dataEnd = checkedEnd(
                    offset: nameEnd,
                    length: entry.compressedSize,
                    limit: centralOffset
                  ) else {
                throw invalid("local and central entry metadata do not match")
            }
            let localNameData = archive.subdata(in: fixedEnd..<nameEnd)
            guard String(data: localNameData, encoding: .utf8) == entry.name else {
                throw invalid("local and central entry names do not match")
            }
            let data = archive.subdata(in: nameEnd..<dataEnd)
            guard CRC32.checksum(data) == entry.crc32 else {
                throw invalid("CRC-32 mismatch for \(entry.name)")
            }
            result[entry.name] = data
            localCursor = dataEnd
        }
        guard localCursor == centralOffset else {
            throw invalid("bytes outside declared ZIP entries are not allowed")
        }
        return result
    }

    private static func isSafeEntryName(_ name: String) -> Bool {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.hasPrefix("/"),
              !name.hasPrefix("\\"),
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains(":"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return true
    }

    private static func checkedEnd(offset: Int, length: Int, limit: Int) -> Int? {
        guard offset >= 0, length >= 0, offset <= limit, length <= limit - offset else {
            return nil
        }
        return offset + length
    }

    private static func invalid(_ reason: String) -> LocalDataBackupError {
        .invalidArchive(reason)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var current = UInt32(value)
        for _ in 0..<8 {
            current = current & 1 == 1
                ? 0xedb88320 ^ (current >> 1)
                : current >> 1
        }
        return current
    }

    static func checksum(_ data: Data) -> UInt32 {
        var result = UInt32.max
        for byte in data {
            let index = Int((result ^ UInt32(byte)) & 0xff)
            result = table[index] ^ (result >> 8)
        }
        return result ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= count - 2 else {
            throw LocalDataBackupError.invalidArchive("truncated 16-bit ZIP field")
        }
        let first = UInt16(self[startIndex + offset])
        let second = UInt16(self[startIndex + offset + 1]) << 8
        return first | second
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= count - 4 else {
            throw LocalDataBackupError.invalidArchive("truncated 32-bit ZIP field")
        }
        return UInt32(self[startIndex + offset])
            | (UInt32(self[startIndex + offset + 1]) << 8)
            | (UInt32(self[startIndex + offset + 2]) << 16)
            | (UInt32(self[startIndex + offset + 3]) << 24)
    }
}
