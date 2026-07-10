import XCTest
@testable import KaosCal

@MainActor
final class CalendarEventLayoutTests: XCTestCase {
    func testOvernightEventSplitsIntoTwoDaySegments() {
        let calendar = testCalendar
        let dates = [date(2026, 7, 6), date(2026, 7, 7)]
        let event = makeEvent(
            id: "overnight",
            start: date(2026, 7, 6, 23),
            end: date(2026, 7, 7, 1, 30)
        )

        let layout = CalendarEventLayout(
            events: [event],
            dates: dates,
            calendar: calendar
        )

        XCTAssertEqual(layout.timedPlacements.count, 2)
        let first = layout.timedPlacements[0]
        XCTAssertEqual(first.dayIndex, 0)
        XCTAssertEqual(first.startMinute, 1_380)
        XCTAssertEqual(first.endMinute, 1_440)
        XCTAssertFalse(first.continuesBefore)
        XCTAssertTrue(first.continuesAfter)

        let second = layout.timedPlacements[1]
        XCTAssertEqual(second.dayIndex, 1)
        XCTAssertEqual(second.startMinute, 0)
        XCTAssertEqual(second.endMinute, 90)
        XCTAssertTrue(second.continuesBefore)
        XCTAssertFalse(second.continuesAfter)
    }

    func testOverlappingEventsUseMinimumColumnsAndTouchingEventStartsNewGroup() {
        let calendar = testCalendar
        let day = date(2026, 7, 6)
        let events = [
            makeEvent(
                id: "long",
                start: date(2026, 7, 6, 9),
                end: date(2026, 7, 6, 12)
            ),
            makeEvent(
                id: "middle",
                start: date(2026, 7, 6, 9, 30),
                end: date(2026, 7, 6, 11)
            ),
            makeEvent(
                id: "short",
                start: date(2026, 7, 6, 10),
                end: date(2026, 7, 6, 10, 30)
            ),
            makeEvent(
                id: "touching",
                start: date(2026, 7, 6, 12),
                end: date(2026, 7, 6, 13)
            )
        ]

        let placements = CalendarEventLayout(
            events: events,
            dates: [day],
            calendar: calendar
        ).timedPlacements

        let overlapGroup = placements.filter { $0.event.id != "touching" }
        XCTAssertEqual(Set(overlapGroup.map(\.columnIndex)), Set([0, 1, 2]))
        XCTAssertTrue(overlapGroup.allSatisfy { $0.columnCount == 3 })

        let touching = try! XCTUnwrap(
            placements.first { $0.event.id == "touching" }
        )
        XCTAssertEqual(touching.columnIndex, 0)
        XCTAssertEqual(touching.columnCount, 1)
    }

    func testMinimumVisualDurationPreventsShortCardsFromOverlapping() {
        let events = [
            makeEvent(
                id: "first-short",
                start: date(2026, 7, 6, 9),
                end: date(2026, 7, 6, 9, 5)
            ),
            makeEvent(
                id: "second-short",
                start: date(2026, 7, 6, 9, 10),
                end: date(2026, 7, 6, 9, 15)
            )
        ]

        let placements = CalendarEventLayout(
            events: events,
            dates: [date(2026, 7, 6)],
            calendar: testCalendar
        ).timedPlacements

        XCTAssertEqual(Set(placements.map(\.columnIndex)), Set([0, 1]))
        XCTAssertTrue(placements.allSatisfy { $0.columnCount == 2 })
        XCTAssertTrue(
            placements.allSatisfy {
                $0.layoutEndMinute - $0.startMinute
                    >= CalendarEventLayout.minimumVisualDurationMinutes
            }
        )
    }

