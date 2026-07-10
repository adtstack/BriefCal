import Foundation
import GRDB

enum EventMutationContext: Equatable {
    case none
    case linked(contextID: String)
    case confirmationRequired(contextIDs: [String])
}

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

    func loadBrief(for event: DisplayEvent) throws -> EventBriefLoadResult {
        try database.write { db in
            switch try eventContexts.resolve(event: event, in: db) {
            case let .linked(contextID, basis):
                guard try eventContexts.updateSnapshot(
                    contextID: contextID,
                    event: event,
                    notes: nil,
                    in: db
                ) != nil,
                let snapshot = try eventContexts.fetchBrief(
                    contextID: contextID,
                    in: db
                ) else {
                    throw ContextStoreError.missingContext(contextID)
                }
                return .loaded(snapshot: snapshot, basis: basis)
            case .notFound:
                return .empty
            case let .candidate(contextIDs, basis),
                 let .ambiguous(contextIDs, basis):
                return .confirmationRequired(
                    contextIDs: contextIDs,
                    basis: basis
                )
            }
        }
    }

    func navigationTarget(
        contextID: String
    ) throws -> EventNavigationTarget? {
        try database.read { db in
            guard let link = try eventContexts.fetchLink(
                contextID: contextID,
                in: db
            ) else {
                return nil
            }
            return EventNavigationTarget(
                contextID: contextID,
                link: link
            )
        }
    }

    func mutationContext(
        for event: DisplayEvent
    ) throws -> EventMutationContext {
        try database.read { db in
            switch try eventContexts.resolve(event: event, in: db) {
            case let .linked(contextID, _):
                return .linked(contextID: contextID)
            case .notFound:
                return .none
            case let .candidate(contextIDs, _),
                 let .ambiguous(contextIDs, _):
                return .confirmationRequired(contextIDs: contextIDs)
            }
        }
    }

    @discardableResult
    func rebindUserApprovedMutation(
        contextID: String,
        to event: DisplayEvent
    ) throws -> EventBriefSnapshot {
        try database.write { db in
            guard try eventContexts.updateSnapshot(
                contextID: contextID,
                event: event,
                notes: nil,
                in: db
            ) != nil,
            let snapshot = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            return snapshot
        }
    }

    func matchLinkedEvent(
        contextID: String,
        among events: [DisplayEvent]
    ) throws -> EventNavigationResolution {
        try database.read { db in
            guard let link = try eventContexts.fetchLink(
                contextID: contextID,
                in: db
            ) else {
                return .notFound
            }
            return try eventContexts.matchLinkedEvent(
                link: link,
                among: events
            )
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
        try persistEventTask(
            for: event,
            section: section,
            title: title,
            requestedSortOrder: sortOrder,
            due: due
        )
    }

    func appendEventTask(
        for event: DisplayEvent,
        section: EventTaskSection,
        title: String,
        due: EventTaskDue = .none
    ) throws -> EventTask {
        try persistEventTask(
            for: event,
            section: section,
            title: title,
            requestedSortOrder: nil,
            due: due
        )
    }

    func updateEventTask(
        contextID: String,
        taskID: String,
        section: EventTaskSection,
        title: String,
        sortOrder: Int,
        due: EventTaskDue
    ) throws -> EventTask {
        try database.write { db in
            let task = try checkedEventTask(
                contextID: contextID,
                taskID: taskID,
                in: db
            )
            return try eventTasks.update(
                task: task,
                section: section,
                title: title,
                sortOrder: sortOrder,
                due: due,
                in: db
            )
        }
    }

    func setEventTaskCompleted(
        contextID: String,
        taskID: String,
        isCompleted: Bool
    ) throws -> EventTask {
        try database.write { db in
            let task = try checkedEventTask(
                contextID: contextID,
                taskID: taskID,
                in: db
            )
            return try eventTasks.setCompleted(
                task: task,
                isCompleted: isCompleted,
                in: db
            )
        }
    }

    func deleteEventTask(
        contextID: String,
        taskID: String
    ) throws {
        try database.write { db in
            let task = try checkedEventTask(
                contextID: contextID,
                taskID: taskID,
                in: db
            )
            guard try eventTasks.delete(task: task, in: db) else {
                throw ContextStoreError.missingEventTask(taskID)
            }
        }
    }

    func setPersonalTaskCompleted(
        taskID: String,
        isCompleted: Bool
    ) throws -> PersonalTask {
        try database.write { db in
            guard let task = try personalTasks.fetch(id: taskID, in: db) else {
                throw ContextStoreError.missingPersonalTask(taskID)
            }
            return try personalTasks.setCompleted(
                task: task,
                isCompleted: isCompleted,
                in: db
            )
        }
    }

    func setTaskCenterItemCompleted(
        id: TaskCenterItemID,
        isCompleted: Bool
    ) throws -> TaskCenterCompletionResult {
        switch id {
        case let .eventTask(taskID, contextID):
            return .eventTask(
                try setEventTaskCompleted(
                    contextID: contextID,
                    taskID: taskID,
                    isCompleted: isCompleted
                )
            )
        case let .personalTask(taskID):
            return .personalTask(
                try setPersonalTaskCompleted(
                    taskID: taskID,
                    isCompleted: isCompleted
                )
            )
        }
    }

    private func persistEventTask(
        for event: DisplayEvent,
        section: EventTaskSection,
        title: String,
        requestedSortOrder: Int?,
        due: EventTaskDue
    ) throws -> EventTask {
        try database.write { db in
            switch try eventContexts.resolve(event: event, in: db) {
            case let .linked(contextID, _):
                let sortOrder: Int
                if let requestedSortOrder {
                    sortOrder = requestedSortOrder
                } else {
                    sortOrder = try eventTasks.nextSortOrder(
                        contextID: contextID,
                        section: section,
                        in: db
                    )
                }
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
                let sortOrder = requestedSortOrder ?? 0
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

    private func checkedEventTask(
        contextID: String,
        taskID: String,
        in db: Database
    ) throws -> EventTask {
        guard let task = try eventTasks.fetch(id: taskID, in: db) else {
            throw ContextStoreError.missingEventTask(taskID)
        }
        guard task.contextID == contextID else {
            throw ContextStoreError.eventTaskContextMismatch(
                taskID: taskID,
                expectedContextID: contextID
            )
        }
        return task
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
