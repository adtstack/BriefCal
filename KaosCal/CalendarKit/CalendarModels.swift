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

struct CalendarSource: Equatable, Identifiable {
    let id: String
    let title: String
    let sourceTitle: String
    let accountType: CalendarAccountType
    let isWritable: Bool
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
    let title: String
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String?
    let isRecurring: Bool
    let occurrenceDate: Date?
    let isDetached: Bool
    let isReadOnly: Bool
    let isInvitation: Bool
}
