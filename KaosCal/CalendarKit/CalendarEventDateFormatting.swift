import Foundation

enum CalendarEventDateFormatting {
    static func normalizedAllDayDateRange(
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> (start: Date, endExclusive: Date) {
        let start = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let normalizedEnd: Date

        if endDate > endDay {
            normalizedEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: endDay
            ) ?? endDate
        } else {
            normalizedEnd = endDay
        }

        guard normalizedEnd > start else {
            return (
                start,
                calendar.date(byAdding: .day, value: 1, to: start)
                    ?? start.addingTimeInterval(86_400)
            )
        }
        return (start, normalizedEnd)
    }

    static func effectiveDateRange(
        for event: DisplayEvent,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        switch event.timeSemantics {
        case let .allDay(start, endExclusive):
            return (
                start.date(in: calendar) ?? event.startDate,
                endExclusive.date(in: calendar) ?? event.endDate
            )
        case let .floating(start, end):
            return (
                start.date(in: calendar) ?? event.startDate,
                end.date(in: calendar) ?? event.endDate
            )
        case .zoned:
            return (event.startDate, event.endDate)
        }
    }

    static func displayedEndDate(
        for event: DisplayEvent,
        calendar: Calendar
    ) -> Date {
        let range = effectiveDateRange(for: event, calendar: calendar)
        guard event.isAllDay,
              range.end > range.start,
              let inclusiveEnd = calendar.date(
                  byAdding: .day,
                  value: -1,
                  to: range.end
              ) else {
            return event.isAllDay ? range.start : range.end
        }

        return max(range.start, inclusiveEnd)
    }

    static func spansMultipleDates(
        _ event: DisplayEvent,
        calendar: Calendar
    ) -> Bool {
        let range = effectiveDateRange(for: event, calendar: calendar)
        return !calendar.isDate(
            range.start,
            inSameDayAs: displayedEndDate(for: event, calendar: calendar)
        )
    }

    static func agendaText(
        for event: DisplayEvent,
        calendar: Calendar
    ) -> String {
        let range = effectiveDateRange(for: event, calendar: calendar)
        let displayedEnd = displayedEndDate(for: event, calendar: calendar)

        if event.isAllDay {
            let start = abbreviatedDate(range.start, calendar: calendar)
            guard spansMultipleDates(event, calendar: calendar) else {
                return "All-day · \(start)"
            }
            let end = abbreviatedDate(displayedEnd, calendar: calendar)
            return "All-day · \(start)–\(end)"
        }

        let start = abbreviatedDateTime(range.start, calendar: calendar)
        let end = spansMultipleDates(event, calendar: calendar)
            ? abbreviatedDateTime(range.end, calendar: calendar)
            : shortTime(range.end, calendar: calendar)
        return "\(start)–\(end)"
    }

    static func inspectorText(
        for event: DisplayEvent,
        calendar: Calendar
    ) -> String {
        let range = effectiveDateRange(for: event, calendar: calendar)
        let displayedEnd = displayedEndDate(for: event, calendar: calendar)

        if event.isAllDay {
            let start = longDate(range.start, calendar: calendar)
            guard spansMultipleDates(event, calendar: calendar) else {
                return "All-day · \(start)"
            }
            let end = longDate(displayedEnd, calendar: calendar)
            return "All-day · \(start) – \(end)"
        }

        let start = longDateTime(range.start, calendar: calendar)
        let end = spansMultipleDates(event, calendar: calendar)
            ? longDateTime(range.end, calendar: calendar)
            : shortTime(range.end, calendar: calendar)
        return "\(start) – \(end)"
    }

    static func monthAndYear(_ date: Date, calendar: Calendar) -> String {
        date.formatted(
            Date.FormatStyle(
                locale: calendar.locale ?? .autoupdatingCurrent,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .month(.wide)
            .year()
        )
    }

    static func weekday(_ date: Date, calendar: Calendar) -> String {
        date.formatted(
            Date.FormatStyle(
                locale: calendar.locale ?? .autoupdatingCurrent,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .weekday(.abbreviated)
        )
    }

    static func dayNumber(_ date: Date, calendar: Calendar) -> String {
        date.formatted(
            Date.FormatStyle(
                locale: calendar.locale ?? .autoupdatingCurrent,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .day()
        )
    }

    static func longDate(_ date: Date, calendar: Calendar) -> String {
        format(date, date: .long, time: .omitted, calendar: calendar)
    }

    static func abbreviatedDate(_ date: Date, calendar: Calendar) -> String {
        format(date, date: .abbreviated, time: .omitted, calendar: calendar)
    }

    static func shortTime(_ date: Date, calendar: Calendar) -> String {
        format(date, date: .omitted, time: .shortened, calendar: calendar)
    }

    static func abbreviatedDateTime(_ date: Date, calendar: Calendar) -> String {
        format(date, date: .abbreviated, time: .shortened, calendar: calendar)
    }

    static func longDateTime(_ date: Date, calendar: Calendar) -> String {
        format(date, date: .long, time: .shortened, calendar: calendar)
    }

    private static func format(
        _ date: Date,
        date dateStyle: Date.FormatStyle.DateStyle,
        time timeStyle: Date.FormatStyle.TimeStyle,
        calendar: Calendar
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: dateStyle,
                time: timeStyle,
                locale: calendar.locale ?? .autoupdatingCurrent,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
        )
    }
}
