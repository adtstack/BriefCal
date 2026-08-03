import Foundation

struct MonthGridDay: Equatable, Identifiable {
    let date: Date
    let dayIndex: Int
    let weekIndex: Int
    let weekdayIndex: Int
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

struct MonthGrid: Equatable {
    let monthStart: Date
    let visibleInterval: DateInterval
    let weekdayOrdinals: [Int]
    let days: [MonthGridDay]
    let weeks: [[MonthGridDay]]

    var interval: DateInterval { visibleInterval }
    var rowCount: Int { weeks.count }

    init(containing date: Date, calendar: Calendar) {
        let monthInterval = calendar.dateInterval(of: .month, for: date)
        let resolvedMonthStart = calendar.startOfDay(
            for: monthInterval?.start ?? date
        )
        let fallbackMonthEnd = calendar.date(
            byAdding: .month,
            value: 1,
            to: resolvedMonthStart
        ) ?? calendar.date(
            byAdding: .day,
            value: 28,
            to: resolvedMonthStart
        ) ?? resolvedMonthStart.addingTimeInterval(28 * 86_400)
        let monthEnd = calendar.startOfDay(
            for: monthInterval?.end ?? fallbackMonthEnd
        )
        monthStart = resolvedMonthStart

        let firstWeekday = Self.normalizedWeekday(calendar.firstWeekday)
        weekdayOrdinals = (0..<7).map { offset in
            ((firstWeekday - 1 + offset) % 7) + 1
        }

        let monthStartWeekday = calendar.component(
            .weekday,
            from: resolvedMonthStart
        )
        let leadingDayCount = (
            monthStartWeekday - firstWeekday + 7
        ) % 7
        let gridStart = calendar.date(
            byAdding: .day,
            value: -leadingDayCount,
            to: resolvedMonthStart
        ) ?? resolvedMonthStart

        let daysThroughMonthEnd = max(
            1,
            calendar.dateComponents(
                [.day],
                from: gridStart,
                to: monthEnd
            ).day ?? 28
        )
        let weekCount = min(6, max(4, (daysThroughMonthEnd + 6) / 7))
        let dayCount = weekCount * 7
        let gridEnd = calendar.date(
            byAdding: .day,
            value: dayCount,
            to: gridStart
        ) ?? gridStart.addingTimeInterval(Double(dayCount) * 86_400)
        visibleInterval = DateInterval(start: gridStart, end: gridEnd)

        let generatedDays = (0..<dayCount).map { dayIndex in
            let day = calendar.date(
                byAdding: .day,
                value: dayIndex,
                to: gridStart
            ) ?? gridStart.addingTimeInterval(Double(dayIndex) * 86_400)
            return MonthGridDay(
                date: day,
                dayIndex: dayIndex,
                weekIndex: dayIndex / 7,
                weekdayIndex: dayIndex % 7,
                isInDisplayedMonth: calendar.isDate(
                    day,
                    equalTo: resolvedMonthStart,
                    toGranularity: .month
                )
            )
        }
        days = generatedDays
        weeks = stride(from: 0, to: dayCount, by: 7).map { start in
            Array(generatedDays[start..<min(start + 7, generatedDays.count)])
        }
    }

    func dayIndex(containing date: Date, calendar: Calendar) -> Int? {
        let target = calendar.startOfDay(for: date)
        return days.firstIndex {
            calendar.isDate($0.date, inSameDayAs: target)
        }
    }

    static func monthStart(
        containing date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func shiftedMonthStart(
        from monthStart: Date,
        by value: Int,
        calendar: Calendar
    ) -> Date {
        let shifted = calendar.date(
            byAdding: .month,
            value: value,
            to: monthStart
        ) ?? monthStart
        return Self.monthStart(containing: shifted, calendar: calendar)
    }

    static func dayIdentifier(
        for date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: date
        )
        return [
            String(components.era ?? 0),
            String(format: "%04d", components.year ?? 0),
            String(format: "%02d", components.month ?? 0),
            String(format: "%02d", components.day ?? 0)
        ].joined(separator: "-")
    }

    private static func normalizedWeekday(_ value: Int) -> Int {
        ((value - 1) % 7 + 7) % 7 + 1
    }
}

struct MonthEventSegment: Equatable, Identifiable {
    let id: String
    let event: DisplayEvent
    let weekIndex: Int
    let representativeDate: Date
    let startDate: Date
    let endDate: Date
    let startDayIndex: Int
    let endDayIndex: Int
    let startWeekdayIndex: Int
    let endWeekdayIndex: Int
    let laneIndex: Int
    let continuesBefore: Bool
    let continuesAfter: Bool
    let isAllDay: Bool

