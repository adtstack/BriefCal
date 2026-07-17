import Foundation
import GRDB

final class TaskProviderRepository {
    private let database: AppDatabase
    private let eventTasks: EventTaskRepository
    private let now: () -> Date
    private let makeID: () -> String

    init(
        database: AppDatabase,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.database = database
        eventTasks = EventTaskRepository(database: database, now: now)
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
        _ = try database.write { db in
            try CalendarTaskDestinationRecord.deleteOne(
                db,
                key: calendarIdentifier
            )
        }
    }

    /// Destination changes apply to tasks created after the change. Existing
    /// unbound tasks are pinned local-only so a later title/completion edit
    /// cannot silently create them in a newly selected provider/list.
    func markExistingUnboundTasksLocalOnly(
        calendarIdentifier: String
    ) throws {
        let timestamp = now()
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO task_provider_preferences (
                        event_task_id, link_mode, created_at, updated_at
                    )
                    SELECT event_tasks.id, ?, ?, ?
                    FROM event_tasks
                    INNER JOIN event_links
                        ON event_links.context_id = event_tasks.context_id
                    LEFT JOIN task_bindings
                        ON task_bindings.event_task_id = event_tasks.id
                    LEFT JOIN provider_pending_operations AS pending
                        ON pending.event_task_id = event_tasks.id
                    WHERE event_links.calendar_identifier = ?
                      AND task_bindings.id IS NULL
                      AND pending.id IS NULL
                    ON CONFLICT(event_task_id) DO UPDATE SET
                        link_mode = excluded.link_mode,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    TaskProviderLinkMode.localOnly.rawValue,
                    timestamp,
                    timestamp,
                    calendarIdentifier
                ]
            )
        }
    }

    func isLocalOnly(eventTaskID: String) throws -> Bool {
        try database.read { db in
            try TaskProviderPreferenceRecord.fetchOne(
                db,
                key: eventTaskID
            )?.linkMode == .localOnly
        }
    }

    func setLocalOnly(eventTaskID: String) throws {
        let timestamp = now()
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO task_provider_preferences (
                        event_task_id, link_mode, created_at, updated_at
                    ) VALUES (?, ?, ?, ?)
                    ON CONFLICT(event_task_id) DO UPDATE SET
                        link_mode = excluded.link_mode,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    eventTaskID,
                    TaskProviderLinkMode.localOnly.rawValue,
                    timestamp,
                    timestamp
                ]
            )
            try db.execute(
                sql: "DELETE FROM provider_pending_operations WHERE event_task_id = ?",
                arguments: [eventTaskID]
            )
            try db.execute(
                sql: "DELETE FROM task_bindings WHERE event_task_id = ?",
                arguments: [eventTaskID]
            )
        }
    }

    func clearLocalOnly(eventTaskID: String) throws {
        _ = try database.write { db in
            try TaskProviderPreferenceRecord.deleteOne(
                db,
                key: eventTaskID
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

    func fetchPendingOperation(
        eventTaskID: String
    ) throws -> ProviderPendingOperationRecord? {
        try database.read { db in
            try ProviderPendingOperationRecord
                .filter(Column("event_task_id") == eventTaskID)
                .fetchOne(db)
        }
    }

    func fetchPendingOperations() throws -> [ProviderPendingOperationRecord] {
        try database.read { db in
            try ProviderPendingOperationRecord.fetchAll(db)
        }
    }

    func preparePendingOperation(
        accountID: String,
        eventTaskID: String,
        operation: ProviderPendingOperationKind,
        remoteID: String?,
        remoteParentID: String,
        expectedVersion: String?
    ) throws -> ProviderPendingOperationRecord {
        let timestamp = now()
        return try database.write { db in
            if var existing = try ProviderPendingOperationRecord
                .filter(Column("event_task_id") == eventTaskID)
                .fetchOne(db) {
                if existing.accountID == accountID {
                    if existing.operation != operation
                        || existing.remoteID != remoteID
                        || existing.remoteParentID != remoteParentID {
                        existing.operation = operation
                        existing.remoteID = remoteID
                        existing.remoteParentID = remoteParentID
                        existing.expectedVersion = expectedVersion
                        existing.attemptCount = 0
                        existing.lastError = nil
                    }
                    existing.updatedAt = timestamp
                    try existing.update(db)
                    return existing
                }
                try existing.delete(db)
            }
            let pending = ProviderPendingOperationRecord(
                id: makeID(),
                accountID: accountID,
                eventTaskID: eventTaskID,
                operation: operation,
                remoteID: remoteID,
                remoteParentID: remoteParentID,
                expectedVersion: expectedVersion,
                attemptCount: 0,
                lastError: nil,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try pending.insert(db)
            return pending
        }
    }

    func beginPendingAttempt(
        operationID: String
    ) throws -> ProviderPendingOperationRecord {
        try database.write { db in
            guard var pending = try ProviderPendingOperationRecord.fetchOne(
                db,
                key: operationID
            ) else {
                throw TaskProviderError.taskNotFound
            }
            guard pending.canRetry else {
                throw TaskProviderError.providerFailure(
                    "This provider operation reached its retry limit. Keep the task local-only or link it to an existing remote task."
                )
            }
            pending.attemptCount += 1
            pending.lastError = nil
            pending.updatedAt = now()
            try pending.update(db)
            return pending
        }
    }

    func recordPendingFailure(
        operationID: String,
        message: String
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE provider_pending_operations
                    SET last_error = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [message, now(), operationID]
            )
        }
    }

    func removePendingOperation(eventTaskID: String) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM provider_pending_operations WHERE event_task_id = ?",
                arguments: [eventTaskID]
            )
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

    /// Fetches cached items that are still present remotely. Linked tasks
    /// marked missing remain available to their Event Brief recovery flow,
    /// but must not be rendered as live Microsoft To Do tasks.
    func fetchProviderItems(
        provider: TaskProviderKind
    ) throws -> [ProviderItemRecord] {
        try database.read { db in
            try ProviderItemRecord.fetchAll(
                db,
                sql: """
                    SELECT provider_items.*
                    FROM provider_items
                    INNER JOIN provider_accounts
                        ON provider_accounts.id = provider_items.account_id
                    LEFT JOIN task_bindings
                        ON task_bindings.provider_item_id = provider_items.id
                    WHERE provider_accounts.provider = ?
                      AND (
                          task_bindings.sync_state IS NULL
                          OR task_bindings.sync_state != ?
                      )
                    ORDER BY
                        provider_items.cached_completed ASC,
                        provider_items.cached_due_at IS NULL ASC,
                        provider_items.cached_due_at ASC,
                        provider_items.cached_title COLLATE NOCASE ASC
                    """,
                arguments: [
                    provider.rawValue,
                    TaskProviderSyncState.missing.rawValue
                ]
            )
        }
    }

    func fetchAccount(id: String) throws -> ProviderAccountRecord? {
        try database.read { db in
            try ProviderAccountRecord.fetchOne(db, key: id)
        }
    }

    /// Stores the minimum display projection for a remote task. This is used
    /// for Microsoft To Do tasks that are not linked to a KaosCal Event Brief.
    @discardableResult
    func upsertProviderItem(
        accountID: String,
        remote: RemoteTaskSnapshot
    ) throws -> ProviderItemRecord {
        let timestamp = now()
        return try database.write { db in
            if var existing = try ProviderItemRecord
                .filter(
                    Column("account_id") == accountID
                        && Column("remote_id") == remote.id
                )
                .fetchOne(db) {
                existing.remoteParentID = remote.parentID
                existing.remoteVersion = remote.version
                existing.cachedTitle = remote.title
                existing.cachedNotes = ""
                existing.cachedDueAt = remote.dueAt
                existing.cachedCompleted = remote.isCompleted
                existing.lastSeenAt = timestamp
                existing.updatedAt = timestamp
                try existing.update(db)
                return existing
            }

            let item = ProviderItemRecord(
                id: makeID(),
                accountID: accountID,
                entityType: "task",
                remoteID: remote.id,
                remoteParentID: remote.parentID,
                remoteVersion: remote.version,
                cachedTitle: remote.title,
                cachedNotes: "",
                cachedDueAt: remote.dueAt,
                cachedCompleted: remote.isCompleted,
                lastSeenAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try item.insert(db)
            return item
        }
    }

    /// Removes an unlinked cached task after a Microsoft delta tombstone.
    /// Bound items are retained so the Event Brief can report a missing remote
    /// counterpart and offer recovery rather than silently losing context.
    func deleteUnboundProviderItem(
        accountID: String,
        remoteID: String
    ) throws {
        _ = try database.write { db in
            guard let item = try ProviderItemRecord
                .filter(
                    Column("account_id") == accountID
                        && Column("remote_id") == remoteID
                )
                .fetchOne(db),
                try TaskBindingRecord
                .filter(Column("provider_item_id") == item.id)
                .fetchOne(db) == nil else {
                return
            }
            try item.delete(db)
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
            let item: ProviderItemRecord
            if var existing = try ProviderItemRecord
                .filter(
                    Column("account_id") == account.id
                        && Column("remote_id") == remote.id
                )
                .fetchOne(db) {
                existing.remoteParentID = remote.parentID
                existing.remoteVersion = remote.version
                existing.cachedTitle = remote.title
                existing.cachedNotes = ""
                existing.cachedDueAt = remote.dueAt
                existing.cachedCompleted = remote.isCompleted
                existing.lastSeenAt = timestamp
                existing.updatedAt = timestamp
                try existing.update(db)
                item = existing
            } else {
                item = ProviderItemRecord(
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
            }
            if let existingBinding = try TaskBindingRecord
                .filter(Column("provider_item_id") == item.id)
                .fetchOne(db) {
                guard existingBinding.eventTaskID == eventTaskID else {
                    throw TaskProviderError.providerFailure(
                        "The remote task is already linked to a different KaosCal task."
                    )
                }
                return existingBinding
            }
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

    /// Atomically replaces an Event Brief task's binding after the user has
    /// explicitly selected a concrete provider/account/list/remote task.
    func replaceLinkedTask(
        account: ProviderAccountRecord,
        remote: RemoteTaskSnapshot,
        eventTaskID: String,
        occurrenceKey: String?,
        syncHash: String,
        applyRemoteToEventTask: Bool = false
    ) throws -> TaskBindingRecord {
        let timestamp = now()
        return try database.write { db in
            if applyRemoteToEventTask {
                guard let task = try eventTasks.fetch(
                    id: eventTaskID,
                    in: db
                ) else {
                    throw TaskProviderError.taskNotFound
                }
                let due: EventTaskDue = remote.dueAt
                    .map(EventTaskDue.fixed) ?? .none
                let updated = try eventTasks.update(
                    task: task,
                    section: task.section,
                    title: remote.title,
                    sortOrder: task.sortOrder,
                    due: due,
                    in: db
                )
                _ = try eventTasks.setCompleted(
                    task: updated,
                    isCompleted: remote.isCompleted,
                    in: db
                )
            }

            let item: ProviderItemRecord
            if var existing = try ProviderItemRecord
                .filter(
                    Column("account_id") == account.id
                        && Column("remote_id") == remote.id
                )
                .fetchOne(db) {
                existing.remoteParentID = remote.parentID
                existing.remoteVersion = remote.version
                existing.cachedTitle = remote.title
                existing.cachedNotes = ""
                existing.cachedDueAt = remote.dueAt
                existing.cachedCompleted = remote.isCompleted
                existing.lastSeenAt = timestamp
                existing.updatedAt = timestamp
                try existing.update(db)
                item = existing
            } else {
                item = ProviderItemRecord(
                    id: makeID(),
                    accountID: account.id,
                    entityType: "task",
                    remoteID: remote.id,
                    remoteParentID: remote.parentID,
                    remoteVersion: remote.version,
                    cachedTitle: remote.title,
                    cachedNotes: "",
                    cachedDueAt: remote.dueAt,
                    cachedCompleted: remote.isCompleted,
                    lastSeenAt: timestamp,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
                try item.insert(db)
            }

            if let owner = try TaskBindingRecord
                .filter(Column("provider_item_id") == item.id)
                .fetchOne(db), owner.eventTaskID != eventTaskID {
                throw TaskProviderError.providerFailure(
                    "The selected remote task is already linked to a different KaosCal task."
                )
            }

            try db.execute(
                sql: "DELETE FROM task_bindings WHERE event_task_id = ?",
                arguments: [eventTaskID]
            )
            try db.execute(
                sql: "DELETE FROM provider_pending_operations WHERE event_task_id = ?",
                arguments: [eventTaskID]
            )
            try db.execute(
                sql: "DELETE FROM task_provider_preferences WHERE event_task_id = ?",
                arguments: [eventTaskID]
            )

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

    /// Applies a provider snapshot to the local Event Brief task and advances
    /// its cache/binding baseline in one SQLite transaction. A nil due
    /// override preserves the task's existing local due policy.
    @discardableResult
    func applyRemoteProjection(
        bindingID: String,
        itemID: String,
        eventTaskID: String,
        remote: RemoteTaskSnapshot,
        syncHash: String,
        dueOverride: EventTaskDue?
    ) throws -> Bool {
        let timestamp = now()
        return try database.write { db in
            guard let binding = try TaskBindingRecord.fetchOne(
                db,
                key: bindingID
            ), binding.providerItemID == itemID,
            binding.eventTaskID == eventTaskID,
            let task = try eventTasks.fetch(id: eventTaskID, in: db) else {
                throw TaskProviderError.taskNotFound
            }

            let targetDue = dueOverride ?? task.due
            let projectionChanged = binding.syncState != .linked
                || task.title != remote.title
                || task.due != targetDue
                || task.isCompleted != remote.isCompleted

            var updated = task
            if task.title != remote.title || task.due != targetDue {
                updated = try eventTasks.update(
                    task: task,
                    section: task.section,
                    title: remote.title,
                    sortOrder: task.sortOrder,
                    due: targetDue,
                    in: db
                )
            }
            if updated.isCompleted != remote.isCompleted {
                _ = try eventTasks.setCompleted(
                    task: updated,
                    isCompleted: remote.isCompleted,
                    in: db
                )
            }

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
                    TaskProviderSyncState.linked.rawValue,
                    syncHash,
                    remote.version,
                    timestamp,
                    bindingID
                ]
            )
            return projectionChanged
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

    @discardableResult
    func markBinding(
        bindingID: String,
        state: TaskProviderSyncState
    ) throws -> Bool {
        try database.write { db in
            guard var binding = try TaskBindingRecord.fetchOne(
                db,
                key: bindingID
            ) else {
                return false
            }
            guard binding.syncState != state else { return false }
            binding.syncState = state
            binding.updatedAt = now()
            try binding.update(db)
            return true
        }
    }

    func removeBinding(bindingID: String) throws {
        _ = try database.write { db in
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
