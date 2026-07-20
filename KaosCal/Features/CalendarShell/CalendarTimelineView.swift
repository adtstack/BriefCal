import Foundation
import SwiftUI

struct CalendarTimelineView: View {
    @ObservedObject var appState: AppState

    private let gutterWidth: CGFloat = 64
    private let headerHeight: CGFloat = 48
    private let hourHeight: CGFloat = 56
    private let allDayRowHeight: CGFloat = 26
    private let minimumCardHeight: CGFloat = 22
    private let minimumWeekDayWidth: CGFloat = 112
    private let minimumDayWidth: CGFloat = 560
    private let minimumOverlapColumnWidth: CGFloat = 44

    private var layout: CalendarEventLayout {
        CalendarEventLayout(
            events: appState.visibleEvents,
            dates: appState.visibleDates,
            calendar: appState.calendar
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = layout
            let dayWidth = dayWidth(
                availableWidth: geometry.size.width,
                layout: layout
            )
            let contentWidth = gutterWidth
                + dayWidth * CGFloat(max(1, layout.dates.count))
            let naturalAllDayHeight = max(
                36,
                8 + CGFloat(layout.allDayRowCount) * allDayRowHeight
            )
            let maximumAllDayHeight = max(
                36,
                min(240, geometry.size.height * 0.35)
            )
            let allDayHeight = min(naturalAllDayHeight, maximumAllDayHeight)
            let timelineViewportHeight = max(
                0,
                geometry.size.height - headerHeight - allDayHeight - 1
            )

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    dayHeader(
                        dates: layout.dates,
                        dayWidth: dayWidth,
                        contentWidth: contentWidth
                    )
                    allDayLane(
                        layout: layout,
                        dayWidth: dayWidth,
                        contentWidth: contentWidth,
                        height: allDayHeight,
                        contentHeight: naturalAllDayHeight
                    )
                    Divider()
                    timelineScroller(
                        layout: layout,
                        dayWidth: dayWidth,
                        contentWidth: contentWidth,
                        viewportHeight: timelineViewportHeight
                    )
                }
                .frame(
                    width: contentWidth,
                    height: geometry.size.height,
                    alignment: .top
                )
            }
            .scrollIndicators(.visible)
            .id(layout.dates.first)
        }
        .accessibilityIdentifier(
            appState.visibleDates.count == 1
                ? "calendar.grid.day"
                : "calendar.grid.week"
        )
    }

    private func dayWidth(
        availableWidth: CGFloat,
        layout: CalendarEventLayout
    ) -> CGFloat {
        let dayCount = max(1, layout.dates.count)
        let maximumColumns = max(
            1,
            layout.timedPlacements.map(\.columnCount).max() ?? 1
        )
        let densityWidth = CGFloat(maximumColumns)
            * minimumOverlapColumnWidth + 8
        let widthWithoutGutter = max(0, availableWidth - gutterWidth)

        if dayCount == 1 {
            return max(minimumDayWidth, widthWithoutGutter, densityWidth)
        }
        return max(
            minimumWeekDayWidth,
            widthWithoutGutter / CGFloat(dayCount),
            densityWidth
        )
    }

    private func dayHeader(
        dates: [Date],
        dayWidth: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Text(appState.calendar.timeZone.abbreviation() ?? "Local")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: gutterWidth, height: headerHeight)

            ForEach(Array(dates.enumerated()), id: \.element) { _, date in
                Button {
                    appState.focusedDate = appState.calendar.startOfDay(for: date)
                    appState.select(.day)
                } label: {
                    VStack(spacing: 2) {
                        Text(
                            CalendarEventDateFormatting.weekday(
                                date,
                                calendar: appState.calendar
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(
                            CalendarEventDateFormatting.dayNumber(
                                date,
                                calendar: appState.calendar
                            )
                        )
                        .font(.headline.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        appState.calendar.isDateInToday(date)
                            ? KaosCalTheme.accentSoft
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: dayWidth, height: headerHeight)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(KaosCalTheme.subtleDivider)
                        .frame(width: 1)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(
                    "Open \(CalendarEventDateFormatting.longDate(date, calendar: appState.calendar)) in Day view"
                )
                .accessibilityIdentifier("calendar.header.\(dayKey(date))")
            }
        }
        .frame(width: contentWidth, height: headerHeight)
        .background(.bar)
    }

    private func allDayLane(
        layout: CalendarEventLayout,
        dayWidth: CGFloat,
        contentWidth: CGFloat,
        height: CGFloat,
        contentHeight: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Text("All-day")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: gutterWidth - 8, alignment: .trailing)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .frame(width: gutterWidth, height: height, alignment: .top)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(
                            Array(layout.dates.enumerated()),
                            id: \.element
                        ) { _, date in
                            Rectangle()
                                .fill(
                                    appState.calendar.isDateInToday(date)
                                        ? KaosCalTheme.accentSoft.opacity(0.45)
                                        : Color.clear
                                )
                                    .frame(width: dayWidth, height: contentHeight)
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(KaosCalTheme.subtleDivider)
                                        .frame(width: 1)
                                }
                                .accessibilityHidden(true)
                        }
                    }

                    ForEach(layout.allDayPlacements) { placement in
                        let span = placement.endDayIndex
                            - placement.startDayIndex + 1
                        let x = CGFloat(placement.startDayIndex) * dayWidth + 3
                        let y = 4
                            + CGFloat(placement.rowIndex) * allDayRowHeight
                        let width = max(24, CGFloat(span) * dayWidth - 6)

                        Button {
                            appState.userSelectEvent(placement.event.id)
                        } label: {
                            AllDayEventCard(
                                placement: placement,
                                isSelected: appState.selectedEventID
                                    == placement.event.id,
                                calendar: appState.calendar,
                                role: appState.calendarRole(
                                    for: placement.event
                                ),
                                restriction: appState.calendarWriteRestriction(
                                    for: placement.event
                                ),
                                hasDuplicateCandidates: appState
                                    .hasDuplicateCandidates(
                                        for: placement.event
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: width, height: 22)
                        .offset(x: x, y: y)
                        .accessibilityIdentifier(
                            "calendar.event.\(placement.event.id).allDay"
                        )
                    }
                }
                .frame(
                    width: contentWidth - gutterWidth,
                    height: contentHeight,
                    alignment: .topLeading
                )
            }
            .scrollDisabled(contentHeight <= height)
            .scrollIndicators(contentHeight > height ? .visible : .hidden)
            .frame(width: contentWidth - gutterWidth, height: height)
        }
        .frame(width: contentWidth, height: height)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("calendar.allDayLane")
    }

    private func timelineScroller(
        layout: CalendarEventLayout,
        dayWidth: CGFloat,
        contentWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                timelineCanvas(
                    layout: layout,
                    dayWidth: dayWidth,
                    contentWidth: contentWidth
                )
            }
            .scrollIndicators(.visible)
            .frame(width: contentWidth, height: viewportHeight)
            .task(id: layout.dates.first) {
                await Task.yield()
                reader.scrollTo(initialScrollHour(layout: layout), anchor: .top)
            }
        }
    }

    private func timelineCanvas(
        layout: CalendarEventLayout,
        dayWidth: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        let canvasHeight = hourHeight * 24

        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    hourRow(
                        hour: hour,
                        dates: layout.dates,
                        dayWidth: dayWidth,
                        contentWidth: contentWidth
                    )
                    .id(hour)
                }
            }

            ForEach(layout.timedPlacements) { placement in
                let frame = timedFrame(
                    placement,
                    dayWidth: dayWidth,
                    canvasHeight: canvasHeight
                )

                Button {
                    appState.userSelectEvent(placement.event.id)
                } label: {
                    TimedEventCard(
                        placement: placement,
                        height: frame.height,
                        isSelected: appState.selectedEventID == placement.event.id,
                        calendar: appState.calendar,
                        role: appState.calendarRole(for: placement.event),
                        restriction: appState.calendarWriteRestriction(
                            for: placement.event
                        ),
                        hasDuplicateCandidates: appState
                            .hasDuplicateCandidates(for: placement.event)
                    )
                }
                .buttonStyle(.plain)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .accessibilityIdentifier(
                    "calendar.event.\(placement.event.id).timed.\(dayKey(layout.dates[placement.dayIndex]))"
                )
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                currentTimeIndicator(
                    now: context.date,
                    dates: layout.dates,
                    dayWidth: dayWidth
                )
            }
        }
        .frame(width: contentWidth, height: canvasHeight, alignment: .topLeading)
        .dropDestination(for: String.self) { references, location in
            guard let reference = references.first(where: {
                $0.hasPrefix("kaoscal-task:")
            }), location.x >= gutterWidth else {
                return false
            }
            let dayIndex = Int((location.x - gutterWidth) / dayWidth)
            guard layout.dates.indices.contains(dayIndex) else {
                return false
            }
            let rawMinute = max(
                0,
                min(23 * 60 + 45, Double(location.y / hourHeight) * 60)
            )
            let snappedMinute = Int(rawMinute / 15) * 15
            guard let start = appState.calendar.date(
                byAdding: .minute,
                value: snappedMinute,
                to: appState.calendar.startOfDay(
                    for: layout.dates[dayIndex]
                )
            ) else {
                return false
            }
            return appState.beginCreatingTaskTimeBlock(
                sidebarTaskReference: reference,
                startAt: start
            )
        } isTargeted: { _ in }
        .accessibilityIdentifier("calendar.timeGrid")
    }

    private func hourRow(
        hour: Int,
        dates: [Date],
        dayWidth: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Text(String(format: "%02d:00", hour))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: gutterWidth - 8, alignment: .trailing)
                .padding(.trailing, 8)
                .frame(height: hourHeight, alignment: .top)
                .offset(y: -6)
                .accessibilityHidden(true)

            ForEach(Array(dates.enumerated()), id: \.element) { _, date in
                Rectangle()
                    .fill(
                        appState.calendar.isDateInToday(date)
                            ? KaosCalTheme.accentSoft.opacity(0.22)
                            : Color.clear
                    )
                    .frame(width: dayWidth, height: hourHeight)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(KaosCalTheme.subtleDivider)
                            .frame(height: 1)
                    }
                    .overlay(alignment: .center) {
                        Rectangle()
                            .fill(KaosCalTheme.subtleDivider.opacity(0.45))
                            .frame(height: 1)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(KaosCalTheme.subtleDivider)
                            .frame(width: 1)
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: contentWidth, height: hourHeight)
    }

    private func timedFrame(
        _ placement: TimedEventPlacement,
        dayWidth: CGFloat,
        canvasHeight: CGFloat
    ) -> CGRect {
        let columnCount = CGFloat(max(1, placement.columnCount))
        let usableWidth = max(24, dayWidth - 6)
        let columnWidth = usableWidth / columnCount
        let width = max(20, columnWidth - 2)
        let x = gutterWidth + CGFloat(placement.dayIndex) * dayWidth + 3
            + CGFloat(placement.columnIndex) * columnWidth
        let rawY = CGFloat(placement.layoutStartMinute / 60) * hourHeight
        let durationHeight = CGFloat(
            (placement.layoutEndMinute - placement.layoutStartMinute) / 60
        ) * hourHeight
        let height = min(canvasHeight, max(minimumCardHeight, durationHeight))
        return CGRect(x: x, y: rawY, width: width, height: height)
    }

    @ViewBuilder
    private func currentTimeIndicator(
        now: Date,
        dates: [Date],
        dayWidth: CGFloat
    ) -> some View {
        if let dayIndex = dates.firstIndex(
            where: { appState.calendar.isDate($0, inSameDayAs: now) }
        ) {
            let components = appState.calendar.dateComponents(
                [.hour, .minute, .second],
                from: now
            )
            let minute = Double(components.hour ?? 0) * 60
                + Double(components.minute ?? 0)
                + Double(components.second ?? 0) / 60
            let x = gutterWidth + CGFloat(dayIndex) * dayWidth
            let y = CGFloat(minute / 60) * hourHeight

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.red.opacity(0.8))
                    .frame(width: dayWidth, height: 1)
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .offset(x: -3)
            }
            .offset(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(
                "Current time, \(CalendarEventDateFormatting.shortTime(now, calendar: appState.calendar))"
            )
            .accessibilityIdentifier("calendar.currentTime.\(dayKey(dates[dayIndex]))")
        }
    }

    private func initialScrollHour(layout: CalendarEventLayout) -> Int {
        let now = Date()
        if layout.dates.contains(
            where: { appState.calendar.isDate($0, inSameDayAs: now) }
        ) {
            let hour = appState.calendar.component(.hour, from: now)
            return max(0, min(23, hour - 1))
        }
        if let firstMinute = layout.timedPlacements.map(\.startMinute).min() {
            return max(0, min(23, Int(firstMinute / 60) - 1))
        }
        return 8
    }

    private func dayKey(_ date: Date) -> String {
        let components = appState.calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct TimedEventCard: View {
    let placement: TimedEventPlacement
    let height: CGFloat
    let isSelected: Bool
    let calendar: Calendar
    let role: CalendarRole
    let restriction: CalendarWriteRestriction?
    let hasDuplicateCandidates: Bool

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(eventRailColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(placement.event.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(height >= 48 ? 2 : 1)
                    Spacer(minLength: 0)
                    statusIcons
                }

                if height >= 34 {
                    Text(segmentTimeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if height >= 58 {
                    Text("\(role.title) · \(placement.event.calendarTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KaosCalTheme.accentSoft.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isSelected ? KaosCalTheme.accent : KaosCalTheme.subtleDivider,
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .help(accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var statusIcons: some View {
        if placement.event.isRecurring {
            Image(systemName: "repeat")
                .font(.system(size: 8))
                .accessibilityHidden(true)
        }
        if hasDuplicateCandidates {
            Image(systemName: "square.on.square")
                .font(.system(size: 8))
                .accessibilityHidden(true)
        }
        if restriction != nil {
            Image(systemName: "lock")
                .font(.system(size: 8))
                .accessibilityHidden(true)
        }
    }

    private var segmentTimeText: String {
        let start = CalendarEventDateFormatting.shortTime(
            placement.clippedStartDate,
            calendar: calendar
        )
        let end = CalendarEventDateFormatting.shortTime(
            placement.clippedEndDate,
            calendar: calendar
        )
        if placement.continuesBefore && placement.continuesAfter {
            return "↤ continues ↦"
        }
        if placement.continuesBefore {
            return "↤–\(end)"
        }
        if placement.continuesAfter {
            return "\(start)–↦"
        }
        return "\(start)–\(end)"
    }

    private var eventRailColor: Color {
        KaosCalTheme.calendarColor(
            placement.event.calendarColor,
            accountType: placement.event.accountType
        )
    }

    private var accessibilityText: String {
        var parts = [
            placement.event.title,
            CalendarEventDateFormatting.agendaText(
                for: placement.event,
                calendar: calendar
            ),
            "\(role.title) role",
            placement.event.calendarTitle,
            placement.event.sourceTitle,
            placement.event.accountType.title
        ]
        if placement.event.isRecurring { parts.append("recurring") }
        if let restriction {
            parts.append("\(restriction.title), \(restriction.message)")
        } else {
            parts.append("original event editable")
        }
        if hasDuplicateCandidates {
            parts.append("possible duplicate calendar event")
        }
        if placement.continuesBefore { parts.append("continues from previous day") }
        if placement.continuesAfter { parts.append("continues to next day") }
        return parts.joined(separator: ", ")
    }
}

private struct AllDayEventCard: View {
    let placement: AllDayEventPlacement
    let isSelected: Bool
    let calendar: Calendar
    let role: CalendarRole
    let restriction: CalendarWriteRestriction?
    let hasDuplicateCandidates: Bool

    var body: some View {
        HStack(spacing: 4) {
            if placement.continuesBefore {
                Image(systemName: "chevron.left")
                    .font(.system(size: 7, weight: .bold))
            }
            Rectangle()
                .fill(eventRailColor)
                .frame(width: 3)
            Text(placement.event.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 2)
            if placement.event.isRecurring {
                Image(systemName: "repeat")
                    .font(.system(size: 8))
                    .accessibilityHidden(true)
            }
            if hasDuplicateCandidates {
                Image(systemName: "square.on.square")
                    .font(.system(size: 8))
                    .accessibilityHidden(true)
            }
            if restriction != nil {
                Image(systemName: "lock")
                    .font(.system(size: 8))
                    .accessibilityHidden(true)
            }
            if placement.continuesAfter {
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KaosCalTheme.accentSoft.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isSelected ? KaosCalTheme.accent : KaosCalTheme.subtleDivider,
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .help(accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var eventRailColor: Color {
        KaosCalTheme.calendarColor(
            placement.event.calendarColor,
            accountType: placement.event.accountType
        )
    }

    private var accessibilityText: String {
        var parts = [
            placement.event.title,
            CalendarEventDateFormatting.agendaText(
                for: placement.event,
                calendar: calendar
            ),
            "\(role.title) role",
            placement.event.calendarTitle,
            placement.event.sourceTitle,
            placement.event.accountType.title,
            "all-day"
        ]
        if placement.event.isRecurring { parts.append("recurring") }
        if let restriction {
            parts.append("\(restriction.title), \(restriction.message)")
        } else {
            parts.append("original event editable")
        }
        if hasDuplicateCandidates {
            parts.append("possible duplicate calendar event")
        }
        if placement.continuesBefore { parts.append("continues from previous period") }
        if placement.continuesAfter { parts.append("continues to next period") }
        return parts.joined(separator: ", ")
    }
}