    func testAllDaySpansClampToVisibleWeekAndReuseRows() {
        let calendar = testCalendar
        let dates = (0..<7).map { offset in
            calendar.date(
                byAdding: .day,
                value: offset,
                to: date(2026, 7, 6)
            )!
        }
        let events = [
            makeEvent(
                id: "spanning",
                start: date(2026, 7, 5),
                end: date(2026, 7, 9),
                isAllDay: true
            ),
            makeEvent(
                id: "collision",
                start: date(2026, 7, 7),
                end: date(2026, 7, 8),
                isAllDay: true
            ),
            makeEvent(
                id: "reuses-row",
                start: date(2026, 7, 9),
                end: date(2026, 7, 10),
                isAllDay: true
            )
        ]

        let layout = CalendarEventLayout(
            events: events,
            dates: dates,
            calendar: calendar
        )

        XCTAssertEqual(layout.allDayRowCount, 2)
        let spanning = try! XCTUnwrap(
            layout.allDayPlacements.first { $0.event.id == "spanning" }
        )
        XCTAssertEqual(spanning.startDayIndex, 0)
        XCTAssertEqual(spanning.endDayIndex, 2)
        XCTAssertEqual(spanning.rowIndex, 0)
        XCTAssertTrue(spanning.continuesBefore)

        let collision = try! XCTUnwrap(
            layout.allDayPlacements.first { $0.event.id == "collision" }
        )
        XCTAssertEqual(collision.rowIndex, 1)

        let reused = try! XCTUnwrap(
            layout.allDayPlacements.first { $0.event.id == "reuses-row" }
        )
        XCTAssertEqual(reused.rowIndex, 0)
    }

    func testOneDayAllDayUsesExactlyOneColumnAndNormalizesInclusiveEnd() {
        let start = date(2026, 7, 6)
        let exclusiveEnd = date(2026, 7, 7)
        let inclusiveEnd = exclusiveEnd.addingTimeInterval(-1)
        let normalizedInclusive = CalendarEventDateFormatting
            .normalizedAllDayDateRange(
                startDate: start,
                endDate: inclusiveEnd,
                calendar: testCalendar
            )
        let normalizedExclusive = CalendarEventDateFormatting
            .normalizedAllDayDateRange(
                startDate: start,
                endDate: exclusiveEnd,
                calendar: testCalendar
            )

        XCTAssertEqual(normalizedInclusive.start, start)
        XCTAssertEqual(normalizedInclusive.endExclusive, exclusiveEnd)
        XCTAssertEqual(normalizedExclusive.endExclusive, exclusiveEnd)

        let layout = CalendarEventLayout(
            events: [makeEvent(
                id: "one-day",
                start: start,
                end: exclusiveEnd,
                isAllDay: true
            )],
            dates: [start, exclusiveEnd],
            calendar: testCalendar
        )
        let placement = try! XCTUnwrap(layout.allDayPlacements.first)
        XCTAssertEqual(placement.startDayIndex, 0)
        XCTAssertEqual(placement.endDayIndex, 0)
    }

    func testEventsTouchingVisibleBoundariesAreExcluded() {
        let day = date(2026, 7, 6)
        let nextDay = date(2026, 7, 7)
        let events = [
            makeEvent(
                id: "before",
                start: date(2026, 7, 5, 23),
                end: day
            ),
            makeEvent(
                id: "inside",
                start: date(2026, 7, 6, 9),
                end: date(2026, 7, 6, 10)
            ),
            makeEvent(
                id: "after",
                start: nextDay,
                end: date(2026, 7, 7, 1)
            )
        ]

        let placements = CalendarEventLayout(
            events: events,
            dates: [day],
            calendar: testCalendar
        ).timedPlacements

        XCTAssertEqual(placements.map(\.event.id), ["inside"])
    }

