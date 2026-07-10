import Foundation

enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case fullAccess
    case denied
    case restricted
    case writeOnly
    case unknown

    var canReadEvents: Bool { self == .fullAccess }

    var title: String {
        switch self {
        case .notDetermined: "Calendar access not requested"
        case .fullAccess: "Full calendar access"
        case .denied: "Calendar access denied"
        case .restricted: "Calendar access restricted"
        case .writeOnly: "Write-only calendar access"
        case .unknown: "Unknown calendar access"
        }
    }
}

enum CalendarAccountType: String, Equatable {
    case exchange
    case calDAV
    case iCloud
    case local
    case subscribed
    case birthdays
    case unknown

    var title: String {
        switch self {
        case .exchange: "Exchange"
        case .calDAV: "CalDAV"
        case .iCloud: "iCloud"
        case .local: "On My Mac"
        case .subscribed: "Subscription"
        case .birthdays: "Birthdays"
        case .unknown: "Calendar"
        }
    }
}

struct CalendarColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct CalendarSource: Equatable, Identifiable {
    let id: String
    let title: String
    let sourceTitle: String
    let accountType: CalendarAccountType
    let isWritable: Bool
    let color: CalendarColor?
}

enum CalendarRecurrenceFrequency: String, CaseIterable, Equatable, Hashable {
    case daily
    case weekly
    case monthly
    case yearly
}

enum CalendarRecurrenceWeekday: Int, CaseIterable, Equatable, Hashable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}

enum CalendarRecurrenceEnd: Equatable {
    case never
    case onDate(Date)
    case afterOccurrences(Int)
}

struct BasicRecurrenceRule: Equatable {
    var frequency: CalendarRecurrenceFrequency
    var interval: Int
    var weekdays: Set<CalendarRecurrenceWeekday>
    var end: CalendarRecurrenceEnd

    init(
        frequency: CalendarRecurrenceFrequency,
        interval: Int = 1,
        weekdays: Set<CalendarRecurrenceWeekday> = [],
        end: CalendarRecurrenceEnd = .never
    ) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.end = end
    }
}

struct UnsupportedRecurrenceSnapshot: Equatable {
    let summary: String
    let signature: String
}

enum CalendarEventRecurrence: Equatable {
    case none
    case basic(BasicRecurrenceRule)
    case unsupported(UnsupportedRecurrenceSnapshot)

    var isRecurring: Bool {
        if case .none = self { return false }
        return true
    }

    var isRepresentable: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

enum CalendarEventMutationScope: String, CaseIterable, Equatable, Hashable {
    case thisEvent
    case futureEvents
}

enum CalendarEventChangedField: String, CaseIterable, Hashable {
    case title
    case calendar
    case time
    case location
    case originalNotes
    case recurrence
    case deletion
}

struct LocalDateTimeComponents: Equatable {
    let calendarIdentifier: Calendar.Identifier
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        calendarIdentifier = calendar.identifier
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
        hour = components.hour ?? 0
        minute = components.minute ?? 0
        second = components.second ?? 0
    }

