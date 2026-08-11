import Foundation
import GRDB

final class TaskPlanningRepository {
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

    func snapshot(
        for id: TaskCenterItemID
    ) throws -> (TaskPlanningMetadata, [TaskChecklistItem]) {
        let identity = Self.identity(for: id)
        return try database.read { db in
            let metadata = try TaskPlanningMetadata.fetchOne(
                db,
                key: ["task_kind": identity.kind.rawValue, "task_id": identity.id]
            ) ?? Self.defaultMetadata(
                kind: identity.kind,
                taskID: identity.id,
                now: now()
            )
            let checklist = try TaskChecklistItem
                .filter(Column("task_kind") == identity.kind.rawValue)
                .filter(Column("parent_task_id") == identity.id)
                .order(Column("sort_order"), Column("created_at"), Column("id"))
                .fetchAll(db)
            return (metadata, checklist)
        }
    }

    func snapshots() throws -> [String: (TaskPlanningMetadata, [TaskChecklistItem])] {
        try database.read { db in
            let metadata = try TaskPlanningMetadata.fetchAll(db)
            let checklist = Dictionary(grouping: try TaskChecklistItem.fetchAll(db)) {
                Self.key(kind: $0.taskKind, id: $0.parentTaskID)
            }
            return Dictionary(uniqueKeysWithValues: metadata.map {
                let key = Self.key(kind: $0.taskKind, id: $0.taskID)
                return (
                    key,
                    (
                        $0,
                        (checklist[key] ?? []).sorted {
                            if $0.sortOrder != $1.sortOrder {
                                return $0.sortOrder < $1.sortOrder
                            }
                            if $0.createdAt != $1.createdAt {
                                return $0.createdAt < $1.createdAt
                            }
                            return $0.id < $1.id
                        }
                    )
                )
            })
        }
    }

    @discardableResult
    func save(
        for id: TaskCenterItemID,
        priority: TaskPriority,
        isImportant: Bool,
        repeatFrequency: TaskRepeatFrequency,
        repeatInterval: Int,
        estimatedMinutes: Int?
    ) throws -> TaskPlanningMetadata {
        guard (1...365).contains(repeatInterval),
              estimatedMinutes.map({ (1...525_600).contains($0) }) ?? true else {
            throw TaskProviderError.unsupported(
                "Repeat interval or estimated duration is outside the supported range."
            )
        }
        let identity = Self.identity(for: id)
        let timestamp = now()
        return try database.write { db in
            var metadata = try TaskPlanningMetadata.fetchOne(
                db,
                key: ["task_kind": identity.kind.rawValue, "task_id": identity.id]
            ) ?? Self.defaultMetadata(
                kind: identity.kind,
                taskID: identity.id,
                now: timestamp
            )
            metadata.priority = priority
            metadata.isImportant = isImportant
            metadata.repeatFrequency = repeatFrequency
            metadata.repeatInterval = repeatFrequency == .none
                ? 1
                : repeatInterval
            metadata.estimatedMinutes = estimatedMinutes
            metadata.updatedAt = timestamp
            try metadata.save(db)
            return metadata
        }
    }

    @discardableResult
    func toggleImportant(for id: TaskCenterItemID) throws -> TaskPlanningMetadata {
        let current = try snapshot(for: id).0
        return try save(
            for: id,
            priority: current.priority,
            isImportant: !current.isImportant,
            repeatFrequency: current.repeatFrequency,
            repeatInterval: current.repeatInterval,
            estimatedMinutes: current.estimatedMinutes
        )
    }

    @discardableResult
    func toggleTimer(for id: TaskCenterItemID) throws -> TaskPlanningMetadata {
        let identity = Self.identity(for: id)
        let timestamp = now()
        return try database.write { db in
            var metadata = try TaskPlanningMetadata.fetchOne(
                db,
                key: ["task_kind": identity.kind.rawValue, "task_id": identity.id]
            ) ?? Self.defaultMetadata(
                kind: identity.kind,
                taskID: identity.id,
                now: timestamp
            )
            if let startedAt = metadata.startedAt {
                metadata.actualSeconds += max(
                    0,
                    Int(timestamp.timeIntervalSince(startedAt).rounded(.down))
                )
                metadata.startedAt = nil
            } else {
                metadata.startedAt = timestamp
            }
            metadata.updatedAt = timestamp
            try metadata.save(db)
            return metadata
        }
    }