    var daySpan: ClosedRange<Int> { startDayIndex...endDayIndex }
    var weekdaySpan: ClosedRange<Int> {
        startWeekdayIndex...endWeekdayIndex
    }
    var spanLength: Int { endDayIndex - startDayIndex + 1 }
}

struct MonthEventWeekLayout: Equatable, Identifiable {
    let index: Int
    let segments: [MonthEventSegment]
    let rowCount: Int

    var id: Int { index }
}

struct MonthEventLayout: Equatable {
    let grid: MonthGrid
    let segments: [MonthEventSegment]
    let weeks: [MonthEventWeekLayout]
    let rowCount: Int

    private let calendar: Calendar

    init(events: [DisplayEvent], grid: MonthGrid, calendar: Calendar) {
        self.grid = grid
        self.calendar = calendar

        let candidates = Self.makeCandidates(
            events: events,
            grid: grid,
            calendar: calendar
        )
        let weekLayouts = (0..<grid.rowCount).map { weekIndex in
            Self.layoutWeek(
                candidates.filter { $0.weekIndex == weekIndex },
                weekIndex: weekIndex
            )
        }
        weeks = weekLayouts
        segments = weekLayouts.flatMap(\.segments)
        rowCount = weekLayouts.map(\.rowCount).max() ?? 0
    }

    func segments(inWeek weekIndex: Int) -> [MonthEventSegment] {
        guard weeks.indices.contains(weekIndex) else { return [] }
        return weeks[weekIndex].segments
    }

    func rowCount(inWeek weekIndex: Int) -> Int {
        guard weeks.indices.contains(weekIndex) else { return 0 }
        return weeks[weekIndex].rowCount
    }

    func segments(on date: Date) -> [MonthEventSegment] {
        guard let dayIndex = grid.dayIndex(
            containing: date,
            calendar: calendar
        ) else { return [] }
        let weekIndex = dayIndex / 7
        return segments(inWeek: weekIndex).filter {
            $0.startDayIndex <= dayIndex && dayIndex <= $0.endDayIndex
        }
    }

    func events(on date: Date) -> [DisplayEvent] {
        uniqueEvents(from: segments(on: date))
    }

    func hiddenEvents(
        on date: Date,
        maximumVisibleLanes: Int
    ) -> [DisplayEvent] {
        let firstHiddenLane = max(0, maximumVisibleLanes)
        return uniqueEvents(
            from: segments(on: date).filter {
                $0.laneIndex >= firstHiddenLane
            }
        )
    }

    func hiddenEventCount(
        on date: Date,
        maximumVisibleLanes: Int
    ) -> Int {
        hiddenEvents(
            on: date,
            maximumVisibleLanes: maximumVisibleLanes
        ).count
    }

    private func uniqueEvents(
        from orderedSegments: [MonthEventSegment]
    ) -> [DisplayEvent] {
        var seen = Set<String>()
        return orderedSegments.compactMap { segment in
            guard seen.insert(segment.event.id).inserted else { return nil }
            return segment.event
        }
    }