    func date(in calendar: Calendar) -> Date? {
        var reconstructionCalendar = Calendar(identifier: calendarIdentifier)
        reconstructionCalendar.locale = calendar.locale
        reconstructionCalendar.timeZone = calendar.timeZone
        return reconstructionCalendar.date(
            from: DateComponents(
                calendar: reconstructionCalendar,
                timeZone: reconstructionCalendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )
    }
}

enum EventTimeSemantics: Equatable {
    case allDay(
        start: LocalDateTimeComponents,
        endExclusive: LocalDateTimeComponents
    )
    case floating(
        start: LocalDateTimeComponents,
        end: LocalDateTimeComponents
    )
    case zoned(timeZoneIdentifier: String)
}

enum DisplayEventIdentity {
    static func make(
        calendarIdentifier: String,
        externalIdentifier: String?,
        calendarItemIdentifier: String?,
        eventIdentifier: String?,
        isRecurring: Bool,
        occurrenceDate: Date?,
        occurrenceLocalComponents: LocalDateTimeComponents? = nil,
        startDate: Date,
        endDate: Date,
        title: String
    ) -> String {
        let itemIdentity: String
        if let externalIdentifier, !externalIdentifier.isEmpty {
            itemIdentity = "external:\(externalIdentifier)"
        } else if let calendarItemIdentifier, !calendarItemIdentifier.isEmpty {
            itemIdentity = "item:\(calendarItemIdentifier)"
        } else if let eventIdentifier, !eventIdentifier.isEmpty {
            itemIdentity = "event:\(eventIdentifier)"
        } else {
            itemIdentity = [
                "anonymous",
                String(startDate.timeIntervalSinceReferenceDate),
                String(endDate.timeIntervalSinceReferenceDate),
                title
            ].joined(separator: ":")
        }

        let base = "\(calendarIdentifier)#\(itemIdentity)"
        guard isRecurring else { return base }
        if let occurrenceLocalComponents {
            let localAnchor = [
                String(describing: occurrenceLocalComponents.calendarIdentifier),
                String(format: "%04d", occurrenceLocalComponents.year),
                String(format: "%02d", occurrenceLocalComponents.month),
                String(format: "%02d", occurrenceLocalComponents.day),
                String(format: "%02d", occurrenceLocalComponents.hour),
                String(format: "%02d", occurrenceLocalComponents.minute),
                String(format: "%02d", occurrenceLocalComponents.second)
            ].joined(separator: ":")
            return "\(base)#occurrence-local:\(localAnchor)"
        }
        let occurrenceAnchor = occurrenceDate ?? startDate
        return "\(base)#occurrence:\(occurrenceAnchor.timeIntervalSinceReferenceDate)"
    }
}

struct DisplayEvent: Equatable, Identifiable {
    let id: String
    let eventIdentifier: String?
    let calendarItemIdentifier: String?
    let calendarItemExternalIdentifier: String?
    let calendarIdentifier: String
    let calendarTitle: String
    let sourceTitle: String
    let accountType: CalendarAccountType
    let calendarColor: CalendarColor?
    let title: String
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String?
    let timeSemantics: EventTimeSemantics
    let isRecurring: Bool
    let occurrenceDate: Date?
    let occurrenceLocalComponents: LocalDateTimeComponents?
    let isDetached: Bool
    let isReadOnly: Bool
    let isInvitation: Bool
    let hasAttendees: Bool
    let originalNotes: String?
    let recurrence: CalendarEventRecurrence

    init(
        id: String,
        eventIdentifier: String?,
        calendarItemIdentifier: String?,
        calendarItemExternalIdentifier: String?,
        calendarIdentifier: String,
        calendarTitle: String,
        sourceTitle: String,
        accountType: CalendarAccountType,
        calendarColor: CalendarColor?,
        title: String,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timeZoneIdentifier: String?,
        timeSemantics: EventTimeSemantics,
        isRecurring: Bool,
        occurrenceDate: Date?,
        occurrenceLocalComponents: LocalDateTimeComponents?,
        isDetached: Bool,
        isReadOnly: Bool,
        isInvitation: Bool,
        hasAttendees: Bool,
        originalNotes: String?,
        recurrence: CalendarEventRecurrence = .none
    ) {
        self.id = id
        self.eventIdentifier = eventIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.calendarItemExternalIdentifier = calendarItemExternalIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.sourceTitle = sourceTitle
        self.accountType = accountType
        self.calendarColor = calendarColor
        self.title = title
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.timeSemantics = timeSemantics
        self.isRecurring = isRecurring
        self.occurrenceDate = occurrenceDate
        self.occurrenceLocalComponents = occurrenceLocalComponents
        self.isDetached = isDetached
        self.isReadOnly = isReadOnly
        self.isInvitation = isInvitation
        self.hasAttendees = hasAttendees
        self.originalNotes = originalNotes
        self.recurrence = recurrence
    }
}

struct CalendarEventMutationReceipt: Equatable {
    let event: DisplayEvent
    let didWrite: Bool
    let scope: CalendarEventMutationScope
    let changedFields: Set<CalendarEventChangedField>
}

extension DisplayEvent {
    func hasSameEditableTime(as other: DisplayEvent) -> Bool {
        guard isAllDay == other.isAllDay else { return false }

        switch (timeSemantics, other.timeSemantics) {
        case let (
            .allDay(start, endExclusive),
            .allDay(otherStart, otherEndExclusive)
        ):
            return start == otherStart
                && endExclusive == otherEndExclusive
        case let (
            .floating(start, end),
            .floating(otherStart, otherEnd)
        ):
            return start == otherStart && end == otherEnd
        case let (
            .zoned(timeZoneIdentifier),
            .zoned(otherTimeZoneIdentifier)
        ):
            return timeZoneIdentifier == otherTimeZoneIdentifier
                && startDate == other.startDate
                && endDate == other.endDate
        default:
            return false
        }
    }
}