    @discardableResult
    func addChecklistItem(
        to id: TaskCenterItemID,
        title: String
    ) throws -> TaskChecklistItem {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 500 else {
            throw TaskProviderError.unsupported("Enter a checklist title up to 500 characters.")
        }
        let identity = Self.identity(for: id)
        let timestamp = now()
        return try database.write { db in
            let nextOrder = (try Int.fetchOne(
                db,
                sql: """
                    SELECT MAX(sort_order) + 1 FROM task_checklist_items
                    WHERE task_kind = ? AND parent_task_id = ?
                    """,
                arguments: [identity.kind.rawValue, identity.id]
            )) ?? 0
            let item = TaskChecklistItem(
                id: makeID(),
                taskKind: identity.kind,
                parentTaskID: identity.id,
                title: normalized,
                isCompleted: false,
                sortOrder: nextOrder,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try item.insert(db)
            return item
        }
    }

    func setChecklistItemCompleted(
        id: String,
        isCompleted: Bool
    ) throws {
        try database.write { db in
            guard var item = try TaskChecklistItem.fetchOne(db, key: id) else {
                throw TaskProviderError.taskNotFound
            }
            item.isCompleted = isCompleted
            item.updatedAt = now()
            try item.update(db)
        }
    }

    func deleteChecklistItem(id: String) throws {
        _ = try database.write { db in
            try TaskChecklistItem.deleteOne(db, key: id)
        }
    }

    func deletePlanning(for id: TaskCenterItemID) throws {
        let identity = Self.identity(for: id)
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM task_checklist_items WHERE task_kind = ? AND parent_task_id = ?",
                arguments: [identity.kind.rawValue, identity.id]
            )
            try db.execute(
                sql: "DELETE FROM task_planning_metadata WHERE task_kind = ? AND task_id = ?",
                arguments: [identity.kind.rawValue, identity.id]
            )
        }
    }

    func copyPlanning(
        from source: TaskCenterItemID,
        to destination: TaskCenterItemID
    ) throws {
        let sourceSnapshot = try snapshot(for: source)
        let target = Self.identity(for: destination)
        let timestamp = now()
        try database.write { db in
            var metadata = sourceSnapshot.0
            metadata = TaskPlanningMetadata(
                taskKind: target.kind,
                taskID: target.id,
                priority: metadata.priority,
                isImportant: metadata.isImportant,
                repeatFrequency: metadata.repeatFrequency,
                repeatInterval: metadata.repeatInterval,
                estimatedMinutes: metadata.estimatedMinutes,
                actualSeconds: 0,
                startedAt: nil,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try metadata.save(db)
            for sourceItem in sourceSnapshot.1 {
                let item = TaskChecklistItem(
                    id: makeID(),
                    taskKind: target.kind,
                    parentTaskID: target.id,
                    title: sourceItem.title,
                    isCompleted: false,
                    sortOrder: sourceItem.sortOrder,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
                try item.insert(db)
            }
        }
    }

    static func key(for id: TaskCenterItemID) -> String {
        let identity = identity(for: id)
        return key(kind: identity.kind, id: identity.id)
    }

    private static func key(kind: LocalTaskKind, id: String) -> String {
        "\(kind.rawValue)\u{1F}\(id)"
    }

    private static func identity(
        for id: TaskCenterItemID
    ) -> (kind: LocalTaskKind, id: String) {
        switch id {
        case let .eventTask(taskID, _): (.event, taskID)
        case let .personalTask(taskID): (.personal, taskID)
        }
    }

    static func defaultMetadata(
        for id: TaskCenterItemID,
        now: Date
    ) -> TaskPlanningMetadata {
        let identity = identity(for: id)
        return defaultMetadata(kind: identity.kind, taskID: identity.id, now: now)
    }

    private static func defaultMetadata(
        kind: LocalTaskKind,
        taskID: String,
        now: Date
    ) -> TaskPlanningMetadata {
        TaskPlanningMetadata(
            taskKind: kind,
            taskID: taskID,
            priority: .none,
            isImportant: false,
            repeatFrequency: .none,
            repeatInterval: 1,
            estimatedMinutes: nil,
            actualSeconds: 0,
            startedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
