import Foundation

struct TimedEventPlacement: Equatable, Identifiable {
    let id: String
    let event: DisplayEvent
    let dayIndex: Int
    let clippedStartDate: Date
    let clippedEndDate: Date
    let startMinute: Double
    let endMinute: Double
    let layoutStartMinute: Double
    let layoutEndMinute: Double
    let columnIndex: Int
    let columnCount: Int
    let continuesBefore: Bool
    let continuesAfter: Bool
}

struct AllDayEventPlacement: Equatable, Identifiable {
    let id: String
    let event: DisplayEvent
    let startDayIndex: Int
    let endDayIndex: Int
    let rowIndex: Int
    let continuesBefore: Bool
    let continuesAfter: Bool
}

struct CalendarEventLayout: Equatable {
    static let minimumVisualDurationMinutes: Double = 24

    let dates: [Date]
    let timedPlacements: [TimedEventPlacement]
    let allDayPlacements: [AllDayEventPlacement]
    let allDayRowCount: Int

    init(events: [DisplayEvent], dates: [Date], calendar: Calendar) {
        let normalizedDates = dates.map { calendar.startOfDay(for: $0) }
        self.dates = normalizedDates

        guard let visibleStart = normalizedDates.first,
              let finalDate = normalizedDates.last,
              let visibleEnd = calendar.date(byAdding: .day, value: 1, to: finalDate) else {
            timedPlacements = []
            allDayPlacements = []
            allDayRowCount = 0
            return
        }

        let interval = DateInterval(start: visibleStart, end: visibleEnd)
        let allDay = Self.makeAllDayPlacements(
            events: events.filter(\.isAllDay),
            dates: normalizedDates,
            visibleInterval: interval,
            calendar: calendar
        )
        let timed = Self.makeTimedPlacements(
            events: events.filter { !$0.isAllDay },
            dates: normalizedDates,
            calendar: calendar
        )

        allDayPlacements = allDay
        timedPlacements = timed
        allDayRowCount = (allDay.map(\.rowIndex).max() ?? -1) + 1
    }

    private static func makeAllDayPlacements(
        events: [DisplayEvent],
        dates: [Date],
        visibleInterval: DateInterval,
        calendar: Calendar
    ) -> [AllDayEventPlacement] {
        guard let visibleStart = dates.first else { return [] }

        let candidates = events.compactMap { event -> AllDayCandidate? in
            let range = CalendarEventDateFormatting.effectiveDateRange(
                for: event,
                calendar: calendar
            )
            guard range.end > visibleInterval.start,
                  range.start < visibleInterval.end,
                  range.end > range.start else {
                return nil
            }

            let eventStart = calendar.startOfDay(for: range.start)
            let eventEndExclusive = calendar.startOfDay(for: range.end)
            let rawStart = calendar.dateComponents(
                [.day],
                from: visibleStart,
                to: eventStart
            ).day ?? 0
            let rawEndExclusive = calendar.dateComponents(
                [.day],
                from: visibleStart,
                to: eventEndExclusive
            ).day ?? 0
            let start = max(0, rawStart)
            let end = min(dates.count, rawEndExclusive) - 1
            guard start <= end else { return nil }

            return AllDayCandidate(
                event: event,
                startDayIndex: start,
                endDayIndex: end,
                continuesBefore: rawStart < 0,
                continuesAfter: rawEndExclusive > dates.count
            )
        }
        .sorted {
            if $0.startDayIndex != $1.startDayIndex {
                return $0.startDayIndex < $1.startDayIndex
            }
            if $0.endDayIndex != $1.endDayIndex {
                return $0.endDayIndex > $1.endDayIndex
            }
            return $0.event.id < $1.event.id
        }

        var rowEndIndices: [Int] = []
        return candidates.map { candidate in
            let row: Int
            if let availableRow = rowEndIndices.firstIndex(
                where: { $0 < candidate.startDayIndex }
            ) {
                row = availableRow
                rowEndIndices[availableRow] = candidate.endDayIndex
            } else {
                row = rowEndIndices.count
                rowEndIndices.append(candidate.endDayIndex)
            }

            return AllDayEventPlacement(
                id: "\(candidate.event.id)#all-day",
                event: candidate.event,
                startDayIndex: candidate.startDayIndex,
                endDayIndex: candidate.endDayIndex,
                rowIndex: row,
                continuesBefore: candidate.continuesBefore,
                continuesAfter: candidate.continuesAfter
            )
        }
    }

