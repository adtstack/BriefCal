import Foundation
import GRDB
import XCTest
@testable import KaosCal

final class LocalDataBackupServiceTests: XCTestCase {
    func testExportCreatesInspectableCurrentSchemaBackup() throws {
        try withTemporaryDirectory { directory in
            let databaseURL = directory.appendingPathComponent("live.sqlite")
            let database = try AppDatabase.open(at: databaseURL)
            try insertFixture(into: database, suffix: "export")
            let service = LocalDataBackupService(database: database)
            let archiveURL = directory.appendingPathComponent("KaosCal Backup.zip")
            let now = Date(timeIntervalSince1970: 1_784_378_096.125)

            let result = try service.exportBackup(
                to: archiveURL,
                now: now,
                appVersion: "0.9-test"
            )
            let inspection = try service.inspectBackup(at: archiveURL)

            XCTAssertEqual(database.databaseURL, databaseURL.standardizedFileURL)
            XCTAssertEqual(result.archiveURL, archiveURL.standardizedFileURL)
            XCTAssertEqual(inspection.manifest, result.manifest)
            XCTAssertEqual(result.manifest.backupFormatVersion, 1)
            XCTAssertEqual(result.manifest.applicationIdentifier, "com.adtstack.kaoscal")
            XCTAssertEqual(result.manifest.applicationVersion, "0.9-test")
            XCTAssertEqual(
                result.manifest.appliedMigrations,
                ["v1_context_store", "v2_event_change_log", "v3_calendar_clarity"]
            )
            XCTAssertEqual(result.manifest.schemaIdentifier, "v3_calendar_clarity")
            XCTAssertEqual(result.manifest.schemaVersion, 3)
            XCTAssertEqual(result.manifest.databaseFilename, "kaoscal.sqlite")
            XCTAssertGreaterThan(result.manifest.databaseByteCount, 0)
            XCTAssertEqual(result.manifest.databaseSHA256.count, 64)
            XCTAssertFalse(result.manifest.containsCompleteCalendarEvents)
            XCTAssertTrue(result.manifest.containsLinkedEventSnapshots)
            XCTAssertTrue(result.manifest.containsEventBriefs)
            XCTAssertFalse(result.manifest.isEncrypted)
            try assertStandardUnzipAccepts(archiveURL)
        }
    }

