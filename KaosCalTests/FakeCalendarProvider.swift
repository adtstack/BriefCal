import Foundation
@testable import KaosCal

enum FakeCalendarProviderError: LocalizedError {
    case failed

    var errorDescription: String? { "Calendar provider failed" }
}

@MainActor
final class FakeCalendarProvider: CalendarProviding {
    var authorizationState: CalendarAuthorizationState
    var storeChangeHandler: (() -> Void)?
    var requestResult = true
    var calendars: [CalendarSource] = []
    var events: [DisplayEvent] = []
    var eventsForInterval: ((DateInterval) -> [DisplayEvent])?
    var error: Error?
    var defaultNewEventCalendarIdentifier: String?
    var createEventHandler: ((CalendarEventDraft) throws -> DisplayEvent)?
    var updateEventHandler: ((DisplayEvent, CalendarEventDraft) throws -> DisplayEvent)?
    var updateMutationHandler: ((
        DisplayEvent,
        CalendarEventDraft,
        CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt)?
    var deleteEventHandler: ((DisplayEvent) throws -> Void)?
    var deleteMutationHandler: ((
        DisplayEvent,
        CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt)?
    private(set) var requestCallCount = 0
    private(set) var listCallCount = 0
    private(set) var fetchCallCount = 0
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastFetchInterval: DateInterval?
    private(set) var lastCreatedDraft: CalendarEventDraft?
    private(set) var lastUpdatedEvent: DisplayEvent?
    private(set) var lastUpdatedDraft: CalendarEventDraft?
    private(set) var lastDeletedEvent: DisplayEvent?
    private(set) var lastUpdateScope: CalendarEventMutationScope?
    private(set) var lastDeleteScope: CalendarEventMutationScope?

    init(authorizationState: CalendarAuthorizationState = .notDetermined) {
        self.authorizationState = authorizationState
    }

    func requestFullAccess() async throws -> Bool {
        requestCallCount += 1
        if let error { throw error }
        authorizationState = requestResult ? .fullAccess : .denied
        return requestResult
    }

    func listCalendars() throws -> [CalendarSource] {
        listCallCount += 1
        if let error { throw error }
        return calendars
    }

    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent] {
        fetchCallCount += 1
        lastFetchInterval = interval
        if let error { throw error }
        return eventsForInterval?(interval) ?? events
    }

    func defaultCalendarIdentifierForNewEvents() -> String? {
        defaultNewEventCalendarIdentifier
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent {
        createCallCount += 1
        lastCreatedDraft = draft
        if let error { throw error }
        if case .unsupported = draft.recurrence {
            throw CalendarEventWriteError.unsupportedRecurrence
        }
        let event = try createEventHandler?(draft)
            ?? makeEvent(draft: draft, idSeed: "created-\(createCallCount)")
        events.append(event)
        return event
    }

    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent {
        if original.isRecurring
            || original.occurrenceDate != nil
            || original.isDetached {
            throw CalendarEventWriteError.recurringScopeRequired
        }
        return try updateEvent(
            original,
            with: draft,
            scope: .thisEvent
        ).event
    }

    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt {
        updateCallCount += 1
        lastUpdatedEvent = original
        lastUpdatedDraft = draft
        lastUpdateScope = scope
        if let error { throw error }
        if let updateMutationHandler {
            return try updateMutationHandler(original, draft, scope)
        }
        let currentDraft = CalendarEventDraft(
            event: original,
            calendar: draft.wallTimeCalendar(fallback: .autoupdatingCurrent)
        )
        let changedFields = draft.changedFields(comparedTo: currentDraft)
        guard !changedFields.isEmpty else {
            return CalendarEventMutationReceipt(
                event: original,
                didWrite: false,
                scope: scope,
                changedFields: []
            )
        }
        let event = try updateEventHandler?(original, draft)
            ?? makeEvent(
                draft: draft,
                idSeed: draft.calendarIdentifier == original.calendarIdentifier
                    ? original.id
                    : "moved-\(updateCallCount)"
            )
        if let index = events.firstIndex(where: { $0.id == original.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        return CalendarEventMutationReceipt(
            event: event,
            didWrite: true,
            scope: scope,
            changedFields: changedFields
        )
    }

    func deleteEvent(_ original: DisplayEvent) throws {
        if original.isRecurring
            || original.occurrenceDate != nil
            || original.isDetached {
            throw CalendarEventWriteError.recurringScopeRequired
        }
        _ = try deleteEvent(original, scope: .thisEvent)
    }

    func deleteEvent(
        _ original: DisplayEvent,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt {
        deleteCallCount += 1
        lastDeletedEvent = original
        lastDeleteScope = scope
        if let error { throw error }
        if let deleteMutationHandler {
            return try deleteMutationHandler(original, scope)
        }
        try deleteEventHandler?(original)
        events.removeAll { $0.id == original.id }
        return CalendarEventMutationReceipt(
            event: original,
            didWrite: true,
            scope: scope,
            changedFields: [.deletion]
        )
    }

    func sendStoreChanged() {
        storeChangeHandler?()
    }

    private func makeEvent(
        draft: CalendarEventDraft,
        idSeed: String
    ) -> DisplayEvent {
        let source = calendars.first {
            $0.id == draft.calendarIdentifier
        }
        var semanticCalendar = Calendar(identifier: .gregorian)
        semanticCalendar.timeZone = draft.timeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? .autoupdatingCurrent
        let timeSemantics: EventTimeSemantics
        if draft.isAllDay {
            timeSemantics = .allDay(
                start: LocalDateTimeComponents(
                    date: draft.startDate,
                    calendar: semanticCalendar
                ),
                endExclusive: LocalDateTimeComponents(
                    date: draft.endDate,
                    calendar: semanticCalendar
                )
            )
        } else if let identifier = draft.timeZoneIdentifier {
            timeSemantics = .zoned(timeZoneIdentifier: identifier)
        } else {
            timeSemantics = .floating(
                start: LocalDateTimeComponents(
                    date: draft.startDate,
                    calendar: semanticCalendar
                ),
                end: LocalDateTimeComponents(
                    date: draft.endDate,
                    calendar: semanticCalendar
                )
            )
        }
        return DisplayEvent(
            id: idSeed,
            eventIdentifier: "event-\(idSeed)",
            calendarItemIdentifier: "item-\(idSeed)",
            calendarItemExternalIdentifier: "external-\(idSeed)",
            calendarIdentifier: draft.calendarIdentifier,
            calendarTitle: source?.title ?? "Calendar",
            sourceTitle: source?.sourceTitle ?? "Local",
            accountType: source?.accountType ?? .unknown,
            calendarColor: source?.color,
            title: draft.title,
            location: draft.location.isEmpty ? nil : draft.location,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            timeSemantics: timeSemantics,
            isRecurring: draft.recurrence.isRecurring,
            occurrenceDate: draft.recurrence.isRecurring
                ? draft.startDate
                : nil,
            occurrenceLocalComponents: draft.recurrence.isRecurring
                ? recurrenceLocalComponents(
                    for: draft,
                    timeSemantics: timeSemantics
                )
                : nil,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: draft.originalNotes.isEmpty
                ? nil
                : draft.originalNotes,
            recurrence: draft.recurrence
        )
    }

    private func recurrenceLocalComponents(
        for draft: CalendarEventDraft,
        timeSemantics: EventTimeSemantics
    ) -> LocalDateTimeComponents? {
        switch timeSemantics {
        case .zoned:
            return nil
        case let .allDay(start, _), let .floating(start, _):
            return start
        }
    }
}
