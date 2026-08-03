import XCTest
@testable import KaosCal

@MainActor
final class CalendarAccessTests: XCTestCase {
    func testNotDeterminedStatusDoesNotFetch() async {
        let provider = FakeCalendarProvider(authorizationState: .notDetermined)
        let state = makeState(provider: provider)

        await state.loadCalendarStatus()

        XCTAssertEqual(state.calendarAuthorizationState, .notDetermined)
        XCTAssertEqual(state.calendarContentState, .disconnected)
        XCTAssertEqual(provider.fetchCallCount, 0)
    }

    func testRequestFullAccessLoadsCalendarAndEvents() async {
        let provider = FakeCalendarProvider()
        provider.calendars = [exchangeCalendar]
        provider.events = [sampleEvent]
        let state = makeState(provider: provider)

        await state.requestCalendarAccess()

        XCTAssertEqual(provider.requestCallCount, 1)
        XCTAssertEqual(state.calendarAuthorizationState, .fullAccess)
        XCTAssertEqual(state.calendarSources, [exchangeCalendar])
        XCTAssertEqual(state.events, [sampleEvent])
        XCTAssertEqual(state.calendarContentState, .loaded)
        XCTAssertEqual(provider.fetchCallCount, 1)
        XCTAssertEqual(
            provider.lastFetchInterval,
            DateInterval(
                start: Date(timeIntervalSince1970: 1_697_328_000),
                end: Date(timeIntervalSince1970: 1_707_696_000)
            )
        )
    }

    func testDeniedStatusShowsPermissionState() async {
        let provider = FakeCalendarProvider(authorizationState: .denied)
        let state = makeState(provider: provider)

        await state.loadCalendarStatus()

        XCTAssertEqual(state.calendarContentState, .permissionDenied)
        XCTAssertTrue(state.events.isEmpty)
    }

    func testUnknownStatusFailsAndClearsPreviouslyLoadedData() async {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.calendars = [exchangeCalendar]
        provider.events = [sampleEvent]
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()

        provider.authorizationState = .unknown
        await state.refreshCalendarData()

        XCTAssertEqual(
            state.calendarContentState,
            .failed("Unknown calendar permission state")
        )
        XCTAssertTrue(state.calendarSources.isEmpty)
        XCTAssertTrue(state.events.isEmpty)
    }

    func testProviderFailureShowsSafeError() async {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.error = FakeCalendarProviderError.failed
        let state = makeState(provider: provider)

        await state.loadCalendarStatus()

        XCTAssertEqual(state.calendarContentState, .failed("Calendar provider failed"))
    }

    func testTransientRefreshFailurePreservesLoadedCalendarData() async {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.calendars = [exchangeCalendar]
        provider.events = [sampleEvent]
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(sampleEvent.id)

        provider.error = FakeCalendarProviderError.failed
        await state.refreshCalendarData()

        XCTAssertEqual(state.calendarContentState, .loaded)
        XCTAssertEqual(state.calendarSources, [exchangeCalendar])
        XCTAssertEqual(state.events, [sampleEvent])
        XCTAssertEqual(state.selectedEventID, sampleEvent.id)
        XCTAssertEqual(state.calendarRefreshError, "Calendar provider failed")
        XCTAssertFalse(state.isCalendarRefreshing)

        provider.error = nil
        await state.refreshCalendarData()

        XCTAssertEqual(state.calendarContentState, .loaded)
        XCTAssertNil(state.calendarRefreshError)
    }

    func testRequestErrorWithDeniedStatusShowsPermissionRecovery() async {
        let provider = FakeCalendarProvider(authorizationState: .denied)
        provider.error = FakeCalendarProviderError.failed
        let state = makeState(provider: provider)

        await state.requestCalendarAccess()

        XCTAssertEqual(state.calendarAuthorizationState, .denied)
        XCTAssertEqual(state.calendarContentState, .permissionDenied)
    }

    func testStoreChangeRefetchesCurrentRange() async {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        XCTAssertEqual(provider.fetchCallCount, 1)

        provider.sendStoreChanged()
        provider.sendStoreChanged()
        provider.sendStoreChanged()
        for _ in 0..<100 where provider.fetchCallCount < 2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(provider.fetchCallCount, 2)
    }