    func testNearMidnightMinimumHeightParticipatesInCollisionLayout() {
        let events = [
            makeEvent(
                id: "earlier",
                start: date(2026, 7, 6, 23, 20),
                end: date(2026, 7, 6, 23, 40)
            ),
            makeEvent(
                id: "midnight",
                start: date(2026, 7, 6, 23, 50),
                end: date(2026, 7, 7)
            )
        ]

        let placements = CalendarEventLayout(
            events: events,
            dates: [date(2026, 7, 6)],
            calendar: testCalendar
        ).timedPlacements
        let midnight = try! XCTUnwrap(
            placements.first { $0.event.id == "midnight" }
        )

        XCTAssertEqual(Set(placements.map(\.columnIndex)), Set([0, 1]))
        XCTAssertTrue(placements.allSatisfy { $0.columnCount == 2 })
        XCTAssertEqual(midnight.layoutEndMinute, 1_440)
        XCTAssertEqual(
            midnight.layoutEndMinute - midnight.layoutStartMinute,
            CalendarEventLayout.minimumVisualDurationMinutes
        )
    }

    func testDSTFallbackOccurrencesAtSameWallTimeUseSeparateColumns() {
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        newYorkCalendar.locale = Locale(identifier: "en_US_POSIX")
        let day = newYorkCalendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1)
        )!
        let events = [
            makeEvent(
                id: "first-0130",
                start: date(2026, 11, 1, 5, 30),
                end: date(2026, 11, 1, 5, 45)
            ),
            makeEvent(
                id: "second-0130",
                start: date(2026, 11, 1, 6, 30),
                end: date(2026, 11, 1, 6, 45)
            )
        ]

        let placements = CalendarEventLayout(
            events: events,
            dates: [day],
            calendar: newYorkCalendar
        ).timedPlacements

        XCTAssertEqual(placements.map(\.startMinute), [90, 90])
        XCTAssertEqual(Set(placements.map(\.columnIndex)), Set([0, 1]))
        XCTAssertTrue(placements.allSatisfy { $0.columnCount == 2 })
    }

    func testDSTSpringForwardUsesWallClockPositions() {
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        newYorkCalendar.locale = Locale(identifier: "en_US_POSIX")
        let day = newYorkCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 8)
        )!
        let event = makeEvent(
            id: "spring-forward",
            start: date(2026, 3, 8, 6, 30),
            end: date(2026, 3, 8, 7, 30)
        )

        let placement = CalendarEventLayout(
            events: [event],
            dates: [day],
            calendar: newYorkCalendar
        ).timedPlacements.first

        XCTAssertEqual(placement?.startMinute, 90)
        XCTAssertEqual(placement?.endMinute, 210)
    }

    func testDenseAllDayEventsRemainAvailableInDistinctRows() {
        let events = (0..<12).map { index in
            makeEvent(
                id: "all-day-\(index)",
                start: date(2026, 7, 6),
                end: date(2026, 7, 7),
                isAllDay: true
            )
        }

        let layout = CalendarEventLayout(
            events: events,
            dates: [date(2026, 7, 6)],
            calendar: testCalendar
        )

        XCTAssertEqual(layout.allDayPlacements.count, 12)
        XCTAssertEqual(layout.allDayRowCount, 12)
        XCTAssertEqual(Set(layout.allDayPlacements.map(\.rowIndex)).count, 12)
    }

    func testAllDayContinuationClampsAcrossBothVisibleEdges() {
        let dates = (0..<7).map { offset in
            testCalendar.date(
                byAdding: .day,
                value: offset,
                to: date(2026, 7, 6)
            )!
        }
        let layout = CalendarEventLayout(
            events: [makeEvent(
                id: "outside-both-sides",
                start: date(2026, 7, 5),
                end: date(2026, 7, 14),
                isAllDay: true
            )],
            dates: dates,
            calendar: testCalendar
        )
        let placement = try! XCTUnwrap(layout.allDayPlacements.first)

        XCTAssertEqual(placement.startDayIndex, 0)
        XCTAssertEqual(placement.endDayIndex, 6)
        XCTAssertTrue(placement.continuesBefore)
        XCTAssertTrue(placement.continuesAfter)
    }

    func testAppStateFiltersDayAndWeekToFocusedPeriod() async {
        let calendar = testCalendar
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        let inside = makeEvent(
            id: "inside",
            start: date(2026, 7, 8, 10),
            end: date(2026, 7, 8, 11)
        )
        let outside = makeEvent(
            id: "outside",
            start: date(2026, 7, 20, 10),
            end: date(2026, 7, 20, 11)
        )
        provider.events = [inside, outside]
        let state = AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 8, 9) },
            calendarProvider: provider
        )
        await state.loadCalendarStatus()

        XCTAssertEqual(state.visibleDates.first, date(2026, 7, 6))
        XCTAssertEqual(state.visibleDates.count, 7)
        XCTAssertEqual(state.visibleEvents.map(\.id), ["inside"])

        state.select(.day)
        XCTAssertEqual(state.visibleDates, [date(2026, 7, 8)])
        XCTAssertEqual(state.visibleEvents.map(\.id), ["inside"])
    }

    func testMovingBeyondLoadedRangeFetchesNewWindowAndClearsSelection() async {
        let calendar = testCalendar
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        let selected = makeEvent(
            id: "selected",
            start: date(2026, 7, 8, 10),
            end: date(2026, 7, 8, 11)
        )
        provider.events = [selected]
        let state = AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 8, 9) },
            calendarProvider: provider
        )
        await state.loadCalendarStatus()
        state.selectedEventID = selected.id

        state.focusedDate = date(2027, 7, 8)
        state.select(.day)
        for _ in 0..<100 where provider.fetchCallCount < 2 {
            await Task.yield()
        }

        XCTAssertEqual(provider.fetchCallCount, 2)
        XCTAssertNil(state.selectedEventID)
        let interval = try! XCTUnwrap(provider.lastFetchInterval)
        XCTAssertLessThanOrEqual(interval.start, date(2027, 7, 8))
        XCTAssertGreaterThan(interval.end, date(2027, 7, 9))
    }

    func testReturningToCachedPeriodCancelsPendingFarRangeLoad() async {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.events = [makeEvent(
            id: "cached",
            start: date(2026, 7, 8, 10),
            end: date(2026, 7, 8, 11)
        )]
        let state = AppState(
            calendar: testCalendar,
            now: { self.date(2026, 7, 8, 9) },
            calendarProvider: provider
        )
        await state.loadCalendarStatus()

        state.focusedDate = date(2027, 7, 8)
        state.select(.day)
        state.goToToday()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(provider.fetchCallCount, 1)
        XCTAssertEqual(state.visibleEvents.map(\.id), ["cached"])
    }

    func testFloatingEventKeepsWallClockTimeInDisplayTimeZone() {
        var seoulCalendar = testCalendar
        seoulCalendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let start = LocalDateTimeComponents(
            date: date(2026, 7, 6, 9),
            calendar: testCalendar
        )
        let end = LocalDateTimeComponents(
            date: date(2026, 7, 6, 10),
            calendar: testCalendar
        )
        let event = makeEvent(
            id: "floating",
            start: date(2026, 7, 6, 9),
            end: date(2026, 7, 6, 10),
            timeSemantics: .floating(start: start, end: end)
        )

        let placement = CalendarEventLayout(
            events: [event],
            dates: [seoulCalendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 6
            ))!],
            calendar: seoulCalendar
        ).timedPlacements.first

        XCTAssertEqual(placement?.startMinute, 540)
        XCTAssertEqual(placement?.endMinute, 600)
    }

    func testGregorianCivilComponentsSurviveNonGregorianDisplayCalendar() {
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        buddhistCalendar.locale = Locale(identifier: "th_TH")
        let startDate = date(2026, 7, 6, 9)
        let endDate = date(2026, 7, 6, 10)
        let event = makeEvent(
            id: "gregorian-floating",
            start: startDate,
            end: endDate,
            timeSemantics: .floating(
                start: LocalDateTimeComponents(
                    date: startDate,
                    calendar: testCalendar
                ),
                end: LocalDateTimeComponents(
                    date: endDate,
                    calendar: testCalendar
                )
            )
        )

        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: buddhistCalendar
        )

        XCTAssertEqual(range.start, startDate)
        XCTAssertEqual(range.end, endDate)
    }

    func testDisplayIdentityIsStableForMovesAndDistinctForOccurrences() {
        let original = date(2026, 7, 6, 9)
        let moved = date(2026, 7, 6, 11)
        let nonRecurringOriginal = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: "external",
            calendarItemIdentifier: "item",
            eventIdentifier: "event",
            isRecurring: false,
            occurrenceDate: nil,
            startDate: original,
            endDate: date(2026, 7, 6, 10),
            title: "standup"
        )
        let nonRecurringMoved = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: "external",
            calendarItemIdentifier: "item",
            eventIdentifier: "event",
            isRecurring: false,
            occurrenceDate: nil,
            startDate: moved,
            endDate: date(2026, 7, 6, 12),
            title: "standup"
        )
        XCTAssertEqual(nonRecurringOriginal, nonRecurringMoved)

        let firstOccurrence = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: "series",
            calendarItemIdentifier: nil,
            eventIdentifier: nil,
            isRecurring: true,
            occurrenceDate: original,
            startDate: moved,
            endDate: date(2026, 7, 6, 12),
            title: "series"
        )
        let secondOccurrence = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: "series",
            calendarItemIdentifier: nil,
            eventIdentifier: nil,
            isRecurring: true,
            occurrenceDate: date(2026, 7, 13, 9),
            startDate: moved,
            endDate: date(2026, 7, 6, 12),
            title: "series"
        )
        XCTAssertNotEqual(firstOccurrence, secondOccurrence)

        let otherCalendar = DisplayEventIdentity.make(
            calendarIdentifier: "other-calendar",
            externalIdentifier: "series",
            calendarItemIdentifier: nil,
            eventIdentifier: nil,
            isRecurring: true,
            occurrenceDate: original,
            startDate: moved,
            endDate: date(2026, 7, 6, 12),
            title: "series"
        )
        XCTAssertNotEqual(firstOccurrence, otherCalendar)

        let anonymousA = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: nil,
            calendarItemIdentifier: nil,
            eventIdentifier: nil,
            isRecurring: false,
            occurrenceDate: nil,
            startDate: original,
            endDate: date(2026, 7, 6, 10),
            title: "A"
        )
        let anonymousB = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: nil,
            calendarItemIdentifier: nil,
            eventIdentifier: nil,
            isRecurring: false,
            occurrenceDate: nil,
            startDate: original,
            endDate: date(2026, 7, 6, 11),
            title: "B"
        )
        XCTAssertNotEqual(anonymousA, anonymousB)
    }

    func testFormattingUsesExplicitCalendarTimeZone() {
        var newYorkCalendar = testCalendar
        newYorkCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnightUTC = date(2026, 7, 6)

        XCTAssertEqual(
            CalendarEventDateFormatting.longDate(
                midnightUTC,
                calendar: newYorkCalendar
            ),
            "July 5, 2026"
        )
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

    private func makeEvent(
        id: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        timeSemantics explicitTimeSemantics: EventTimeSemantics? = nil
    ) -> DisplayEvent {
        let startComponents = LocalDateTimeComponents(
            date: start,
            calendar: testCalendar
        )
        let endComponents = LocalDateTimeComponents(
            date: end,
            calendar: testCalendar
        )
        let timeSemantics: EventTimeSemantics = explicitTimeSemantics
            ?? (isAllDay
                ? .allDay(start: startComponents, endExclusive: endComponents)
                : .zoned(timeZoneIdentifier: "UTC"))

        return DisplayEvent(
            id: id,
            eventIdentifier: id,
            calendarItemIdentifier: "item-\(id)",
            calendarItemExternalIdentifier: nil,
            calendarIdentifier: "calendar",
            calendarTitle: "KAOS-TEST",
            sourceTitle: "Work",
            accountType: .exchange,
            calendarColor: nil,
            title: id,
            location: nil,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            timeZoneIdentifier: "UTC",
            timeSemantics: timeSemantics,
            isRecurring: false,
            occurrenceDate: nil,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false
        )
    }
}
