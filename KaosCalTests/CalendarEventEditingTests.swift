import EventKit
import GRDB
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

    func testBasicRecurrenceValidationAndDraftRoundTrip() throws {
        let weekly = BasicRecurrenceRule(
            frequency: .weekly,
            interval: 2,
            weekdays: [.monday, .wednesday],
            end: .afterOccurrences(8)
        )
        var draft = timedDraft(timeZoneIdentifier: "GMT")
        draft.recurrence = .basic(weekly)

        let validated = try draft.validated(calendar: calendar)
        XCTAssertEqual(validated.recurrence, .basic(weekly))

        for frequency in [
            CalendarRecurrenceFrequency.daily,
            .monthly,
            .yearly
        ] {
            var frequencyDraft = draft
            frequencyDraft.recurrence = .basic(BasicRecurrenceRule(
                frequency: frequency,
                interval: 3,
                end: .onDate(date(2027, 7, 10))
            ))
            XCTAssertNoThrow(
                try frequencyDraft.validated(calendar: calendar)
            )
        }

        let event = makeEvent(
            id: "recurrence-round-trip",
            isRecurring: true,
            recurrence: .basic(weekly)
        )
        XCTAssertEqual(
            CalendarEventDraft(event: event, calendar: calendar).recurrence,
            .basic(weekly)
        )
    }

    func testRecurrenceValidationRejectsInvalidShapes() {
        let invalidRules: [(
            BasicRecurrenceRule,
            CalendarEventWriteError
        )] = [
            (
                BasicRecurrenceRule(frequency: .daily, interval: 0),
                .invalidRecurrenceInterval
            ),
            (
                BasicRecurrenceRule(frequency: .weekly),
                .invalidRecurrenceWeekdays
            ),
            (
                BasicRecurrenceRule(
                    frequency: .daily,
                    weekdays: [.friday]
                ),
                .invalidRecurrenceWeekdays
            ),
            (
                BasicRecurrenceRule(
                    frequency: .monthly,
                    end: .afterOccurrences(0)
                ),
                .invalidRecurrenceEnd
            ),
            (
                BasicRecurrenceRule(
                    frequency: .yearly,
                    end: .onDate(date(2025, 7, 10))
                ),
                .invalidRecurrenceEnd
            )
        ]

        for (rule, expectedError) in invalidRules {
            var draft = timedDraft(timeZoneIdentifier: "GMT")
            draft.recurrence = .basic(rule)
            XCTAssertThrowsError(
                try draft.validated(calendar: calendar)
            ) { error in
                XCTAssertEqual(
                    error as? CalendarEventWriteError,
                    expectedError
                )
            }
        }
    }

    func testEventKitBasicRecurrenceMappingRoundTripsExactly() throws {
        let eventStore = EKEventStore()
        let provider = EventKitProvider(eventStore: eventStore)
        let expectedRules: [CalendarEventRecurrence] = [
            .basic(BasicRecurrenceRule(
                frequency: .daily,
                interval: 2
            )),
            .basic(BasicRecurrenceRule(
                frequency: .weekly,
                interval: 3,
                weekdays: [.monday, .thursday],
                end: .afterOccurrences(11)
            )),
            .basic(BasicRecurrenceRule(
                frequency: .monthly,
                end: .onDate(date(2027, 7, 10))
            )),
            .basic(BasicRecurrenceRule(
                frequency: .yearly,
                interval: 4
            ))
        ]

        for expected in expectedRules {
            let event = EKEvent(eventStore: eventStore)
            event.startDate = date(2026, 7, 10, 9)
            event.endDate = date(2026, 7, 10, 10)
            event.timeZone = TimeZone(secondsFromGMT: 0)
            event.recurrenceRules = try provider
                .makeEventKitRecurrenceRules(for: expected)

            XCTAssertEqual(
                provider.recurrenceRepresentation(for: event),
                expected
            )
        }
    }

    func testEventKitSingleEventNormalizesSyntheticOccurrenceDate() {
        let eventStore = EKEventStore()
        let provider = EventKitProvider(eventStore: eventStore)
        let event = EKEvent(eventStore: eventStore)
        event.startDate = date(2026, 7, 10, 9)
        event.endDate = date(2026, 7, 10, 10)

        if let syntheticOccurrenceDate = event.occurrenceDate {
            XCTAssertEqual(syntheticOccurrenceDate, event.startDate)
        }
        let classification = provider.recurrenceClassification(for: event)
        XCTAssertFalse(classification.isRecurring)
        XCTAssertNil(classification.occurrenceDate)
        XCTAssertEqual(provider.recurrenceRepresentation(for: event), .none)
    }

    func testEventKitRecurrenceClassificationUsesMembershipSignalsOnly() {
        let anchor = date(2026, 7, 10, 9)

        XCTAssertEqual(
            EventKitProvider.classifyRecurrence(
                hasRecurrenceRules: false,
                isDetached: false,
                rawOccurrenceDate: anchor
            ),
            EventKitRecurrenceClassification(
                isRecurring: false,
                occurrenceDate: nil
            )
        )
        XCTAssertEqual(
            EventKitProvider.classifyRecurrence(
                hasRecurrenceRules: true,
                isDetached: false,
                rawOccurrenceDate: anchor
            ),
            EventKitRecurrenceClassification(
                isRecurring: true,
                occurrenceDate: anchor
            )
        )
        XCTAssertEqual(
            EventKitProvider.classifyRecurrence(
                hasRecurrenceRules: false,
                isDetached: true,
                rawOccurrenceDate: anchor
            ),
            EventKitRecurrenceClassification(
                isRecurring: true,
                occurrenceDate: anchor
            )
        )
        XCTAssertEqual(
            EventKitProvider.classifyRecurrence(
                hasRecurrenceRules: true,
                isDetached: false,
                rawOccurrenceDate: nil
            ),
            EventKitRecurrenceClassification(
                isRecurring: true,
                occurrenceDate: nil
            )
        )
    }

    func testEventKitComplexAndMultipleRecurrencesStayUnsupported() throws {
        let eventStore = EKEventStore()
        let provider = EventKitProvider(eventStore: eventStore)
        let event = EKEvent(eventStore: eventStore)
        event.startDate = date(2026, 7, 10, 9)
        event.endDate = date(2026, 7, 10, 10)
        event.recurrenceRules = [
            EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: nil
            ),
            EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                end: nil
            )
        ]

        guard case let .unsupported(multiple) = provider
            .recurrenceRepresentation(for: event) else {
            return XCTFail("Expected multiple rules to stay unsupported")
        }
        XCTAssertEqual(multiple.summary, "Multiple recurrence rules")
        XCTAssertFalse(multiple.signature.isEmpty)

        event.recurrenceRules = [EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(
                .monday,
                weekNumber: 1
            )],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )]
        guard case let .unsupported(advanced) = provider
            .recurrenceRepresentation(for: event) else {
            return XCTFail("Expected ordinal rule to stay unsupported")
        }
        XCTAssertEqual(advanced.summary, "Advanced recurrence rule")
        XCTAssertNotEqual(advanced.signature, multiple.signature)
        XCTAssertThrowsError(
            try provider.makeEventKitRecurrenceRules(
                for: .unsupported(advanced)
            )
        ) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .unsupportedRecurrence
            )
        }
    }

    func testProviderSemanticOccurrenceMatchingUsesOriginalAnchor() {
        let provider = EventKitProvider(eventStore: EKEventStore())
        let originalAnchor = date(2026, 7, 10, 9)
        let original = makeEvent(
            id: "occurrence-original",
            isRecurring: true,
            startDate: originalAnchor,
            occurrenceDate: originalAnchor
        )
        let detachedMove = makeEvent(
            id: "occurrence-detached",
            isRecurring: true,
            startDate: date(2026, 7, 10, 14),
            occurrenceDate: originalAnchor,
            isDetached: true
        )
        let sibling = makeEvent(
            id: "occurrence-sibling",
            isRecurring: true,
            startDate: date(2026, 7, 17, 9),
            occurrenceDate: date(2026, 7, 17, 9)
        )

        XCTAssertTrue(
            provider.semanticOccurrenceMatches(detachedMove, original)
        )
        XCTAssertFalse(provider.semanticOccurrenceMatches(sibling, original))

        let localStart = LocalDateTimeComponents(
            date: date(2026, 7, 10, 9),
            calendar: calendar
        )
        let localEnd = LocalDateTimeComponents(
            date: date(2026, 7, 10, 10),
            calendar: calendar
        )
        let floatingBefore = makeFloatingEvent(
            id: "floating-anchor-before",
            rawStart: date(2026, 7, 10, 9),
            rawEnd: date(2026, 7, 10, 10),
            civilStart: localStart,
            civilEnd: localEnd
        )
        let floatingAfterDefaultZoneChange = makeFloatingEvent(
            id: "floating-anchor-after",
            rawStart: date(2026, 7, 10, 16),
            rawEnd: date(2026, 7, 10, 17),
            civilStart: localStart,
            civilEnd: localEnd
        )
        XCTAssertTrue(provider.semanticOccurrenceMatches(
            floatingAfterDefaultZoneChange,
            floatingBefore
        ))
    }

    func testFakeProviderReturnsScopeAwareMutationReceipts() throws {
        let provider = makeProvider()
        var draft = timedDraft(timeZoneIdentifier: "GMT")
        draft.recurrence = .basic(BasicRecurrenceRule(
            frequency: .weekly,
            weekdays: [.friday]
        ))
        let created = try provider.createEvent(draft)
        XCTAssertTrue(created.isRecurring)
        XCTAssertEqual(created.recurrence, draft.recurrence)

        var update = CalendarEventDraft(event: created, calendar: calendar)
        update.title = "Updated series"
        update.recurrence = .basic(BasicRecurrenceRule(
            frequency: .weekly,
            interval: 2,
            weekdays: [.friday]
        ))
        let receipt = try provider.updateEvent(
            created,
            with: update,
            scope: .futureEvents
        )

        XCTAssertTrue(receipt.didWrite)
        XCTAssertEqual(receipt.scope, .futureEvents)
        XCTAssertEqual(receipt.changedFields, [.title, .recurrence])
        XCTAssertEqual(provider.lastUpdateScope, .futureEvents)
        XCTAssertEqual(receipt.event.title, "Updated series")

        let deletion = try provider.deleteEvent(
            receipt.event,
            scope: .futureEvents
        )
        XCTAssertEqual(deletion.scope, .futureEvents)
        XCTAssertEqual(deletion.changedFields, [.deletion])
        XCTAssertEqual(provider.lastDeleteScope, .futureEvents)
    }

    func testFakeProviderNoOpReceiptDoesNotClaimAWrite() throws {
        let original = makeEvent(id: "no-op")
        let provider = makeProvider(events: [original])
        let draft = CalendarEventDraft(event: original, calendar: calendar)

        let receipt = try provider.updateEvent(
            original,
            with: draft,
            scope: .thisEvent
        )

        XCTAssertFalse(receipt.didWrite)
        XCTAssertTrue(receipt.changedFields.isEmpty)
        XCTAssertEqual(receipt.event, original)
        XCTAssertEqual(provider.events, [original])
    }

    func testSingleEventMutationIgnoresSyntheticOccurrenceAnchor() throws {
        let syntheticAnchor = date(2026, 7, 10, 9)
        let original = makeEvent(
            id: "single-with-synthetic-anchor",
            occurrenceDate: syntheticAnchor
        )
        let provider = makeProvider(events: [original])
        var draft = CalendarEventDraft(event: original, calendar: calendar)
        draft.title = "Updated single event"

        XCTAssertFalse(original.isRecurring)
        XCTAssertEqual(original.occurrenceDate, syntheticAnchor)
        let updated = try provider.updateEvent(original, with: draft)
        XCTAssertEqual(updated.title, "Updated single event")
        XCTAssertEqual(provider.lastUpdateScope, .thisEvent)

        try provider.deleteEvent(updated)
        XCTAssertEqual(provider.lastDeleteScope, .thisEvent)
        XCTAssertTrue(provider.events.isEmpty)
    }

    func testDefaultScopedProviderRoutesSyntheticSingleUpdateAndDelete() throws {
        let syntheticAnchor = date(2026, 7, 10, 9)
        let original = makeEvent(
            id: "default-single-with-anchor",
            occurrenceDate: syntheticAnchor
        )
        let provider = DefaultScopedCalendarProviderSpy()
        var draft = CalendarEventDraft(event: original, calendar: calendar)
        draft.title = "Updated through default scope"

        let update = try provider.updateEvent(
            original,
            with: draft,
            scope: .thisEvent
        )
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertTrue(update.didWrite)
        XCTAssertEqual(update.scope, .thisEvent)
        XCTAssertEqual(update.changedFields, [.title])

        let deletion = try provider.deleteEvent(
            original,
            scope: .thisEvent
        )
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertEqual(deletion.scope, .thisEvent)
        XCTAssertEqual(deletion.changedFields, [.deletion])
    }

    func testDefaultScopedProviderRejectsInvalidRecurrenceScopes() {
        let provider = DefaultScopedCalendarProviderSpy()
        let recurring = makeEvent(
            id: "default-recurring",
            isRecurring: true
        )
        let single = makeEvent(id: "default-single")
        let recurringDraft = CalendarEventDraft(
            event: recurring,
            calendar: calendar
        )
        let singleDraft = CalendarEventDraft(
            event: single,
            calendar: calendar
        )

        XCTAssertThrowsError(try provider.updateEvent(
            recurring,
            with: recurringDraft,
            scope: .thisEvent
        )) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .recurringScopeRequired
            )
        }
        XCTAssertThrowsError(try provider.deleteEvent(
            recurring,
            scope: .thisEvent
        )) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .recurringScopeRequired
            )
        }
        XCTAssertThrowsError(try provider.updateEvent(
            single,
            with: singleDraft,
            scope: .futureEvents
        )) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .unsupportedRecurrence
            )
        }
        XCTAssertThrowsError(try provider.deleteEvent(
            single,
            scope: .futureEvents
        )) { error in
            XCTAssertEqual(
                error as? CalendarEventWriteError,
                .unsupportedRecurrence
            )
        }
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
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

        let didRequestUpdate = await state.saveEventEditor(draft)
        XCTAssertFalse(didRequestUpdate)
        XCTAssertNotNil(state.pendingEventMutation)
        XCTAssertEqual(provider.updateCallCount, 0)

        let didUpdate = await state.confirmPendingEventMutation()
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

    func testLinkedCalendarMoveConfirmsAndRebindsWhileDeleteRoutesToReview() async throws {
        let original = makeEvent(id: "linked-block")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep this")
        )
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
        XCTAssertNotNil(state.pendingEventMutation)
        XCTAssertNotNil(state.eventEditorSession)

        let didConfirmMove = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirmMove)
        XCTAssertEqual(provider.updateCallCount, 1)
        let moved = try XCTUnwrap(state.selectedEvent)
        XCTAssertEqual(moved.calendarIdentifier, writableLocalCalendar.id)
        let rebound = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(rebound.context.notes, "Keep this")
        XCTAssertEqual(
            rebound.link.calendarIdentifier,
            writableLocalCalendar.id
        )

        state.beginEditingSelectedEvent()

        let didDelete = await state.deleteEventEditorTarget()
        XCTAssertFalse(didDelete)
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertNotNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNil(state.eventEditorError)
    }

    func testLinkedOriginalDeletionPreparationAndBackAreWriteFree() async throws {
        let original = makeEvent(id: "linked-delete-review")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep this deletion note"
        ))
        let task = try store.appendEventTask(
            for: original,
            section: .before,
            title: "Review before deleting"
        )
        let provider = makeProvider(events: [original])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        let prepared = state.prepareLinkedOriginalDeletion(scope: .thisEvent)

        XCTAssertTrue(prepared)
        XCTAssertEqual(provider.deleteCallCount, 0)
        let preview = try XCTUnwrap(state.pendingLinkedOriginalDeletion)
        XCTAssertEqual(preview.contextID, context.id)
        XCTAssertEqual(preview.scope, .thisEvent)
        XCTAssertEqual(preview.brief, before)
        XCTAssertTrue(preview.impact.hasNotes)
        XCTAssertEqual(preview.impact.notesCharacterCount, 23)
        XCTAssertEqual(preview.impact.taskCount, 1)
        XCTAssertEqual(
            preview.impact.taskSections.first(where: { $0.section == .before }),
            EventMutationTaskSummary(
                section: .before,
                count: 1,
                titles: [task.title]
            )
        )
        XCTAssertTrue(preview.impact.recentHistory.isEmpty)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            before
        )
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)

        state.cancelPendingLinkedOriginalDeletion()

        XCTAssertNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertNil(state.eventEditorError)
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            before
        )
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)
    }

    func testLinkedSingleDeletionPreservesBriefAndCreatesNonUndoableLog() async throws {
        let original = makeEvent(id: "linked-delete-success")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep successful deletion notes"
        ))
        let beforeTask = try store.appendEventTask(
            for: original,
            section: .before,
            title: "Prepare"
        )
        let afterTask = try store.appendEventTask(
            for: original,
            section: .after,
            title: "Follow up"
        )
        let provider = makeProvider(events: [original])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )
        let expectedSnapshot = try XCTUnwrap(
            state.pendingLinkedOriginalDeletion?.expectedSnapshot
        )

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertTrue(deleted)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertEqual(provider.lastDeletedEvent, original)
        XCTAssertEqual(provider.lastDeleteScope, .thisEvent)
        XCTAssertTrue(provider.events.isEmpty)
        XCTAssertTrue(state.events.isEmpty)
        XCTAssertNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNil(state.eventEditorSession)
        XCTAssertNil(state.selectedEvent)
        XCTAssertEqual(state.selectedSection, .tasks)
        XCTAssertFalse(state.canUndoLastEventMutation(for: original))

        let retained = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(retained.context.lifecycleStatus, .cancelled)
        XCTAssertEqual(retained.link.linkStatus, .orphaned)
        XCTAssertEqual(retained.context.notes, "Keep successful deletion notes")
        XCTAssertEqual(
            retained.tasks.map(\.id),
            [beforeTask.id, afterTask.id]
        )
        let cancellation = try XCTUnwrap(
            store.changeHistory(contextID: context.id).first
        )
        XCTAssertEqual(cancellation.changeType, .cancelled)
        XCTAssertEqual(cancellation.scope, .single)
        XCTAssertEqual(cancellation.before, expectedSnapshot)
        XCTAssertEqual(cancellation.after, expectedSnapshot)
        XCTAssertEqual(cancellation.undoState, .unavailable)
        XCTAssertNil(cancellation.undoneAt)
        XCTAssertNil(cancellation.undoOfChangeID)

        let recoveryBrief = try XCTUnwrap(
            state.recoveryBriefs.first(where: {
                $0.context.id == context.id
            })
        )
        XCTAssertEqual(recoveryBrief.context.lifecycleStatus, .cancelled)
        XCTAssertEqual(recoveryBrief.link.linkStatus, .orphaned)
        XCTAssertTrue(recoveryBrief.hasRecordedOriginalDeletion)
        guard case let .loaded(taskItems) = state.taskCenterState else {
            return XCTFail("Expected retained tasks in Task Center")
        }
        let retainedTaskItem = try XCTUnwrap(
            taskItems.first(where: { $0.id == .eventTask(
                taskID: beforeTask.id,
                contextID: context.id
            ) })
        )
        XCTAssertEqual(retainedTaskItem.eventLifecycleStatus, .cancelled)
        XCTAssertEqual(retainedTaskItem.eventLinkStatus, .orphaned)
        XCTAssertTrue(retainedTaskItem.wasOriginalDeletedByKaosCal)

        await state.openOriginalEvent(contextID: context.id)
        XCTAssertEqual(
            state.linkedEventRecoverySession?.stage,
            .deletedOriginal
        )
    }

    func testLinkedRecurringDeletionAllowsThisEventAndBlocksFutureEvents() async throws {
        let recurring = makeEvent(
            id: "linked-recurring-delete",
            isRecurring: true
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: recurring,
            notes: "Keep recurring deletion notes"
        ))
        let task = try store.appendEventTask(
            for: recurring,
            section: .during,
            title: "Keep occurrence task"
        )
        let provider = makeProvider(events: [recurring])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(recurring.id)
        state.beginEditingSelectedEvent()

        let preparedFuture = state.prepareLinkedOriginalDeletion(
            scope: .futureEvents
        )

        XCTAssertFalse(preparedFuture)
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertNil(state.pendingLinkedOriginalDeletion)
        XCTAssertTrue(
            state.eventEditorError?.contains("this and future occurrences")
                == true
        )

        state.clearEventEditorError()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )
        XCTAssertEqual(provider.deleteCallCount, 0)

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertTrue(deleted)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertEqual(provider.lastDeleteScope, .thisEvent)
        let retained = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(retained.context.lifecycleStatus, .cancelled)
        XCTAssertEqual(retained.link.linkStatus, .orphaned)
        XCTAssertEqual(retained.context.notes, "Keep recurring deletion notes")
        XCTAssertEqual(retained.tasks.map(\.id), [task.id])
        let cancellation = try XCTUnwrap(
            store.changeHistory(contextID: context.id).first
        )
        XCTAssertEqual(cancellation.changeType, .cancelled)
        XCTAssertEqual(cancellation.scope, .thisEvent)
        XCTAssertEqual(cancellation.undoState, .unavailable)
    }

    func testLinkedDeletionProviderFailureKeepsReviewAndLocalBriefIntact() async throws {
        let original = makeEvent(id: "linked-delete-provider-failure")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep provider failure notes"
        ))
        let task = try store.appendEventTask(
            for: original,
            section: .after,
            title: "Keep provider failure task"
        )
        let provider = makeProvider(events: [original])
        provider.deleteMutationHandler = { _, _ in
            throw FakeCalendarProviderError.failed
        }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertFalse(deleted)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertEqual(provider.events, [original])
        XCTAssertNotNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertEqual(state.eventEditorError, "Calendar provider failed")
        let after = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.link.linkStatus, .active)
        XCTAssertEqual(after.context.notes, "Keep provider failure notes")
        XCTAssertEqual(after.tasks.map(\.id), [task.id])
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)
    }

    func testLinkedDeletionStalePreflightStopsBeforeProviderWrite() async throws {
        let original = makeEvent(id: "linked-delete-stale")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep stale deletion notes"
        ))
        let provider = makeProvider(events: [original])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )
        let refreshedEvent = makeEvent(
            id: original.id,
            startDate: date(2026, 7, 10, 15)
        )
        let refreshed = try store.rebindUserApprovedMutation(
            contextID: context.id,
            to: refreshedEvent
        )

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertFalse(deleted)
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertEqual(provider.events, [original])
        XCTAssertNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertNotNil(state.eventEditorError)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            refreshed
        )
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)
    }

    func testLinkedDeletionLocalFinalizeFailureCannotRetryProviderDelete() async throws {
        let original = makeEvent(id: "linked-delete-local-failure")
        let database = try AppDatabase.inMemory()
        let store = ContextStore(database: database)
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep local failure notes"
        ))
        let task = try store.appendEventTask(
            for: original,
            section: .after,
            title: "Recover local failure task"
        )
        let provider = makeProvider(events: [original])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        try database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_linked_cancelled_log
                BEFORE INSERT ON event_change_log
                WHEN NEW.change_type = 'cancelled'
                BEGIN
                    SELECT RAISE(ABORT, 'linked cancellation rejected');
                END
                """)
        }

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertFalse(deleted)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertTrue(provider.events.isEmpty)
        XCTAssertNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNil(state.eventEditorSession)
        XCTAssertNil(state.selectedEvent)
        XCTAssertEqual(state.selectedSection, .tasks)
        XCTAssertTrue(
            state.eventEditorError?.hasPrefix(
                "The original calendar event was deleted, but its local Event Brief could not be finalized. Do not retry Delete."
            ) == true
        )
        let retained = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(retained, before)
        XCTAssertEqual(retained.link.linkStatus, .active)
        XCTAssertEqual(retained.context.notes, "Keep local failure notes")
        XCTAssertEqual(retained.tasks.map(\.id), [task.id])
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)

        let retried = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertFalse(retried)
        XCTAssertEqual(provider.deleteCallCount, 1)
    }

    func testLinkedDeletionLinkRaceAfterProviderWriteUsesNonRetryablePartialPath() async throws {
        let original = makeEvent(id: "linked-delete-link-race")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep link-race notes"
        ))
        let provider = makeProvider(events: [original])
        let concurrentlyRebound = makeEvent(
            id: original.id,
            startDate: date(2026, 7, 10, 16),
            calendarIdentifier: writableLocalCalendar.id
        )
        provider.deleteMutationHandler = { event, scope in
            _ = try store.rebindUserApprovedMutation(
                contextID: context.id,
                to: concurrentlyRebound
            )
            provider.events.removeAll { $0.id == event.id }
            return CalendarEventMutationReceipt(
                event: event,
                didWrite: true,
                scope: scope,
                changedFields: [.deletion]
            )
        }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertFalse(deleted)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertTrue(provider.events.isEmpty)
        XCTAssertNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNil(state.eventEditorSession)
        XCTAssertTrue(
            state.eventEditorError?.contains("Do not retry Delete") == true
        )
        let retained = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(retained.link.linkStatus, .active)
        XCTAssertEqual(
            retained.link.calendarIdentifier,
            writableLocalCalendar.id
        )
        XCTAssertEqual(retained.context.notes, "Keep link-race notes")
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)

        let retried = await state.confirmPendingLinkedOriginalDeletion()
        XCTAssertFalse(retried)
        XCTAssertEqual(provider.deleteCallCount, 1)
    }

    func testLinkedDeletionNoOpReceiptKeepsReviewAndLocalState() async throws {
        let original = makeEvent(id: "linked-delete-no-op")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep no-op notes"
        ))
        let provider = makeProvider(events: [original])
        provider.deleteMutationHandler = { event, scope in
            CalendarEventMutationReceipt(
                event: event,
                didWrite: false,
                scope: scope,
                changedFields: []
            )
        }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertFalse(deleted)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertEqual(provider.events, [original])
        XCTAssertNotNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNotNil(state.eventEditorSession)
        XCTAssertTrue(
            state.eventEditorError?.contains(
                "did not confirm a deletion"
            ) == true
        )
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            before
        )
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)
    }

    func testLinkedDeletionInvalidPositiveReceiptClosesReviewWithoutLocalFinalize() async throws {
        let original = makeEvent(id: "linked-delete-invalid-receipt")
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep invalid-receipt notes"
        ))
        let provider = makeProvider(events: [original])
        provider.deleteMutationHandler = { event, scope in
            provider.events.removeAll { $0.id == event.id }
            return CalendarEventMutationReceipt(
                event: event,
                didWrite: true,
                scope: scope,
                changedFields: []
            )
        }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        XCTAssertTrue(
            state.prepareLinkedOriginalDeletion(scope: .thisEvent)
        )
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        let deleted = await state.confirmPendingLinkedOriginalDeletion()

        XCTAssertFalse(deleted)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertTrue(provider.events.isEmpty)
        XCTAssertNil(state.pendingLinkedOriginalDeletion)
        XCTAssertNil(state.eventEditorSession)
        XCTAssertTrue(
            state.eventEditorError?.contains("invalid receipt") == true
        )
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            before
        )
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)

        let retried = await state.confirmPendingLinkedOriginalDeletion()
        XCTAssertFalse(retried)
        XCTAssertEqual(provider.deleteCallCount, 1)
    }

    func testPastDeletionLogAfterRelinkDoesNotLabelLaterCancelledOrphanAsDeletedOriginal() async throws {
        let timestamp = date(2026, 7, 10, 12)
        let original = makeEvent(id: "cancelled-orphan-provenance")
        let database = try AppDatabase.inMemory()
        let store = ContextStore(database: database, now: { timestamp })
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "External cancellation notes"
        ))
        let task = try store.appendEventTask(
            for: original,
            section: .after,
            title: "External cancellation task"
        )
        let preparation = try store.prepareLinkedOriginalDeletion(
            contextID: context.id
        )
        let deleted = try store.finalizeLinkedOriginalDeletion(
            contextID: context.id,
            expectedLink: preparation.brief.link,
            expectedSnapshot: preparation.changeSnapshot,
            scope: .single
        )
        XCTAssertTrue(deleted.hasRecordedOriginalDeletion)

        let replacement = makeEvent(
            id: "cancelled-orphan-replacement",
            startDate: date(2026, 7, 10, 13)
        )
        let relinked = try store.relinkLocalBrief(
            contextID: context.id,
            to: replacement,
            expectedLink: deleted.link,
            at: timestamp,
            calendar: calendar
        )
        XCTAssertFalse(relinked.hasRecordedOriginalDeletion)
        XCTAssertEqual(
            relinked,
            try store.eventContexts.fetchBrief(contextID: context.id)
        )

        // Simulate a later provider-side cancellation/orphan transition without
        // adding a KaosCal original-deletion record for the replacement link.
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE event_contexts
                    SET lifecycle_status = 'cancelled'
                    WHERE id = ?
                    """,
                arguments: [context.id]
            )
            try db.execute(
                sql: """
                    UPDATE event_links
                    SET link_status = 'orphaned'
                    WHERE context_id = ?
                    """,
                arguments: [context.id]
            )
        }
        let history = try store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.changeType), [.relinked, .cancelled])
        XCTAssertEqual(history.map(\.createdAt), [timestamp, timestamp])
        let state = makeState(provider: makeProvider(), store: store)

        await state.loadCalendarStatus()

        let brief = try XCTUnwrap(
            state.recoveryBriefs.first(where: {
                $0.context.id == context.id
            })
        )
        XCTAssertEqual(brief.context.lifecycleStatus, .cancelled)
        XCTAssertEqual(brief.link.linkStatus, .orphaned)
        XCTAssertFalse(brief.hasRecordedOriginalDeletion)
        guard case let .loaded(taskItems) = state.taskCenterState else {
            return XCTFail("Expected external cancellation task")
        }
        let item = try XCTUnwrap(taskItems.first(where: {
            $0.id == .eventTask(
                taskID: task.id,
                contextID: context.id
            )
        }))
        XCTAssertFalse(item.wasOriginalDeletedByKaosCal)

        await state.openOriginalEvent(contextID: context.id)
        XCTAssertEqual(state.linkedEventRecoverySession?.stage, .orphaned)
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

        let didRequestMove = await state.saveEventEditor(draft)
        XCTAssertFalse(didRequestMove)
        XCTAssertNotNil(state.pendingEventMutation)
        XCTAssertEqual(provider.updateCallCount, 0)

        let didMove = await state.confirmPendingEventMutation()
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

    func testOriginalWritePolicyBlocksReadOnlyAndMeetingEvents() async {
        let blockedEvents = [
            makeEvent(id: "read-only", isReadOnly: true),
            makeEvent(id: "invitation", isInvitation: true),
            makeEvent(id: "meeting", hasAttendees: true),
            makeEvent(id: "subscribed", accountType: .subscribed),
            makeEvent(id: "birthdays", accountType: .birthdays)
        ]

        for event in blockedEvents {
            let provider = makeProvider(events: [event])
            let state = makeState(provider: provider)
            await state.loadCalendarStatus()
            state.selectEvent(event.id)

            state.beginEditingSelectedEvent()

            XCTAssertNil(state.eventEditorSession)
            XCTAssertEqual(
                state.eventEditorError,
                state.calendarWriteRestriction(for: event)?.message
            )
            XCTAssertEqual(provider.updateCallCount, 0)
            XCTAssertEqual(provider.deleteCallCount, 0)
        }
    }

    func testRecurringEventRequiresExplicitScopeAndConfirmation() async throws {
        let recurring = makeEvent(id: "recurring", isRecurring: true)
        let provider = makeProvider(events: [recurring])
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(recurring.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession?.initialDraft)
        draft.title = "This occurrence changed"

        let withoutScope = await state.saveEventEditor(draft)
        XCTAssertFalse(withoutScope)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError.recurringScopeRequired.localizedDescription
        )

        state.clearEventEditorError()
        let requested = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(requested)
        XCTAssertNotNil(state.pendingEventMutation)
        XCTAssertEqual(provider.updateCallCount, 0)

        let confirmed = await state.confirmPendingEventMutation()
        XCTAssertTrue(confirmed)
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertEqual(provider.lastUpdateScope, .thisEvent)
        XCTAssertEqual(state.selectedEvent?.title, "This occurrence changed")
    }

    func testRecurringRuleChangeRequiresFutureScope() async throws {
        let recurring = makeEvent(id: "rule-scope", isRecurring: true)
        let provider = makeProvider(events: [recurring])
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(recurring.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession?.initialDraft)
        draft.recurrence = .basic(BasicRecurrenceRule(
            frequency: .weekly,
            interval: 2,
            weekdays: [.friday]
        ))

        let thisEvent = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(thisEvent)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError
                .recurrenceChangeRequiresFutureScope.localizedDescription
        )

        state.clearEventEditorError()
        let requestedFuture = await state.saveEventEditor(
            draft,
            scope: .futureEvents
        )
        XCTAssertFalse(requestedFuture)
        XCTAssertNotNil(state.pendingEventMutation)
        XCTAssertEqual(provider.updateCallCount, 0)

        let confirmed = await state.confirmPendingEventMutation()
        XCTAssertTrue(confirmed)
        XCTAssertEqual(provider.lastUpdateScope, .futureEvents)
        XCTAssertEqual(state.selectedEvent?.recurrence, draft.recurrence)
    }

    func testDetachedAndUnsupportedFutureScopesStopBeforeProviderWrite() async {
        let unsupported = CalendarEventRecurrence.unsupported(
            UnsupportedRecurrenceSnapshot(
                summary: "Complex Exchange rule",
                signature: "complex:v1"
            )
        )
        let blocked = [
            makeEvent(
                id: "detached-future",
                isRecurring: true,
                isDetached: true
            ),
            makeEvent(
                id: "unsupported-future",
                isRecurring: true,
                recurrence: unsupported
            )
        ]

        for event in blocked {
            let provider = makeProvider(events: [event])
            let state = makeState(provider: provider)
            await state.loadCalendarStatus()
            state.selectEvent(event.id)
            state.beginEditingSelectedEvent()
            guard var draft = state.eventEditorSession?.initialDraft else {
                return XCTFail("Expected safe this-event editing to open")
            }
            draft.title = "Future write must stop"

            let didSave = await state.saveEventEditor(
                draft,
                scope: .futureEvents
            )

            XCTAssertFalse(didSave)
            XCTAssertEqual(provider.updateCallCount, 0)
            XCTAssertNil(state.pendingEventMutation)
            XCTAssertNotNil(state.eventEditorError)
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

    func testDedicatedLookupMatcherRequiresExactRecurringAnchor() {
        let provider = EventKitProvider(eventStore: EKEventStore())
        let occurrence = date(2026, 7, 10, 9)
        let original = makeEvent(
            id: "lookup-original",
            isRecurring: true,
            startDate: occurrence,
            occurrenceDate: occurrence
        )
        let query = CalendarEventLookupQuery(
            eventIdentifier: original.eventIdentifier,
            calendarItemIdentifier: original.calendarItemIdentifier,
            calendarItemExternalIdentifier: original.calendarItemExternalIdentifier,
            calendarIdentifier: original.calendarIdentifier,
            occurrence: .instant(occurrence),
            searchAnchors: [occurrence],
            lastKnown: CalendarEventLookupSnapshot(
                calendarTitle: original.calendarTitle,
                sourceTitle: original.sourceTitle,
                title: original.title,
                location: original.location,
                startDate: original.startDate,
                endDate: original.endDate,
                isAllDay: false,
                timeSemantics: original.timeSemantics
            )
        )
        let detached = makeEvent(
            id: "lookup-detached",
            isRecurring: true,
            startDate: date(2026, 7, 10, 14),
            occurrenceDate: occurrence,
            isDetached: true
        )
        let sibling = makeEvent(
            id: "lookup-sibling",
            isRecurring: true,
            startDate: date(2026, 7, 17, 9),
            occurrenceDate: date(2026, 7, 17, 9)
        )
        let syntheticSingle = makeEvent(
            id: "lookup-single",
            startDate: occurrence,
            occurrenceDate: occurrence
        )

        XCTAssertTrue(provider.lookupOccurrenceMatches(detached, query: query))
        XCTAssertFalse(provider.lookupOccurrenceMatches(sibling, query: query))
        XCTAssertFalse(provider.lookupOccurrenceMatches(syntheticSingle, query: query))
    }

    func testDedicatedLookupMatcherUsesFloatingCivilAnchor() {
        let provider = EventKitProvider(eventStore: EKEventStore())
        let civilStart = LocalDateTimeComponents(
            date: date(2026, 7, 10, 9),
            calendar: calendar
        )
        let civilEnd = LocalDateTimeComponents(
            date: date(2026, 7, 10, 10),
            calendar: calendar
        )
        let candidate = DisplayEvent(
            id: "floating-lookup",
            eventIdentifier: "floating-event",
            calendarItemIdentifier: "floating-item",
            calendarItemExternalIdentifier: "floating-external",
            calendarIdentifier: "calendar",
            calendarTitle: "KAOS-TEST",
            sourceTitle: "Work",
            accountType: .exchange,
            calendarColor: nil,
            title: "Floating lookup",
            location: nil,
            startDate: date(2026, 7, 10, 16),
            endDate: date(2026, 7, 10, 17),
            isAllDay: false,
            timeZoneIdentifier: nil,
            timeSemantics: .floating(start: civilStart, end: civilEnd),
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 16),
            occurrenceLocalComponents: civilStart,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil,
            recurrence: .basic(BasicRecurrenceRule(frequency: .weekly))
        )
        let query = CalendarEventLookupQuery(
            eventIdentifier: candidate.eventIdentifier,
            calendarItemIdentifier: candidate.calendarItemIdentifier,
            calendarItemExternalIdentifier: candidate.calendarItemExternalIdentifier,
            calendarIdentifier: candidate.calendarIdentifier,
            occurrence: .floating(civilStart),
            searchAnchors: [candidate.startDate],
            lastKnown: CalendarEventLookupSnapshot(
                calendarTitle: candidate.calendarTitle,
                sourceTitle: candidate.sourceTitle,
                title: candidate.title,
                location: nil,
                startDate: candidate.startDate,
                endDate: candidate.endDate,
                isAllDay: false,
                timeSemantics: candidate.timeSemantics
            )
        )

        XCTAssertTrue(provider.lookupOccurrenceMatches(candidate, query: query))
    }

    func testDedicatedLookupRecurringSeedInAnotherCalendarIsInconclusive() throws {
        let provider = EventKitProvider(eventStore: EKEventStore())
        let occurrence = date(2026, 7, 10, 9)
        let original = makeEvent(
            id: "cross-calendar-series",
            isRecurring: true,
            startDate: occurrence,
            occurrenceDate: occurrence
        )
        let query = try CalendarEventLookupQuery(event: original)
        let firstSeriesOccurrenceInAnotherCalendar = makeEvent(
            id: original.id,
            isRecurring: true,
            startDate: date(2026, 7, 17, 9),
            occurrenceDate: date(2026, 7, 17, 9),
            calendarIdentifier: "destination-calendar"
        )

        XCTAssertFalse(provider.lookupOccurrenceMatches(
            firstSeriesOccurrenceInAnotherCalendar,
            query: query
        ))
        XCTAssertEqual(
            provider.lookupStrongIdentifierMismatchIssue(
                firstSeriesOccurrenceInAnotherCalendar,
                query: query
            ),
            .recurringOccurrenceUnavailable
        )
        XCTAssertEqual(
            provider.lookupTerminalResult(
                strongIdentifierMismatchIssue:
                    .recurringOccurrenceUnavailable,
                savedCalendarIsAvailable: true
            ),
            .inconclusive(.recurringOccurrenceUnavailable)
        )
    }

    func testDedicatedLookupShapeMismatchIsInconclusiveButNoSeedIsNotFound() throws {
        let provider = EventKitProvider(eventStore: EKEventStore())
        let original = makeEvent(
            id: "single-became-recurring",
            startDate: date(2026, 7, 10, 9)
        )
        let query = try CalendarEventLookupQuery(event: original)
        let currentRecurringItem = makeEvent(
            id: original.id,
            isRecurring: true,
            startDate: date(2026, 7, 12, 14),
            occurrenceDate: date(2026, 7, 12, 14)
        )

        XCTAssertFalse(provider.lookupOccurrenceMatches(
            currentRecurringItem,
            query: query
        ))
        XCTAssertEqual(
            provider.lookupStrongIdentifierMismatchIssue(
                currentRecurringItem,
                query: query
            ),
            .strongIdentifierOccurrenceMismatch
        )
        XCTAssertEqual(
            provider.lookupTerminalResult(
                strongIdentifierMismatchIssue:
                    .strongIdentifierOccurrenceMismatch,
                savedCalendarIsAvailable: true
            ),
            .inconclusive(.strongIdentifierOccurrenceMismatch)
        )
        XCTAssertEqual(
            provider.lookupTerminalResult(
                strongIdentifierMismatchIssue: nil,
                savedCalendarIsAvailable: true
            ),
            .notFound
        )
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
        accountType: CalendarAccountType = .exchange,
        isRecurring: Bool = false,
        recurrence: CalendarEventRecurrence? = nil,
        startDate: Date? = nil,
        occurrenceDate: Date? = nil,
        isDetached: Bool = false,
        calendarIdentifier: String? = nil
    ) -> DisplayEvent {
        let start = startDate ?? date(2026, 7, 10, 9)
        let recurrence = recurrence ?? (isRecurring
            ? .basic(BasicRecurrenceRule(
                frequency: .weekly,
                weekdays: [.friday]
            ))
            : .none)
        return DisplayEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            calendarItemIdentifier: "item-\(id)",
            calendarItemExternalIdentifier: "external-\(id)",
            calendarIdentifier: calendarIdentifier ?? writableExchangeCalendar.id,
            calendarTitle: writableExchangeCalendar.title,
            sourceTitle: writableExchangeCalendar.sourceTitle,
            accountType: accountType,
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
            occurrenceDate: occurrenceDate ?? (isRecurring ? start : nil),
            occurrenceLocalComponents: nil,
            isDetached: isDetached,
            isReadOnly: isReadOnly,
            isInvitation: isInvitation,
            hasAttendees: hasAttendees,
            originalNotes: nil,
            recurrence: recurrence
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

@MainActor
private final class DefaultScopedCalendarProviderSpy: CalendarProviding {
    var authorizationState = CalendarAuthorizationState.fullAccess
    var storeChangeHandler: (() -> Void)?
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0

    func requestFullAccess() async throws -> Bool { true }
    func listCalendars() throws -> [CalendarSource] { [] }
    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent] { [] }
    func lookupEvent(
        _ query: CalendarEventLookupQuery
    ) throws -> CalendarEventLookupResult { .notFound }
    func defaultCalendarIdentifierForNewEvents() -> String? { nil }

    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent {
        throw FakeCalendarProviderError.failed
    }

    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent {
        updateCallCount += 1
        return original
    }

    func deleteEvent(_ original: DisplayEvent) throws {
        deleteCallCount += 1
    }
}
