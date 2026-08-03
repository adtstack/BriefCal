import Foundation
import GRDB

enum EventMutationContext: Equatable {
    case none
    case linked(contextID: String)
    case confirmationRequired(contextIDs: [String])
}

struct LinkedEventLookupTarget: Equatable {
    let brief: EventBriefSnapshot
    let query: CalendarEventLookupQuery
}

struct LinkedOriginalDeletionPreparation: Equatable {
    let brief: EventBriefSnapshot
    let impact: EventMutationImpact
    let changeSnapshot: EventChangeSnapshot
}

enum EventChangeLogError: Error, Equatable {
    case missingChange(String)
    case changeContextMismatch(
        changeID: String,
        expectedContextID: String
    )
    case invalidInitialUndoState(EventChangeUndoState)
    case undoUnavailable(String)
    case unsupportedUndo(String)
    case undoSourceMismatch(String)
}

extension EventChangeLogError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingChange(changeID):
            "The local event change is missing: \(changeID)."
        case let .changeContextMismatch(changeID, expectedContextID):
            "Change \(changeID) does not belong to context \(expectedContextID)."
        case .invalidInitialUndoState:
            "A new event change must start as available or unavailable for undo."
        case let .undoUnavailable(changeID):
            "Change \(changeID) is no longer available for undo."
        case let .unsupportedUndo(changeID):
            "Change \(changeID) cannot be safely undone by KaosCal."
        case let .undoSourceMismatch(changeID):
            "The event changed after \(changeID), so KaosCal did not apply its undo."
        }
    }
}

