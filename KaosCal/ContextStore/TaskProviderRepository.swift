import Foundation
import GRDB

final class TaskProviderRepository {
    private let database: AppDatabase
    private let now: () -> Date
    private let makeID: () -> String

    init(
        database: AppDatabase,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.database = database
        self.now = now
        self.makeID = makeID
    }

    func fetchAccounts() throws -> [ProviderAccountRecord] {
        try database.read { db in
            try ProviderAccountRecord.fetchAll(db)
        }
    }

    func upsertAccount(
        provider: TaskProviderKind,
        accountKey: String,
        displayName: String,
        authorizationState: TaskProviderAuthorizationState
    ) throws -> ProviderAccountRecord {
        let timestamp = now()
        return try database.write { db in
            if var existing = try ProviderAccountRecord
                .filter(
                    Column("provider") == provider.rawValue
                        && Column("account_key") == accountKey
                )
                .fetchOne(db) {
                existing.displayName = displayName
                existing.authorizationState = authorizationState
                existing.updatedAt = timestamp
                try existing.update(db)
                return existing
            }
            let account = ProviderAccountRecord(
                id: makeID(),
                provider: provider,
                accountKey: accountKey,
                displayName: displayName,
                authorizationState: authorizationState,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try account.insert(db)
            return account
        }
    }

    func updateAuthorization(
        accountID: String,
        state: TaskProviderAuthorizationState
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE provider_accounts
                    SET authorization_state = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [state.rawValue, now(), accountID]
            )
        }
    }

    func deleteAccounts(provider: TaskProviderKind) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM provider_accounts WHERE provider = ?",
                arguments: [provider.rawValue]
            )
        }
    }

    func fetchDestination(
        calendarIdentifier: String
    ) throws -> CalendarTaskDestinationRecord? {
        try database.read { db in
            try CalendarTaskDestinationRecord.fetchOne(
                db,
                key: calendarIdentifier
            )
        }
    }

    func fetchDestinations() throws -> [CalendarTaskDestinationRecord] {
        try database.read { db in
            try CalendarTaskDestinationRecord.fetchAll(db)
        }
    }

    func saveDestination(
        _ destination: CalendarTaskDestinationRecord
    ) throws {
        try database.write { db in
            try destination.save(db)
        }
    }

    func deleteDestination(calendarIdentifier: String) throws {
        try database.write { db in
            try CalendarTaskDestinationRecord.deleteOne(
                db,
                key: calendarIdentifier
            )
        }
    }

    func fetchBinding(
        eventTaskID: String
    ) throws -> TaskBindingRecord? {
        try database.read { db in
            try TaskBindingRecord
                .filter(Column("event_task_id") == eventTaskID)
                .fetchOne(db)
        }
    }

    func fetchBinding(
        personalTaskID: String
    ) throws -> TaskBindingRecord? {
        try database.read { db in
            try TaskBindingRecord
                .filter(Column("personal_task_id") == personalTaskID)
                .fetchOne(db)
        }
    }

    func fetchBinding(providerItemID: String) throws -> TaskBindingRecord? {
        try database.read { db in
            try TaskBindingRecord
                .filter(Column("provider_item_id") == providerItemID)
                .fetchOne(db)
        }
    }

    func fetchBindings() throws -> [TaskBindingRecord] {
        try database.read { db in
            try TaskBindingRecord.fetchAll(db)
        }
    }

    func fetchProviderItem(
        id: String
    ) throws -> ProviderItemRecord? {
        try database.read { db in
            try ProviderItemRecord.fetchOne(db, key: id)
        }
    }

    func fetchProviderItem(
        accountID: String,
        remoteID: String
    ) throws -> ProviderItemRecord? {
        try database.read { db in
            try ProviderItemRecord
                .filter(
                    Column("account_id") == accountID
                        && Column("remote_id") == remoteID
                )
                .fetchOne(db)
        }
    }

    func fetchAccount(id: String) throws -> ProviderAccountRecord? {
        try database.read { db in
            try ProviderAccountRecord.fetchOne(db, key: id)
        }
    }

    func insertLinkedTask(
        account: ProviderAccountRecord,
        remote: RemoteTaskSnapshot,
        eventTaskID: String,
        occurrenceKey: String?,
        syncHash: String
    ) throws -> TaskBindingRecord {
        let timestamp = now()
        return try database.write { db in
            let item = ProviderItemRecord(
                id: makeID(),
                accountID: account.id,
                entityType: "task",
                remoteID: remote.id,
                remoteParentID: remote.parentID,
                remoteVersion: remote.version,
                cachedTitle: remote.title,
                // OAuth provider descriptions are not needed to render an
                // event task. Keeping them out of the SQLite cache also keeps
                // them out of local backup archives.
                cachedNotes: "",
                cachedDueAt: remote.dueAt,
                cachedCompleted: remote.isCompleted,
                lastSeenAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try item.insert(db)
            let binding = TaskBindingRecord(
                id: makeID(),
                providerItemID: item.id,
                eventTaskID: eventTaskID,
                personalTaskID: nil,
                occurrenceKey: occurrenceKey,
                syncState: .linked,
                lastSyncedHash: syncHash,
                remoteVersion: remote.version,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try binding.insert(db)
            return binding
        }
    }

    func updateLinkedTask(
        bindingID: String,
        itemID: String,
        remote: RemoteTaskSnapshot,
        syncState: TaskProviderSyncState,
        syncHash: String?
    ) throws {
        let timestamp = now()
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE provider_items
                    SET remote_parent_id = ?, remote_version = ?, cached_title = ?,
                        cached_notes = '', cached_due_at = ?, cached_completed = ?,
                        last_seen_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    remote.parentID,
                    remote.version,
                    remote.title,
                    remote.dueAt,
                    remote.isCompleted,
                    timestamp,
                    timestamp,
                    itemID
                ]
            )
            try db.execute(
                sql: """
                    UPDATE task_bindings
                    SET sync_state = ?, last_synced_hash = ?, remote_version = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    syncState.rawValue,
                    syncHash,
                    remote.version,
                    timestamp,
                    bindingID
                ]
            )
        }
    }

    func markBinding(
        bindingID: String,
        state: TaskProviderSyncState
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE task_bindings
                    SET sync_state = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [state.rawValue, now(), bindingID]
            )
        }
    }

    func removeBinding(bindingID: String) throws {
        try database.write { db in
            try TaskBindingRecord.deleteOne(db, key: bindingID)
        }
    }

    func fetchSyncCursor(
        accountID: String,
        key: String
    ) throws -> String? {
        try database.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT cursor_value FROM provider_sync_cursors
                    WHERE account_id = ? AND cursor_key = ?
                    """,
                arguments: [accountID, key]
            )
        }
    }

    func saveSyncCursor(
        accountID: String,
        key: String,
        value: String
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO provider_sync_cursors (
                        account_id, cursor_key, cursor_value, updated_at
                    ) VALUES (?, ?, ?, ?)
                    ON CONFLICT(account_id, cursor_key) DO UPDATE SET
                        cursor_value = excluded.cursor_value,
                        updated_at = excluded.updated_at
                    """,
                arguments: [accountID, key, value, now()]
            )
        }
    }

    func deleteSyncCursor(accountID: String, key: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM provider_sync_cursors
                    WHERE account_id = ? AND cursor_key = ?
                    """,
                arguments: [accountID, key]
            )
        }
    }
}