    func testImportRestoresThroughSameDatabaseWriterAndKeepsAutomaticBackup() throws {
        try withTemporaryDirectory { directory in
            let source = try AppDatabase.open(
                at: directory.appendingPathComponent("source.sqlite")
            )
            try insertFixture(into: source, suffix: "source")
            let sourceService = LocalDataBackupService(database: source)
            let archiveURL = directory.appendingPathComponent("source.zip")
            _ = try sourceService.exportBackup(
                to: archiveURL,
                now: Date(timeIntervalSince1970: 10),
                appVersion: "test"
            )

            let target = try AppDatabase.open(
                at: directory.appendingPathComponent("target.sqlite")
            )
            try insertFixture(into: target, suffix: "target")
            let store = ContextStore(database: target)
            let targetService = LocalDataBackupService(database: target)
            let automaticDirectory = directory.appendingPathComponent("Automatic")

            let result = try targetService.importBackup(
                from: archiveURL,
                automaticBackupDirectory: automaticDirectory,
                now: Date(timeIntervalSince1970: 20),
                appVersion: "test"
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: result.automaticBackupURL.path))
            XCTAssertNoThrow(try targetService.inspectBackup(at: result.automaticBackupURL))
            XCTAssertEqual(try contextIDs(in: target), ["context-source"])
            XCTAssertEqual(
                try store.eventContexts.fetchAll().map(\.id),
                ["context-source"]
            )
            XCTAssertEqual(
                try store.calendarRoles.fetchAll().map(\.calendarIdentifier),
                ["calendar-source"]
            )

            // Existing repositories retain the same writer identity and see
            // the restored rows; no live SQLite file replacement occurred.
            try target.write { db in
                try db.execute(
                    sql: "UPDATE event_contexts SET notes = 'same writer' WHERE id = ?",
                    arguments: ["context-source"]
                )
            }
            XCTAssertEqual(
                try String.fetchOne(
                    target,
                    sql: "SELECT notes FROM event_contexts WHERE id = ?",
                    arguments: ["context-source"]
                ),
                "same writer"
            )
        }
    }

    func testResetDeletesAllSixUserTablesAndAutomaticBackupCanRestoreThem() throws {
        try withTemporaryDirectory { directory in
            let database = try AppDatabase.open(
                at: directory.appendingPathComponent("reset.sqlite")
            )
            try insertFixture(into: database, suffix: "reset")
            let service = LocalDataBackupService(database: database)

            let result = try service.resetLocalData(
                automaticBackupDirectory: directory.appendingPathComponent("Automatic"),
                now: Date(timeIntervalSince1970: 30),
                appVersion: "test"
            )

            XCTAssertEqual(
                result.deletedRowCounts,
                LocalDataDeletedRowCounts(
                    eventContexts: 1,
                    eventLinks: 1,
                    eventTasks: 1,
                    personalTasks: 1,
                    eventChangeLog: 1,
                    calendarPreferences: 1
                )
            )
            XCTAssertEqual(result.deletedRowCounts.total, 6)
            XCTAssertEqual(try allUserTableCounts(in: database), [0, 0, 0, 0, 0, 0])
            XCTAssertEqual(
                try database.appliedMigrations(),
                ["v1_context_store", "v2_event_change_log", "v3_calendar_clarity"]
            )

            _ = try service.importBackup(
                from: result.automaticBackupURL,
                automaticBackupDirectory: directory.appendingPathComponent("Restore Safety"),
                now: Date(timeIntervalSince1970: 40),
                appVersion: "test"
            )
            XCTAssertEqual(try allUserTableCounts(in: database), [1, 1, 1, 1, 1, 1])
        }
    }

    func testInspectRejectsCRCMutationAndPathTraversalName() throws {
        try withTemporaryDirectory { directory in
            let database = try AppDatabase.open(
                at: directory.appendingPathComponent("live.sqlite")
            )
            let service = LocalDataBackupService(database: database)
            let archiveURL = directory.appendingPathComponent("valid.zip")
            _ = try service.exportBackup(
                to: archiveURL,
                now: Date(timeIntervalSince1970: 50),
                appVersion: "test"
            )

            let archiveSymlinkURL = directory.appendingPathComponent("input-link.zip")
            try FileManager.default.createSymbolicLink(
                at: archiveSymlinkURL,
                withDestinationURL: archiveURL
            )
            XCTAssertThrowsError(try service.inspectBackup(at: archiveSymlinkURL)) { error in
                guard case LocalDataBackupError.invalidArchive = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }

            var crcMutation = try Data(contentsOf: archiveURL)
            let databaseHeader = try XCTUnwrap(crcMutation.range(of: Data("SQLite format 3\0".utf8)))
            crcMutation[databaseHeader.lowerBound + 20] ^= 0xff
            let crcURL = directory.appendingPathComponent("bad-crc.zip")
            try crcMutation.write(to: crcURL)
            XCTAssertThrowsError(try service.inspectBackup(at: crcURL)) { error in
                guard case let LocalDataBackupError.invalidArchive(reason) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertTrue(reason.contains("CRC-32"))
            }

            var traversalMutation = try Data(contentsOf: archiveURL)
            replaceAll(
                Data("manifest.json".utf8),
                with: Data("../evil.json_".utf8),
                in: &traversalMutation
            )
            let traversalURL = directory.appendingPathComponent("traversal.zip")
            try traversalMutation.write(to: traversalURL)
            XCTAssertThrowsError(try service.inspectBackup(at: traversalURL)) { error in
                guard case LocalDataBackupError.invalidArchive = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }

            var attributedMutation = try Data(contentsOf: archiveURL)
            let centralSignature = Data([0x50, 0x4b, 0x01, 0x02])
            let centralRange = try XCTUnwrap(attributedMutation.range(of: centralSignature))
            attributedMutation[centralRange.lowerBound + 38] = 1
            let attributedURL = directory.appendingPathComponent("attributed.zip")
            try attributedMutation.write(to: attributedURL)
            XCTAssertThrowsError(try service.inspectBackup(at: attributedURL)) { error in
                guard case LocalDataBackupError.invalidArchive = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testInspectRejectsUnsupportedZIPEnvelopeFeatures() throws {
        try withTemporaryDirectory { directory in
            let database = try AppDatabase.open(
                at: directory.appendingPathComponent("live.sqlite")
            )
            let service = LocalDataBackupService(database: database)
            let archiveURL = directory.appendingPathComponent("valid.zip")
            _ = try service.exportBackup(
                to: archiveURL,
                now: Date(timeIntervalSince1970: 55),
                appVersion: "test"
            )
            let validArchive = try Data(contentsOf: archiveURL)

            try assertArchiveRejected(
                named: "trailing",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { $0.append(0) }
            try assertArchiveRejected(
                named: "multi-disk",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { data in
                data.writeLittleEndian(UInt16(1), at: data.count - 22 + 4)
            }
            try assertArchiveRejected(
                named: "encrypted",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { data in
                let central = try XCTUnwrap(centralDirectoryOffsets(in: data).first)
                data.writeLittleEndian(UInt16(0x0801), at: central + 8)
            }
            try assertArchiveRejected(
                named: "data-descriptor",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { data in
                let central = try XCTUnwrap(centralDirectoryOffsets(in: data).first)
                data.writeLittleEndian(UInt16(0x0808), at: central + 8)
            }
            try assertArchiveRejected(
                named: "deflate",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { data in
                let central = try XCTUnwrap(centralDirectoryOffsets(in: data).first)
                data.writeLittleEndian(UInt16(8), at: central + 10)
            }
            try assertArchiveRejected(
                named: "zip64",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { data in
                let central = try XCTUnwrap(centralDirectoryOffsets(in: data).first)
                data.writeLittleEndian(UInt16(45), at: central + 6)
            }
            try assertArchiveRejected(
                named: "overlap",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { data in
                let central = try XCTUnwrap(centralDirectoryOffsets(in: data).last)
                data.writeLittleEndian(UInt32(0), at: central + 42)
            }
            try assertArchiveRejected(
                named: "oversize",
                validArchive: validArchive,
                directory: directory,
                service: service
            ) { data in
                let central = try XCTUnwrap(centralDirectoryOffsets(in: data).first)
                data.writeLittleEndian(
                    UInt32(LocalDataBackupService.maximumDatabaseByteCount + 1),
                    at: central + 24
                )
            }
        }
    }

    func testExportRejectsExtraSchemaObjectAndLiveDatabaseDestination() throws {
        try withTemporaryDirectory { directory in
            let databaseURL = directory.appendingPathComponent("live.sqlite")
            let hardLinkURL = directory.appendingPathComponent("live-hard-link.sqlite")
            try Data().write(to: databaseURL)
            try FileManager.default.linkItem(at: databaseURL, to: hardLinkURL)
            let database = try AppDatabase.open(at: databaseURL)
            let service = LocalDataBackupService(database: database)

            XCTAssertThrowsError(
                try service.exportBackup(
                    to: databaseURL,
                    now: Date(timeIntervalSince1970: 60),
                    appVersion: "test"
                )
            ) { error in
                guard case LocalDataBackupError.unsafeDestination = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }

            for sidecarSuffix in ["-wal", "-shm", "-journal"] {
                XCTAssertThrowsError(
                    try service.exportBackup(
                        to: URL(fileURLWithPath: databaseURL.path + sidecarSuffix),
                        now: Date(timeIntervalSince1970: 61),
                        appVersion: "test"
                    )
                ) { error in
                    guard case LocalDataBackupError.unsafeDestination = error else {
                        return XCTFail("Unexpected error: \(error)")
                    }
                }
            }

            let linkedParentURL = directory.appendingPathComponent("linked-parent")
            try FileManager.default.createSymbolicLink(
                at: linkedParentURL,
                withDestinationURL: directory
            )
            for protectedSuffix in ["", "-wal", "-shm", "-journal"] {
                let linkedDestination = URL(
                    fileURLWithPath: linkedParentURL
                        .appendingPathComponent("live.sqlite").path + protectedSuffix
                )
                XCTAssertThrowsError(
                    try service.exportBackup(
                        to: linkedDestination,
                        now: Date(timeIntervalSince1970: 61),
                        appVersion: "test"
                    )
                ) { error in
                    guard case LocalDataBackupError.unsafeDestination = error else {
                        return XCTFail("Unexpected error: \(error)")
                    }
                }
            }

            XCTAssertThrowsError(
                try service.exportBackup(
                    to: hardLinkURL,
                    now: Date(timeIntervalSince1970: 61),
                    appVersion: "test"
                )
            ) { error in
                guard case LocalDataBackupError.unsafeDestination = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }

            let victimURL = directory.appendingPathComponent("victim.txt")
            try Data("untouched".utf8).write(to: victimURL)
            let symlinkURL = directory.appendingPathComponent("backup-link.zip")
            try FileManager.default.createSymbolicLink(
                at: symlinkURL,
                withDestinationURL: victimURL
            )
            XCTAssertThrowsError(
                try service.exportBackup(
                    to: symlinkURL,
                    now: Date(timeIntervalSince1970: 62),
                    appVersion: "test"
                )
            ) { error in
                guard case LocalDataBackupError.unsafeDestination = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: victimURL), Data("untouched".utf8))

            try database.write { db in
                try db.execute(sql: "CREATE VIEW unexpected_backup_view AS SELECT 1 AS value")
            }
            XCTAssertThrowsError(
                try service.exportBackup(
                    to: directory.appendingPathComponent("extra-schema.zip"),
                    now: Date(timeIntervalSince1970: 70),
                    appVersion: "test"
                )
            ) { error in
                guard case let LocalDataBackupError.invalidDatabase(reason) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertTrue(reason.contains("sqlite_master"))
            }
        }
    }

    func testExportRejectsSQLitePrefixedHiddenTrigger() throws {
        try withTemporaryDirectory { directory in
            let databaseURL = directory.appendingPathComponent("hidden-trigger.sqlite")
            try createCurrentDatabase(at: databaseURL)

            try runSQLite3(
                at: databaseURL,
                sql: """
                    PRAGMA writable_schema = ON;
                    INSERT INTO sqlite_master (
                        type, name, tbl_name, rootpage, sql
                    ) VALUES (
                        'trigger',
                        'sqlite_kaoscal_hidden',
                        'personal_tasks',
                        0,
                        'CREATE TRIGGER sqlite_kaoscal_hidden AFTER INSERT ON personal_tasks BEGIN DELETE FROM grdb_migrations; END'
                    );
                    PRAGMA writable_schema = OFF;
                    """
            )

            let database = try AppDatabase.open(at: databaseURL)
            let service = LocalDataBackupService(database: database)
            XCTAssertEqual(
                try database.read { db in
                    try String.fetchOne(
                        db,
                        sql: "SELECT name FROM sqlite_master WHERE name = ?",
                        arguments: ["sqlite_kaoscal_hidden"]
                    )
                },
                "sqlite_kaoscal_hidden"
            )
            XCTAssertThrowsError(
                try service.exportBackup(
                    to: directory.appendingPathComponent("hidden-trigger.zip"),
                    now: Date(timeIntervalSince1970: 80),
                    appVersion: "test"
                )
            ) { error in
                guard case let LocalDataBackupError.invalidDatabase(reason) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertTrue(reason.contains("sqlite_master"))
            }
        }
    }

    func testExportRejectsUnexpectedMigrationLedgerEntry() throws {
        try withTemporaryDirectory { directory in
            let database = try AppDatabase.open(
                at: directory.appendingPathComponent("future-ledger.sqlite")
            )
            try database.write { db in
                try db.execute(
                    sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                    arguments: ["v4_future_data_only"]
                )
            }
            let service = LocalDataBackupService(database: database)

            XCTAssertThrowsError(
                try service.exportBackup(
                    to: directory.appendingPathComponent("future-ledger.zip"),
                    now: Date(timeIntervalSince1970: 90),
                    appVersion: "test"
                )
            ) { error in
                guard case let LocalDataBackupError.incompatibleSchema(expected, found) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(
                    expected,
                    ["v1_context_store", "v2_event_change_log", "v3_calendar_clarity"]
                )
                XCTAssertEqual(found, ["4 migration ledger entries"])
            }
        }
    }

    private func createCurrentDatabase(at databaseURL: URL) throws {
        let database = try AppDatabase.open(at: databaseURL)
        XCTAssertEqual(
            try database.appliedMigrations(),
            ["v1_context_store", "v2_event_change_log", "v3_calendar_clarity"]
        )
    }

    private func runSQLite3(at databaseURL: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(data: outputData, encoding: .utf8) ?? "sqlite3 produced non-UTF-8 output"
        )
    }

    private func insertFixture(into database: AppDatabase, suffix: String) throws {
        let contextID = "context-\(suffix)"
        let timestamp = "2026-07-12 10:00:00.000"
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO event_contexts (
                        id, title_snapshot, lifecycle_status, notes,
                        created_at, updated_at
                    ) VALUES (?, ?, 'scheduled', '', ?, ?)
                    """,
                arguments: [contextID, "Fixture \(suffix)", timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_links (
                        id, context_id, calendar_identifier, source_title,
                        calendar_title_snapshot, title_snapshot,
                        start_snapshot, end_snapshot, is_all_day,
                        is_recurring, time_semantics, time_zone_identifier,
                        occurrence_identity_key, is_detached, fingerprint,
                        link_status, last_seen_at, created_at, updated_at
                    ) VALUES (
                        ?, ?, 'calendar', 'Exchange', '일정', ?, ?, ?,
                        0, 0, 'zoned', 'Asia/Seoul', 'single:v1', 0, ?,
                        'active', ?, ?, ?
                    )
                    """,
                arguments: [
                    "link-\(suffix)", contextID, "Fixture \(suffix)",
                    timestamp, "2026-07-12 11:00:00.000", "fingerprint-\(suffix)",
                    timestamp, timestamp, timestamp,
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_tasks (
                        id, context_id, section, title, completed,
                        sort_order, due_kind, created_at, updated_at
                    ) VALUES (?, ?, 'before', ?, 0, 0, 'none', ?, ?)
                    """,
                arguments: ["task-\(suffix)", contextID, "Task \(suffix)", timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO personal_tasks (
                        id, title, notes, completed, sort_order,
                        created_at, updated_at
                    ) VALUES (?, ?, '', 0, 0, ?, ?)
                    """,
                arguments: ["personal-\(suffix)", "Personal \(suffix)", timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_change_log (
                        id, context_id, change_type, scope, before_payload,
                        after_payload, undo_state, created_at
                    ) VALUES (?, ?, 'created', 'single', '{}', '{}', 'unavailable', ?)
                    """,
                arguments: ["change-\(suffix)", contextID, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO calendar_preferences (
                        calendar_identifier, source_title_snapshot,
                        calendar_title_snapshot, role, created_at, updated_at
                    ) VALUES (?, 'Exchange', '일정', 'work', ?, ?)
                    """,
                arguments: ["calendar-\(suffix)", timestamp, timestamp]
            )
        }
    }

    private func contextIDs(in database: AppDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM event_contexts ORDER BY id")
        }
    }

    private func allUserTableCounts(in database: AppDatabase) throws -> [Int] {
        try database.read { db in
            try [
                "event_contexts",
                "event_links",
                "event_tasks",
                "personal_tasks",
                "event_change_log",
                "calendar_preferences",
            ].map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            }
        }
    }

    private func replaceAll(_ needle: Data, with replacement: Data, in data: inout Data) {
        XCTAssertEqual(needle.count, replacement.count)
        var searchStart = data.startIndex
        while searchStart < data.endIndex,
              let range = data.range(of: needle, in: searchStart..<data.endIndex) {
            data.replaceSubrange(range, with: replacement)
            searchStart = range.lowerBound + replacement.count
        }
    }

    private func assertStandardUnzipAccepts(_ archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", archiveURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(data: data, encoding: .utf8) ?? "unzip produced non-UTF-8 output"
        )
    }

    private func assertArchiveRejected(
        named name: String,
        validArchive: Data,
        directory: URL,
        service: LocalDataBackupService,
        mutate: (inout Data) throws -> Void
    ) throws {
        var archive = validArchive
        try mutate(&archive)
        let url = directory.appendingPathComponent("\(name).zip")
        try archive.write(to: url)
        XCTAssertThrowsError(try service.inspectBackup(at: url), name)
    }

    private func centralDirectoryOffsets(in data: Data) -> [Int] {
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        var offsets: [Int] = []
        var cursor = data.startIndex
        while cursor < data.endIndex,
              let range = data.range(of: signature, in: cursor..<data.endIndex) {
            offsets.append(range.lowerBound)
            cursor = range.upperBound
        }
        return offsets
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalDataBackupServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private extension String {
    static func fetchOne(
        _ database: AppDatabase,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> String? {
        try database.read { db in
            try String.fetchOne(db, sql: sql, arguments: arguments)
        }
    }
}

private extension Data {
    mutating func writeLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { bytes in
            replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
    }
}
