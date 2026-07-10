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
    let isDetached: Bool
    let isReadOnly: Bool
    let isInvitation: Bool
}
