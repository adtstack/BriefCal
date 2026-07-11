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
        state.selectEvent(selected.id)

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

    func testMiniMonthSelectionUsesVisiblePeriodPipelineWithoutWrites() async {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        let selected = makeEvent(
            id: "mini-month-selected",
            start: date(2026, 7, 8, 10),
            end: date(2026, 7, 8, 11)
        )
        provider.events = [selected]
        let state = AppState(
            calendar: testCalendar,
            now: { self.date(2026, 7, 8, 9) },
            calendarProvider: provider
        )
        await state.loadCalendarStatus()
        state.selectEvent(selected.id)

        state.selectMiniMonthDate(date(2026, 7, 9, 15))
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(state.selectedEventID, selected.id)
        XCTAssertEqual(provider.fetchCallCount, 1)

        let farDate = date(2027, 7, 8, 15)
        state.selectMiniMonthDate(farDate)
        for _ in 0..<100 where provider.fetchCallCount < 2 {
            await Task.yield()
        }

        XCTAssertNil(state.selectedEventID)
        XCTAssertEqual(provider.fetchCallCount, 2)
        let interval = try! XCTUnwrap(provider.lastFetchInterval)
        XCTAssertLessThanOrEqual(interval.start, farDate)
        XCTAssertGreaterThan(interval.end, farDate)

        state.selectMiniMonthDate(date(2027, 7, 9, 15))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(provider.fetchCallCount, 2)
        XCTAssertEqual(provider.createCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
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

        let localOccurrence = LocalDateTimeComponents(
            date: original,
            calendar: testCalendar
        )
        let sameLocalOccurrenceAfterTimeZoneChange = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: "series",
            calendarItemIdentifier: nil,
            eventIdentifier: nil,
            isRecurring: true,
            occurrenceDate: date(2026, 7, 6, 16),
            occurrenceLocalComponents: localOccurrence,
            startDate: date(2026, 7, 6, 16),
            endDate: date(2026, 7, 6, 17),
            title: "series"
        )
        let originalLocalOccurrence = DisplayEventIdentity.make(
            calendarIdentifier: "calendar",
            externalIdentifier: "series",
            calendarItemIdentifier: nil,
            eventIdentifier: nil,
            isRecurring: true,
            occurrenceDate: original,
            occurrenceLocalComponents: localOccurrence,
            startDate: moved,
            endDate: date(2026, 7, 6, 12),
            title: "series"
        )
        XCTAssertEqual(
            originalLocalOccurrence,
            sameLocalOccurrenceAfterTimeZoneChange
        )

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
            occurrenceLocalComponents: nil,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil
        )
    }
}

