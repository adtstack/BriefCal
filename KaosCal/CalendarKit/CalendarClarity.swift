import Foundation

enum CalendarRole: String, Codable, CaseIterable, Hashable, Identifiable {
    case work
    case personal
    case family
    case shared
    case subscription
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .work: "Work"
        case .personal: "Personal"
        case .family: "Family"
        case .shared: "Shared"
        case .subscription: "Subscription"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .work: "briefcase.fill"
        case .personal: "person.fill"
        case .family: "house.fill"
        case .shared: "person.2.fill"
        case .subscription: "dot.radiowaves.left.and.right"
        case .other: "calendar"
        }
    }

    static func inferred(for source: CalendarSource) -> CalendarRole {
        switch source.accountType {
        case .subscribed, .birthdays:
            .subscription
        case .exchange, .calDAV, .iCloud, .local, .unknown:
            .other
        }
    }
}

enum CalendarSetFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case work
    case personal
    case family
    case shared
    case subscription
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All Calendars"
        case .work: CalendarRole.work.title
        case .personal: CalendarRole.personal.title
        case .family: CalendarRole.family.title
        case .shared: CalendarRole.shared.title
        case .subscription: CalendarRole.subscription.title
        case .other: CalendarRole.other.title
        }
    }

    var symbolName: String {
        switch self {
        case .all: "calendar"
        case .work: CalendarRole.work.symbolName
        case .personal: CalendarRole.personal.symbolName
        case .family: CalendarRole.family.symbolName
        case .shared: CalendarRole.shared.symbolName
        case .subscription: CalendarRole.subscription.symbolName
        case .other: CalendarRole.other.symbolName
        }
    }

    func includes(role: CalendarRole) -> Bool {
        switch self {
        case .all:
            true
        case .work:
            role == .work
        case .personal:
            role == .personal
        case .family:
            role == .family
        case .shared:
            role == .shared
        case .subscription:
            role == .subscription
        case .other:
            role == .other
        }
    }
}

struct CalendarDescriptor: Equatable, Identifiable {
    let source: CalendarSource
    let role: CalendarRole
    let isRoleExplicit: Bool

    var id: String { source.id }

    init(
        source: CalendarSource,
        explicitRole: CalendarRole?
    ) {
        self.source = source
        role = explicitRole ?? CalendarRole.inferred(for: source)
        isRoleExplicit = explicitRole != nil
    }
}

enum CalendarWriteRestriction: Error, Equatable {
    case invitation
    case attendee
    case subscribedCalendar
    case birthdaysCalendar
    case providerReadOnly

    var title: String {
        switch self {
        case .invitation: "Invitation"
        case .attendee: "Meeting with attendees"
        case .subscribedCalendar: "Subscribed calendar"
        case .birthdaysCalendar: "Birthdays calendar"
        case .providerReadOnly: "Read-only calendar"
        }
    }

    var symbolName: String {
        switch self {
        case .invitation, .attendee:
            "person.crop.circle.badge.exclamationmark"
        case .subscribedCalendar, .birthdaysCalendar, .providerReadOnly:
            "lock"
        }
    }

    var message: String {
        switch self {
        case .invitation:
            "Invitation changes stay in Calendar.app; the local Event Brief remains editable."
        case .attendee:
            "This meeting has attendees. Original changes stay in Calendar.app; the local Event Brief remains editable."
        case .subscribedCalendar:
            "Subscribed calendars are read-only. The local Event Brief remains editable."
        case .birthdaysCalendar:
            "The Birthdays calendar is managed outside KaosCal and is read-only. The local Event Brief remains editable."
        case .providerReadOnly:
            "macOS Calendar reports this calendar as read-only. The local Event Brief remains editable."
        }
    }

    static func restriction(
        for event: DisplayEvent
    ) -> CalendarWriteRestriction? {
        if event.isInvitation { return .invitation }
        if event.hasAttendees { return .attendee }
        if event.accountType == .subscribed { return .subscribedCalendar }
        if event.accountType == .birthdays { return .birthdaysCalendar }
        if event.isReadOnly { return .providerReadOnly }
        return nil
    }

    static func restriction(
        for source: CalendarSource
    ) -> CalendarWriteRestriction? {
        switch source.accountType {
        case .subscribed:
            return .subscribedCalendar
        case .birthdays:
            return .birthdaysCalendar
        case .exchange, .calDAV, .iCloud, .local, .unknown:
            return source.isWritable ? nil : .providerReadOnly
        }
    }
}

extension CalendarWriteRestriction: LocalizedError {
    var errorDescription: String? { message }
}

enum CalendarDuplicateMatchKind: String, Equatable, Hashable {
    case timedWithinTolerance
    case sameAllDayRange
}

struct CalendarDuplicateCandidate: Equatable, Identifiable {
    let event: DisplayEvent
    let matchKind: CalendarDuplicateMatchKind

    var id: String { event.id }
}

enum CalendarDuplicateCandidateDetector {
    static let timedTolerance: TimeInterval = 15 * 60

