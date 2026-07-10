import Foundation

enum TimeZoneChangeBehavior: String, CaseIterable, Identifiable {
    case preserveLocalTime
    case preserveInstant

    var id: Self { self }

    var title: String {
        switch self {
        case .preserveLocalTime:
            "Keep local time"
        case .preserveInstant:
            "Keep instant"
        }
    }
}

struct CalendarEventDraft: Equatable {
    var title: String
    var calendarIdentifier: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var timeZoneIdentifier: String?
    var referenceTimeZoneIdentifier: String
    var location: String
    var originalNotes: String
    var recurrence: CalendarEventRecurrence

    init(
        title: String,
        calendarIdentifier: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timeZoneIdentifier: String?,
        referenceTimeZoneIdentifier: String,
        location: String = "",
        originalNotes: String = "",
        recurrence: CalendarEventRecurrence = .none
    ) {
        self.title = title
        self.calendarIdentifier = calendarIdentifier
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.referenceTimeZoneIdentifier = referenceTimeZoneIdentifier
        self.location = location
        self.originalNotes = originalNotes
        self.recurrence = recurrence
    }

    init(event: DisplayEvent, calendar: Calendar) {
        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: calendar
        )
        title = event.title
        calendarIdentifier = event.calendarIdentifier
        startDate = range.start
        endDate = range.end
        isAllDay = event.isAllDay
        timeZoneIdentifier = event.isAllDay
            ? nil
            : event.timeZoneIdentifier
        referenceTimeZoneIdentifier = calendar.timeZone.identifier
        location = event.location ?? ""
        originalNotes = event.originalNotes ?? ""
        recurrence = event.recurrence
    }

    func validated(
        calendar: Calendar,
        enforceRecurrenceEndBoundary: Bool = true,
        rebaseRecurrenceEndDate: Bool = true
    ) throws -> Self {
        var result = self
        guard var referenceTimeZone = TimeZone(
            identifier: referenceTimeZoneIdentifier
        ) else {
            throw CalendarEventWriteError.invalidTimeZone(
                referenceTimeZoneIdentifier
            )
        }

        if result.isAllDay || result.timeZoneIdentifier == nil,
           referenceTimeZone.identifier != calendar.timeZone.identifier {
            if rebaseRecurrenceEndDate,
               case var .basic(rule) = result.recurrence,
               case let .onDate(endDate) = rule.end {
                rule.end = .onDate(try Self.reinterpreting(
                    endDate,
                    from: referenceTimeZone,
                    to: calendar.timeZone
                ))
                result.recurrence = .basic(rule)
            }
            result.startDate = try Self.reinterpreting(
                result.startDate,
                from: referenceTimeZone,
                to: calendar.timeZone
            )
            result.endDate = try Self.reinterpreting(
                result.endDate,
                from: referenceTimeZone,
                to: calendar.timeZone
            )
            result.referenceTimeZoneIdentifier = calendar.timeZone.identifier
            referenceTimeZone = calendar.timeZone
        }
        var wallTimeCalendar = calendar
        wallTimeCalendar.timeZone = referenceTimeZone
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.calendarIdentifier = calendarIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        result.location = location.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.title.isEmpty else {
            throw CalendarEventWriteError.emptyTitle
        }
        guard !result.calendarIdentifier.isEmpty else {
            throw CalendarEventWriteError.calendarUnavailable
        }

        if result.isAllDay {
            guard result.endDate > result.startDate else {
                throw CalendarEventWriteError.invalidDateRange
            }
            let normalized = CalendarEventDateFormatting.normalizedAllDayDateRange(
                startDate: result.startDate,
                endDate: result.endDate,
                calendar: wallTimeCalendar
            )
            result.startDate = normalized.start
            result.endDate = normalized.endExclusive
            result.timeZoneIdentifier = nil
        } else {
            guard result.endDate > result.startDate else {
                throw CalendarEventWriteError.invalidDateRange
            }
            if let identifier = result.timeZoneIdentifier,
               TimeZone(identifier: identifier) == nil {
                throw CalendarEventWriteError.invalidTimeZone(identifier)
            }
        }

        result.recurrence = try result.recurrence.validated(
            eventStart: result.startDate,
            enforceEndBoundary: enforceRecurrenceEndBoundary
        )

        return result
    }

    func changedFields(
        comparedTo current: CalendarEventDraft
    ) -> Set<CalendarEventChangedField> {
        var fields = Set<CalendarEventChangedField>()
        if title != current.title {
            fields.insert(.title)
        }
        if calendarIdentifier != current.calendarIdentifier {
            fields.insert(.calendar)
        }
        if startDate != current.startDate
            || endDate != current.endDate
            || isAllDay != current.isAllDay
            || timeZoneIdentifier != current.timeZoneIdentifier {
            fields.insert(.time)
        }
        if location != current.location {
            fields.insert(.location)
        }
        if originalNotes != current.originalNotes {
            fields.insert(.originalNotes)
        }
        if recurrence != current.recurrence {
            fields.insert(.recurrence)
        }
        return fields
    }

    func changingAllDay(
        to allDay: Bool,
        calendar: Calendar
    ) -> Self {
        guard allDay != isAllDay else { return self }
        var result = self
        result.isAllDay = allDay

        if allDay {
            let start = calendar.startOfDay(for: startDate)
            let displayedEndDay = calendar.startOfDay(for: endDate)
            let endIsExclusiveMidnight = endDate == displayedEndDay
                && endDate > startDate
            let inclusiveEndDay = endIsExclusiveMidnight
                ? calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: displayedEndDay
                ) ?? start
                : displayedEndDay
            let lastDay = max(inclusiveEndDay, start)
            result.startDate = start
            result.endDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: lastDay
            ) ?? lastDay.addingTimeInterval(86_400)
            result.timeZoneIdentifier = nil
            result.referenceTimeZoneIdentifier = calendar.timeZone.identifier
        } else {
            let startDay = calendar.startOfDay(for: startDate)
            result.startDate = calendar.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: startDay
            ) ?? startDay
            result.endDate = calendar.date(
                byAdding: .hour,
                value: 1,
                to: result.startDate
            ) ?? result.startDate.addingTimeInterval(3_600)
            result.timeZoneIdentifier = calendar.timeZone.identifier
            result.referenceTimeZoneIdentifier = calendar.timeZone.identifier
        }
        return result
    }

    func changingTimeZone(
        to newIdentifier: String?,
        behavior: TimeZoneChangeBehavior,
        displayCalendar: Calendar
    ) throws -> Self {
        guard !isAllDay else { return self }
        if let newIdentifier,
           TimeZone(identifier: newIdentifier) == nil {
            throw CalendarEventWriteError.invalidTimeZone(newIdentifier)
        }
        guard newIdentifier != timeZoneIdentifier else { return self }

        var result = self
        if behavior == .preserveLocalTime {
            let oldTimeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                ?? displayCalendar.timeZone
            let newTimeZone = newIdentifier.flatMap(TimeZone.init(identifier:))
                ?? displayCalendar.timeZone
            result.startDate = try Self.reinterpreting(
                startDate,
                from: oldTimeZone,
                to: newTimeZone
            )
            result.endDate = try Self.reinterpreting(
                endDate,
                from: oldTimeZone,
                to: newTimeZone
            )
        }
        result.timeZoneIdentifier = newIdentifier
        if newIdentifier == nil {
            result.referenceTimeZoneIdentifier = displayCalendar.timeZone.identifier
        }
        return result
    }

    func wallTimeCalendar(fallback: Calendar) -> Calendar {
        var result = fallback
        if let timeZone = TimeZone(identifier: referenceTimeZoneIdentifier) {
            result.timeZone = timeZone
        }
        return result
    }

    private static func reinterpreting(
        _ date: Date,
        from oldTimeZone: TimeZone,
        to newTimeZone: TimeZone
    ) throws -> Date {
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = oldTimeZone
        let sourceComponents = sourceCalendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second],
            from: date
        )
        var destinationCalendar = Calendar(identifier: .gregorian)
        destinationCalendar.timeZone = newTimeZone
        var requested = DateComponents()
        requested.era = sourceComponents.era
        requested.year = sourceComponents.year
        requested.month = sourceComponents.month
        requested.day = sourceComponents.day
        requested.hour = sourceComponents.hour
        requested.minute = sourceComponents.minute
        requested.second = sourceComponents.second

        let approximate = destinationCalendar.date(from: requested) ?? date
        let searchStart = approximate.addingTimeInterval(-172_800)
        let first = destinationCalendar.nextDate(
            after: searchStart,
            matching: requested,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        )
        let last = destinationCalendar.nextDate(
            after: searchStart,
            matching: requested,
            matchingPolicy: .strict,
            repeatedTimePolicy: .last,
            direction: .forward
        )
        guard let first, let last else {
            throw CalendarEventWriteError.nonexistentLocalTime(
                newTimeZone.identifier
            )
        }
        guard first == last else {
            throw CalendarEventWriteError.ambiguousLocalTime(
                newTimeZone.identifier
            )
        }
        return first
    }
}

