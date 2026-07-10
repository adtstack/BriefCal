import XCTest
@testable import KaosCal

@MainActor
final class CalendarEventEditingTests: XCTestCase {
    func testValidationTrimsFieldsAndRejectsInvalidValues() throws {
        let draft = CalendarEventDraft(
            title: "  Planning  ",
            calendarIdentifier: "  calendar  ",
            startDate: date(2026, 7, 10, 9),
            endDate: date(2026, 7, 10, 10),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Seoul",
            referenceTimeZoneIdentifier: calendar.timeZone.identifier,
            location: "  Room A  ",
            originalNotes: "Original note"
        )

        let validated = try draft.validated(calendar: calendar)

        XCTAssertEqual(validated.title, "Planning")
        XCTAssertEqual(validated.calendarIdentifier, "calendar")
        XCTAssertEqual(validated.location, "Room A")
        XCTAssertThrowsError(try CalendarEventDraft(
            title: "   ",
            calendarIdentifier: "calendar",
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: false,
            timeZoneIdentifier: "UTC",
            referenceTimeZoneIdentifier: calendar.timeZone.identifier
        ).validated(calendar: calendar)) { error in
            XCTAssertEqual(error as? CalendarEventWriteError, .emptyTitle)
        }
        XCTAssertThrowsError(try CalendarEventDraft(
            title: "Invalid range",
            calendarIdentifier: "calendar",
            startDate: draft.endDate,
            endDate: draft.startDate,
            isAllDay: false,
            timeZoneIdentifier: "UTC",
            referenceTimeZoneIdentifier: calendar.timeZone.identifier
        ).validated(calendar: calendar)) { error in
            XCTAssertEqual(error as? CalendarEventWriteError, .invalidDateRange)
        }
        XCTAssertThrowsError(try CalendarEventDraft(
            title: "Invalid zone",
            calendarIdentifier: "calendar",
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: false,
            timeZoneIdentifier: "Mars/Olympus",
            referenceTimeZoneIdentifier: calendar.timeZone.identifier
        ).validated(calendar: calendar)) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .invalidTimeZone("Mars/Olympus")
            )
        }
    }

    func testAllDayValidationUsesExclusiveEndAndNoTimeZone() throws {
        let draft = CalendarEventDraft(
            title: "Conference",
            calendarIdentifier: "calendar",
            startDate: date(2026, 7, 10, 13),
            endDate: date(2026, 7, 11, 18),
            isAllDay: true,
            timeZoneIdentifier: "Asia/Seoul",
            referenceTimeZoneIdentifier: calendar.timeZone.identifier
        )

        let validated = try draft.validated(calendar: calendar)

        XCTAssertEqual(validated.startDate, date(2026, 7, 10))
        XCTAssertEqual(validated.endDate, date(2026, 7, 12))
        XCTAssertNil(validated.timeZoneIdentifier)
    }

    func testPreserveInstantChangesZoneWithoutChangingDates() throws {
        let draft = timedDraft(timeZoneIdentifier: "Asia/Seoul")

        let changed = try draft.changingTimeZone(
            to: "America/New_York",
            behavior: .preserveInstant,
            displayCalendar: calendar
        )

        XCTAssertEqual(changed.startDate, draft.startDate)
        XCTAssertEqual(changed.endDate, draft.endDate)
        XCTAssertEqual(changed.timeZoneIdentifier, "America/New_York")
    }

    func testPreserveLocalTimeReinterpretsTheSameWallClock() throws {
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let draft = CalendarEventDraft(
            title: "Cross-zone",
            calendarIdentifier: "calendar",
            startDate: seoul.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 10,
                hour: 9
            ))!,
            endDate: seoul.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 10,
                hour: 10
            ))!,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Seoul",
            referenceTimeZoneIdentifier: seoul.timeZone.identifier
        )

        let changed = try draft.changingTimeZone(
            to: "America/New_York",
            behavior: .preserveLocalTime,
            displayCalendar: seoul
        )
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let components = newYork.dateComponents(
            [.year, .month, .day, .hour],
            from: changed.startDate
        )

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(
            changed.endDate.timeIntervalSince(changed.startDate),
            3_600,
            accuracy: 0.001
        )
    }

    func testAllDayToggleProducesOneHourTimedDraft() {
        let allDay = CalendarEventDraft(
            title: "All day",
            calendarIdentifier: "calendar",
            startDate: date(2026, 7, 10),
            endDate: date(2026, 7, 11),
            isAllDay: true,
            timeZoneIdentifier: nil,
            referenceTimeZoneIdentifier: calendar.timeZone.identifier
        )

        let timed = allDay.changingAllDay(to: false, calendar: calendar)

        XCTAssertFalse(timed.isAllDay)
        XCTAssertEqual(timed.startDate, date(2026, 7, 10, 9))
        XCTAssertEqual(timed.endDate, date(2026, 7, 10, 10))
        XCTAssertEqual(timed.timeZoneIdentifier, calendar.timeZone.identifier)
    }

    func testTimedEventEndingAtMidnightDoesNotGainAnExtraAllDayDate() {
        let timed = CalendarEventDraft(
            title: "Late work",
            calendarIdentifier: "calendar",
            startDate: date(2026, 7, 10, 23),
            endDate: date(2026, 7, 11),
            isAllDay: false,
            timeZoneIdentifier: "GMT",
            referenceTimeZoneIdentifier: calendar.timeZone.identifier
        )

        let allDay = timed.changingAllDay(to: true, calendar: calendar)

        XCTAssertEqual(allDay.startDate, date(2026, 7, 10))
        XCTAssertEqual(allDay.endDate, date(2026, 7, 11))
    }

    func testPreserveLocalTimeRejectsNonexistentDSTTime() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = utc.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 2,
            minute: 30
        ))!
        let draft = CalendarEventDraft(
            title: "DST gap",
            calendarIdentifier: "calendar",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: "GMT",
            referenceTimeZoneIdentifier: "GMT"
        )

        XCTAssertThrowsError(try draft.changingTimeZone(
            to: "America/New_York",
            behavior: .preserveLocalTime,
            displayCalendar: utc
        )) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .nonexistentLocalTime("America/New_York")
            )
        }
    }

    func testPreserveLocalTimeRejectsAmbiguousDSTTime() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = utc.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1,
            hour: 1,
            minute: 30
        ))!
        let draft = CalendarEventDraft(
            title: "DST overlap",
            calendarIdentifier: "calendar",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: "GMT",
            referenceTimeZoneIdentifier: "GMT"
        )

        XCTAssertThrowsError(try draft.changingTimeZone(
            to: "America/New_York",
            behavior: .preserveLocalTime,
            displayCalendar: utc
        )) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .ambiguousLocalTime("America/New_York")
            )
        }
    }

    func testCivilDraftsRebaseToCurrentZoneWithoutChangingWallTime() throws {
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let start = seoul.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10
        ))!
        let end = seoul.date(byAdding: .day, value: 1, to: start)!
        let allDayDraft = CalendarEventDraft(
            title: "Civil date",
            calendarIdentifier: "calendar",
            startDate: start,
            endDate: end,
            isAllDay: true,
            timeZoneIdentifier: nil,
            referenceTimeZoneIdentifier: seoul.timeZone.identifier
        )
        let floatingStart = seoul.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10,
            hour: 9
        ))!
        let floatingDraft = CalendarEventDraft(
            title: "Floating civil time",
            calendarIdentifier: "calendar",
            startDate: floatingStart,
            endDate: floatingStart.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: nil,
            referenceTimeZoneIdentifier: seoul.timeZone.identifier
        )

        let allDay = try allDayDraft.validated(calendar: newYork)
        let floating = try floatingDraft.validated(calendar: newYork)
        let allDayStart = newYork.dateComponents(
            [.year, .month, .day, .hour],
            from: allDay.startDate
        )
        let allDayEnd = newYork.dateComponents(
            [.year, .month, .day, .hour],
            from: allDay.endDate
        )
        let floatingStartComponents = newYork.dateComponents(
            [.year, .month, .day, .hour],
            from: floating.startDate
        )

        XCTAssertEqual(allDayStart.year, 2026)
        XCTAssertEqual(allDayStart.month, 7)
        XCTAssertEqual(allDayStart.day, 10)
        XCTAssertEqual(allDayStart.hour, 0)
        XCTAssertEqual(allDayEnd.day, 11)
        XCTAssertEqual(allDayEnd.hour, 0)
        XCTAssertEqual(
            allDay.referenceTimeZoneIdentifier,
            newYork.timeZone.identifier
        )
        XCTAssertEqual(floatingStartComponents.year, 2026)
        XCTAssertEqual(floatingStartComponents.month, 7)
        XCTAssertEqual(floatingStartComponents.day, 10)
        XCTAssertEqual(floatingStartComponents.hour, 9)
        XCTAssertEqual(
            floating.referenceTimeZoneIdentifier,
            newYork.timeZone.identifier
        )

        let civilStart = LocalDateTimeComponents(
            date: floatingStart,
            calendar: seoul
        )
        let civilEnd = LocalDateTimeComponents(
            date: floatingStart.addingTimeInterval(3_600),
            calendar: seoul
        )
        let beforeZoneChange = makeFloatingEvent(
            id: "floating-before-zone-change",
            rawStart: floatingStart,
            rawEnd: floatingStart.addingTimeInterval(3_600),
            civilStart: civilStart,
            civilEnd: civilEnd
        )
        let afterZoneChange = makeFloatingEvent(
            id: "floating-after-zone-change",
            rawStart: floating.startDate,
            rawEnd: floating.endDate,
            civilStart: civilStart,
            civilEnd: civilEnd
        )
        XCTAssertTrue(
            beforeZoneChange.hasSameEditableTime(as: afterZoneChange)
        )
    }

    func testAppStateCreatesInProviderDefaultExchangeCalendarAndFocusesReceipt() async throws {
        let provider = makeProvider()
        provider.calendars = [writableLocalCalendar, writableExchangeCalendar]
        provider.defaultNewEventCalendarIdentifier = writableExchangeCalendar.id
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()

        state.beginCreatingEvent()
        var draft = try XCTUnwrap(state.eventEditorSession?.initialDraft)
        XCTAssertEqual(draft.calendarIdentifier, writableExchangeCalendar.id)
        draft.title = "  Created through EventKit  "
        draft.location = "Room A"

        let didCreate = await state.saveEventEditor(draft)
        XCTAssertTrue(didCreate)
        XCTAssertEqual(provider.createCallCount, 1)
        XCTAssertEqual(provider.lastCreatedDraft?.title, "Created through EventKit")
        XCTAssertEqual(state.selectedSection, .day)
        XCTAssertEqual(state.selectedEvent?.title, "Created through EventKit")
        XCTAssertNil(state.eventEditorSession)
        XCTAssertNil(state.eventEditorError)
    }

    func testLinkedSameCalendarUpdateRebindsWithoutLosingLocalBrief() async throws {
        let original = makeEvent(id: "linked")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Local brief note")
        )
        let task = try store.appendEventTask(
            for: original,
            section: .before,
            title: "Prepare"
        )
        let provider = makeProvider(events: [original])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()

        guard case let .linked(contextID) = state.eventEditorSession?.mutationContext,
              contextID == context.id else {
            return XCTFail("Expected linked mutation context")
        }
        var draft = try XCTUnwrap(state.eventEditorSession?.initialDraft)
        draft.title = "Updated title"
        draft.startDate = draft.startDate.addingTimeInterval(7_200)
        draft.endDate = draft.endDate.addingTimeInterval(7_200)
        draft.originalNotes = "Calendar event note"

        let didUpdate = await state.saveEventEditor(draft)
        XCTAssertTrue(didUpdate)
        XCTAssertEqual(provider.updateCallCount, 1)
        let updated = try XCTUnwrap(provider.events.first)
        let target = try XCTUnwrap(
            store.navigationTarget(contextID: context.id)
        )
        XCTAssertEqual(target.link.startSnapshot, updated.startDate)
        guard case let .loaded(snapshot, _) = try store.loadBrief(for: updated) else {
            return XCTFail("Expected rebound Event Brief")
        }
        XCTAssertEqual(snapshot.context.id, context.id)
        XCTAssertEqual(snapshot.context.notes, "Local brief note")
        XCTAssertEqual(snapshot.tasks.map(\.id), [task.id])
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Prepare"])
    }

    func testLinkedCalendarMoveAndDeleteStopBeforeProviderWrite() async throws {
        let original = makeEvent(id: "linked-block")
        let store = ContextStore(database: try AppDatabase.inMemory())
        _ = try store.saveNotes(for: original, notes: "Keep this")
        let provider = makeProvider(events: [original])
        provider.calendars = [writableExchangeCalendar, writableLocalCalendar]
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession?.initialDraft)
        draft.calendarIdentifier = writableLocalCalendar.id

        let didMove = await state.saveEventEditor(draft)
        XCTAssertFalse(didMove)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError.linkedCalendarMoveDeferred
                .localizedDescription
        )

        let didDelete = await state.deleteEventEditorTarget()
        XCTAssertFalse(didDelete)
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError.linkedDeleteDeferred.localizedDescription
        )
    }

    func testUnlinkedCalendarMoveAndDeleteAreAllowed() async throws {
        let original = makeEvent(id: "unlinked")
        let provider = makeProvider(events: [original])
        provider.calendars = [writableExchangeCalendar, writableLocalCalendar]
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession?.initialDraft)
        draft.calendarIdentifier = writableLocalCalendar.id

        let didMove = await state.saveEventEditor(draft)
        XCTAssertTrue(didMove)
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertEqual(state.selectedEvent?.calendarIdentifier, writableLocalCalendar.id)

        state.beginEditingSelectedEvent()
        let didDelete = await state.deleteEventEditorTarget()
        XCTAssertTrue(didDelete)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertTrue(state.events.isEmpty)
        XCTAssertNil(state.selectedEvent)
    }

    func testProviderConflictKeepsEditorOpen() async throws {
        let original = makeEvent(id: "stale")
        let provider = makeProvider(events: [original])
        provider.updateEventHandler = { _, _ in
            throw CalendarEventWriteError.eventChangedExternally
        }
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        let session = try XCTUnwrap(state.eventEditorSession)
        var draft = session.initialDraft
        draft.title = "Would overwrite external change"

        let didSave = await state.saveEventEditor(draft)
        XCTAssertFalse(didSave)
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertEqual(state.eventEditorSession, session)
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError.eventChangedExternally.localizedDescription
        )
    }

    func testCalendarSaveWithLocalRebindCollisionReportsPartialSuccess() async throws {
        let original = makeEvent(id: "partial-original")
        let conflictingReceipt = makeEvent(id: "partial-conflict")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let originalContext = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Original local note")
        )
        let conflictingContext = try XCTUnwrap(
            store.saveNotes(
                for: conflictingReceipt,
                notes: "Conflicting local note"
            )
        )
        let provider = makeProvider(events: [original])
        provider.updateEventHandler = { _, _ in conflictingReceipt }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        let originalBefore = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: originalContext.id)
        )
        let conflictBefore = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: conflictingContext.id)
        )
        var draft = try XCTUnwrap(state.eventEditorSession?.initialDraft)
        draft.title = "Calendar side saved"

        let didSave = await state.saveEventEditor(draft)

        XCTAssertFalse(didSave)
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertTrue(
            state.eventEditorError?.hasPrefix(
                "The calendar event was saved, but its local Event Brief could not be refreshed."
            ) == true
        )
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: originalContext.id),
            originalBefore
        )
        let conflictAfter = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: conflictingContext.id)
        )
        XCTAssertEqual(conflictAfter.context.notes, conflictBefore.context.notes)
        XCTAssertEqual(
            conflictAfter.link.eventIdentifier,
            conflictBefore.link.eventIdentifier
        )
        XCTAssertEqual(conflictAfter.tasks, conflictBefore.tasks)
    }

    func testOriginalWritePolicyBlocksReadOnlyMeetingAndRecurringEvents() async {
        let blockedEvents = [
            makeEvent(id: "read-only", isReadOnly: true),
            makeEvent(id: "invitation", isInvitation: true),
            makeEvent(id: "meeting", hasAttendees: true),
            makeEvent(id: "recurring", isRecurring: true)
        ]

        for event in blockedEvents {
            let provider = makeProvider(events: [event])
            let state = makeState(provider: provider)
            await state.loadCalendarStatus()
            state.selectEvent(event.id)

            state.beginEditingSelectedEvent()

            XCTAssertNil(state.eventEditorSession)
            XCTAssertNotNil(state.eventEditorError)
            XCTAssertEqual(provider.updateCallCount, 0)
            XCTAssertEqual(provider.deleteCallCount, 0)
        }
    }

    func testActiveEditorCannotBeReplacedAndPermissionRevocationClearsIt() async throws {
        let provider = makeProvider()
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.beginCreatingEvent()
        let firstSession = try XCTUnwrap(state.eventEditorSession)

        state.beginCreatingEvent()

        XCTAssertEqual(state.eventEditorSession, firstSession)
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError.editorAlreadyOpen.localizedDescription
        )

        provider.authorizationState = .denied
        await state.refreshCalendarData()
        XCTAssertNil(state.eventEditorSession)
        XCTAssertEqual(state.eventEditorOperationState, .idle)
        XCTAssertEqual(state.calendarContentState, .permissionDenied)
    }

    func testFailedLocalNotesFlushBlocksOriginalEditor() async throws {
        let blocker = makeEvent(id: "existing-context")
        let target = makeEvent(id: "failed-draft")
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            makeID: { "duplicate-context-id" }
        )
        _ = try store.saveNotes(for: blocker, notes: "Occupy generated ID")
        let provider = makeProvider(events: [target])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(target.id)
        state.updateSelectedEventNotes("Unsaved local draft")

        state.beginEditingSelectedEvent()

        XCTAssertNil(state.eventEditorSession)
        guard case .failed = state.notesSaveState else {
            return XCTFail("Expected failed local note save")
        }
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError.localDraftSaveRequired
                .localizedDescription
        )
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var writableExchangeCalendar: CalendarSource {
        CalendarSource(
            id: "calendar",
            title: "KAOS-TEST",
            sourceTitle: "Work",
            accountType: .exchange,
            isWritable: true,
            color: nil
        )
    }

    private var writableLocalCalendar: CalendarSource {
        CalendarSource(
            id: "local-calendar",
            title: "Local Test",
            sourceTitle: "On My Mac",
            accountType: .local,
            isWritable: true,
            color: nil
        )
    }

    private func makeProvider(
        events: [DisplayEvent] = []
    ) -> FakeCalendarProvider {
        let provider = FakeCalendarProvider(
            authorizationState: .fullAccess
        )
        provider.calendars = [writableExchangeCalendar]
        provider.events = events
        return provider
    }

    private func makeState(
        provider: FakeCalendarProvider,
        store: ContextStore? = nil
    ) -> AppState {
        AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 10, 12) },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: store == nil ? .unavailable : .ready
        )
    }

    private func makeEvent(
        id: String,
        isReadOnly: Bool = false,
        isInvitation: Bool = false,
        hasAttendees: Bool = false,
        isRecurring: Bool = false
    ) -> DisplayEvent {
        let start = date(2026, 7, 10, 9)
        return DisplayEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            calendarItemIdentifier: "item-\(id)",
            calendarItemExternalIdentifier: "external-\(id)",
            calendarIdentifier: writableExchangeCalendar.id,
            calendarTitle: writableExchangeCalendar.title,
            sourceTitle: writableExchangeCalendar.sourceTitle,
            accountType: .exchange,
            calendarColor: nil,
            title: "Event \(id)",
            location: nil,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: calendar.timeZone.identifier,
            timeSemantics: .zoned(
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            isRecurring: isRecurring,
            occurrenceDate: nil,
            occurrenceLocalComponents: nil,
            isDetached: false,
            isReadOnly: isReadOnly,
            isInvitation: isInvitation,
            hasAttendees: hasAttendees,
            originalNotes: nil
        )
    }

    private func makeFloatingEvent(
        id: String,
        rawStart: Date,
        rawEnd: Date,
        civilStart: LocalDateTimeComponents,
        civilEnd: LocalDateTimeComponents
    ) -> DisplayEvent {
        DisplayEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            calendarItemIdentifier: "item-\(id)",
            calendarItemExternalIdentifier: "external-\(id)",
            calendarIdentifier: writableExchangeCalendar.id,
            calendarTitle: writableExchangeCalendar.title,
            sourceTitle: writableExchangeCalendar.sourceTitle,
            accountType: .exchange,
            calendarColor: nil,
            title: "Floating event",
            location: nil,
            startDate: rawStart,
            endDate: rawEnd,
            isAllDay: false,
            timeZoneIdentifier: nil,
            timeSemantics: .floating(
                start: civilStart,
                end: civilEnd
            ),
            isRecurring: false,
            occurrenceDate: nil,
            occurrenceLocalComponents: nil,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func timedDraft(
        timeZoneIdentifier: String?
    ) -> CalendarEventDraft {
        CalendarEventDraft(
            title: "Planning",
            calendarIdentifier: "calendar",
            startDate: date(2026, 7, 10, 9),
            endDate: date(2026, 7, 10, 10),
            isAllDay: false,
            timeZoneIdentifier: timeZoneIdentifier,
            referenceTimeZoneIdentifier: calendar.timeZone.identifier
        )
    }
}
