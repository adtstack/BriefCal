import Foundation

#if DEBUG
private enum UITestCalendarProviderError: LocalizedError {
    case transientRefresh

    var errorDescription: String? {
        "Injected UI test refresh failure"
    }
}

/// Deterministic, process-local data used only by launches that explicitly pass
/// `--ui-testing`. It prevents UI automation from reading calendars, Keychain,
/// provider accounts, or the production SQLite database.
@MainActor
final class UITestCalendarProvider: CalendarProviding {
    private enum Scenario {
        case baseline
        case refreshFailure

        init(name: String?) {
            self = name == "refresh-failure" ? .refreshFailure : .baseline
        }
    }

    let authorizationState: CalendarAuthorizationState = .fullAccess
    var storeChangeHandler: (() -> Void)?

    private let scenario: Scenario
    private let sources: [CalendarSource]
    private var events: [DisplayEvent]
    private var fetchCounts: [String: Int] = [:]

    init(scenarioName: String?) {
        scenario = Scenario(name: scenarioName)
        let source = CalendarSource(
            id: "ui-calendar",
            title: "UI Test Calendar",
            sourceTitle: "Local Fixture",
            sourceIdentifier: "ui-source",
            accountType: .local,
            isWritable: true,
            color: CalendarColor(red: 0.20, green: 0.47, blue: 0.95, alpha: 1)
        )
        sources = [source]
        events = [Self.fixtureEvent(source: source)]
    }

    func requestFullAccess() async throws -> Bool { true }

    func listCalendars() async throws -> [CalendarSource] {
        await Task.yield()
        return sources
    }

    func fetchEvents(in interval: DateInterval) async throws -> [DisplayEvent] {
        await Task.yield()
        let key = [
            interval.start.timeIntervalSinceReferenceDate,
            interval.end.timeIntervalSinceReferenceDate
        ].map { String($0) }.joined(separator: ":")
        let priorFetchCount = fetchCounts[key, default: 0]
        fetchCounts[key] = priorFetchCount + 1
        if scenario == .refreshFailure, priorFetchCount > 0 {
            throw UITestCalendarProviderError.transientRefresh
        }
        return events.filter {
            $0.startDate < interval.end && $0.endDate > interval.start
        }
    }

    func lookupEvent(
        _ query: CalendarEventLookupQuery
    ) async throws -> CalendarEventLookupResult {
        await Task.yield()
        guard let event = events.first(where: {
            $0.calendarIdentifier == query.calendarIdentifier
                && ($0.eventIdentifier == query.eventIdentifier
                    || $0.calendarItemIdentifier == query.calendarItemIdentifier
                    || $0.calendarItemExternalIdentifier
                        == query.calendarItemExternalIdentifier)
        }) else {
            return .notFound
        }
        return .found(CalendarEventLookupMatch(
            event: event,
            basis: .eventIdentifierAndOccurrence
        ))
    }

    func defaultCalendarIdentifierForNewEvents() -> String? {
        sources.first?.id
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent {
        throw CalendarEventWriteError.readOnlyCalendar
    }

    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent {
        throw CalendarEventWriteError.readOnlyCalendar
    }

    func deleteEvent(_ original: DisplayEvent) throws {
        throw CalendarEventWriteError.readOnlyCalendar
    }

    private static func fixtureEvent(source: CalendarSource) -> DisplayEvent {
        let start = Date(timeIntervalSince1970: 1_785_747_600)
        let end = Date(timeIntervalSince1970: 1_785_751_200)
        return DisplayEvent(
            id: "ui-event-planning",
            eventIdentifier: "ui-event-planning",
            calendarItemIdentifier: "ui-item-planning",
            calendarItemExternalIdentifier: "ui-external-planning",
            calendarIdentifier: source.id,
            calendarTitle: source.title,
            sourceTitle: source.sourceTitle,
            accountType: source.accountType,
            calendarColor: source.color,
            title: "Planning Review",
            location: "Design Room",
            startDate: start,
            endDate: end,
            isAllDay: false,
            timeZoneIdentifier: "GMT",
            timeSemantics: .zoned(timeZoneIdentifier: "GMT"),
            isRecurring: false,
            occurrenceDate: nil,
            occurrenceLocalComponents: nil,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: "Deterministic UI automation fixture",
            recurrence: .none,
            availability: .busy,
            isCancelled: false,
            isDeclinedByCurrentUser: false
        )
    }
}
#endif
