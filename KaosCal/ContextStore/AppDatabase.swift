import Foundation
import GRDB

struct AppDatabase: Sendable {
    private let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try DatabaseMigrations.migrator.migrate(writer)
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(
            DatabaseQueue(configuration: makeConfiguration())
        )
    }

    static func open(at fileURL: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try AppDatabase(
            DatabaseQueue(
                path: fileURL.path,
                configuration: makeConfiguration()
            )
        )
    }

    static func openDefault(
        fileManager: FileManager = .default
    ) throws -> AppDatabase {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(
            "KaosCal",
            isDirectory: true
        )
        return try open(
            at: directory.appendingPathComponent("kaoscal.sqlite")
        )
    }

    func read<T>(_ value: (Database) throws -> T) throws -> T {
        try writer.read(value)
    }

    func write<T>(_ updates: (Database) throws -> T) throws -> T {
        try writer.write(updates)
    }

    func appliedMigrations() throws -> [String] {
        try read { db in
            try DatabaseMigrations.migrator.completedMigrations(db)
        }
    }

    func foreignKeysEnabled() throws -> Bool {
        try read { db in
            try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") ?? false
        }
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.label = "KaosCal Context Store"
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }
}
