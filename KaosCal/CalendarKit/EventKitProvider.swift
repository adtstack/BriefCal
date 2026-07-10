import AppKit
import EventKit
import Foundation

@MainActor
final class EventKitProvider: CalendarProviding {
    private let eventStore: EKEventStore
    private let notificationCenter: NotificationCenter
    private var storeChangeObserver: NSObjectProtocol?

    var storeChangeHandler: (() -> Void)?

    init(
        eventStore: EKEventStore = EKEventStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.eventStore = eventStore
        self.notificationCenter = notificationCenter
        storeChangeObserver = notificationCenter.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.storeChangeHandler?()
            }
        }
    }

    deinit {
        if let storeChangeObserver {
            notificationCenter.removeObserver(storeChangeObserver)
        }
    }

    var authorizationState: CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unknown
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func listCalendars() throws -> [CalendarSource] {
        eventStore.calendars(for: .event)
            .map { calendar in
                CalendarSource(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title,
                    accountType: accountType(for: calendar.source.sourceType),
                    isWritable: calendar.allowsContentModifications,
                    color: colorSnapshot(for: calendar)
                )
            }
            .sorted {
                if $0.sourceTitle == $1.sourceTitle {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
            .map(makeDisplayEvent)
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
    }

    func defaultCalendarIdentifierForNewEvents() -> String? {
        guard let calendar = eventStore.defaultCalendarForNewEvents,
              calendar.allowsContentModifications else {
            return nil
        }
        return calendar.calendarIdentifier
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent {
        try requireFullAccess()
        let normalized = try draft.validated(calendar: validationCalendar())
        let calendar = try writableCalendar(
            identifier: normalized.calendarIdentifier
        )
        let event = EKEvent(eventStore: eventStore)
        applyAll(normalized, calendar: calendar, to: event)
        try eventStore.save(event, span: .thisEvent, commit: true)
        return makeDisplayEvent(event)
    }

    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent {
        try requireFullAccess()
        try validateWritePolicy(original)
        let normalized = try draft.validated(calendar: validationCalendar())
        let event = try resolveEvent(for: original)
        try validateCurrentWritePolicy(event)
        guard editableFieldsMatch(
            makeDisplayEvent(event),
            original
        ) else {
            throw CalendarEventWriteError.eventChangedExternally
        }
        let calendar = try writableCalendar(
            identifier: normalized.calendarIdentifier
        )
        let current = makeDisplayEvent(event)
        let comparisonCalendar = normalized.wallTimeCalendar(
            fallback: validationCalendar()
        )
        let currentDraft = try CalendarEventDraft(
            event: current,
            calendar: comparisonCalendar
        ).validated(calendar: comparisonCalendar)
        guard currentDraft != normalized else {
            return current
        }
        applyChanges(
            from: currentDraft,
            to: normalized,
            calendar: calendar,
            event: event
        )
        try eventStore.save(event, span: .thisEvent, commit: true)
        return makeDisplayEvent(event)
    }

    func deleteEvent(_ original: DisplayEvent) throws {
        try requireFullAccess()
        try validateWritePolicy(original)
        let event = try resolveEvent(for: original)
        try validateCurrentWritePolicy(event)
        guard editableFieldsMatch(
            makeDisplayEvent(event),
            original
        ) else {
            throw CalendarEventWriteError.eventChangedExternally
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    private func makeDisplayEvent(_ event: EKEvent) -> DisplayEvent {
        let title = event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled event"
        let isRecurring = event.hasRecurrenceRules
            || event.occurrenceDate != nil
            || event.isDetached
        let timeSemantics = makeTimeSemantics(event)
        let occurrenceLocalComponents = makeOccurrenceLocalComponents(
            event,
            isRecurring: isRecurring,
            timeSemantics: timeSemantics
        )
        let stableID = DisplayEventIdentity.make(
            calendarIdentifier: event.calendar.calendarIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            eventIdentifier: event.eventIdentifier,
            isRecurring: isRecurring,
            occurrenceDate: event.occurrenceDate,
            occurrenceLocalComponents: occurrenceLocalComponents,
            startDate: event.startDate,
            endDate: event.endDate,
            title: title
        )

        return DisplayEvent(
            id: stableID,
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            sourceTitle: event.calendar.source.title,
            accountType: accountType(for: event.calendar.source.sourceType),
            calendarColor: colorSnapshot(for: event.calendar),
            title: title,
            location: event.location,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZone?.identifier,
            timeSemantics: timeSemantics,
            isRecurring: isRecurring,
            occurrenceDate: event.occurrenceDate,
            occurrenceLocalComponents: occurrenceLocalComponents,
            isDetached: event.isDetached,
            isReadOnly: !event.calendar.allowsContentModifications,
            isInvitation: event.organizer.map { !$0.isCurrentUser } ?? false,
            hasAttendees: event.hasAttendees,
            originalNotes: event.notes
        )
    }

    private func requireFullAccess() throws {
        guard authorizationState.canReadEvents else {
            throw CalendarEventWriteError.fullAccessRequired
        }
    }

    private func validateWritePolicy(_ event: DisplayEvent) throws {
        if event.isInvitation || event.hasAttendees {
            throw CalendarEventWriteError.meetingIsCalendarAppOnly
        }
        if event.isReadOnly {
            throw CalendarEventWriteError.readOnlyCalendar
        }
        if event.isRecurring || event.occurrenceDate != nil || event.isDetached {
            throw CalendarEventWriteError.recurringScopeRequired
        }
    }

    private func validateCurrentWritePolicy(_ event: EKEvent) throws {
        guard event.calendar.allowsContentModifications else {
            throw CalendarEventWriteError.readOnlyCalendar
        }
        if requiresCalendarAppMeetingManagement(event) {
            throw CalendarEventWriteError.meetingIsCalendarAppOnly
        }
        if event.hasRecurrenceRules
            || event.occurrenceDate != nil
            || event.isDetached {
            throw CalendarEventWriteError.recurringScopeRequired
        }
    }

    private func writableCalendar(identifier: String) throws -> EKCalendar {
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            throw CalendarEventWriteError.calendarUnavailable
        }
        guard calendar.allowsContentModifications else {
            throw CalendarEventWriteError.readOnlyCalendar
        }
        return calendar
    }

    private func resolveEvent(for original: DisplayEvent) throws -> EKEvent {
        if let identifier = original.eventIdentifier,
           !identifier.isEmpty,
           let event = eventStore.event(withIdentifier: identifier),
           candidate(event, matchesCalendarOf: original) {
            return event
        }

        if let identifier = original.calendarItemIdentifier,
           !identifier.isEmpty,
           let event = eventStore.calendarItem(
               withIdentifier: identifier
           ) as? EKEvent,
           candidate(event, matchesCalendarOf: original) {
            return event
        }

        if let identifier = original.calendarItemExternalIdentifier,
           !identifier.isEmpty {
            let matches = eventStore.calendarItems(
                withExternalIdentifier: identifier
            )
                .compactMap { $0 as? EKEvent }
                .filter { candidate($0, matchesCalendarOf: original) }
            if matches.count == 1, let event = matches.first {
                return event
            }
            if matches.count > 1 {
                throw CalendarEventWriteError.ambiguousEvent
            }
        }

        throw CalendarEventWriteError.eventUnavailable
    }

    private func candidate(
        _ event: EKEvent,
        matchesCalendarOf original: DisplayEvent
    ) -> Bool {
        event.calendar.calendarIdentifier == original.calendarIdentifier
            && !event.hasRecurrenceRules
            && event.occurrenceDate == nil
            && !event.isDetached
    }

    private func editableFieldsMatch(
        _ current: DisplayEvent,
        _ original: DisplayEvent
    ) -> Bool {
        current.calendarIdentifier == original.calendarIdentifier
            && current.title == original.title
            && current.location == original.location
            && current.hasSameEditableTime(as: original)
            && current.originalNotes == original.originalNotes
    }

    private func applyAll(
        _ draft: CalendarEventDraft,
        calendar: EKCalendar,
        to event: EKEvent
    ) {
        event.calendar = calendar
        event.title = draft.title
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.originalNotes.isEmpty
            ? nil
            : draft.originalNotes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.timeZone = draft.isAllDay
            ? nil
            : draft.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private func applyChanges(
        from current: CalendarEventDraft,
        to draft: CalendarEventDraft,
        calendar: EKCalendar,
        event: EKEvent
    ) {
        if draft.calendarIdentifier != current.calendarIdentifier {
            event.calendar = calendar
        }
        if draft.title != current.title {
            event.title = draft.title
        }
        if draft.location != current.location {
            event.location = draft.location.isEmpty ? nil : draft.location
        }
        if draft.originalNotes != current.originalNotes {
            event.notes = draft.originalNotes.isEmpty
                ? nil
                : draft.originalNotes
        }
        if draft.startDate != current.startDate
            || draft.endDate != current.endDate
            || draft.isAllDay != current.isAllDay
            || draft.timeZoneIdentifier != current.timeZoneIdentifier {
            event.startDate = draft.startDate
            event.endDate = draft.endDate
            event.isAllDay = draft.isAllDay
            event.timeZone = draft.isAllDay
                ? nil
                : draft.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        }
    }

    private func requiresCalendarAppMeetingManagement(
        _ event: EKEvent
    ) -> Bool {
        event.hasAttendees
            || (event.organizer.map { !$0.isCurrentUser } ?? false)
    }

    private func validationCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private func makeTimeSemantics(_ event: EKEvent) -> EventTimeSemantics {
        let semanticCalendar = semanticCalendar(for: event)

        if event.isAllDay {
            let range = CalendarEventDateFormatting.normalizedAllDayDateRange(
                startDate: event.startDate,
                endDate: event.endDate,
                calendar: semanticCalendar
            )
            return .allDay(
                start: LocalDateTimeComponents(
                    date: range.start,
                    calendar: semanticCalendar
                ),
                endExclusive: LocalDateTimeComponents(
                    date: range.endExclusive,
                    calendar: semanticCalendar
                )
            )
        }

        let start = LocalDateTimeComponents(
            date: event.startDate,
            calendar: semanticCalendar
        )
        let end = LocalDateTimeComponents(
            date: event.endDate,
            calendar: semanticCalendar
        )

        if let identifier = event.timeZone?.identifier {
            return .zoned(timeZoneIdentifier: identifier)
        }
        return .floating(start: start, end: end)
    }

    private func makeOccurrenceLocalComponents(
        _ event: EKEvent,
        isRecurring: Bool,
        timeSemantics: EventTimeSemantics
    ) -> LocalDateTimeComponents? {
        guard isRecurring else { return nil }
        switch timeSemantics {
        case .zoned:
            return nil
        case let .allDay(start, _), let .floating(start, _):
            guard let occurrenceDate = event.occurrenceDate else {
                return start
            }
            return LocalDateTimeComponents(
                date: occurrenceDate,
                calendar: semanticCalendar(for: event)
            )
        }
    }

    private func semanticCalendar(for event: EKEvent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = event.timeZone ?? .autoupdatingCurrent
        return calendar
    }

    private func colorSnapshot(for calendar: EKCalendar) -> CalendarColor? {
        guard let cgColor = calendar.cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return CalendarColor(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
    }

    private func accountType(for sourceType: EKSourceType) -> CalendarAccountType {
        switch sourceType {
        case .exchange:
            return .exchange
        case .calDAV:
            return .calDAV
        case .mobileMe:
            return .iCloud
        case .local:
            return .local
        case .subscribed:
            return .subscribed
        case .birthdays:
            return .birthdays
        @unknown default:
            return .unknown
        }
    }
}