    static func candidateIndex(
        among events: [DisplayEvent],
        calendar: Calendar
    ) -> [String: [CalendarDuplicateCandidate]] {
        let titleGroups = Dictionary(grouping: events) {
            normalizedTitle($0.title)
        }
        var result: [String: [CalendarDuplicateCandidate]] = [:]

        for (titleKey, group) in titleGroups where !titleKey.isEmpty {
            guard group.count > 1 else { continue }
            for lhsIndex in group.indices {
                let rhsStart = group.index(after: lhsIndex)
                guard rhsStart < group.endIndex else { continue }
                for rhsIndex in rhsStart..<group.endIndex {
                    let lhs = group[lhsIndex]
                    let rhs = group[rhsIndex]
                    guard lhs.id != rhs.id,
                          lhs.calendarIdentifier != rhs.calendarIdentifier,
                          !representsSameUnderlyingOccurrence(lhs, rhs),
                          let kind = matchKind(
                              lhs,
                              rhs,
                              calendar: calendar
                          ) else {
                        continue
                    }
                    result[lhs.id, default: []].append(
                        CalendarDuplicateCandidate(
                            event: rhs,
                            matchKind: kind
                        )
                    )
                    result[rhs.id, default: []].append(
                        CalendarDuplicateCandidate(
                            event: lhs,
                            matchKind: kind
                        )
                    )
                }
            }
        }

        return result.mapValues(sortedCandidates)
    }

    static func candidates(
        for event: DisplayEvent,
        among events: [DisplayEvent],
        calendar: Calendar
    ) -> [CalendarDuplicateCandidate] {
        let titleKey = normalizedTitle(event.title)
        guard !titleKey.isEmpty else { return [] }

        return events.compactMap { candidate in
            guard candidate.id != event.id,
                  candidate.calendarIdentifier != event.calendarIdentifier,
                  normalizedTitle(candidate.title) == titleKey,
                  !representsSameUnderlyingOccurrence(event, candidate) else {
                return nil
            }

            guard let matchKind = matchKind(
                event,
                candidate,
                calendar: calendar
            ) else {
                return nil
            }
            return CalendarDuplicateCandidate(
                event: candidate,
                matchKind: matchKind
            )
        }
        .sorted(by: candidateSort)
    }

    private static func sortedCandidates(
        _ candidates: [CalendarDuplicateCandidate]
    ) -> [CalendarDuplicateCandidate] {
        candidates.sorted(by: candidateSort)
    }

    private static func candidateSort(
        _ lhs: CalendarDuplicateCandidate,
        _ rhs: CalendarDuplicateCandidate
    ) -> Bool {
        if lhs.event.id != rhs.event.id {
            return lhs.event.id < rhs.event.id
        }
        if lhs.event.calendarIdentifier != rhs.event.calendarIdentifier {
            return lhs.event.calendarIdentifier
                < rhs.event.calendarIdentifier
        }
        return lhs.event.startDate < rhs.event.startDate
    }

    private static func matchKind(
        _ lhs: DisplayEvent,
        _ rhs: DisplayEvent,
        calendar: Calendar
    ) -> CalendarDuplicateMatchKind? {
        guard lhs.isAllDay == rhs.isAllDay else { return nil }
        let lhsRange = CalendarEventDateFormatting.effectiveDateRange(
            for: lhs,
            calendar: calendar
        )
        let rhsRange = CalendarEventDateFormatting.effectiveDateRange(
            for: rhs,
            calendar: calendar
        )

        if lhs.isAllDay {
            return civilDayKey(lhsRange.start, calendar: calendar)
                    == civilDayKey(rhsRange.start, calendar: calendar)
                && civilDayKey(lhsRange.end, calendar: calendar)
                    == civilDayKey(rhsRange.end, calendar: calendar)
                ? .sameAllDayRange
                : nil
        }

        guard abs(lhsRange.start.timeIntervalSince(rhsRange.start))
                <= timedTolerance,
              abs(lhsRange.end.timeIntervalSince(rhsRange.end))
                <= timedTolerance else {
            return nil
        }
        return .timedWithinTolerance
    }

    private static func normalizedTitle(_ title: String) -> String {
        let folded = title.folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive
            ],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let alphanumericAndSpaces = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                ? String(scalar)
                : " "
        }.joined()
        return alphanumericAndSpaces
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func representsSameUnderlyingOccurrence(
        _ lhs: DisplayEvent,
        _ rhs: DisplayEvent
    ) -> Bool {
        guard sharesStrongIdentifier(lhs, rhs),
              lhs.isRecurring == rhs.isRecurring else {
            return false
        }
        guard lhs.isRecurring else { return true }

        if let lhsLocal = lhs.occurrenceLocalComponents,
           let rhsLocal = rhs.occurrenceLocalComponents {
            return lhsLocal == rhsLocal
        }
        let lhsAnchor = lhs.occurrenceDate ?? lhs.startDate
        let rhsAnchor = rhs.occurrenceDate ?? rhs.startDate
        return abs(lhsAnchor.timeIntervalSince(rhsAnchor)) < 0.001
    }

    private static func sharesStrongIdentifier(
        _ lhs: DisplayEvent,
        _ rhs: DisplayEvent
    ) -> Bool {
        sameNonEmpty(lhs.eventIdentifier, rhs.eventIdentifier)
            || sameNonEmpty(
                lhs.calendarItemIdentifier,
                rhs.calendarItemIdentifier
            )
            || sameNonEmpty(
                lhs.calendarItemExternalIdentifier,
                rhs.calendarItemExternalIdentifier
            )
    }

    private static func sameNonEmpty(
        _ lhs: String?,
        _ rhs: String?
    ) -> Bool {
        guard let lhs, !lhs.isEmpty,
              let rhs, !rhs.isEmpty else {
            return false
        }
        return lhs == rhs
    }

    private static func civilDayKey(
        _ date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: date
        )
        return [
            components.era ?? 0,
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        ].map(String.init).joined(separator: "-")
    }
}