final class ContextStore {
    let eventContexts: EventContextRepository
    let eventTasks: EventTaskRepository
    let personalTasks: PersonalTaskRepository
    let taskCenter: TaskCenterRepository
    let taskPlanning: TaskPlanningRepository
    let taskProviders: TaskProviderRepository
    let calendarRoles: CalendarRoleRepository
    let calendarUsage: CalendarUsagePreferenceRepository
    let calendarSets: CalendarSetRepository
    let references: ContextReferenceRepository
    let localDataBackups: LocalDataBackupService

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
        taskPlanning = TaskPlanningRepository(
            database: database,
            now: now,
            makeID: makeID
        )
        taskProviders = TaskProviderRepository(
            database: database,
            now: now,
            makeID: makeID
        )
        calendarRoles = CalendarRoleRepository(
            database: database,
            now: now
        )
        calendarUsage = CalendarUsagePreferenceRepository(
            database: database,
            now: now
        )
        calendarSets = CalendarSetRepository(
            database: database,
            now: now,
            makeID: makeID
        )
        references = ContextReferenceRepository(
            database: database,
            now: now,
            makeID: makeID
        )
        localDataBackups = LocalDataBackupService(
            database: database,
            databaseURL: database.databaseURL
        )
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
    func refreshTemporalLifecycle(
        at date: Date,
        calendar: Calendar
    ) throws -> [String] {
        try database.write { db in
            try eventContexts.reconcileTemporalLifecycle(
                at: date,
                calendar: calendar,
                in: db
            )
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

    func linkedEventLookupTarget(
        contextID: String
    ) throws -> LinkedEventLookupTarget {
        try database.read { db in
            guard let brief = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            return LinkedEventLookupTarget(
                brief: brief,
                query: try brief.link.calendarEventLookupQuery()
            )
        }
    }

    func fetchRecoveryBriefs() throws -> [EventBriefSnapshot] {
        try eventContexts.fetchAllBriefs()
    }

    @discardableResult
    func markLinkedEventMissing(
        contextID: String
    ) throws -> EventBriefSnapshot {
        try database.write { db in
            try eventContexts.markMissing(contextID: contextID, in: db)
        }
    }

    @discardableResult
    func refreshStrongLookup(
        contextID: String,
        event: DisplayEvent,
        at date: Date,
        calendar: Calendar
    ) throws -> EventBriefSnapshot {
        try database.write { db in
            guard let link = try eventContexts.fetchLink(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            guard link.linkStatus == .active || link.linkStatus == .missing else {
                throw ContextStoreError.invalidEventLinkTransition
            }
            guard try eventContexts.updateSnapshot(
                contextID: contextID,
                event: event,
                notes: nil,
                in: db
            ) != nil else {
                throw ContextStoreError.missingContext(contextID)
            }
            if var context = try EventContext.fetchOne(db, key: contextID),
               context.lifecycleStatus == .cancelled {
                context.lifecycleStatus = .scheduled
                context.updatedAt = date
                try context.update(db)
            }
            _ = try eventContexts.reconcileTemporalLifecycle(
                at: date,
                calendar: calendar,
                in: db
            )
            guard let brief = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            return brief
        }
    }

    @discardableResult
    func markCalendarEventCancelled(
        contextID: String,
        event: DisplayEvent,
        at date: Date
    ) throws -> EventBriefSnapshot {
        try database.write { db in
            guard let link = try eventContexts.fetchLink(
                contextID: contextID,
                in: db
            ), link.linkStatus == .active || link.linkStatus == .missing else {
                throw ContextStoreError.invalidEventLinkTransition
            }
            guard try eventContexts.updateSnapshot(
                contextID: contextID,
                event: event,
                notes: nil,
                in: db
            ) != nil,
            var context = try EventContext.fetchOne(db, key: contextID) else {
                throw ContextStoreError.missingContext(contextID)
            }
            context.lifecycleStatus = .cancelled
            context.updatedAt = date
            try context.update(db)
            guard let brief = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            return brief
        }
    }

    @discardableResult
    func keepLocalBriefAsOrphan(
        contextID: String
    ) throws -> EventBriefSnapshot {
        try database.write { db in
            try eventContexts.keepAsOrphan(contextID: contextID, in: db)
        }
    }

    @discardableResult
    func relinkLocalBrief(
        contextID: String,
        to event: DisplayEvent,
        expectedLink: EventLink,
        calendarStatusIsCancelled: Bool = false,
        at date: Date,
        calendar: Calendar
    ) throws -> EventBriefSnapshot {
        try database.write { db in
            guard EventIdentityFingerprint.firstNonEmpty(
                event.eventIdentifier,
                event.calendarItemIdentifier,
                event.calendarItemExternalIdentifier
            ) != nil else {
                throw CalendarEventLookupError.missingStrongIdentifier
            }
            guard let current = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            guard current.link == expectedLink else {
                throw ContextStoreError.invalidEventLinkTransition
            }
            switch try eventContexts.resolve(event: event, in: db) {
            case let .linked(existingContextID, _):
                guard existingContextID == contextID else {
                    throw ContextStoreError.eventAlreadyLinked(existingContextID)
                }
            case let .candidate(contextIDs, _),
                 let .ambiguous(contextIDs, _):
                let otherContextIDs = contextIDs.filter { $0 != contextID }
                guard otherContextIDs.isEmpty else {
                    throw ContextStoreError.identityConfirmationRequired(
                        otherContextIDs
                    )
                }
            case .notFound:
                break
            }

            let before = try EventChangeSnapshot(link: current.link)
            _ = try eventContexts.relink(
                contextID: contextID,
                to: event,
                at: date,
                calendar: calendar,
                in: db
            )
            if calendarStatusIsCancelled,
               var context = try EventContext.fetchOne(db, key: contextID) {
                context.lifecycleStatus = .cancelled
                context.updatedAt = date
                try context.update(db)
            }
            let after = try EventChangeSnapshot(event: event)
            try db.execute(
                sql: """
                    UPDATE event_change_log
                    SET undo_state = 'superseded'
                    WHERE context_id = ? AND undo_state = 'available'
                    """,
                arguments: [contextID]
            )
            let record = try makeChangeRecord(
                contextID: contextID,
                changeType: .relinked,
                scope: event.isRecurring ? .thisEvent : .single,
                before: before,
                after: after,
                undoState: .unavailable,
                undoneAt: nil,
                undoOfChangeID: nil,
                createdAt: date
            )
            try record.insert(db)
            guard let relinked = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            return relinked
        }
    }

    func deleteLocalBrief(contextID: String) throws {
        try database.write { db in
            guard let link = try eventContexts.fetchLink(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            guard link.linkStatus == .missing || link.linkStatus == .orphaned else {
                throw ContextStoreError.invalidEventLinkTransition
            }
            try eventContexts.delete(contextID: contextID, in: db)
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

    func mutationImpact(
        contextID: String,
        recentHistoryLimit: Int = 5
    ) throws -> EventMutationImpact {
        try database.read { db in
            guard let brief = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            let trimmedNotes = brief.context.notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let taskSections = EventTaskSection.allCases.map { section in
                let tasks = brief.tasks.filter { $0.section == section }
                return EventMutationTaskSummary(
                    section: section,
                    count: tasks.count,
                    titles: tasks.map(\.title)
                )
            }
            let eventTaskIDs = Set(brief.tasks.map(\.id))
            let providerLinkedTaskCount = try TaskBindingRecord.fetchAll(db)
                .reduce(into: 0) { count, binding in
                    if binding.eventTaskID.map(eventTaskIDs.contains) == true {
                        count += 1
                    }
                }
            return EventMutationImpact(
                contextID: contextID,
                hasNotes: !trimmedNotes.isEmpty,
                notesCharacterCount: trimmedNotes.count,
                taskCount: brief.tasks.count,
                providerLinkedTaskCount: providerLinkedTaskCount,
                taskSections: taskSections,
                recentHistory: try Self.fetchChangeHistory(
                    contextID: contextID,
                    limit: recentHistoryLimit,
                    in: db
                )
            )
        }
    }

    func prepareLinkedOriginalDeletion(
        contextID: String,
        recentHistoryLimit: Int = 5
    ) throws -> LinkedOriginalDeletionPreparation {
        try database.read { db in
            guard let brief = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            guard brief.link.linkStatus == .active else {
                throw ContextStoreError.invalidEventLinkTransition
            }
            let trimmedNotes = brief.context.notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let taskSections = EventTaskSection.allCases.map { section in
                let tasks = brief.tasks.filter { $0.section == section }
                return EventMutationTaskSummary(
                    section: section,
                    count: tasks.count,
                    titles: tasks.map(\.title)
                )
            }
            let eventTaskIDs = Set(brief.tasks.map(\.id))
            let providerLinkedTaskCount = try TaskBindingRecord.fetchAll(db)
                .reduce(into: 0) { count, binding in
                    if binding.eventTaskID.map(eventTaskIDs.contains) == true {
                        count += 1
                    }
                }
            let impact = EventMutationImpact(
                contextID: contextID,
                hasNotes: !trimmedNotes.isEmpty,
                notesCharacterCount: trimmedNotes.count,
                taskCount: brief.tasks.count,
                providerLinkedTaskCount: providerLinkedTaskCount,
                taskSections: taskSections,
                recentHistory: try Self.fetchChangeHistory(
                    contextID: contextID,
                    limit: recentHistoryLimit,
                    in: db
                )
            )
            return LinkedOriginalDeletionPreparation(
                brief: brief,
                impact: impact,
                changeSnapshot: try EventChangeSnapshot(link: brief.link)
            )
        }
    }

    @discardableResult
    func validateLinkedOriginalDeletion(
        contextID: String,
        expectedLink: EventLink,
        expectedSnapshot: EventChangeSnapshot
    ) throws -> EventBriefSnapshot {
        try database.read { db in
            guard let brief = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            guard brief.link.linkStatus == .active,
                  brief.link == expectedLink,
                  try EventChangeSnapshot(link: brief.link)
                    == expectedSnapshot else {
                throw ContextStoreError.invalidEventLinkTransition
            }
            return brief
        }
    }

    @discardableResult
    func finalizeLinkedOriginalDeletion(
        contextID: String,
        expectedLink: EventLink,
        expectedSnapshot: EventChangeSnapshot,
        scope: EventChangeScope
    ) throws -> EventBriefSnapshot {
        try database.write { db in
            guard let current = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            let requiredScope: EventChangeScope = current.link.isRecurring
                ? .thisEvent
                : .single
            guard current.link.linkStatus == .active,
                  current.link == expectedLink,
                  scope == requiredScope,
                  try EventChangeSnapshot(link: current.link)
                    == expectedSnapshot else {
                throw ContextStoreError.invalidEventLinkTransition
            }

            let timestamp = now()
            var context = current.context
            context.lifecycleStatus = .cancelled
            context.updatedAt = timestamp
            try context.update(db)

            var link = current.link
            link.linkStatus = .orphaned
            link.updatedAt = timestamp
            try link.update(db)

            try db.execute(
                sql: """
                    UPDATE event_change_log
                    SET undo_state = 'superseded'
                    WHERE context_id = ? AND undo_state = 'available'
                    """,
                arguments: [contextID]
            )
            let record = try makeChangeRecord(
                contextID: contextID,
                changeType: .cancelled,
                scope: scope,
                before: expectedSnapshot,
                after: expectedSnapshot,
                undoState: .unavailable,
                undoneAt: nil,
                undoOfChangeID: nil,
                createdAt: timestamp
            )
            try record.insert(db)

            guard let result = try eventContexts.fetchBrief(
                contextID: contextID,
                in: db
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            return result
        }
    }

    func changeHistory(
        contextID: String,
        limit: Int = 20
    ) throws -> [EventChangeLog] {
        try database.read { db in
            try Self.fetchChangeHistory(
                contextID: contextID,
                limit: limit,
                in: db
            )
        }
    }

    @discardableResult
    func rebindAndRecordMutation(
        contextID: String,
        from beforeEvent: DisplayEvent,
        to afterEvent: DisplayEvent,
        changeType: EventChangeType,
        scope: EventChangeScope,
        undoState: EventChangeUndoState
    ) throws -> EventChangeLog {
        guard undoState == .available || undoState == .unavailable else {
            throw EventChangeLogError.invalidInitialUndoState(undoState)
        }
        let before = try EventChangeSnapshot(event: beforeEvent)
        let after = try EventChangeSnapshot(event: afterEvent)
        if undoState == .available,
           (scope != .single
               || !before.supportsSingleEventUndo
               || !after.supportsSingleEventUndo) {
            throw EventChangeLogError.unsupportedUndo(contextID)
        }

        return try database.write { db in
            guard try eventContexts.updateSnapshot(
                contextID: contextID,
                event: afterEvent,
                notes: nil,
                in: db
            ) != nil else {
                throw ContextStoreError.missingContext(contextID)
            }
            try db.execute(
                sql: """
                    UPDATE event_change_log
                    SET undo_state = 'superseded'
                    WHERE context_id = ? AND undo_state = 'available'
                    """,
                arguments: [contextID]
            )
            let record = try makeChangeRecord(
                contextID: contextID,
                changeType: changeType,
                scope: scope,
                before: before,
                after: after,
                undoState: undoState,
                undoneAt: nil,
                undoOfChangeID: nil,
                createdAt: now()
            )
            try record.insert(db)
            return try Self.makeChangeLog(record)
        }
    }

    @discardableResult
    func rebindAfterUndo(
        contextID: String,
        originalChangeID: String,
        from currentEvent: DisplayEvent,
        to restoredEvent: DisplayEvent,
        scope: EventChangeScope
    ) throws -> EventChangeLog {
        let current = try EventChangeSnapshot(event: currentEvent)
        let restored = try EventChangeSnapshot(event: restoredEvent)

        return try database.write { db in
            guard var original = try EventChangeLogRecord.fetchOne(
                db,
                key: originalChangeID
            ) else {
                throw EventChangeLogError.missingChange(originalChangeID)
            }
            guard original.contextID == contextID else {
                throw EventChangeLogError.changeContextMismatch(
                    changeID: originalChangeID,
                    expectedContextID: contextID
                )
            }
            guard original.undoState == .available else {
                throw EventChangeLogError.undoUnavailable(originalChangeID)
            }
            let originalLog = try Self.makeChangeLog(original)
            guard original.scope == .single,
                  scope == .single,
                  originalLog.before.supportsSingleEventUndo,
                  originalLog.after.supportsSingleEventUndo,
                  current.supportsSingleEventUndo,
                  restored.supportsSingleEventUndo else {
                throw EventChangeLogError.unsupportedUndo(originalChangeID)
            }
            guard current.hasSameUndoableState(as: originalLog.after) else {
                throw EventChangeLogError.undoSourceMismatch(originalChangeID)
            }
            guard try eventContexts.updateSnapshot(
                contextID: contextID,
                event: restoredEvent,
                notes: nil,
                in: db
            ) != nil else {
                throw ContextStoreError.missingContext(contextID)
            }

            let timestamp = now()
            original.undoState = .undone
            original.undoneAt = timestamp
            try original.update(db)

            let restoredRecord = try makeChangeRecord(
                contextID: contextID,
                changeType: .restored,
                scope: scope,
                before: current,
                after: restored,
                undoState: .unavailable,
                undoneAt: nil,
                undoOfChangeID: originalChangeID,
                createdAt: timestamp
            )
            try restoredRecord.insert(db)
            return try Self.makeChangeLog(restoredRecord)
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
            try Self.deleteTaskPlanning(
                kind: .event,
                taskID: taskID,
                in: db
            )
            guard try eventTasks.delete(task: task, in: db) else {
                throw ContextStoreError.missingEventTask(taskID)
            }
        }
    }

    func deletePersonalTask(taskID: String) throws {
        try database.write { db in
            guard try personalTasks.fetch(id: taskID, in: db) != nil else {
                throw ContextStoreError.missingPersonalTask(taskID)
            }
            try Self.deleteTaskPlanning(
                kind: .personal,
                taskID: taskID,
                in: db
            )
            _ = try PersonalTask.deleteOne(db, key: taskID)
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

    func repeatEventTask(
        taskID: String,
        due: EventTaskDue
    ) throws -> EventTask {
        try database.write { db in
            guard let source = try eventTasks.fetch(id: taskID, in: db) else {
                throw ContextStoreError.missingEventTask(taskID)
            }
            let nextOrder = try eventTasks.nextSortOrder(
                contextID: source.contextID,
                section: source.section,
                in: db
            )
            let repeated = try eventTasks.makeTask(
                contextID: source.contextID,
                section: source.section,
                title: source.title,
                sortOrder: nextOrder,
                due: due
            )
            try eventTasks.insert(task: repeated, in: db)
            return repeated
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

    /// Completes a Task Center item, stops its running timer, and creates the
    /// next recurrence as one SQLite transaction. A failure at any point rolls
    /// the source task back to its original state.
    func applyTaskCenterCompletion(
        id: TaskCenterItemID,
        isCompleted: Bool,
        calendar: Calendar
    ) throws -> TaskCenterCompletionOutcome {
        try database.write { db in
            let timestamp = now()
            let identity = Self.taskPlanningIdentity(for: id)
            var planning = try TaskPlanningMetadata.fetchOne(
                db,
                key: [
                    "task_kind": identity.kind.rawValue,
                    "task_id": identity.id,
                ]
            ) ?? TaskPlanningRepository.defaultMetadata(
                for: id,
                now: timestamp
            )
            let checklist = try TaskChecklistItem
                .filter(Column("task_kind") == identity.kind.rawValue)
                .filter(Column("parent_task_id") == identity.id)
                .order(Column("sort_order"), Column("created_at"), Column("id"))
                .fetchAll(db)

            let result: TaskCenterCompletionResult
            let wasCompleted: Bool
            switch id {
            case let .eventTask(taskID, contextID):
                let task = try checkedEventTask(
                    contextID: contextID,
                    taskID: taskID,
                    in: db
                )
                wasCompleted = task.isCompleted
                result = .eventTask(
                    try eventTasks.setCompleted(
                        task: task,
                        isCompleted: isCompleted,
                        in: db
                    )
                )
            case let .personalTask(taskID):
                guard let task = try personalTasks.fetch(id: taskID, in: db) else {
                    throw ContextStoreError.missingPersonalTask(taskID)
                }
                wasCompleted = task.isCompleted
                result = .personalTask(
                    try personalTasks.setCompleted(
                        task: task,
                        isCompleted: isCompleted,
                        in: db
                    )
                )
            }

            if isCompleted, !wasCompleted, let startedAt = planning.startedAt {
                planning.actualSeconds += max(
                    0,
                    Int(timestamp.timeIntervalSince(startedAt).rounded(.down))
                )
                planning.startedAt = nil
                planning.updatedAt = timestamp
                try planning.save(db)
            }

            guard isCompleted,
                  !wasCompleted,
                  planning.repeatFrequency != .none else {
                return TaskCenterCompletionOutcome(
                    completed: result,
                    repeated: nil
                )
            }

            let repeated: TaskCenterCompletionResult
            let destination: TaskCenterItemID
            switch result {
            case let .personalTask(task):
                let next = PersonalTask(
                    id: makeID(),
                    title: task.title,
                    notes: task.notes,
                    dueAt: Self.nextRepeatingDate(
                        task.dueAt,
                        frequency: planning.repeatFrequency,
                        interval: planning.repeatInterval,
                        calendar: calendar
                    ),
                    isCompleted: false,
                    sortOrder: task.sortOrder,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    completedAt: nil
                )
                try next.insert(db)
                repeated = .personalTask(next)
                destination = .personalTask(taskID: next.id)
            case let .eventTask(task):
                let nextDue: EventTaskDue = switch task.due {
                case .none:
                    .none
                case let .relative(anchor, offsetMinutes):
                    .relative(anchor: anchor, offsetMinutes: offsetMinutes)
                case let .fixed(date):
                    .fixed(Self.nextRepeatingDate(
                        date,
                        frequency: planning.repeatFrequency,
                        interval: planning.repeatInterval,
                        calendar: calendar
                    ) ?? date)
                }
                let nextOrder = try eventTasks.nextSortOrder(
                    contextID: task.contextID,
                    section: task.section,
                    in: db
                )
                let next = try eventTasks.makeTask(
                    contextID: task.contextID,
                    section: task.section,
                    title: task.title,
                    sortOrder: nextOrder,
                    due: nextDue
                )
                try eventTasks.insert(task: next, in: db)
                repeated = .eventTask(next)
                destination = .eventTask(
                    taskID: next.id,
                    contextID: next.contextID
                )
            }

            try copyTaskPlanning(
                planning,
                checklist: checklist,
                to: destination,
                timestamp: timestamp,
                in: db
            )
            return TaskCenterCompletionOutcome(
                completed: result,
                repeated: repeated
            )
        }
    }

    private func copyTaskPlanning(
        _ source: TaskPlanningMetadata,
        checklist: [TaskChecklistItem],
        to destination: TaskCenterItemID,
        timestamp: Date,
        in db: Database
    ) throws {
        let target = Self.taskPlanningIdentity(for: destination)
        let metadata = TaskPlanningMetadata(
            taskKind: target.kind,
            taskID: target.id,
            priority: source.priority,
            isImportant: source.isImportant,
            repeatFrequency: source.repeatFrequency,
            repeatInterval: source.repeatInterval,
            estimatedMinutes: source.estimatedMinutes,
            actualSeconds: 0,
            startedAt: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try metadata.save(db)
        for sourceItem in checklist {
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

    private static func taskPlanningIdentity(
        for id: TaskCenterItemID
    ) -> (kind: LocalTaskKind, id: String) {
        switch id {
        case let .eventTask(taskID, _): (.event, taskID)
        case let .personalTask(taskID): (.personal, taskID)
        }
    }

    private static func nextRepeatingDate(
        _ date: Date?,
        frequency: TaskRepeatFrequency,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        guard let date else { return nil }
        let component: Calendar.Component
        switch frequency {
        case .none:
            return date
        case .daily:
            component = .day
        case .weekly:
            component = .weekOfYear
        case .monthly:
            component = .month
        case .yearly:
            component = .year
        }
        return calendar.date(
            byAdding: component,
            value: max(1, interval),
            to: date
        )
    }

    private static func deleteTaskPlanning(
        kind: LocalTaskKind,
        taskID: String,
        in db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM task_checklist_items WHERE task_kind = ? AND parent_task_id = ?",
            arguments: [kind.rawValue, taskID]
        )
        try db.execute(
            sql: "DELETE FROM task_planning_metadata WHERE task_kind = ? AND task_id = ?",
            arguments: [kind.rawValue, taskID]
        )
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

    private func makeChangeRecord(
        contextID: String,
        changeType: EventChangeType,
        scope: EventChangeScope,
        before: EventChangeSnapshot,
        after: EventChangeSnapshot,
        undoState: EventChangeUndoState,
        undoneAt: Date?,
        undoOfChangeID: String?,
        createdAt: Date
    ) throws -> EventChangeLogRecord {
        EventChangeLogRecord(
            id: makeID(),
            contextID: contextID,
            changeType: changeType,
            scope: scope,
            beforePayload: try Self.encodeChangeSnapshot(before),
            afterPayload: try Self.encodeChangeSnapshot(after),
            undoState: undoState,
            undoneAt: undoneAt,
            undoOfChangeID: undoOfChangeID,
            createdAt: createdAt
        )
    }

    private static func fetchChangeHistory(
        contextID: String,
        limit: Int,
        in db: Database
    ) throws -> [EventChangeLog] {
        guard limit > 0 else { return [] }
        let records = try EventChangeLogRecord.fetchAll(
            db,
            sql: """
                SELECT *
                FROM event_change_log
                WHERE context_id = ?
                ORDER BY created_at DESC, rowid DESC
                LIMIT ?
                """,
            arguments: [contextID, limit]
        )
        return try records.map(makeChangeLog)
    }

    private static func makeChangeLog(
        _ record: EventChangeLogRecord
    ) throws -> EventChangeLog {
        EventChangeLog(
            id: record.id,
            contextID: record.contextID,
            changeType: record.changeType,
            scope: record.scope,
            before: try decodeChangeSnapshot(record.beforePayload),
            after: try decodeChangeSnapshot(record.afterPayload),
            undoState: record.undoState,
            undoneAt: record.undoneAt,
            undoOfChangeID: record.undoOfChangeID,
            createdAt: record.createdAt
        )
    }

    private static func encodeChangeSnapshot(
        _ snapshot: EventChangeSnapshot
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return String(
            decoding: try encoder.encode(snapshot),
            as: UTF8.self
        )
    }

    private static func decodeChangeSnapshot(
        _ payload: String
    ) throws -> EventChangeSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(
            EventChangeSnapshot.self,
            from: Data(payload.utf8)
        )
    }
}