extension CalendarEventRecurrence {
    func validated(
        eventStart: Date,
        enforceEndBoundary: Bool = true
    ) throws -> Self {
        guard case var .basic(rule) = self else { return self }

        guard rule.interval > 0 else {
            throw CalendarEventWriteError.invalidRecurrenceInterval
        }
        if rule.frequency == .weekly {
            guard !rule.weekdays.isEmpty else {
                throw CalendarEventWriteError.invalidRecurrenceWeekdays
            }
        } else if !rule.weekdays.isEmpty {
            throw CalendarEventWriteError.invalidRecurrenceWeekdays
        }

        switch rule.end {
        case .never:
            break
        case let .onDate(endDate):
            guard !enforceEndBoundary || endDate >= eventStart else {
                throw CalendarEventWriteError.invalidRecurrenceEnd
            }
        case let .afterOccurrences(count):
            guard count > 0 else {
                throw CalendarEventWriteError.invalidRecurrenceEnd
            }
        }

        rule.weekdays = Set(rule.weekdays)
        return .basic(rule)
    }
}

enum CalendarEventWriteError: Error, Equatable {
    case fullAccessRequired
    case noWritableCalendar
    case calendarUnavailable
    case readOnlyCalendar
    case meetingIsCalendarAppOnly
    case recurringScopeRequired
    case eventUnavailable
    case ambiguousEvent
    case eventChangedExternally
    case emptyTitle
    case invalidDateRange
    case invalidTimeZone(String)
    case nonexistentLocalTime(String)
    case ambiguousLocalTime(String)
    case localIdentityConfirmationRequired
    case localDraftSaveRequired
    case editorAlreadyOpen
    case linkedCalendarMoveDeferred
    case linkedDeleteDeferred
    case invalidRecurrenceInterval
    case invalidRecurrenceWeekdays
    case invalidRecurrenceEnd
    case unsupportedRecurrence
    case recurrenceChangeRequiresFutureScope
    case futureScopeRequiresRecurringEvent
    case detachedFutureScopeUnsupported
}

