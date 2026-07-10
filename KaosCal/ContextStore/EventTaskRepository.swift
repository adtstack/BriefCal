import Foundation
import GRDB

enum ContextStoreError: Error, Equatable {
    case emptyTitle
    case invalidRelativeDue
    case identityConfirmationRequired([String])
    case missingContext(String)
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
            try EventTask.fetchOne(db, key: id)
        }
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
        try validate(title: title, due: due)
        return try database.write { db in
            guard var task = try EventTask.fetchOne(db, key: id) else {
                return nil
            }
            apply(due: due, to: &task)
            task.section = section
            task.title = title
            task.sortOrder = sortOrder
            task.updatedAt = now()
            try task.update(db)
            return task
        }
    }

    @discardableResult
    func setCompleted(
        id: String,
        isCompleted: Bool
    ) throws -> EventTask? {
        try database.write { db in
            guard var task = try EventTask.fetchOne(db, key: id) else {
                return nil
            }
            let timestamp = now()
            task.isCompleted = isCompleted
            task.completedAt = isCompleted ? timestamp : nil
            task.updatedAt = timestamp
            try task.update(db)
            return task
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
