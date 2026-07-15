import Foundation
import GRDB
import XCTest
@testable import KaosCal

final class CalendarClarityTests: XCTestCase {
    func testRoleInferenceDescriptorAndVirtualSetsAreConservative() {
        let exchange = makeSource(
            id: "exchange",
            accountType: .exchange
        )
        let subscribed = makeSource(
            id: "subscribed",
            accountType: .subscribed,
            isWritable: false
        )
        let birthdays = makeSource(
            id: "birthdays",
            accountType: .birthdays,
            isWritable: false
        )

        XCTAssertEqual(CalendarRole.inferred(for: exchange), .other)
        XCTAssertEqual(CalendarRole.inferred(for: subscribed), .subscription)
        XCTAssertEqual(CalendarRole.inferred(for: birthdays), .subscription)

        let inferred = CalendarDescriptor(
            source: exchange,
            explicitRole: nil
        )
        XCTAssertEqual(inferred.role, .other)
        XCTAssertFalse(inferred.isRoleExplicit)

        let explicit = CalendarDescriptor(
            source: exchange,
            explicitRole: .work
        )
        XCTAssertEqual(explicit.id, exchange.id)
        XCTAssertEqual(explicit.role, .work)
        XCTAssertTrue(explicit.isRoleExplicit)

        for role in CalendarRole.allCases {
            XCTAssertTrue(CalendarSetFilter.all.includes(role: role))
            let roleFilter = CalendarSetFilter.role(role)
            XCTAssertEqual(roleFilter.id, "role:\(role.rawValue)")
            XCTAssertEqual(roleFilter.title, role.title)
            XCTAssertEqual(roleFilter.symbolName, role.symbolName)
            XCTAssertTrue(roleFilter.includes(role: role))
            XCTAssertTrue(CalendarSetFilter.allCases.contains(roleFilter))
        }
        XCTAssertTrue(CalendarSetFilter.work.includes(role: .work))
        XCTAssertFalse(CalendarSetFilter.work.includes(role: .personal))
        XCTAssertEqual(
            CalendarSetFilter.subscription.symbolName,
            CalendarRole.subscription.symbolName
        )
        XCTAssertEqual(
            CalendarSetFilter.allCases,
            [.all, .work, .personal, .family, .shared, .subscription, .other]
        )
    }

    func testCalendarSetSelectionIdentityAndSavedIdentifierValidation() {
        XCTAssertEqual(CalendarSetFilter.all.id, "all")
        XCTAssertEqual(CalendarSetFilter.work, .role(.work))
        XCTAssertEqual(CalendarSetFilter.work.id, "role:work")
        XCTAssertEqual(CalendarSetFilter.work.title, CalendarRole.work.title)

        let saved = CalendarSetFilter(savedSetIdentifier: "  set-123  ")
        XCTAssertEqual(saved, .saved("set-123"))
        XCTAssertEqual(saved?.id, "saved:set-123")
        XCTAssertEqual(saved?.title, "Saved Set")
        XCTAssertEqual(saved?.symbolName, "calendar.badge.checkmark")
        XCTAssertEqual(saved?.savedSetIdentifier, "set-123")
        XCTAssertFalse(saved?.includes(role: .work) ?? true)

        XCTAssertNil(CalendarSetFilter(savedSetIdentifier: ""))
        XCTAssertNil(CalendarSetFilter(savedSetIdentifier: " \n\t "))
        XCTAssertNil(CalendarSetFilter.all.savedSetIdentifier)
        XCTAssertNil(CalendarSetFilter.role(.personal).savedSetIdentifier)
    }

    func testCalendarUsageDefaultsAreConservativeAndIndependent() {
        let exchange = makeSource(id: "exchange")
        let subscribed = makeSource(
            id: "subscribed",
            accountType: .subscribed,
            isWritable: false
        )
        let birthdays = makeSource(
            id: "birthdays",
            accountType: .birthdays,
            isWritable: false
        )

        XCTAssertEqual(
            CalendarUsagePolicy.resolved(for: exchange, preference: nil),
            CalendarUsagePolicy(
                isVisible: true,
                blocksAvailability: true,
                isVisibilityExplicit: false,
                isBlockingExplicit: false
            )
        )
        XCTAssertTrue(
            CalendarUsagePolicy.resolved(
                for: subscribed,
                preference: nil
            ).isVisible
        )
        XCTAssertFalse(
            CalendarUsagePolicy.resolved(
                for: subscribed,
                preference: nil
            ).blocksAvailability
        )
        XCTAssertFalse(
            CalendarUsagePolicy.resolved(
                for: birthdays,
                preference: nil
            ).blocksAvailability
        )
    }

