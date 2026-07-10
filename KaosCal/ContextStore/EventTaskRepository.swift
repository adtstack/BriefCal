import Foundation
import GRDB

enum ContextStoreError: Error, Equatable {
    case emptyTitle
    case invalidRelativeDue
    case identityConfirmationRequired([String])
    case missingContext(String)
    case missingEventTask(String)
    case eventTaskContextMismatch(
        taskID: String,
        expectedContextID: String
    )
    case missingPersonalTask(String)
}

extension ContextStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Task title cannot be empty."
        case .invalidRelativeDue:
            "The relative due date is invalid."
        case .identityConfirmationRequired:
            "Confirm the matching calendar event before changing local data."
        case let .missingContext(contextID):
            "The local event context is missing: \(contextID)."
        case let .missingEventTask(taskID):
            "The event task is missing: \(taskID)."
        case let .eventTaskContextMismatch(taskID, expectedContextID):
            "Event task \(taskID) does not belong to context \(expectedContextID)."
        case let .missingPersonalTask(taskID):
            "The personal task is missing: \(taskID)."
        }
    }
}

final class EventTaskRepository {
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

    func create(
        contextID: String,
        section: EventTaskSection,
        title: String,
        sortOrder: Int,
        due: EventTaskDue = .none
    ) throws -> EventTask {
        let task = try makeTask(
            contextID: contextID,
            section: section,
            title: title,
            sortOrder: sortOrder,
            due: due
        )
        try database.write { db in
            try task.insert(db)
        }
        return task
    }

    func fetch(id: String) throws -> EventTask? {
        try database.read { db in
            try fetch(id: id, in: db)
        }
    }

    func fetch(id: String, in db: Database) throws -> EventTask? {
        try EventTask.fetchOne(db, key: id)
    }

    func fetch(
        contextID: String,
        section: EventTaskSection? = nil
    ) throws -> [EventTask] {
        try database.read { db in
            var tasks = try EventTask
                .filter(EventTask.Columns.contextID == contextID)
                .fetchAll(db)
            if let section {
                tasks = tasks.filter { $0.section == section }
            }
            return tasks.sorted(by: Self.taskOrder)
        }
    }

    @discardableResult
    func update(
        id: String,
        section: EventTaskSection,
        title: String,
        sortOrder: Int,
        due: EventTaskDue
    ) throws -> EventTask? {
        return try database.write { db in
            guard let task = try fetch(id: id, in: db) else {
                return nil
            }
            return try update(
                task: task,
                section: section,
                title: title,
                sortOrder: sortOrder,
                due: due,
                in: db
            )
        }
    }

    @discardableResult
    func setCompleted(
        id: String,
        isCompleted: Bool
    ) throws -> EventTask? {
        try database.write { db in
            guard let task = try fetch(id: id, in: db) else {
                return nil
            }
            return try setCompleted(
                task: task,
                isCompleted: isCompleted,
                in: db
            )
        }
    }

    func delete(id: String) throws {
        try database.write { db in
            _ = try EventTask.deleteOne(db, key: id)
        }
    }

    func count() throws -> Int {
        try database.read { db in
            try EventTask.fetchCount(db)
        }
    }

    func makeTask(
        contextID: String,
        section: EventTaskSection,
        title: String,
        sortOrder: Int,
        due: EventTaskDue
    ) throws -> EventTask {
        try validate(title: title, due: due)
        let timestamp = now()
        var task = EventTask(
            id: makeID(),
            contextID: contextID,
            section: section,
            title: title,
            isCompleted: false,
            sortOrder: sortOrder,
            dueKind: .none,
            relativeAnchor: nil,
            offsetMinutes: nil,
            fixedDueAt: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            completedAt: nil
        )
        apply(due: due, to: &task)
        return task
    }

    func insert(task: EventTask, in db: Database) throws {
        try task.insert(db)
    }

    func update(
        task existingTask: EventTask,
        section: EventTaskSection,
        title: String,
        sortOrder: Int,
        due: EventTaskDue,
        in db: Database
    ) throws -> EventTask {
        try validate(title: title, due: due)
        var task = existingTask
        apply(due: due, to: &task)
        task.section = section
        task.title = title
        task.sortOrder = sortOrder
        task.updatedAt = now()
        try task.update(db)
        return task
    }

    func setCompleted(
        task existingTask: EventTask,
        isCompleted: Bool,
        in db: Database
    ) throws -> EventTask {
        guard existingTask.isCompleted != isCompleted else {
            return existingTask
        }
        var task = existingTask
        let timestamp = now()
        task.isCompleted = isCompleted
        task.completedAt = isCompleted ? timestamp : nil
        task.updatedAt = timestamp
        try task.update(db)
        return task
    }

    @discardableResult
    func delete(task: EventTask, in db: Database) throws -> Bool {
        try EventTask.deleteOne(db, key: task.id)
    }

    func nextSortOrder(
        contextID: String,
        section: EventTaskSection,
        in db: Database
    ) throws -> Int {
        let maximum = try Int.fetchOne(
            db,
            sql: """
                SELECT MAX(sort_order)
                FROM event_tasks
                WHERE context_id = ? AND section = ?
                """,
            arguments: [contextID, section.rawValue]
        )
        return (maximum ?? -1) + 1
    }

    private func validate(
        title: String,
        due: EventTaskDue
    ) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContextStoreError.emptyTitle
        }
        guard case let .relative(anchor, offsetMinutes) = due else { return }
        guard offsetMinutes >= 0,
              offsetMinutes <= EventTaskDuePolicy.maximumOffsetMinutes else {
            throw ContextStoreError.invalidRelativeDue
        }
        if (anchor == .atStart || anchor == .atEnd), offsetMinutes != 0 {
            throw ContextStoreError.invalidRelativeDue
        }
    }

    private func apply(due: EventTaskDue, to task: inout EventTask) {
        switch due {
        case .none:
            task.dueKind = .none
            task.relativeAnchor = nil
            task.offsetMinutes = nil
            task.fixedDueAt = nil
        case let .relative(anchor, offsetMinutes):
            task.dueKind = .relative
            task.relativeAnchor = anchor
            task.offsetMinutes = offsetMinutes
            task.fixedDueAt = nil
        case let .fixed(date):
            task.dueKind = .fixed
            task.relativeAnchor = nil
            task.offsetMinutes = nil
            task.fixedDueAt = date
        }
    }

    private static func taskOrder(_ lhs: EventTask, _ rhs: EventTask) -> Bool {
        if lhs.section.sortRank != rhs.section.sortRank {
            return lhs.section.sortRank < rhs.section.sortRank
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}
