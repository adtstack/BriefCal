import Foundation
import GRDB
import XCTest
@testable import KaosCal

final class ContextStoreTests: XCTestCase {
    func testMigrationIsAppliedAndForeignKeysAreEnabled() throws {
        let database = try AppDatabase.inMemory()

        XCTAssertEqual(
            try database.appliedMigrations(),
            ["v1_context_store", "v2_event_change_log"]
        )
        XCTAssertTrue(try database.foreignKeysEnabled())
    }

    func testChangeLogMigrationEnforcesChecksForeignKeysAndUndoUniqueness() throws {
        let database = try AppDatabase.inMemory()
        let timestamp = "2026-07-10 08:00:00.000"

        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "dangling", "missing", "moved", "single",
                        "{}", "{}", "unavailable", timestamp
                    ]
                )
            }
        )

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO event_contexts (
                        id, title_snapshot, lifecycle_status, notes,
                        created_at, updated_at
                    ) VALUES (?, ?, 'scheduled', '', ?, ?)
                    """,
                arguments: ["change-context", "Fixture", timestamp, timestamp]
            )
        }

        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "bad-type", "change-context", "unknown", "single",
                        "{}", "{}", "unavailable", timestamp
                    ]
                )
            }
        )
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "bad-undone", "change-context", "moved", "single",
                        "{}", "{}", "undone", timestamp
                    ]
                )
            }
        )
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "bad-restore", "change-context", "restored", "single",
                        "{}", "{}", "unavailable", timestamp
                    ]
                )
            }
        )

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO event_change_log (
                        id, context_id, change_type, scope,
                        before_payload, after_payload, undo_state,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "original-change", "change-context", "moved", "single",
                    "{}", "{}", "available", timestamp
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_change_log (
                        id, context_id, change_type, scope,
                        before_payload, after_payload, undo_state,
                        undo_of_change_id, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "restore", "change-context", "restored", "single",
                    "{}", "{}", "unavailable", "original-change", timestamp
                ]
            )
        }
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            undo_of_change_id, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "duplicate-restore", "change-context", "restored",
                        "single", "{}", "{}", "unavailable",
                        "original-change", timestamp
                    ]
                )
            }
        )

        let indexNames = try database.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'index' AND tbl_name = 'event_change_log'
                    """
            )
        }
        XCTAssertTrue(indexNames.contains("event_change_log_context_created"))
        XCTAssertTrue(indexNames.contains("event_change_log_unique_undo"))
    }

    func testMigrationRejectsInvalidIdentityDueAndCompletionRows() throws {
        let database = try AppDatabase.inMemory()

        func insertContext(_ id: String) throws {
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_contexts (
                            id, title_snapshot, lifecycle_status, notes,
                            created_at, updated_at
                        ) VALUES (
                            ?, 'Fixture', 'scheduled', '',
                            '2026-07-10 08:00:00.000',
                            '2026-07-10 08:00:00.000'
                        )
                        """,
                    arguments: [id]
                )
            }
        }

        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_tasks (
                        id, context_id, section, title, completed,
                        sort_order, due_kind, created_at, updated_at
                    ) VALUES (
                        'dangling', 'missing', 'before', 'Dangling', 0,
                        0, 'none', '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )

        try insertContext("all-day-mismatch")
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_links (
                        id, context_id, calendar_identifier, source_title,
                        calendar_title_snapshot, title_snapshot,
                        start_snapshot, end_snapshot, is_all_day,
                        is_recurring, time_semantics, time_zone_identifier,
                        occurrence_identity_key, is_detached, fingerprint,
                        link_status, last_seen_at, created_at, updated_at
                    ) VALUES (
                        'bad-all-day-link', 'all-day-mismatch', 'calendar',
                        'Work', 'KAOS-TEST', 'Fixture',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 09:00:00.000', 1, 0, 'zoned', 'UTC',
                        'single:v1', 0, 'fingerprint', 'active',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )

        try insertContext("bad-occurrence")
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_links (
                        id, context_id, calendar_identifier, source_title,
                        calendar_title_snapshot, title_snapshot,
                        start_snapshot, end_snapshot, is_all_day,
                        is_recurring, time_semantics, time_zone_identifier,
                        occurrence_date, occurrence_identity_key,
                        is_detached, fingerprint, link_status,
                        last_seen_at, created_at, updated_at
                    ) VALUES (
                        'bad-occurrence-link', 'bad-occurrence', 'calendar',
                        'Work', 'KAOS-TEST', 'Fixture',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 09:00:00.000', 0, 0, 'zoned', 'UTC',
                        '2026-07-10 08:00:00.000', 'instant:v1:1',
                        0, 'fingerprint-2', 'active',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )

        try insertContext("task-context")
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_tasks (
                        id, context_id, section, title, completed,
                        sort_order, due_kind, relative_anchor,
                        offset_minutes, created_at, updated_at
                    ) VALUES (
                        'too-far', 'task-context', 'before', 'Too far', 0,
                        0, 'relative', 'before_start', 2628001,
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO personal_tasks (
                        id, title, notes, completed, sort_order,
                        created_at, updated_at, completed_at
                    ) VALUES (
                        'bad-completion', 'Done?', '', 1, 0,
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000', NULL
                    )
                    """)
            }
        )

        let indexNames = try database.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'index' AND tbl_name = 'event_links'
                    """
            )
        }
        XCTAssertTrue(
            indexNames.contains("event_links_unique_event_occurrence")
        )
        XCTAssertTrue(
            indexNames.contains("event_links_series_occurrence")
        )
    }

    func testSelectionAndEmptyNotesDoNotCreateContext() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "event")

        XCTAssertEqual(try harness.store.resolve(event: event), .notFound)
        XCTAssertNil(try harness.store.saveNotes(for: event, notes: "  "))
        XCTAssertEqual(try harness.store.eventContexts.count(), 0)
    }

    func testLoadBriefIsLazyAndRequiresConfirmationForWeakMatch() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "brief",
            title: "Téam   Sync",
            location: "Room Ａ"
        )

        XCTAssertEqual(try harness.store.loadBrief(for: event), .empty)
        XCTAssertEqual(try harness.store.eventContexts.count(), 0)

        let context = try XCTUnwrap(
            harness.store.saveNotes(for: event, notes: "Local brief")
        )
        guard case let .loaded(snapshot, basis) = try harness.store.loadBrief(
            for: event
        ) else {
            return XCTFail("Expected a linked brief")
        }
        XCTAssertEqual(basis, .eventIdentifier)
        XCTAssertEqual(snapshot.context.id, context.id)
        XCTAssertEqual(snapshot.context.notes, "Local brief")

        let weakCandidate = makeEvent(
            id: "weak-brief",
            title: " team sync ",
            location: "room a",
            includeIdentifiers: false
        )
        XCTAssertEqual(
            try harness.store.loadBrief(for: weakCandidate),
            .confirmationRequired(
                contextIDs: [context.id],
                basis: .fingerprint
            )
        )
        XCTAssertEqual(try harness.store.eventContexts.count(), 1)
        XCTAssertEqual(
            try harness.store.eventContexts.fetch(id: context.id)?.titleSnapshot,
            event.title
        )
    }

    func testFirstNotesCreateContextAndLinkTogether() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "event")

        let context = try XCTUnwrap(
            harness.store.saveNotes(for: event, notes: "Bring the brief")
        )
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertEqual(brief.context.notes, "Bring the brief")
        XCTAssertEqual(brief.link.eventIdentifier, "event-id-event")
        XCTAssertEqual(brief.link.calendarTitleSnapshot, "KAOS-TEST")
        XCTAssertTrue(brief.tasks.isEmpty)
        XCTAssertEqual(
            try harness.store.resolve(event: event),
            .linked(contextID: context.id, basis: .eventIdentifier)
        )
    }

    func testFirstEventTaskCreatesContextLinkAndTaskAtomically() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "event",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10)
        )

        let task = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Prepare slides",
            sortOrder: 0,
            due: .relative(anchor: .beforeStart, offsetMinutes: 30)
        )
        let contextID = try linkedContextID(
            harness.store.resolve(event: event)
        )
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: contextID)
        )
        let eventRange = brief.link.effectiveDateRange(calendar: testCalendar)

        XCTAssertEqual(try harness.store.eventContexts.count(), 1)
        XCTAssertEqual(try harness.store.eventTasks.count(), 1)
        XCTAssertEqual(
            task.effectiveDueDate(
                eventStart: eventRange.start,
                eventEnd: eventRange.end
            ),
            date(2026, 7, 10, 8, 30)
        )
    }

    func testFailedLinkInsertRollsBackNewContext() throws {
        let database = try AppDatabase.inMemory()
        let firstIDs = IDSequence(["context-1", "shared-link", "task-1"])
        let firstStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 8) },
            makeID: firstIDs.next
        )
        _ = try firstStore.addEventTask(
            for: makeEvent(id: "first"),
            section: .before,
            title: "First",
            sortOrder: 0
        )

        let secondIDs = IDSequence(["context-2", "shared-link", "task-2"])
        let secondStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 9) },
            makeID: secondIDs.next
        )

        XCTAssertThrowsError(
            try secondStore.addEventTask(
                for: makeEvent(id: "second"),
                section: .before,
                title: "Second",
                sortOrder: 0
            )
        )
        XCTAssertEqual(try secondStore.eventContexts.count(), 1)
        XCTAssertEqual(try secondStore.eventTasks.count(), 1)
        XCTAssertEqual(
            try secondStore.resolve(event: makeEvent(id: "second")),
            .candidate(
                contextIDs: ["context-1"],
                basis: .exactSnapshot
            )
        )
    }

    func testConcurrentFirstNoteAndTaskShareOneContext() throws {
        let database = try AppDatabase.inMemory()
        let noteIDs = IDSequence(["note-context", "note-link"])
        let taskIDs = IDSequence(["task-context", "task-link", "task"])
        let noteStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 8) },
            makeID: noteIDs.next
        )
        let taskStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 8) },
            makeID: taskIDs.next
        )
        let event = makeEvent(id: "concurrent")
        let errorLock = NSLock()
        var errors: [Error] = []

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                if index == 0 {
                    _ = try noteStore.saveNotes(
                        for: event,
                        notes: "Concurrent notes"
                    )
                } else {
                    _ = try taskStore.addEventTask(
                        for: event,
                        section: .before,
                        title: "Concurrent task",
                        sortOrder: 0
                    )
                }
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
        }

        XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors)")
        XCTAssertEqual(try noteStore.eventContexts.count(), 1)
        XCTAssertEqual(try noteStore.eventTasks.count(), 1)
        let contextID = try linkedContextID(noteStore.resolve(event: event))
        let brief = try XCTUnwrap(
            noteStore.eventContexts.fetchBrief(contextID: contextID)
        )
        XCTAssertEqual(brief.context.notes, "Concurrent notes")
        XCTAssertEqual(brief.tasks.map(\.title), ["Concurrent task"])
    }

    func testEventTaskOrderingUpdateCompletionAndDueValidation() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "ordered",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10)
        )
        let during = try harness.store.addEventTask(
            for: event,
            section: .during,
            title: "During",
            sortOrder: 0
        )
        let after = try harness.store.addEventTask(
            for: event,
            section: .after,
            title: "After",
            sortOrder: 0,
            due: .relative(anchor: .afterEnd, offsetMinutes: 15)
        )
        let before = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Before",
            sortOrder: 0
        )
        let contextID = try linkedContextID(
            harness.store.resolve(event: event)
        )

        XCTAssertEqual(
            try harness.store.eventTasks.fetch(contextID: contextID).map(\.id),
            [before.id, during.id, after.id]
        )
        let updated = try XCTUnwrap(
            harness.store.eventTasks.update(
                id: during.id,
                section: .before,
                title: "During moved",
                sortOrder: 1,
                due: .fixed(date(2026, 7, 10, 8, 45))
            )
        )
        XCTAssertEqual(updated.due, .fixed(date(2026, 7, 10, 8, 45)))
        let completed = try XCTUnwrap(
            harness.store.eventTasks.setCompleted(
                id: after.id,
                isCompleted: true
            )
        )
        XCTAssertTrue(completed.isCompleted)
        XCTAssertNotNil(completed.completedAt)

        XCTAssertThrowsError(
            try harness.store.eventTasks.create(
                contextID: contextID,
                section: .before,
                title: "Invalid",
                sortOrder: 2,
                due: .relative(anchor: .atStart, offsetMinutes: 5)
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidRelativeDue
            )
        }
        XCTAssertThrowsError(
            try harness.store.eventTasks.create(
                contextID: contextID,
                section: .before,
                title: "Too far away",
                sortOrder: 3,
                due: .relative(
                    anchor: .beforeStart,
                    offsetMinutes:
                        EventTaskDuePolicy.maximumOffsetMinutes + 1
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidRelativeDue
            )
        }
    }

    func testAppendEventTaskAllocatesSectionOrderInsideTransaction() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "append-order")

        let first = try harness.store.appendEventTask(
            for: event,
            section: .before,
            title: "First"
        )
        let second = try harness.store.appendEventTask(
            for: event,
            section: .before,
            title: "Second"
        )
        _ = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Explicit",
            sortOrder: 8
        )
        let afterExplicit = try harness.store.appendEventTask(
            for: event,
            section: .before,
            title: "After explicit"
        )
        let during = try harness.store.appendEventTask(
            for: event,
            section: .during,
            title: "During"
        )

        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(second.sortOrder, 1)
        XCTAssertEqual(afterExplicit.sortOrder, 9)
        XCTAssertEqual(during.sortOrder, 0)
    }

    func testContextScopedEventTaskMutationRejectsWrongContextAndMissingTask() throws {
        let harness = try makeHarness()
        let firstTask = try harness.store.appendEventTask(
            for: makeEvent(id: "scoped-first"),
            section: .before,
            title: "First"
        )
        let secondTask = try harness.store.appendEventTask(
            for: makeEvent(
                id: "scoped-second",
                title: "Other event",
                start: date(2026, 7, 10, 11),
                end: date(2026, 7, 10, 12)
            ),
            section: .after,
            title: "Second"
        )

        XCTAssertThrowsError(
            try harness.store.updateEventTask(
                contextID: secondTask.contextID,
                taskID: firstTask.id,
                section: .after,
                title: "Wrong mutation",
                sortOrder: 3,
                due: .none
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .eventTaskContextMismatch(
                    taskID: firstTask.id,
                    expectedContextID: secondTask.contextID
                )
            )
        }
        XCTAssertThrowsError(
            try harness.store.deleteEventTask(
                contextID: secondTask.contextID,
                taskID: firstTask.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .eventTaskContextMismatch(
                    taskID: firstTask.id,
                    expectedContextID: secondTask.contextID
                )
            )
        }
        XCTAssertThrowsError(
            try harness.store.setEventTaskCompleted(
                contextID: firstTask.contextID,
                taskID: "missing-task",
                isCompleted: true
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .missingEventTask("missing-task")
            )
        }

        let unchanged = try XCTUnwrap(
            harness.store.eventTasks.fetch(id: firstTask.id)
        )
        XCTAssertEqual(unchanged.title, "First")
        XCTAssertEqual(unchanged.section, .before)
        XCTAssertFalse(unchanged.isCompleted)
    }

    func testCompletionIsIdempotentForEventAndPersonalTasks() throws {
        var current = date(2026, 7, 10, 12)
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { current }
        )
        let eventTask = try store.appendEventTask(
            for: makeEvent(id: "idempotent"),
            section: .after,
            title: "Follow up"
        )
        let personalTask = try store.personalTasks.create(title: "Personal")

        current = date(2026, 7, 10, 13)
        let completedEvent = try store.setEventTaskCompleted(
            contextID: eventTask.contextID,
            taskID: eventTask.id,
            isCompleted: true
        )
        let completedPersonal = try store.setPersonalTaskCompleted(
            taskID: personalTask.id,
            isCompleted: true
        )

        current = date(2026, 7, 10, 14)
        let repeatedEvent = try store.setEventTaskCompleted(
            contextID: eventTask.contextID,
            taskID: eventTask.id,
            isCompleted: true
        )
        let repeatedPersonal = try store.setPersonalTaskCompleted(
            taskID: personalTask.id,
            isCompleted: true
        )

        XCTAssertEqual(repeatedEvent.completedAt, completedEvent.completedAt)
        XCTAssertEqual(repeatedEvent.updatedAt, completedEvent.updatedAt)
        XCTAssertEqual(
            repeatedPersonal.completedAt,
            completedPersonal.completedAt
        )
        XCTAssertEqual(
            repeatedPersonal.updatedAt,
            completedPersonal.updatedAt
        )
    }

    func testDeletingContextCascadesLinkAndEventTasks() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "cascade")
        _ = try harness.store.addEventTask(
            for: event,
            section: .after,
            title: "Follow up",
            sortOrder: 0
        )
        let contextID = try linkedContextID(
            harness.store.resolve(event: event)
        )

        try harness.store.eventContexts.delete(contextID: contextID)

        XCTAssertNil(
            try harness.store.eventContexts.fetchBrief(contextID: contextID)
        )
        XCTAssertEqual(try harness.store.eventTasks.count(), 0)
        XCTAssertEqual(try harness.store.resolve(event: event), .notFound)
    }

    func testPersonalTaskCRUDAndLists() throws {
        let harness = try makeHarness()
        let undated = try harness.store.personalTasks.create(
            title: "Inbox",
            sortOrder: 2
        )
        let today = try harness.store.personalTasks.create(
            title: "Today",
            dueAt: date(2026, 7, 10, 18),
            sortOrder: 1
        )
        let upcoming = try harness.store.personalTasks.create(
            title: "Upcoming",
            dueAt: date(2026, 7, 11),
            sortOrder: 0
        )

        XCTAssertEqual(
            try harness.store.personalTasks.fetch(
                list: .today,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [today.id, undated.id]
        )
        XCTAssertEqual(
            try harness.store.personalTasks.fetch(
                list: .upcoming,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [upcoming.id]
        )

        _ = try harness.store.personalTasks.update(
            id: undated.id,
            title: "Inbox edited",
            notes: "local only",
            dueAt: nil,
            sortOrder: 3
        )
        _ = try harness.store.personalTasks.setCompleted(
            id: today.id,
            isCompleted: true
        )
        XCTAssertEqual(
            try harness.store.personalTasks.fetch(
                list: .completed,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [today.id]
        )

        try harness.store.personalTasks.delete(id: upcoming.id)
        XCTAssertNil(try harness.store.personalTasks.fetch(id: upcoming.id))
    }

    func testTypedTaskCenterIdentityRoutesCollidingRawIDs() throws {
        let IDs = IDSequence([
            "event-context",
            "event-link",
            "shared-task-id",
            "shared-task-id"
        ])
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) },
            makeID: IDs.next
        )
        let eventTask = try store.appendEventTask(
            for: makeEvent(id: "typed-routing"),
            section: .before,
            title: "Event task"
        )
        let personalTask = try store.personalTasks.create(
            title: "Personal task"
        )

        XCTAssertEqual(eventTask.id, personalTask.id)
        let items = try store.taskCenter.fetch(
            list: .today,
            now: date(2026, 7, 10, 12),
            calendar: testCalendar
        )
        XCTAssertEqual(
            Set(items.map(\.id)),
            Set([
                .eventTask(
                    taskID: eventTask.id,
                    contextID: eventTask.contextID
                ),
                .personalTask(taskID: personalTask.id)
            ])
        )

        let personalResult = try store.setTaskCenterItemCompleted(
            id: .personalTask(taskID: personalTask.id),
            isCompleted: true
        )
        guard case let .personalTask(completedPersonal) = personalResult else {
            return XCTFail("Expected personal task completion")
        }
        XCTAssertTrue(completedPersonal.isCompleted)
        XCTAssertFalse(
            try XCTUnwrap(store.eventTasks.fetch(id: eventTask.id)).isCompleted
        )

        let eventResult = try store.setTaskCenterItemCompleted(
            id: .eventTask(
                taskID: eventTask.id,
                contextID: eventTask.contextID
            ),
            isCompleted: true
        )
        guard case let .eventTask(completedEvent) = eventResult else {
            return XCTFail("Expected event task completion")
        }
        XCTAssertTrue(completedEvent.isCompleted)
        XCTAssertTrue(
            try XCTUnwrap(
                store.personalTasks.fetch(id: personalTask.id)
            ).isCompleted
        )

        XCTAssertThrowsError(
            try store.setTaskCenterItemCompleted(
                id: .personalTask(taskID: "missing-personal"),
                isCompleted: true
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .missingPersonalTask("missing-personal")
            )
        }
    }

    func testTaskCenterCombinesEventAndPersonalTasksAtDayBoundary() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "center",
            start: date(2026, 7, 10, 15),
            end: date(2026, 7, 10, 16)
        )
        let eventTask = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Event preparation",
            sortOrder: 0
        )
        let personalToday = try harness.store.personalTasks.create(
            title: "Personal today",
            sortOrder: 1
        )
        let personalUpcoming = try harness.store.personalTasks.create(
            title: "Personal upcoming",
            dueAt: date(2026, 7, 11),
            sortOrder: 0
        )

        let today = try harness.store.taskCenter.fetch(
            list: .today,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(
            Set(today.map(\.id)),
            Set([
                .eventTask(
                    taskID: eventTask.id,
                    contextID: eventTask.contextID
                ),
                .personalTask(taskID: personalToday.id)
            ])
        )
        guard case let .event(
            contextID,
            section,
            eventTitle,
            calendarTitle,
            sourceTitle,
            eventStart,
            eventEnd,
            isAllDay
        ) = try XCTUnwrap(today.first {
            $0.id == .eventTask(
                taskID: eventTask.id,
                contextID: eventTask.contextID
            )
        }).source else {
            return XCTFail("Expected event task source")
        }
        XCTAssertEqual(contextID, eventTask.contextID)
        XCTAssertEqual(section, .before)
        XCTAssertEqual(eventTitle, event.title)
        XCTAssertEqual(calendarTitle, "KAOS-TEST")
        XCTAssertEqual(sourceTitle, "Work")
        XCTAssertEqual(eventStart, event.startDate)
        XCTAssertEqual(eventEnd, event.endDate)
        XCTAssertFalse(isAllDay)

        XCTAssertEqual(
            try harness.store.taskCenter.fetch(
                list: .upcoming,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [.personalTask(taskID: personalUpcoming.id)]
        )
    }

    func testTaskCenterUsesLocalTimeSemanticsForFloatingAndAllDayDueDates() throws {
        let harness = try makeHarness()
        var seoulCalendar = testCalendar
        seoulCalendar.timeZone = TimeZone(identifier: "Asia/Seoul")!

        let floatingStart = LocalDateTimeComponents(
            date: date(2026, 7, 11, 9),
            calendar: testCalendar
        )
        let floatingEnd = LocalDateTimeComponents(
            date: date(2026, 7, 11, 10),
            calendar: testCalendar
        )
        let floatingEvent = makeEvent(
            id: "floating",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            timeSemantics: .floating(
                start: floatingStart,
                end: floatingEnd
            )
        )
        let floatingTask = try harness.store.addEventTask(
            for: floatingEvent,
            section: .before,
            title: "Floating preparation",
            sortOrder: 0,
            due: .relative(anchor: .beforeStart, offsetMinutes: 30)
        )

        let allDayStart = LocalDateTimeComponents(
            date: date(2026, 7, 11),
            calendar: testCalendar
        )
        let allDayEnd = LocalDateTimeComponents(
            date: date(2026, 7, 12),
            calendar: testCalendar
        )
        let allDayEvent = makeEvent(
            id: "all-day",
            start: date(2026, 7, 11),
            end: date(2026, 7, 12).addingTimeInterval(-1),
            isAllDay: true,
            timeSemantics: .allDay(
                start: allDayStart,
                endExclusive: allDayEnd
            )
        )
        let allDayTask = try harness.store.addEventTask(
            for: allDayEvent,
            section: .after,
            title: "All-day follow-up",
            sortOrder: 0,
            due: .relative(anchor: .atEnd, offsetMinutes: 0)
        )

        let upcoming = try harness.store.taskCenter.fetch(
            list: .upcoming,
            now: harness.now,
            calendar: seoulCalendar
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: upcoming.map {
            ($0.id, $0)
        })
        let expectedFloatingDue = seoulCalendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 11,
                hour: 8,
                minute: 30
            )
        )
        let expectedAllDayDue = seoulCalendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 12
            )
        )

        XCTAssertEqual(
            itemsByID[.eventTask(
                taskID: floatingTask.id,
                contextID: floatingTask.contextID
            )]?.dueAt,
            expectedFloatingDue
        )
        XCTAssertEqual(
            itemsByID[.eventTask(
                taskID: allDayTask.id,
                contextID: allDayTask.contextID
            )]?.dueAt,
            expectedAllDayDue
        )
    }

    func testObservingLinkedMoveRefreshesSnapshotWithoutLosingLocalData() throws {
        let harness = try makeHarness()
        let original = makeEvent(
            id: "moving",
            externalIdentifier: "stable-external"
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Original notes")
        )
        let task = try harness.store.addEventTask(
            for: original,
            section: .during,
            title: "Keep this task",
            sortOrder: 0
        )
        let moved = makeEvent(
            id: "moving-refreshed",
            title: "Renamed meeting",
            location: "Room B",
            start: date(2026, 7, 10, 14),
            end: date(2026, 7, 10, 15),
            externalIdentifier: "stable-external"
        )

        XCTAssertEqual(
            try harness.store.resolve(event: moved),
            .linked(
                contextID: context.id,
                basis: .externalIdentifierAndOccurrence
            )
        )
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertEqual(brief.context.titleSnapshot, "Renamed meeting")
        XCTAssertEqual(brief.context.startSnapshot, date(2026, 7, 10, 14))
        XCTAssertEqual(brief.context.endSnapshot, date(2026, 7, 10, 15))
        XCTAssertEqual(brief.context.notes, "Original notes")
        XCTAssertEqual(brief.link.titleSnapshot, "Renamed meeting")
        XCTAssertEqual(brief.link.locationSnapshot, "Room B")
        XCTAssertEqual(brief.link.startSnapshot, date(2026, 7, 10, 14))
        XCTAssertEqual(
            brief.link.eventIdentifier,
            "event-id-moving-refreshed"
        )
        XCTAssertEqual(brief.tasks.map(\.id), [task.id])
        let todayItems = try harness.store.taskCenter.fetch(
            list: .today,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(
            todayItems.first {
                $0.id == .eventTask(
                    taskID: task.id,
                    contextID: task.contextID
                )
            }?.dueAt,
            date(2026, 7, 10, 14)
        )
    }

    func testRecurringOccurrencesResolveSeparatelyAndDetachedMoveStaysLinked() throws {
        let harness = try makeHarness()
        let firstOccurrence = makeEvent(
            id: "occurrence-1",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            externalIdentifier: "series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let secondOccurrence = makeEvent(
            id: "occurrence-2",
            start: date(2026, 7, 17, 9),
            end: date(2026, 7, 17, 10),
            externalIdentifier: "series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 17, 9)
        )
        let firstContext = try XCTUnwrap(
            harness.store.saveNotes(for: firstOccurrence, notes: "First")
        )
        let secondContext = try XCTUnwrap(
            harness.store.saveNotes(for: secondOccurrence, notes: "Second")
        )

        XCTAssertNotEqual(firstContext.id, secondContext.id)
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: firstOccurrence)),
            firstContext.id
        )
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: secondOccurrence)),
            secondContext.id
        )

        let detachedMoved = makeEvent(
            id: "occurrence-moved",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14),
            externalIdentifier: "series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            isDetached: true
        )
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: detachedMoved)),
            firstContext.id
        )
    }

    func testNavigationMatchingIsReadOnlyStrongAndOccurrenceScoped() throws {
        let harness = try makeHarness()
        let original = makeEvent(
            id: "navigation-original",
            externalIdentifier: "navigation-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Keep snapshot")
        )
        let before = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )

        let target = try XCTUnwrap(
            harness.store.navigationTarget(contextID: context.id)
        )
        XCTAssertEqual(target.contextID, context.id)
        XCTAssertEqual(target.link, before.link)

        let matchingOccurrence = makeEvent(
            id: "navigation-live",
            title: "Moved live event",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14),
            externalIdentifier: "navigation-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            isDetached: true
        )
        let siblingOccurrence = makeEvent(
            id: "navigation-sibling",
            start: date(2026, 7, 17, 9),
            end: date(2026, 7, 17, 10),
            externalIdentifier: "navigation-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 17, 9)
        )

        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: context.id,
                among: [siblingOccurrence, matchingOccurrence]
            ),
            .linked(
                event: matchingOccurrence,
                basis: .externalIdentifierAndOccurrence
            )
        )

        let weakOccurrence = makeEvent(
            id: "navigation-weak",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            includeIdentifiers: false
        )
        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: context.id,
                among: [weakOccurrence]
            ),
            .confirmationRequired(
                eventIDs: [weakOccurrence.id],
                basis: .exactSnapshot
            )
        )
        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: "missing-context",
                among: [matchingOccurrence]
            ),
            .notFound
        )

        let after = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after, before)
    }

    func testUserApprovedMutationRebindsChangedCalendarAndIdentifiers() throws {
        let store = try makeHarness().store
        let original = makeEvent(
            id: "before",
            title: "Before",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            externalIdentifier: "external-before",
            calendarIdentifier: "calendar-before"
        )
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep this local note")
        )
        _ = try store.appendEventTask(
            for: original,
            section: .before,
            title: "Keep this task"
        )
        let updated = makeEvent(
            id: "after",
            title: "After",
            start: date(2026, 7, 11, 13),
            end: date(2026, 7, 11, 14),
            externalIdentifier: "external-after",
            calendarIdentifier: "calendar-after"
        )

        XCTAssertEqual(
            try store.mutationContext(for: original),
            .linked(contextID: context.id)
        )
        let rebound = try store.rebindUserApprovedMutation(
            contextID: context.id,
            to: updated
        )

        XCTAssertEqual(rebound.context.notes, "Keep this local note")
        XCTAssertEqual(rebound.context.titleSnapshot, "After")
        XCTAssertEqual(rebound.link.calendarIdentifier, "calendar-after")
        XCTAssertEqual(rebound.link.eventIdentifier, "event-id-after")
        XCTAssertEqual(rebound.tasks.map(\.title), ["Keep this task"])
        guard case let .linked(linkedID, _) = try store.resolve(event: updated) else {
            return XCTFail("Expected updated event to stay linked")
        }
        XCTAssertEqual(linkedID, context.id)
    }

    func testMutationImpactSummarizesLocalDataAndRecentHistory() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "impact-original")
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: original,
                notes: "  Local note  "
            )
        )
        _ = try harness.store.appendEventTask(
            for: original,
            section: .before,
            title: "Prepare"
        )
        _ = try harness.store.appendEventTask(
            for: original,
            section: .during,
            title: "Join"
        )
        let moved = makeEvent(
            id: "impact-moved",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14),
            calendarIdentifier: "destination-calendar"
        )
        let firstChange = try harness.store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: moved,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let renamed = makeEvent(
            id: "impact-renamed",
            title: "Renamed event",
            start: moved.startDate,
            end: moved.endDate,
            calendarIdentifier: moved.calendarIdentifier
        )
        let secondChange = try harness.store.rebindAndRecordMutation(
            contextID: context.id,
            from: moved,
            to: renamed,
            changeType: .detailsUpdated,
            scope: .single,
            undoState: .unavailable
        )

        let impact = try harness.store.mutationImpact(
            contextID: context.id,
            recentHistoryLimit: 1
        )

        XCTAssertTrue(impact.hasNotes)
        XCTAssertEqual(impact.notesCharacterCount, 10)
        XCTAssertEqual(impact.taskCount, 2)
        XCTAssertEqual(
            impact.taskSections,
            [
                EventMutationTaskSummary(
                    section: .before,
                    count: 1,
                    titles: ["Prepare"]
                ),
                EventMutationTaskSummary(
                    section: .during,
                    count: 1,
                    titles: ["Join"]
                ),
                EventMutationTaskSummary(
                    section: .after,
                    count: 0,
                    titles: []
                )
            ]
        )
        XCTAssertEqual(impact.recentHistory.map(\.id), [secondChange.id])
        XCTAssertEqual(impact.recentHistory.first?.before.startDate, moved.startDate)
        XCTAssertEqual(
            impact.recentHistory.first?.after.calendarIdentifier,
            "destination-calendar"
        )

        let history = try harness.store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.id), [secondChange.id, firstChange.id])
        XCTAssertEqual(history[0].undoState, .unavailable)
        XCTAssertEqual(history[1].undoState, .superseded)
        XCTAssertEqual(history[1].before.calendarIdentifier, "calendar")
        XCTAssertEqual(
            history[1].after.calendarIdentifier,
            "destination-calendar"
        )
    }

    func testRebindAndChangeLogAppendRollBackTogether() throws {
        let IDs = IDSequence([
            "rollback-context", "rollback-link",
            "duplicate-log", "duplicate-log"
        ])
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) },
            makeID: IDs.next
        )
        let original = makeEvent(id: "rollback-original")
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep local data")
        )
        let firstMove = makeEvent(
            id: "rollback-first",
            start: date(2026, 7, 10, 11),
            end: date(2026, 7, 10, 12)
        )
        let firstChange = try store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: firstMove,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let beforeFailure = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        let secondMove = makeEvent(
            id: "rollback-second",
            start: date(2026, 7, 10, 15),
            end: date(2026, 7, 10, 16)
        )

        XCTAssertThrowsError(
            try store.rebindAndRecordMutation(
                contextID: context.id,
                from: firstMove,
                to: secondMove,
                changeType: .moved,
                scope: .single,
                undoState: .available
            )
        )

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            beforeFailure
        )
        let history = try store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.id), [firstChange.id])
        XCTAssertEqual(history.first?.undoState, .available)
    }

    func testUndoRebindMarksOriginalAndAppendsRestoredAtomically() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "undo-original")
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Keep note")
        )
        let task = try harness.store.appendEventTask(
            for: original,
            section: .after,
            title: "Keep task"
        )
        let moved = makeEvent(
            id: "undo-moved",
            start: date(2026, 7, 11, 13),
            end: date(2026, 7, 11, 14),
            calendarIdentifier: "destination-calendar"
        )
        let originalChange = try harness.store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: moved,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let restoredReceipt = makeEvent(id: "undo-restored")

        let restoredChange = try harness.store.rebindAfterUndo(
            contextID: context.id,
            originalChangeID: originalChange.id,
            from: moved,
            to: restoredReceipt,
            scope: .single
        )

        XCTAssertEqual(restoredChange.changeType, .restored)
        XCTAssertEqual(restoredChange.undoState, .unavailable)
        XCTAssertEqual(restoredChange.undoOfChangeID, originalChange.id)
        XCTAssertEqual(restoredChange.before.calendarIdentifier, moved.calendarIdentifier)
        XCTAssertEqual(
            restoredChange.after.calendarIdentifier,
            restoredReceipt.calendarIdentifier
        )
        let history = try harness.store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.id), [restoredChange.id, originalChange.id])
        XCTAssertEqual(history[1].undoState, .undone)
        XCTAssertEqual(history[1].undoneAt, harness.now)
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(brief.context.id, context.id)
        XCTAssertEqual(brief.context.notes, "Keep note")
        XCTAssertEqual(brief.link.startSnapshot, restoredReceipt.startDate)
        XCTAssertEqual(brief.tasks.map(\.id), [task.id])

        XCTAssertThrowsError(
            try harness.store.rebindAfterUndo(
                contextID: context.id,
                originalChangeID: originalChange.id,
                from: restoredReceipt,
                to: moved,
                scope: .single
            )
        ) { error in
            XCTAssertEqual(
                error as? EventChangeLogError,
                .undoUnavailable(originalChange.id)
            )
        }
        XCTAssertEqual(
            try harness.store.changeHistory(contextID: context.id).count,
            2
        )
    }

    func testUndoRollbackKeepsLinkAndOriginalChangeAvailable() throws {
        let IDs = IDSequence([
            "undo-rollback-context", "undo-rollback-link",
            "duplicate-undo-log", "duplicate-undo-log"
        ])
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) },
            makeID: IDs.next
        )
        let original = makeEvent(id: "undo-rollback-original")
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep")
        )
        let moved = makeEvent(
            id: "undo-rollback-moved",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14)
        )
        let change = try store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: moved,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let beforeFailure = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertThrowsError(
            try store.rebindAfterUndo(
                contextID: context.id,
                originalChangeID: change.id,
                from: moved,
                to: makeEvent(id: "undo-rollback-restored"),
                scope: .single
            )
        )

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            beforeFailure
        )
        let history = try store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, change.id)
        XCTAssertEqual(history.first?.undoState, .available)
        XCTAssertNil(history.first?.undoneAt)
    }

    func testUserApprovedMutationCollisionRollsBackBothContextsAndTasks() throws {
        let store = try makeHarness().store
        let first = makeEvent(id: "collision-first")
        let second = makeEvent(
            id: "collision-second",
            title: "Other event",
            location: "Room B",
            start: date(2026, 7, 10, 11),
            end: date(2026, 7, 10, 12)
        )
        let firstContext = try XCTUnwrap(
            store.saveNotes(for: first, notes: "First local note")
        )
        let secondContext = try XCTUnwrap(
            store.saveNotes(for: second, notes: "Second local note")
        )
        _ = try store.appendEventTask(
            for: first,
            section: .before,
            title: "First task"
        )
        _ = try store.appendEventTask(
            for: second,
            section: .after,
            title: "Second task"
        )
        let firstBefore = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: firstContext.id)
        )
        let secondBefore = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: secondContext.id)
        )

        XCTAssertThrowsError(
            try store.rebindUserApprovedMutation(
                contextID: firstContext.id,
                to: second
            )
        )

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: firstContext.id),
            firstBefore
        )
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: secondContext.id),
            secondBefore
        )
    }

    func testUserApprovedMutationMissingContextChangesNothing() throws {
        let store = try makeHarness().store
        let event = makeEvent(id: "missing-rebind")
        let context = try XCTUnwrap(
            store.saveNotes(for: event, notes: "Existing note")
        )
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertThrowsError(
            try store.rebindUserApprovedMutation(
                contextID: "missing-context",
                to: makeEvent(id: "new-receipt")
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .missingContext("missing-context")
            )
        }

        XCTAssertEqual(try store.eventContexts.count(), 1)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            before
        )
    }

    func testMutationContextDoesNotAutoChooseWeakCandidate() throws {
        let store = try makeHarness().store
        let original = makeEvent(
            id: "weak-original",
            title: "Weak candidate",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            calendarIdentifier: "calendar",
            includeIdentifiers: false
        )
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Candidate note")
        )
        let candidate = makeEvent(
            id: "weak-candidate",
            title: original.title,
            start: original.startDate,
            end: original.endDate,
            calendarIdentifier: "calendar"
        )

        XCTAssertEqual(
            try store.mutationContext(for: candidate),
            .confirmationRequired(contextIDs: [context.id])
        )
    }

    func testFloatingOccurrenceUsesCivilAnchorAcrossTimeZoneAndDetachedMove() throws {
        let harness = try makeHarness()
        let occurrenceStart = localComponents(2026, 7, 10, 9)
        let occurrenceEnd = localComponents(2026, 7, 10, 10)
        let original = makeEvent(
            id: "floating-occurrence",
            start: date(2026, 7, 10),
            end: date(2026, 7, 10, 1),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10),
            occurrenceLocalComponents: occurrenceStart,
            timeSemantics: .floating(
                start: occurrenceStart,
                end: occurrenceEnd
            )
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Civil anchor")
        )
        let sameCivilTimeInAnotherZone = makeEvent(
            id: "floating-occurrence",
            start: date(2026, 7, 10, 16),
            end: date(2026, 7, 10, 17),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 16),
            occurrenceLocalComponents: occurrenceStart,
            timeSemantics: .floating(
                start: occurrenceStart,
                end: occurrenceEnd
            )
        )

        XCTAssertEqual(
            try linkedContextID(
                harness.store.resolve(event: sameCivilTimeInAnotherZone)
            ),
            context.id
        )

        let detachedStart = localComponents(2026, 7, 10, 13)
        let detachedEnd = localComponents(2026, 7, 10, 14)
        let detached = makeEvent(
            id: "floating-detached",
            start: date(2026, 7, 10, 20),
            end: date(2026, 7, 10, 21),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 16),
            occurrenceLocalComponents: occurrenceStart,
            isDetached: true,
            timeSemantics: .floating(
                start: detachedStart,
                end: detachedEnd
            )
        )
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: detached)),
            context.id
        )

        let nextOccurrenceStart = localComponents(2026, 7, 17, 9)
        let nextOccurrenceEnd = localComponents(2026, 7, 17, 10)
        let nextOccurrence = makeEvent(
            id: "floating-occurrence",
            start: date(2026, 7, 17),
            end: date(2026, 7, 17, 1),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 17),
            occurrenceLocalComponents: nextOccurrenceStart,
            timeSemantics: .floating(
                start: nextOccurrenceStart,
                end: nextOccurrenceEnd
            )
        )
        XCTAssertEqual(
            try harness.store.resolve(event: nextOccurrence),
            .notFound
        )
    }

    func testAllDayOccurrenceUsesCivilAnchorAcrossRawDateChange() throws {
        let harness = try makeHarness()
        let start = localComponents(2026, 7, 10)
        let end = localComponents(2026, 7, 11)
        let first = makeEvent(
            id: "all-day-occurrence",
            start: date(2026, 7, 9, 15),
            end: date(2026, 7, 10, 15).addingTimeInterval(-1),
            externalIdentifier: "all-day-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 9, 15),
            occurrenceLocalComponents: start,
            isAllDay: true,
            timeSemantics: .allDay(start: start, endExclusive: end)
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: first, notes: "All-day civil")
        )
        let sameCivilDate = makeEvent(
            id: "all-day-occurrence",
            start: date(2026, 7, 10, 7),
            end: date(2026, 7, 11, 7).addingTimeInterval(-1),
            externalIdentifier: "all-day-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 7),
            occurrenceLocalComponents: start,
            isAllDay: true,
            timeSemantics: .allDay(start: start, endExclusive: end)
        )

        XCTAssertNotEqual(first.occurrenceDate, sameCivilDate.occurrenceDate)
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: sameCivilDate)),
            context.id
        )
    }

    func testFingerprintIsNormalizedAndNeverAutoLinks() throws {
        let harness = try makeHarness()
        let original = makeEvent(
            id: "fingerprint",
            title: "Téam   Sync",
            location: "Room Ａ"
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Keep")
        )
        let changedIdentifiers = makeEvent(
            id: "different",
            title: " team sync ",
            location: "room a",
            includeIdentifiers: false
        )

        let originalFingerprint = EventIdentityFingerprint.make(event: original)
        let changedFingerprint = EventIdentityFingerprint.make(
            event: changedIdentifiers
        )
        XCTAssertEqual(originalFingerprint, changedFingerprint)
        XCTAssertEqual(
            originalFingerprint,
            "v1:f1a3dcf23724448190fa8ce0a40fdad3d877bde91067e5f0b180f902c39d428a"
        )
        XCTAssertTrue(originalFingerprint.hasPrefix("v1:"))
        XCTAssertEqual(originalFingerprint.count, 67)
        XCTAssertEqual(
            try harness.store.resolve(event: changedIdentifiers),
            .candidate(contextIDs: [context.id], basis: .fingerprint)
        )
        XCTAssertThrowsError(
            try harness.store.saveNotes(
                for: changedIdentifiers,
                notes: "Must confirm"
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .identityConfirmationRequired([context.id])
            )
        }
    }

    func testSeriesIdentitySkipsEmptyIdentifiers() throws {
        let fallbackEvent = makeEvent(
            id: "series-fallback",
            externalIdentifier: "",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let fallbackSnapshot = try EventLinkSnapshot(event: fallbackEvent)

        XCTAssertEqual(
            fallbackSnapshot.recurrenceSeriesIdentifier,
            "item-id-series-fallback"
        )
        XCTAssertNotNil(fallbackSnapshot.seriesFingerprint)

        let noSeriesIdentifier = makeEvent(
            id: "series-missing",
            externalIdentifier: "",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            includeIdentifiers: false
        )
        let missingSnapshot = try EventLinkSnapshot(
            event: noSeriesIdentifier
        )

        XCTAssertNil(missingSnapshot.recurrenceSeriesIdentifier)
        XCTAssertNil(missingSnapshot.seriesFingerprint)
    }

    func testFileBackedDatabaseReopensWithAllPhaseThreeData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaosCal-ContextStore-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("kaoscal.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let event = makeEvent(id: "persistent")
        let floatingStart = localComponents(2026, 7, 11, 9)
        let floatingEnd = localComponents(2026, 7, 11, 10)
        let floatingEvent = makeEvent(
            id: "persistent-floating",
            title: "Persistent floating event",
            timeSemantics: .floating(
                start: floatingStart,
                end: floatingEnd
            )
        )
        let allDayStart = localComponents(2026, 7, 12)
        let allDayEnd = localComponents(2026, 7, 13)
        let allDayEvent = makeEvent(
            id: "persistent-all-day",
            start: date(2026, 7, 12),
            end: date(2026, 7, 13).addingTimeInterval(-1),
            externalIdentifier: "persistent-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 12),
            occurrenceLocalComponents: allDayStart,
            isAllDay: true,
            timeSemantics: .allDay(
                start: allDayStart,
                endExclusive: allDayEnd
            )
        )
        var contextID = ""
        var eventTaskID = ""
        var floatingContextID = ""
        var floatingTaskID = ""
        var allDayContextID = ""
        var personalTaskID = ""

        do {
            let database = try AppDatabase.open(at: databaseURL)
            let IDs = IDSequence([
                "context", "link", "event-task", "personal-task"
            ])
            let store = ContextStore(
                database: database,
                now: { self.date(2026, 7, 10, 12) },
                makeID: IDs.next
            )
            let context = try XCTUnwrap(
                store.saveNotes(for: event, notes: "Persistent notes")
            )
            let eventTask = try store.addEventTask(
                for: event,
                section: .after,
                title: "Persistent event task",
                sortOrder: 0,
                due: .relative(anchor: .afterEnd, offsetMinutes: 45)
            )
            _ = try store.eventTasks.setCompleted(
                id: eventTask.id,
                isCompleted: true
            )
            let floatingContext = try XCTUnwrap(
                store.saveNotes(
                    for: floatingEvent,
                    notes: "Floating notes"
                )
            )
            let floatingTask = try store.addEventTask(
                for: floatingEvent,
                section: .before,
                title: "Persistent fixed task",
                sortOrder: 0,
                due: .fixed(date(2026, 7, 11, 8, 30))
            )
            let allDayContext = try XCTUnwrap(
                store.saveNotes(
                    for: allDayEvent,
                    notes: "All-day recurring notes"
                )
            )
            let personalTask = try store.personalTasks.create(
                title: "Persistent personal task",
                dueAt: date(2026, 7, 10, 18)
            )
            _ = try store.personalTasks.setCompleted(
                id: personalTask.id,
                isCompleted: true
            )
            contextID = context.id
            eventTaskID = eventTask.id
            floatingContextID = floatingContext.id
            floatingTaskID = floatingTask.id
            allDayContextID = allDayContext.id
            personalTaskID = personalTask.id
        }

        do {
            let database = try AppDatabase.open(at: databaseURL)
            let store = ContextStore(database: database)
            let brief = try XCTUnwrap(
                store.eventContexts.fetchBrief(contextID: contextID)
            )
            let floatingBrief = try XCTUnwrap(
                store.eventContexts.fetchBrief(contextID: floatingContextID)
            )
            let allDayBrief = try XCTUnwrap(
                store.eventContexts.fetchBrief(contextID: allDayContextID)
            )

            XCTAssertEqual(
                try database.appliedMigrations(),
                ["v1_context_store", "v2_event_change_log"]
            )
            XCTAssertEqual(brief.context.notes, "Persistent notes")
            XCTAssertEqual(brief.tasks.map(\.id), [eventTaskID])
            XCTAssertTrue(try XCTUnwrap(brief.tasks.first).isCompleted)
            XCTAssertEqual(
                try XCTUnwrap(brief.tasks.first).due,
                .relative(anchor: .afterEnd, offsetMinutes: 45)
            )
            XCTAssertEqual(
                floatingBrief.tasks.map(\.id),
                [floatingTaskID]
            )
            XCTAssertEqual(
                try XCTUnwrap(floatingBrief.tasks.first).due,
                .fixed(date(2026, 7, 11, 8, 30))
            )
            XCTAssertEqual(floatingBrief.link.timeSemantics, .floating)
            XCTAssertNotNil(floatingBrief.link.startLocalComponents)
            XCTAssertEqual(allDayBrief.link.timeSemantics, .allDay)
            XCTAssertTrue(allDayBrief.link.isRecurring)
            XCTAssertNotNil(allDayBrief.link.occurrenceLocalComponents)
            XCTAssertTrue(
                allDayBrief.link.occurrenceIdentityKey
                    .hasPrefix("local:v1:")
            )
            XCTAssertEqual(
                try store.personalTasks.fetch(id: personalTaskID)?.title,
                "Persistent personal task"
            )
            XCTAssertTrue(
                try XCTUnwrap(
                    store.personalTasks.fetch(id: personalTaskID)
                ).isCompleted
            )
            XCTAssertEqual(
                try linkedContextID(store.resolve(event: event)),
                contextID
            )
            let storage = try database.read { db in
                try XCTUnwrap(Row.fetchOne(db, sql: """
                    SELECT
                        typeof(created_at) AS created_type,
                        created_at AS created_value
                    FROM event_contexts
                    WHERE id = ?
                    """, arguments: [contextID]))
            }
            XCTAssertEqual(storage["created_type"] as String?, "text")
            XCTAssertEqual(
                storage["created_value"] as String?,
                "2026-07-10 12:00:00.000"
            )
            let matchingCreationDates = try database.read { db in
                try EventContext
                    .filter(Column("created_at") == date(2026, 7, 10, 12))
                    .fetchCount(db)
            }
            XCTAssertEqual(matchingCreationDates, 3)
            let completedItems = try store.taskCenter.fetch(
                list: .completed,
                now: date(2026, 7, 10, 12),
                calendar: testCalendar
            )
            XCTAssertEqual(
                Set(completedItems.map(\.id)),
                Set([
                    .eventTask(
                        taskID: eventTaskID,
                        contextID: contextID
                    ),
                    .personalTask(taskID: personalTaskID)
                ])
            )
        }
    }

    private struct Harness {
        let store: ContextStore
        let now: Date
    }

    private func makeHarness() throws -> Harness {
        let now = date(2026, 7, 10, 12)
        let IDs = IDSequence((1...100).map { "id-\($0)" })
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { now },
            makeID: IDs.next
        )
        return Harness(store: store, now: now)
    }

    private func linkedContextID(
        _ resolution: EventContextResolution
    ) throws -> String {
        guard case let .linked(contextID, _) = resolution else {
            throw TestError.expectedLinkedContext
        }
        return contextID
    }

    private enum TestError: Error {
        case expectedLinkedContext
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        testCalendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func localComponents(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> LocalDateTimeComponents {
        LocalDateTimeComponents(
            date: date(year, month, day, hour, minute),
            calendar: testCalendar
        )
    }

    private func makeEvent(
        id: String,
        title: String = "Team Sync",
        location: String? = "Room A",
        start: Date? = nil,
        end: Date? = nil,
        externalIdentifier: String? = nil,
        calendarIdentifier: String = "calendar",
        isRecurring: Bool = false,
        occurrenceDate: Date? = nil,
        occurrenceLocalComponents: LocalDateTimeComponents? = nil,
        isDetached: Bool = false,
        includeIdentifiers: Bool = true,
        isAllDay: Bool = false,
        timeSemantics: EventTimeSemantics? = nil
    ) -> DisplayEvent {
        let start = start ?? date(2026, 7, 10, 9)
        let end = end ?? date(2026, 7, 10, 10)
        let timeSemantics = timeSemantics
            ?? .zoned(timeZoneIdentifier: "UTC")
        let timeZoneIdentifier: String?
        switch timeSemantics {
        case let .zoned(identifier):
            timeZoneIdentifier = identifier
        case .allDay, .floating:
            timeZoneIdentifier = nil
        }
        return DisplayEvent(
            id: id,
            eventIdentifier: includeIdentifiers ? "event-id-\(id)" : nil,
            calendarItemIdentifier: includeIdentifiers ? "item-id-\(id)" : nil,
            calendarItemExternalIdentifier: externalIdentifier,
            calendarIdentifier: calendarIdentifier,
            calendarTitle: "KAOS-TEST",
            sourceTitle: "Work",
            accountType: .exchange,
            calendarColor: nil,
            title: title,
            location: location,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            timeSemantics: timeSemantics,
            isRecurring: isRecurring,
            occurrenceDate: occurrenceDate,
            occurrenceLocalComponents: occurrenceLocalComponents,
            isDetached: isDetached,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil
        )
    }
}

private final class IDSequence {
    private var values: [String]
    private var fallback = 0

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        if !values.isEmpty {
            return values.removeFirst()
        }
        fallback += 1
        return "fallback-\(fallback)"
    }
}
