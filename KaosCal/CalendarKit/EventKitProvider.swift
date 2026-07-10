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

    private func makeDisplayEvent(_ event: EKEvent) -> DisplayEvent {
        let title = event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled event"
        let isRecurring = event.hasRecurrenceRules
            || event.occurrenceDate != nil
            || event.isDetached
        let stableID = DisplayEventIdentity.make(
            calendarIdentifier: event.calendar.calendarIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            eventIdentifier: event.eventIdentifier,
            isRecurring: isRecurring,
            occurrenceDate: event.occurrenceDate,
            startDate: event.startDate,
            endDate: event.endDate,
            title: title
        )
        let timeSemantics = makeTimeSemantics(event)

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
            isDetached: event.isDetached,
            isReadOnly: !event.calendar.allowsContentModifications,
            isInvitation: event.organizer.map { !$0.isCurrentUser } ?? false
        )
    }

    private func makeTimeSemantics(_ event: EKEvent) -> EventTimeSemantics {
        var semanticCalendar = Calendar(identifier: .gregorian)
        semanticCalendar.timeZone = event.timeZone ?? .autoupdatingCurrent

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