    func testFetchedEventsRefreshInjectedLocalContextStore() async throws {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        let original = makeEvent(
            startDate: Date(timeIntervalSince1970: 1_700_003_600),
            endDate: Date(timeIntervalSince1970: 1_700_007_200),
            isAllDay: false
        )
        let moved = makeEvent(
            startDate: Date(timeIntervalSince1970: 1_700_010_800),
            endDate: Date(timeIntervalSince1970: 1_700_014_400),
            isAllDay: false
        )
        provider.events = [moved]
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep local notes")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let state = AppState(
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: .ready
        )

        await state.loadCalendarStatus()

        let brief = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(state.localContextStoreState, .ready)
        XCTAssertEqual(brief.context.notes, "Keep local notes")
        XCTAssertEqual(brief.context.startSnapshot, moved.startDate)
        XCTAssertEqual(brief.context.endSnapshot, moved.endDate)
    }

    func testAllDayExclusiveEndBecomesInclusiveDisplayDate() {
        let state = makeState(provider: FakeCalendarProvider())
        let start = Date(timeIntervalSince1970: 1_720_569_600)
        let exclusiveEnd = Date(timeIntervalSince1970: 1_720_828_800)
        let event = makeEvent(
            startDate: start,
            endDate: exclusiveEnd,
            isAllDay: true
        )

        let displayedEnd = CalendarEventDateFormatting.displayedEndDate(
            for: event,
            calendar: state.calendar
        )

        XCTAssertEqual(displayedEnd, Date(timeIntervalSince1970: 1_720_742_400))
        XCTAssertTrue(
            CalendarEventDateFormatting.spansMultipleDates(
                event,
                calendar: state.calendar
            )
        )
    }

    func testTimedEventCrossingMidnightSpansMultipleDates() {
        let state = makeState(provider: FakeCalendarProvider())
        let event = makeEvent(
            startDate: Date(timeIntervalSince1970: 1_720_648_800),
            endDate: Date(timeIntervalSince1970: 1_720_656_000),
            isAllDay: false
        )

        XCTAssertTrue(
            CalendarEventDateFormatting.spansMultipleDates(
                event,
                calendar: state.calendar
            )
        )
    }

    func testPermissionRevocationClearsPreviouslyLoadedCalendarData() async {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.calendars = [exchangeCalendar]
        provider.events = [sampleEvent]
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(sampleEvent.id)

        provider.authorizationState = .denied
        await state.refreshCalendarData()

        XCTAssertEqual(state.calendarContentState, .permissionDenied)
        XCTAssertTrue(state.calendarSources.isEmpty)
        XCTAssertTrue(state.events.isEmpty)
        XCTAssertNil(state.selectedEventID)
        XCTAssertNil(state.selectedEvent)
    }

    private func makeState(provider: FakeCalendarProvider) -> AppState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return AppState(
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            calendarProvider: provider
        )
    }

    private var exchangeCalendar: CalendarSource {
        CalendarSource(
            id: "exchange-calendar",
            title: "KAOS-TEST",
            sourceTitle: "Work",
            sourceIdentifier: "work-source",
            accountType: .exchange,
            isWritable: true,
            color: nil
        )
    }

    private var sampleEvent: DisplayEvent {
        makeEvent(
            startDate: Date(timeIntervalSince1970: 1_700_003_600),
            endDate: Date(timeIntervalSince1970: 1_700_007_200),
            isAllDay: false
        )
    }

    private func makeEvent(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) -> DisplayEvent {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startComponents = LocalDateTimeComponents(
            date: startDate,
            calendar: calendar
        )
        let endComponents = LocalDateTimeComponents(
            date: endDate,
            calendar: calendar
        )
        let timeSemantics: EventTimeSemantics = isAllDay
            ? .allDay(start: startComponents, endExclusive: endComponents)
            : .zoned(timeZoneIdentifier: "Asia/Seoul")

        return DisplayEvent(
            id: "event#1",
            eventIdentifier: "event",
            calendarItemIdentifier: "item",
            calendarItemExternalIdentifier: "external",
            calendarIdentifier: "exchange-calendar",
            calendarTitle: "KAOS-TEST",
            sourceTitle: "Work",
            accountType: .exchange,
            calendarColor: nil,
            title: "Phase 1 fixture",
            location: nil,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            timeZoneIdentifier: "Asia/Seoul",
            timeSemantics: timeSemantics,
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
}
