import Foundation
import GRDB

final class ContextStore {
    let eventContexts: EventContextRepository
    let eventTasks: EventTaskRepository
    let personalTasks: PersonalTaskRepository
    let taskCenter: TaskCenterRepository

    private let database: AppDatabase

    init(
        database: AppDatabase,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.database = database
        eventContexts = EventContextRepository(
            database: database,
            now: now,
            makeID: makeID
        )
        eventTasks = EventTaskRepository(
            database: database,
            now: now,
            makeID: makeID
        )
        personalTasks = PersonalTaskRepository(
            database: database,
            now: now,
            makeID: makeID
        )
        taskCenter = TaskCenterRepository(database: database)
    }

    func resolve(event: DisplayEvent) throws -> EventContextResolution {
        try database.write { db in
            try resolveAndRefresh(event: event, in: db)
        }
    }

    func observe(events: [DisplayEvent]) throws -> [EventContextResolution] {
        try database.write { db in
            try events.map { event in
                try resolveAndRefresh(event: event, in: db)
            }
        }
    }

    @discardableResult
    func saveNotes(
        for event: DisplayEvent,
        notes: String
    ) throws -> EventContext? {
        try database.write { db in
            switch try eventContexts.resolve(event: event, in: db) {
            case let .linked(contextID, _):
                return try eventContexts.updateSnapshot(
                    contextID: contextID,
                    event: event,
                    notes: notes,
                    in: db
                )
            case .notFound:
                guard !notes.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty else {
                    return nil
                }
                let records = try eventContexts.makeRecords(
                    for: event,
                    notes: notes
                )
                try eventContexts.insert(
                    context: records.context,
                    link: records.link,
                    in: db
                )
                return records.context
            case let .candidate(contextIDs, _),
                 let .ambiguous(contextIDs, _):
                throw ContextStoreError.identityConfirmationRequired(
                    contextIDs
                )
            }
        }
    }

    func addEventTask(
        for event: DisplayEvent,
        section: EventTaskSection,
        title: String,
        sortOrder: Int,
        due: EventTaskDue = .none
    ) throws -> EventTask {
        try database.write { db in
            switch try eventContexts.resolve(event: event, in: db) {
            case let .linked(contextID, _):
                let task = try eventTasks.makeTask(
                    contextID: contextID,
                    section: section,
                    title: title,
                    sortOrder: sortOrder,
                    due: due
                )
                guard try eventContexts.updateSnapshot(
                    contextID: contextID,
                    event: event,
                    notes: nil,
                    in: db
                ) != nil else {
                    throw ContextStoreError.missingContext(contextID)
                }
                try eventTasks.insert(task: task, in: db)
                return task
            case .notFound:
                let records = try eventContexts.makeRecords(
                    for: event,
                    notes: ""
                )
                let task = try eventTasks.makeTask(
                    contextID: records.context.id,
                    section: section,
                    title: title,
                    sortOrder: sortOrder,
                    due: due
                )
                try eventContexts.insert(
                    context: records.context,
                    link: records.link,
                    in: db
                )
                try eventTasks.insert(task: task, in: db)
                return task
            case let .candidate(contextIDs, _),
                 let .ambiguous(contextIDs, _):
                throw ContextStoreError.identityConfirmationRequired(
                    contextIDs
                )
            }
        }
    }

    private func resolveAndRefresh(
        event: DisplayEvent,
        in db: Database
    ) throws -> EventContextResolution {
        let resolution = try eventContexts.resolve(event: event, in: db)
        if case let .linked(contextID, _) = resolution {
            guard try eventContexts.updateSnapshot(
                contextID: contextID,
                event: event,
                notes: nil,
                in: db
            ) != nil else {
                throw ContextStoreError.missingContext(contextID)
            }
        }
        return resolution
    }
}
