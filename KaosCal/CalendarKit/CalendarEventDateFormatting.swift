import Foundation

enum CalendarEventDateFormatting {
    static func displayedEndDate(
        for event: DisplayEvent,
        calendar: Calendar
    ) -> Date {
        guard event.isAllDay,
              event.endDate > event.startDate,
              let inclusiveEnd = calendar.date(
                  byAdding: .day,
                  value: -1,
                  to: event.endDate
              ) else {
            return event.isAllDay ? event.startDate : event.endDate
        }

        return max(event.startDate, inclusiveEnd)
    }

    static func spansMultipleDates(
        _ event: DisplayEvent,
        calendar: Calendar
    ) -> Bool {
        !calendar.isDate(
            event.startDate,
            inSameDayAs: displayedEndDate(for: event, calendar: calendar)
        )
    }

    static func agendaText(
        for event: DisplayEvent,
        calendar: Calendar
    ) -> String {
        let displayedEnd = displayedEndDate(for: event, calendar: calendar)

        if event.isAllDay {
            let start = event.startDate.formatted(date: .abbreviated, time: .omitted)
            guard spansMultipleDates(event, calendar: calendar) else {
                return "All-day · \(start)"
            }
            let end = displayedEnd.formatted(date: .abbreviated, time: .omitted)
            return "All-day · \(start)–\(end)"
        }

        let start = event.startDate.formatted(date: .abbreviated, time: .shortened)
        let end = spansMultipleDates(event, calendar: calendar)
            ? event.endDate.formatted(date: .abbreviated, time: .shortened)
            : event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end)"
    }

    static func inspectorText(
        for event: DisplayEvent,
        calendar: Calendar
    ) -> String {
        let displayedEnd = displayedEndDate(for: event, calendar: calendar)

        if event.isAllDay {
            let start = event.startDate.formatted(date: .long, time: .omitted)
            guard spansMultipleDates(event, calendar: calendar) else {
                return "All-day · \(start)"
            }
            let end = displayedEnd.formatted(date: .long, time: .omitted)
            return "All-day · \(start) – \(end)"
        }

        let start = event.startDate.formatted(date: .long, time: .shortened)
        let end = spansMultipleDates(event, calendar: calendar)
            ? event.endDate.formatted(date: .long, time: .shortened)
            : event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
