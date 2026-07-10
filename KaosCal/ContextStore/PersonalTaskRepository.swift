import Foundation
import GRDB

final class PersonalTaskRepository {
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
        title: String,
        notes: String = "",
        dueAt: Date? = nil,
        sortOrder: Int = 0
    ) throws -> PersonalTask {
        try validate(title: title)
        let timestamp = now()
        let task = PersonalTask(
            id: makeID(),
            title: title,
            notes: notes,
            dueAt: dueAt,
            isCompleted: false,
            sortOrder: sortOrder,
            createdAt: timestamp,
            updatedAt: timestamp,
            completedAt: nil
        )
        try database.write { db in
            try task.insert(db)
        }
        return task
    }

    func fetch(id: String) throws -> PersonalTask? {
        try database.read { db in
            try fetch(id: id, in: db)
        }
    }

    func fetch(id: String, in db: Database) throws -> PersonalTask? {
        try PersonalTask.fetchOne(db, key: id)
    }

    func fetch(
        list: PersonalTaskList,
        now currentDate: Date,
        calendar: Calendar
    ) throws -> [PersonalTask] {
        let tasks = try database.read { db in
            try PersonalTask.fetchAll(db)
        }
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: currentDate)
        ) ?? currentDate

        switch list {
        case .today:
            return tasks.filter {
                !$0.isCompleted && ($0.dueAt.map { $0 < tomorrow } ?? true)
            }.sorted(by: Self.openTaskOrder)
        case .upcoming:
            return tasks.filter {
                !$0.isCompleted && ($0.dueAt.map { $0 >= tomorrow } ?? false)
            }.sorted(by: Self.openTaskOrder)
        case .completed:
            return tasks.filter(\.isCompleted).sorted(by: Self.completedTaskOrder)
        }
    }

    @discardableResult
    func update(
        id: String,
        title: String,
        notes: String,
        dueAt: Date?,
        sortOrder: Int
    ) throws -> PersonalTask? {
        try validate(title: title)
        return try database.write { db in
            guard var task = try PersonalTask.fetchOne(db, key: id) else {
                return nil
            }
            task.title = title
            task.notes = notes
            task.dueAt = dueAt
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
    ) throws -> PersonalTask? {
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
            _ = try PersonalTask.deleteOne(db, key: id)
        }
    }

    func count() throws -> Int {
        try database.read { db in
            try PersonalTask.fetchCount(db)
        }
    }

    func setCompleted(
        task existingTask: PersonalTask,
        isCompleted: Bool,
        in db: Database
    ) throws -> PersonalTask {
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

    private func validate(title: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContextStoreError.emptyTitle
        }
    }

    private static func openTaskOrder(
        _ lhs: PersonalTask,
        _ rhs: PersonalTask
    ) -> Bool {
        if lhs.dueAt != rhs.dueAt {
            return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }

    private static func completedTaskOrder(
        _ lhs: PersonalTask,
        _ rhs: PersonalTask
    ) -> Bool {
        if lhs.completedAt != rhs.completedAt {
            return (lhs.completedAt ?? .distantPast)
                > (rhs.completedAt ?? .distantPast)
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
    }
}