struct CalendarEventMutationPartialSuccess: LocalizedError {
    let provisionalEvent: DisplayEvent
    let underlyingDescription: String

    var errorDescription: String? {
        "The calendar event was saved, but KaosCal could not identify the post-save occurrence. Do not retry this change. Reload and review it in Calendar.app; any local Event Brief was kept."
    }
}

extension CalendarEventWriteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fullAccessRequired:
            "Full calendar access is required to change original events."
        case .noWritableCalendar:
            "No writable calendar is available."
        case .calendarUnavailable:
            "The selected calendar is no longer available."
        case .readOnlyCalendar:
            "This calendar does not allow original event changes."
        case .meetingIsCalendarAppOnly:
            "Meetings with attendees and invitations stay in Calendar.app."
        case .recurringScopeRequired:
            "Choose whether this recurring change applies to This Event or This and Future Events."
        case .eventUnavailable:
            "The original event is no longer available. Reload before trying again."
        case .ambiguousEvent:
            "KaosCal found more than one strong event match and did not change any event."
        case .eventChangedExternally:
            "The event changed outside KaosCal. Reopen the editor to review the latest version."
        case .emptyTitle:
            "Event title cannot be empty."
        case .invalidDateRange:
            "Event end must be after its start."
        case let .invalidTimeZone(identifier):
            "Unknown IANA time zone: \(identifier)."
        case let .nonexistentLocalTime(identifier):
            "That local time does not exist in \(identifier) because of a daylight-saving transition. Choose another time."
        case let .ambiguousLocalTime(identifier):
            "That local time occurs twice in \(identifier) because of a daylight-saving transition. Choose an unambiguous time."
        case .localIdentityConfirmationRequired:
            "Confirm the matching Event Brief before changing the original event."
        case .localDraftSaveRequired:
            "The local Event Brief draft could not be saved. Resolve that error before changing the original event."
        case .editorAlreadyOpen:
            "Finish or cancel the current event edit before opening another one."
        case .linkedCalendarMoveDeferred:
            "Moving an event with a local Event Brief requires the linked-impact review."
        case .linkedDeleteDeferred:
            "Deleting an event with a local Event Brief needs the Phase 7 orphan review flow."
        case .invalidRecurrenceInterval:
            "A recurrence interval must be a positive number."
        case .invalidRecurrenceWeekdays:
            "Weekly recurrence needs at least one weekday, and weekdays are only valid for weekly recurrence."
        case .invalidRecurrenceEnd:
            "Recurrence must end on or after the first event, or after a positive occurrence count."
        case .unsupportedRecurrence:
            "This recurrence rule is too complex to change safely in KaosCal. Use Calendar.app for recurrence changes."
        case .recurrenceChangeRequiresFutureScope:
            "Changing a recurrence rule requires the This and Future Events scope."
        case .futureScopeRequiresRecurringEvent:
            "The This and Future Events scope is only valid for a recurring event."
        case .detachedFutureScopeUnsupported:
            "KaosCal cannot safely apply future changes from a detached occurrence. Use Calendar.app."
        }
    }
}