    func testWriteRestrictionUsesSafePrecedenceAndDoesNotGuessACLReason() {
        let baseline = makeEvent(
            id: "restriction",
            calendarIdentifier: "calendar",
            accountType: .subscribed,
            isReadOnly: true,
            isInvitation: true,
            hasAttendees: true
        )

        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: baseline),
            .invitation
        )
        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: replacing(
                baseline,
                isInvitation: false
            )),
            .attendee
        )
        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: replacing(
                baseline,
                isInvitation: false,
                hasAttendees: false
            )),
            .subscribedCalendar
        )
        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: replacing(
                baseline,
                accountType: .birthdays,
                isInvitation: false,
                hasAttendees: false
            )),
            .birthdaysCalendar
        )
        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: replacing(
                baseline,
                accountType: .exchange,
                isInvitation: false,
                hasAttendees: false
            )),
            .providerReadOnly
        )
        XCTAssertNil(CalendarWriteRestriction.restriction(for: replacing(
            baseline,
            accountType: .exchange,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false
        )))
        XCTAssertEqual(
            CalendarWriteRestriction.providerReadOnly.message,
            "macOS Calendar reports this calendar as read-only. The local Event Brief remains editable."
        )

        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: makeSource(
                id: "unexpected-writable-subscription",
                accountType: .subscribed,
                isWritable: true
            )),
            .subscribedCalendar
        )
        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: makeSource(
                id: "unexpected-writable-birthdays",
                accountType: .birthdays,
                isWritable: true
            )),
            .birthdaysCalendar
        )
        XCTAssertNil(CalendarWriteRestriction.restriction(for: makeSource(
            id: "writable-exchange"
        )))
        XCTAssertEqual(
            CalendarWriteRestriction.restriction(for: makeSource(
                id: "viewer-exchange",
                isWritable: false
            )),
            .providerReadOnly
        )
    }

    func testTimedDuplicateCandidatesAreNormalizedBoundedAndDeterministic() {
        let target = makeEvent(
            id: "target",
            calendarIdentifier: "work",
            title: "Team Sync",
            start: date(2026, 7, 12, 9),
            end: date(2026, 7, 12, 10)
        )
        let boundary = makeEvent(
            id: "boundary",
            calendarIdentifier: "personal",
            title: "  TEAM--sync! ",
            start: date(2026, 7, 12, 9, 15),
            end: date(2026, 7, 12, 10, 15)
        )
        let exact = makeEvent(
            id: "exact",
            calendarIdentifier: "shared",
            title: "team sync",
            start: target.startDate,
            end: target.endDate
        )
        let outside = makeEvent(
            id: "outside",
            calendarIdentifier: "family",
            title: "Team Sync",
            start: date(2026, 7, 12, 9, 16),
            end: date(2026, 7, 12, 10, 16)
        )
        let sameCalendar = makeEvent(
            id: "same-calendar",
            calendarIdentifier: target.calendarIdentifier,
            title: "Team Sync",
            start: target.startDate,
            end: target.endDate
        )

        let candidates = CalendarDuplicateCandidateDetector.candidates(
            for: target,
            among: [outside, exact, sameCalendar, boundary, target],
            calendar: testCalendar
        )

        XCTAssertEqual(candidates.map(\.event.id), ["boundary", "exact"])
        XCTAssertEqual(
            Set(candidates.map(\.matchKind)),
            [.timedWithinTolerance]
        )

        let index = CalendarDuplicateCandidateDetector.candidateIndex(
            among: [outside, exact, sameCalendar, boundary, target],
            calendar: testCalendar
        )
        XCTAssertEqual(
            index[target.id]?.map(\.event.id),
            ["boundary", "exact"]
        )
        XCTAssertEqual(
            index[outside.id]?.map(\.event.id),
            ["boundary"]
        )
    }

    func testDuplicateDetectorExcludesSameStrongOccurrence() {
        let target = makeEvent(
            id: "first-copy",
            calendarIdentifier: "work",
            title: "Review",
            start: date(2026, 7, 12, 9),
            end: date(2026, 7, 12, 10),
            strongIdentifier: "same-item"
        )
        let sameUnderlying = makeEvent(
            id: "second-copy",
            calendarIdentifier: "personal",
            title: "Review",
            start: target.startDate,
            end: target.endDate,
            strongIdentifier: "same-item"
        )
        let independent = makeEvent(
            id: "independent",
            calendarIdentifier: "shared",
            title: "Review",
            start: target.startDate,
            end: target.endDate,
            strongIdentifier: "different-item"
        )

        XCTAssertEqual(
            CalendarDuplicateCandidateDetector.candidates(
                for: target,
                among: [sameUnderlying, independent],
                calendar: testCalendar
            ).map(\.event.id),
            ["independent"]
        )
    }

    func testAllDayDuplicateUsesCivilExclusiveRange() {
        let target = makeEvent(
            id: "all-day",
            calendarIdentifier: "work",
            title: "Company Holiday",
            start: date(2026, 3, 8),
            end: date(2026, 3, 9),
            isAllDay: true
        )
        let sameRange = makeEvent(
            id: "same-range",
            calendarIdentifier: "subscription",
            title: "company holiday",
            start: date(2026, 3, 8),
            end: date(2026, 3, 9),
            isAllDay: true
        )
        let longer = makeEvent(
            id: "longer",
            calendarIdentifier: "shared",
            title: "Company Holiday",
            start: date(2026, 3, 8),
            end: date(2026, 3, 10),
            isAllDay: true
        )
        let timed = makeEvent(
            id: "timed",
            calendarIdentifier: "personal",
            title: "Company Holiday",
            start: date(2026, 3, 8),
            end: date(2026, 3, 9)
        )

        let candidates = CalendarDuplicateCandidateDetector.candidates(
            for: target,
            among: [timed, longer, sameRange],
            calendar: testCalendar
        )
        XCTAssertEqual(candidates.map(\.event.id), ["same-range"])
        XCTAssertEqual(candidates.first?.matchKind, .sameAllDayRange)
    }

    func testV3MigrationIsSparseAndPreservesV1V2Rows() throws {
        let queue = try DatabaseQueue()
        try DatabaseMigrations.migrator.migrate(
            queue,
            upTo: "v2_event_change_log"
        )
        let timestamp = "2026-07-12 09:00:00.000"
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO event_contexts (
                        id, title_snapshot, start_snapshot, end_snapshot,
                        lifecycle_status, notes, created_at, updated_at
                    ) VALUES (
                        'context', 'Fixture', ?, ?, 'scheduled',
                        'Keep me', ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp, timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_links (
                        id, context_id, event_identifier,
                        calendar_identifier, source_title,
                        calendar_title_snapshot, title_snapshot,
                        start_snapshot, end_snapshot, is_all_day,
                        is_recurring, time_semantics, time_zone_identifier,
                        occurrence_identity_key, is_detached, fingerprint,
                        link_status, last_seen_at, created_at, updated_at
                    ) VALUES (
                        'link', 'context', 'event', 'calendar', 'Source',
                        'Calendar', 'Fixture', ?, ?, 0, 0, 'zoned',
                        'Asia/Seoul', 'single:v1', 0, 'fingerprint',
                        'active', ?, ?, ?
                    )
                    """,
                arguments: [
                    timestamp, timestamp, timestamp, timestamp, timestamp
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_tasks (
                        id, context_id, section, title, completed,
                        sort_order, due_kind, created_at, updated_at
                    ) VALUES (
                        'event-task', 'context', 'before', 'Keep task',
                        0, 0, 'none', ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO personal_tasks (
                        id, title, notes, completed, sort_order,
                        created_at, updated_at
                    ) VALUES (
                        'personal-task', 'Keep personal', 'Keep notes',
                        0, 0, ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_change_log (
                        id, context_id, change_type, scope,
                        before_payload, after_payload, undo_state,
                        created_at
                    ) VALUES (
                        'change', 'context', 'details_updated', 'single',
                        '{"before":true}', '{"after":true}',
                        'unavailable', ?
                    )
                    """,
                arguments: [timestamp]
            )
        }

        let before = try legacyRows(in: queue)
        let database = try AppDatabase(queue)

        XCTAssertEqual(try legacyRows(in: queue), before)
        XCTAssertEqual(
            try database.appliedMigrations(),
            [
                "v1_context_store",
                "v2_event_change_log",
                "v3_calendar_clarity",
                "v4_task_provider",
                "v5_oauth_task_providers",
                "v6_context_references",
                "v7_microsoft_to_do_provider",
                "v8_calendar_usage",
                "v9_saved_calendar_sets"
            ]
        )
        XCTAssertEqual(
            try database.read { db in
                try CalendarRolePreference.fetchCount(db)
            },
            0
        )
        XCTAssertEqual(
            try database.read { db in
                try CalendarUsagePreference.fetchCount(db)
            },
            0
        )
        XCTAssertThrowsError(try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO calendar_preferences (
                        calendar_identifier, source_title_snapshot,
                        calendar_title_snapshot, role, created_at, updated_at
                    ) VALUES ('bad', 'Source', 'Calendar', 'invalid', ?, ?)
                    """,
                arguments: [timestamp, timestamp]
            )
        })
        XCTAssertThrowsError(try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO calendar_usage_preferences (
                        calendar_identifier, source_identifier_snapshot,
                        source_title_snapshot, calendar_title_snapshot,
                        visibility_override, blocking_override,
                        created_at, updated_at
                    ) VALUES (
                        'empty', 'source', 'Source', 'Calendar',
                        NULL, NULL, ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp]
            )
        })
    }

    func testRoleRepositoryUpsertsReopensDeletesAndResets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("clarity.sqlite")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        var current = date(2026, 7, 12, 9)
        let source = makeSource(id: "calendar")

        do {
            let store = ContextStore(
                database: try AppDatabase.open(at: databaseURL),
                now: { current }
            )
            XCTAssertEqual(try store.calendarRoles.count(), 0)

            let created = try store.calendarRoles.upsert(
                source: source,
                role: .work
            )
            XCTAssertEqual(created.role, .work)
            XCTAssertEqual(created.calendarTitleSnapshot, source.title)
            XCTAssertEqual(created.createdAt, current)
            XCTAssertEqual(created.updatedAt, current)
            XCTAssertEqual(try store.calendarRoles.count(), 1)

            current = date(2026, 7, 12, 10)
            let renamed = makeSource(
                id: source.id,
                title: "Renamed Calendar",
                sourceTitle: "Renamed Source"
            )
            let updated = try store.calendarRoles.upsert(
                source: renamed,
                role: .personal
            )
            XCTAssertEqual(updated.role, .personal)
            XCTAssertEqual(updated.createdAt, created.createdAt)
            XCTAssertEqual(updated.updatedAt, current)
            XCTAssertEqual(updated.calendarTitleSnapshot, "Renamed Calendar")
        }

        do {
            let store = ContextStore(
                database: try AppDatabase.open(at: databaseURL)
            )
            let reopened = try XCTUnwrap(
                store.calendarRoles.fetch(calendarIdentifier: source.id)
            )
            XCTAssertEqual(reopened.role, .personal)
            XCTAssertEqual(try store.calendarRoles.fetchAll(), [reopened])
            XCTAssertTrue(try store.calendarRoles.delete(
                calendarIdentifier: source.id
            ))
            XCTAssertFalse(try store.calendarRoles.delete(
                calendarIdentifier: source.id
            ))

            _ = try store.calendarRoles.upsert(source: source, role: .family)
            _ = try store.calendarRoles.upsert(
                source: makeSource(id: "second"),
                role: .shared
            )
            XCTAssertEqual(try store.calendarRoles.reset(), 2)
            XCTAssertEqual(try store.calendarRoles.count(), 0)
        }
    }

    func testUsageRepositoryKeepsIndependentSparseOverrides() throws {
        let database = try AppDatabase.inMemory()
        let store = ContextStore(
            database: database,
            now: { self.date(2026, 7, 12, 9) }
        )
        let source = makeSource(
            id: "calendar",
            title: "Focus",
            sourceTitle: "Work",
            sourceIdentifier: "work-source"
        )

        try store.calendarUsage.setVisibility(false, for: [source])
        var preference = try XCTUnwrap(
            store.calendarUsage.fetch(calendarIdentifier: source.id)
        )
        XCTAssertEqual(preference.visibilityOverride, false)
        XCTAssertNil(preference.blockingOverride)
        XCTAssertEqual(preference.sourceIdentifierSnapshot, "work-source")

        try store.calendarUsage.setBlocksAvailability(false, for: [source])
        preference = try XCTUnwrap(
            store.calendarUsage.fetch(calendarIdentifier: source.id)
        )
        XCTAssertEqual(preference.visibilityOverride, false)
        XCTAssertEqual(preference.blockingOverride, false)

        try store.calendarUsage.setVisibility(nil, for: [source])
        preference = try XCTUnwrap(
            store.calendarUsage.fetch(calendarIdentifier: source.id)
        )
        XCTAssertNil(preference.visibilityOverride)
        XCTAssertEqual(preference.blockingOverride, false)

        try store.calendarUsage.setBlocksAvailability(nil, for: [source])
        XCTAssertNil(try store.calendarUsage.fetch(
            calendarIdentifier: source.id
        ))
        XCTAssertEqual(try store.calendarUsage.count(), 0)
    }

    private func legacyRows(
        in queue: DatabaseQueue
    ) throws -> [String] {
        try queue.read { db in
            try [
                String.fetchOne(
                    db,
                    sql: "SELECT notes FROM event_contexts WHERE id = 'context'"
                ),
                String.fetchOne(
                    db,
                    sql: "SELECT fingerprint FROM event_links WHERE id = 'link'"
                ),
                String.fetchOne(
                    db,
                    sql: "SELECT title FROM event_tasks WHERE id = 'event-task'"
                ),
                String.fetchOne(
                    db,
                    sql: "SELECT notes FROM personal_tasks WHERE id = 'personal-task'"
                ),
                String.fetchOne(
                    db,
                    sql: "SELECT before_payload FROM event_change_log WHERE id = 'change'"
                )
            ].compactMap { $0 }
        }
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        testCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func makeSource(
        id: String,
        title: String = "Calendar",
        sourceTitle: String = "Source",
        sourceIdentifier: String = "source",
        accountType: CalendarAccountType = .exchange,
        isWritable: Bool = true
    ) -> CalendarSource {
        CalendarSource(
            id: id,
            title: title,
            sourceTitle: sourceTitle,
            sourceIdentifier: sourceIdentifier,
            accountType: accountType,
            isWritable: isWritable,
            color: nil
        )
    }

    private func makeEvent(
        id: String,
        calendarIdentifier: String,
        title: String = "Fixture",
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        accountType: CalendarAccountType = .exchange,
        isReadOnly: Bool = false,
        isInvitation: Bool = false,
        hasAttendees: Bool = false,
        strongIdentifier: String? = nil
    ) -> DisplayEvent {
        let start = start ?? date(2026, 7, 12, 9)
        let end = end ?? date(2026, 7, 12, 10)
        let timeSemantics: EventTimeSemantics = isAllDay
            ? .allDay(
                start: LocalDateTimeComponents(
                    date: start,
                    calendar: testCalendar
                ),
                endExclusive: LocalDateTimeComponents(
                    date: end,
                    calendar: testCalendar
                )
            )
            : .zoned(timeZoneIdentifier: testCalendar.timeZone.identifier)
        return DisplayEvent(
            id: id,
            eventIdentifier: strongIdentifier,
            calendarItemIdentifier: nil,
            calendarItemExternalIdentifier: nil,
            calendarIdentifier: calendarIdentifier,
            calendarTitle: calendarIdentifier,
            sourceTitle: "Source",
            accountType: accountType,
            calendarColor: nil,
            title: title,
            location: nil,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            timeZoneIdentifier: isAllDay
                ? nil
                : testCalendar.timeZone.identifier,
            timeSemantics: timeSemantics,
            isRecurring: false,
            occurrenceDate: nil,
            occurrenceLocalComponents: nil,
            isDetached: false,
            isReadOnly: isReadOnly,
            isInvitation: isInvitation,
            hasAttendees: hasAttendees,
            originalNotes: nil,
            recurrence: .none
        )
    }

    private func replacing(
        _ event: DisplayEvent,
        accountType: CalendarAccountType? = nil,
        isReadOnly: Bool? = nil,
        isInvitation: Bool? = nil,
        hasAttendees: Bool? = nil
    ) -> DisplayEvent {
        DisplayEvent(
            id: event.id,
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarItemExternalIdentifier:
                event.calendarItemExternalIdentifier,
            calendarIdentifier: event.calendarIdentifier,
            calendarTitle: event.calendarTitle,
            sourceTitle: event.sourceTitle,
            accountType: accountType ?? event.accountType,
            calendarColor: event.calendarColor,
            title: event.title,
            location: event.location,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZoneIdentifier,
            timeSemantics: event.timeSemantics,
            isRecurring: event.isRecurring,
            occurrenceDate: event.occurrenceDate,
            occurrenceLocalComponents: event.occurrenceLocalComponents,
            isDetached: event.isDetached,
            isReadOnly: isReadOnly ?? event.isReadOnly,
            isInvitation: isInvitation ?? event.isInvitation,
            hasAttendees: hasAttendees ?? event.hasAttendees,
            originalNotes: event.originalNotes,
            recurrence: event.recurrence
        )
    }
}