    private static func makeTimedPlacements(
        events: [DisplayEvent],
        dates: [Date],
        calendar: Calendar
    ) -> [TimedEventPlacement] {
        var segmentsByDay: [[TimedSegment]] = Array(
            repeating: [],
            count: dates.count
        )

        for (dayIndex, dayStart) in dates.enumerated() {
            guard let dayEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: dayStart
            ) else { continue }

            for event in events {
                let range = CalendarEventDateFormatting.effectiveDateRange(
                    for: event,
                    calendar: calendar
                )
                guard range.end > range.start else { continue }
                let segmentStart = max(range.start, dayStart)
                let segmentEnd = min(range.end, dayEnd)
                guard segmentStart < segmentEnd else { continue }

                let startMinute = wallClockMinute(
                    for: segmentStart,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    calendar: calendar
                )
                var endMinute = wallClockMinute(
                    for: segmentEnd,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    calendar: calendar
                )
                if endMinute <= startMinute {
                    let actualDuration = segmentEnd.timeIntervalSince(segmentStart) / 60
                    endMinute = min(1_440, startMinute + max(1, actualDuration))
                }
                let desiredLayoutEnd = max(
                    endMinute,
                    startMinute + minimumVisualDurationMinutes
                )
                let overflow = max(0, desiredLayoutEnd - 1_440)
                let layoutStartMinute = max(0, startMinute - overflow)
                let layoutEndMinute = min(
                    1_440,
                    max(endMinute, layoutStartMinute + minimumVisualDurationMinutes)
                )

                segmentsByDay[dayIndex].append(
                    TimedSegment(
                        event: event,
                        dayIndex: dayIndex,
                        startDate: segmentStart,
                        endDate: segmentEnd,
                        startMinute: startMinute,
                        endMinute: endMinute,
                        layoutStartMinute: layoutStartMinute,
                        layoutEndMinute: layoutEndMinute,
                        continuesBefore: range.start < dayStart,
                        continuesAfter: range.end > dayEnd
                    )
                )
            }
        }

        return segmentsByDay
            .flatMap(layoutTimedDay)
            .sorted {
                if $0.dayIndex != $1.dayIndex {
                    return $0.dayIndex < $1.dayIndex
                }
                if $0.startMinute != $1.startMinute {
                    return $0.startMinute < $1.startMinute
                }
                if $0.columnIndex != $1.columnIndex {
                    return $0.columnIndex < $1.columnIndex
                }
                return $0.event.id < $1.event.id
            }
    }

    private static func layoutTimedDay(
        _ segments: [TimedSegment]
    ) -> [TimedEventPlacement] {
        let sorted = segments.sorted {
            if $0.layoutStartMinute != $1.layoutStartMinute {
                return $0.layoutStartMinute < $1.layoutStartMinute
            }
            if $0.startMinute != $1.startMinute {
                return $0.startMinute < $1.startMinute
            }
            if $0.layoutEndMinute != $1.layoutEndMinute {
                return $0.layoutEndMinute > $1.layoutEndMinute
            }
            return $0.event.id < $1.event.id
        }

        var result: [TimedEventPlacement] = []
        var group: [TimedSegment] = []
        var groupEndMinute: Double?

        for segment in sorted {
            if let end = groupEndMinute, segment.layoutStartMinute >= end {
                result.append(contentsOf: layoutOverlapGroup(group))
                group = []
                groupEndMinute = nil
            }
            group.append(segment)
            groupEndMinute = max(
                groupEndMinute ?? segment.layoutEndMinute,
                segment.layoutEndMinute
            )
        }

        result.append(contentsOf: layoutOverlapGroup(group))
        return result
    }

    private static func layoutOverlapGroup(
        _ group: [TimedSegment]
    ) -> [TimedEventPlacement] {
        guard !group.isEmpty else { return [] }

        var columnEndMinutes: [Double] = []
        var assignments: [(TimedSegment, Int)] = []

        for segment in group {
            let column: Int
            if let availableColumn = columnEndMinutes.firstIndex(
                where: { $0 <= segment.layoutStartMinute }
            ) {
                column = availableColumn
                columnEndMinutes[availableColumn] = segment.layoutEndMinute
            } else {
                column = columnEndMinutes.count
                columnEndMinutes.append(segment.layoutEndMinute)
            }
            assignments.append((segment, column))
        }

        let columnCount = max(1, columnEndMinutes.count)
        return assignments.map { segment, column in
            TimedEventPlacement(
                id: "\(segment.event.id)#day-\(segment.dayIndex)",
                event: segment.event,
                dayIndex: segment.dayIndex,
                clippedStartDate: segment.startDate,
                clippedEndDate: segment.endDate,
                startMinute: segment.startMinute,
                endMinute: segment.endMinute,
                layoutStartMinute: segment.layoutStartMinute,
                layoutEndMinute: segment.layoutEndMinute,
                columnIndex: column,
                columnCount: columnCount,
                continuesBefore: segment.continuesBefore,
                continuesAfter: segment.continuesAfter
            )
        }
    }

    private static func wallClockMinute(
        for date: Date,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> Double {
        if date <= dayStart { return 0 }
        if date >= dayEnd { return 1_440 }

        let components = calendar.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        return Double(components.hour ?? 0) * 60
            + Double(components.minute ?? 0)
            + Double(components.second ?? 0) / 60
    }
}

private struct AllDayCandidate {
    let event: DisplayEvent
    let startDayIndex: Int
    let endDayIndex: Int
    let continuesBefore: Bool
    let continuesAfter: Bool
}

private struct TimedSegment {
    let event: DisplayEvent
    let dayIndex: Int
    let startDate: Date
    let endDate: Date
    let startMinute: Double
    let endMinute: Double
    let layoutStartMinute: Double
    let layoutEndMinute: Double
    let continuesBefore: Bool
    let continuesAfter: Bool
}