    private static func makeCandidates(
        events: [DisplayEvent],
        grid: MonthGrid,
        calendar: Calendar
    ) -> [MonthSegmentCandidate] {
        events.flatMap { event -> [MonthSegmentCandidate] in
            let range = CalendarEventDateFormatting.effectiveDateRange(
                for: event,
                calendar: calendar
            )
            guard range.end > range.start,
                  range.end > grid.visibleInterval.start,
                  range.start < grid.visibleInterval.end else {
                return []
            }

            let eventStartDay = calendar.startOfDay(for: range.start)
            let eventEndDay = calendar.startOfDay(for: range.end)
            let eventEndDayExclusive: Date
            if range.end > eventEndDay {
                eventEndDayExclusive = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: eventEndDay
                ) ?? range.end
            } else {
                eventEndDayExclusive = eventEndDay
            }

            let rawStartDayIndex = calendar.dateComponents(
                [.day],
                from: grid.visibleInterval.start,
                to: eventStartDay
            ).day ?? 0
            let rawEndDayIndexExclusive = calendar.dateComponents(
                [.day],
                from: grid.visibleInterval.start,
                to: eventEndDayExclusive
            ).day ?? 0
            let visibleStartDayIndex = max(0, rawStartDayIndex)
            let visibleEndDayIndexExclusive = min(
                grid.days.count,
                rawEndDayIndexExclusive
            )
            guard visibleStartDayIndex < visibleEndDayIndexExclusive else {
                return []
            }

            let firstWeek = visibleStartDayIndex / 7
            let lastWeek = (visibleEndDayIndexExclusive - 1) / 7
            return (firstWeek...lastWeek).map { weekIndex in
                let weekStartDayIndex = weekIndex * 7
                let weekEndDayIndex = weekStartDayIndex + 6
                let segmentStartDayIndex = max(
                    visibleStartDayIndex,
                    weekStartDayIndex
                )
                let segmentEndDayIndex = min(
                    visibleEndDayIndexExclusive - 1,
                    weekEndDayIndex
                )
                let segmentStartBoundary = grid.days[
                    segmentStartDayIndex
                ].date
                let segmentEndBoundary = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: grid.days[segmentEndDayIndex].date
                ) ?? grid.visibleInterval.end

                return MonthSegmentCandidate(
                    event: event,
                    weekIndex: weekIndex,
                    representativeDate: segmentStartBoundary,
                    startDate: max(range.start, segmentStartBoundary),
                    endDate: min(range.end, segmentEndBoundary),
                    startDayIndex: segmentStartDayIndex,
                    endDayIndex: segmentEndDayIndex,
                    continuesBefore: rawStartDayIndex < segmentStartDayIndex,
                    continuesAfter: rawEndDayIndexExclusive - 1
                        > segmentEndDayIndex,
                    effectiveStartDate: range.start,
                    effectiveEndDate: range.end
                )
            }
        }
    }

    private static func layoutWeek(
        _ candidates: [MonthSegmentCandidate],
        weekIndex: Int
    ) -> MonthEventWeekLayout {
        let ordered = candidates.sorted(by: candidatePrecedes)
        var occupiedThroughDayByLane: [Int] = []
        var placed: [MonthEventSegment] = []

        for candidate in ordered {
            let laneIndex: Int
            if let reusableLane = occupiedThroughDayByLane.firstIndex(
                where: { $0 < candidate.startDayIndex }
            ) {
                laneIndex = reusableLane
                occupiedThroughDayByLane[reusableLane] = candidate.endDayIndex
            } else {
                laneIndex = occupiedThroughDayByLane.count
                occupiedThroughDayByLane.append(candidate.endDayIndex)
            }

            placed.append(
                MonthEventSegment(
                    id: [
                        candidate.event.id,
                        "month-week-\(weekIndex)",
                        "days-\(candidate.startDayIndex)-\(candidate.endDayIndex)"
                    ].joined(separator: "#"),
                    event: candidate.event,
                    weekIndex: weekIndex,
                    representativeDate: candidate.representativeDate,
                    startDate: candidate.startDate,
                    endDate: candidate.endDate,
                    startDayIndex: candidate.startDayIndex,
                    endDayIndex: candidate.endDayIndex,
                    startWeekdayIndex: candidate.startDayIndex % 7,
                    endWeekdayIndex: candidate.endDayIndex % 7,
                    laneIndex: laneIndex,
                    continuesBefore: candidate.continuesBefore,
                    continuesAfter: candidate.continuesAfter,
                    isAllDay: candidate.event.isAllDay
                )
            )
        }

        placed.sort {
            if $0.laneIndex != $1.laneIndex {
                return $0.laneIndex < $1.laneIndex
            }
            if $0.startDayIndex != $1.startDayIndex {
                return $0.startDayIndex < $1.startDayIndex
            }
            return $0.event.id < $1.event.id
        }
        return MonthEventWeekLayout(
            index: weekIndex,
            segments: placed,
            rowCount: occupiedThroughDayByLane.count
        )
    }

    private static func candidatePrecedes(
        _ lhs: MonthSegmentCandidate,
        _ rhs: MonthSegmentCandidate
    ) -> Bool {
        if lhs.startDayIndex != rhs.startDayIndex {
            return lhs.startDayIndex < rhs.startDayIndex
        }
        if lhs.event.isAllDay != rhs.event.isAllDay {
            return lhs.event.isAllDay
        }
        let lhsSpan = lhs.endDayIndex - lhs.startDayIndex
        let rhsSpan = rhs.endDayIndex - rhs.startDayIndex
        if lhsSpan != rhsSpan {
            return lhsSpan > rhsSpan
        }
        if lhs.effectiveStartDate != rhs.effectiveStartDate {
            return lhs.effectiveStartDate < rhs.effectiveStartDate
        }
        if lhs.effectiveEndDate != rhs.effectiveEndDate {
            return lhs.effectiveEndDate > rhs.effectiveEndDate
        }
        return lhs.event.id < rhs.event.id
    }
}

private struct MonthSegmentCandidate {
    let event: DisplayEvent
    let weekIndex: Int
    let representativeDate: Date
    let startDate: Date
    let endDate: Date
    let startDayIndex: Int
    let endDayIndex: Int
    let continuesBefore: Bool
    let continuesAfter: Bool
    let effectiveStartDate: Date
    let effectiveEndDate: Date
}