final class MiniMonthGridTests: XCTestCase {
    func testAugustGridHonorsFirstWeekdayAndUsesSixRows() {
        let sundayCalendar = makeCalendar(firstWeekday: 1)
        let mondayCalendar = makeCalendar(firstWeekday: 2)
        let sundayGrid = MiniMonthGrid(
            containing: date(2026, 8, 15, calendar: sundayCalendar),
            calendar: sundayCalendar
        )
        let mondayGrid = MiniMonthGrid(
            containing: date(2026, 8, 15, calendar: mondayCalendar),
            calendar: mondayCalendar
        )

        XCTAssertEqual(sundayGrid.days.count, 42)
        XCTAssertEqual(mondayGrid.days.count, 42)
        XCTAssertEqual(Set(sundayGrid.days.map(\.date)).count, 42)
        XCTAssertEqual(Set(mondayGrid.days.map(\.date)).count, 42)
        XCTAssertEqual(sundayGrid.days.filter(\.isInDisplayedMonth).count, 31)
        XCTAssertEqual(mondayGrid.days.filter(\.isInDisplayedMonth).count, 31)
        XCTAssertEqual(dayKey(sundayGrid.days.first!.date, calendar: sundayCalendar), "2026-07-26")
        XCTAssertEqual(dayKey(sundayGrid.days.last!.date, calendar: sundayCalendar), "2026-09-05")
        XCTAssertEqual(dayKey(mondayGrid.days.first!.date, calendar: mondayCalendar), "2026-07-27")
        XCTAssertEqual(dayKey(mondayGrid.days.last!.date, calendar: mondayCalendar), "2026-09-06")
        XCTAssertEqual(sundayGrid.weekdayOrdinals, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(mondayGrid.weekdayOrdinals, [2, 3, 4, 5, 6, 7, 1])
    }

    func testLeapMonthAndYearBoundaryUseCalendarMonthIdentity() {
        let calendar = makeCalendar(firstWeekday: 2)
        let leapGrid = MiniMonthGrid(
            containing: date(2024, 2, 12, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(leapGrid.days.filter(\.isInDisplayedMonth).count, 29)
        XCTAssertEqual(dayKey(leapGrid.days.first!.date, calendar: calendar), "2024-01-29")
        XCTAssertEqual(dayKey(leapGrid.days.last!.date, calendar: calendar), "2024-03-10")

        let decemberStart = MiniMonthGrid.monthStart(
            containing: date(2026, 12, 31, calendar: calendar),
            calendar: calendar
        )
        let januaryStart = MiniMonthGrid.shiftedMonthStart(
            from: decemberStart,
            by: 1,
            calendar: calendar
        )
        XCTAssertEqual(dayKey(januaryStart, calendar: calendar), "2027-01-01")

        let januaryGrid = MiniMonthGrid(
            containing: januaryStart,
            calendar: calendar
        )
        XCTAssertEqual(januaryGrid.days.filter(\.isInDisplayedMonth).count, 31)
    }

    func testDSTMonthsContainConsecutiveCivilDays() {
        let calendar = makeCalendar(
            timeZoneIdentifier: "America/New_York",
            firstWeekday: 1
        )
        let march = MiniMonthGrid(
            containing: date(2026, 3, 15, calendar: calendar),
            calendar: calendar
        )
        let november = MiniMonthGrid(
            containing: date(2026, 11, 15, calendar: calendar),
            calendar: calendar
        )

        assertCivilSequence(march.days.map(\.date), calendar: calendar)
        assertCivilSequence(november.days.map(\.date), calendar: calendar)

        let march8 = try! XCTUnwrap(
            march.days.first { dayKey($0.date, calendar: calendar) == "2026-03-08" }
        ).date
        let march9 = try! XCTUnwrap(
            march.days.first { dayKey($0.date, calendar: calendar) == "2026-03-09" }
        ).date
        XCTAssertEqual(march9.timeIntervalSince(march8), 23 * 60 * 60)

        let november1 = try! XCTUnwrap(
            november.days.first { dayKey($0.date, calendar: calendar) == "2026-11-01" }
        ).date
        let november2 = try! XCTUnwrap(
            november.days.first { dayKey($0.date, calendar: calendar) == "2026-11-02" }
        ).date
        XCTAssertEqual(november2.timeIntervalSince(november1), 25 * 60 * 60)
    }

    func testContainingMonthUsesInjectedCalendarTimeZone() {
        let absoluteDate = Date(timeIntervalSince1970: 1_772_325_000)
        let losAngeles = makeCalendar(
            timeZoneIdentifier: "America/Los_Angeles",
            firstWeekday: 1
        )
        let tokyo = makeCalendar(
            timeZoneIdentifier: "Asia/Tokyo",
            firstWeekday: 1
        )

        let losAngelesGrid = MiniMonthGrid(
            containing: absoluteDate,
            calendar: losAngeles
        )
        let tokyoGrid = MiniMonthGrid(
            containing: absoluteDate,
            calendar: tokyo
        )

        XCTAssertEqual(dayKey(losAngelesGrid.monthStart, calendar: losAngeles), "2026-02-01")
        XCTAssertEqual(dayKey(tokyoGrid.monthStart, calendar: tokyo), "2026-03-01")
    }

    func testCivilIdentifiersStayUniqueAcrossSpilloverCells() {
        let calendar = makeCalendar(firstWeekday: 2)
        let grid = MiniMonthGrid(
            containing: date(2026, 8, 15, calendar: calendar),
            calendar: calendar
        )
        let identifiers = grid.days.map {
            MiniMonthGrid.dayIdentifier(for: $0.date, calendar: calendar)
        }

        XCTAssertEqual(Set(identifiers).count, 42)
        XCTAssertEqual(identifiers.first, "2026-07-27")
        XCTAssertEqual(identifiers.last, "2026-09-06")
        XCTAssertTrue(identifiers.allSatisfy { $0.split(separator: "-").count == 3 })
    }

    private func makeCalendar(
        timeZoneIdentifier: String = "UTC",
        firstWeekday: Int
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )!
    }

    private func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year!,
            components.month!,
            components.day!
        )
    }

    private func assertCivilSequence(
        _ dates: [Date],
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for pair in zip(dates, dates.dropFirst()) {
            XCTAssertEqual(
                calendar.date(byAdding: .day, value: 1, to: pair.0),
                pair.1,
                file: file,
                line: line
            )
            XCTAssertEqual(
                calendar.component(.hour, from: pair.1),
                0,
                file: file,
                line: line
            )
        }
    }
}
