import SwiftUI

struct MonthCalendarView: View {
    @ObservedObject var appState: AppState
    @State private var overflowSelection: MonthOverflowSelection?
    @State private var weekCount = MonthTimeline.initialWeekCount
    @State private var isExtendingTimeline = false
    @FocusState private var keyboardFocusedDayID: String?

    private let weekdayHeaderHeight: CGFloat = 28
    private let dateHeaderHeight: CGFloat = 27
    private let eventRowHeight: CGFloat = 21
    private let overflowRowHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            monthTimeline(size: geometry.size)
        }
        .focusSection()
        .popover(item: $overflowSelection) { selection in
            MonthDayOverflowView(
                appState: appState,
                date: selection.date,
                events: selection.events,
                openDay: {
                    overflowSelection = nil
                    openDay(selection.date)
                },
                selectEvent: { event in
                    overflowSelection = nil
                    selectEvent(event)
                }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Month, \(CalendarEventDateFormatting.monthAndYear(appState.focusedDate, calendar: appState.calendar))"
        )
        .accessibilityIdentifier("calendar.grid.month")
        .task(id: anchorWeekIdentifier) {
            weekCount = MonthTimeline.initialWeekCount
            isExtendingTimeline = false
            let grid = MonthTimeline.grid(
                containing: appState.focusedDate,
                weekCount: MonthTimeline.initialWeekCount,
                calendar: appState.calendar
            )
            _ = await appState.ensureCalendarDataCovers(
                grid.visibleInterval
            )
        }
    }

    private func monthTimeline(size: CGSize) -> some View {
        let grid = MonthTimeline.grid(
            containing: appState.focusedDate,
            weekCount: weekCount,
            calendar: appState.calendar
        )
        let events = appState.displayedEvents(in: grid.visibleInterval)
        let layout = MonthEventLayout(
            events: events,
            grid: grid,
            calendar: appState.calendar
        )
        let availableHeight = max(0, size.height - weekdayHeaderHeight)
        let weekHeight = max(72, availableHeight / 6)
        let maximumVisibleLanes = visibleLaneCount(for: weekHeight)

        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                weekdayHeader(grid: grid)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(grid.weeks.enumerated()),
                            id: \.offset
                        ) { weekIndex, week in
                            monthWeek(
                                week,
                                weekIndex: weekIndex,
                                layout: layout,
                                height: weekHeight,
                                maximumVisibleLanes: maximumVisibleLanes
                            )
                            .id(weekIdentifier(week))
                            .onAppear {
                                extendTimelineIfNeeded(
                                    after: weekIndex
                                )
                            }
                        }
                    }
                }
                .contentMargins(0, for: .scrollContent)
                .defaultScrollAnchor(.top)
                .scrollIndicators(.visible)
                .id(anchorWeekIdentifier)
                .accessibilityIdentifier("month.timeline")
            }
            .frame(width: size.width, height: size.height, alignment: .top)

            if events.isEmpty {
                Label(
                    appState.calendarWorkspaceEmptyMessage,
                    systemImage: appState.calendarWorkspaceEmptySymbolName
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, weekdayHeaderHeight + 12)
                .allowsHitTesting(false)
                .accessibilityIdentifier("month.emptyPeriod")
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Scrollable month timeline, starting \(CalendarEventDateFormatting.monthAndYear(grid.monthStart, calendar: appState.calendar))"
        )
    }

    private func weekdayHeader(grid: MonthGrid) -> some View {
        HStack(spacing: 0) {
            ForEach(grid.weekdayOrdinals, id: \.self) { ordinal in
                Text(weekdaySymbol(for: ordinal))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: weekdayHeaderHeight
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(height: weekdayHeaderHeight)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BriefCalTheme.subtleDivider)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private func monthWeek(
        _ week: [MonthGridDay],
        weekIndex: Int,
        layout: MonthEventLayout,
        height: CGFloat,
        maximumVisibleLanes: Int
    ) -> some View {
        GeometryReader { geometry in
            let dayWidth = geometry.size.width / 7

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        dayCell(
                            day,
                            eventCount: layout.events(on: day.date).count
                        )
                        .frame(width: dayWidth, height: height)
                    }
                }

                ForEach(
                    layout.segments(inWeek: weekIndex).filter {
                        $0.laneIndex < maximumVisibleLanes
                    }
                ) { segment in
                    let chipWidth = max(
                        22,
                        dayWidth * CGFloat(segment.weekdaySpan.count) - 6
                    )
                    eventButton(
                        segment,
                        availableWidth: chipWidth
                    )
                        .frame(
                            width: chipWidth,
                            height: eventRowHeight - 2
                        )
                        .offset(
                            x: dayWidth
                                * CGFloat(segment.startWeekdayIndex) + 3,
                            y: dateHeaderHeight
                                + CGFloat(segment.laneIndex) * eventRowHeight
                                + 1
                        )
                }

                ForEach(week) { day in
                    let hiddenEvents = layout.hiddenEvents(
                        on: day.date,
                        maximumVisibleLanes: maximumVisibleLanes
                    )
                    if !hiddenEvents.isEmpty {
                        moreButton(
                            date: day.date,
                            events: hiddenEvents
                        )
                        .frame(
                            width: max(20, dayWidth - 8),
                            height: overflowRowHeight
                        )
                        .offset(
                            x: dayWidth * CGFloat(day.weekdayIndex) + 4,
                            y: max(
                                dateHeaderHeight,
                                height - overflowRowHeight - 1
                            )
                        )
                    }
                }

                ForEach(week.filter {
                    MonthTimeline.isMonthStart(
                        $0.date,
                        calendar: appState.calendar
                    )
                }) { day in
                    Rectangle()
                        .fill(BriefCalTheme.accent.opacity(0.58))
                        .frame(width: 3, height: height)
                        .offset(
                            x: dayWidth * CGFloat(day.weekdayIndex)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .dropDestination(for: String.self) { references, location in
                guard let reference = references.first(where: {
                    $0.hasPrefix("briefcal-event:")
                }), dayWidth > 0 else {
                    return false
                }
                let dayIndex = min(
                    max(Int(location.x / dayWidth), 0),
                    week.count - 1
                )
                guard week.indices.contains(dayIndex) else { return false }
                Task {
                    _ = await appState.beginMovingCalendarEvent(
                        eventReference: reference,
                        to: .day(week[dayIndex].date)
                    )
                }
                return true
            } isTargeted: { _ in }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BriefCalTheme.subtleDivider)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private func dayCell(
        _ day: MonthGridDay,
        eventCount: Int
    ) -> some View {
        let dayID = MonthGrid.dayIdentifier(
            for: day.date,
            calendar: appState.calendar
        )
        let isFocused = appState.calendar.isDate(
            day.date,
            inSameDayAs: appState.focusedDate
        )
        let isToday = appState.calendar.isDate(
            day.date,
            inSameDayAs: appState.taskReferenceDate
        )
        let isKeyboardFocused = keyboardFocusedDayID == dayID

        return Button {
            focusDate(day.date)
        } label: {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(dayBackground(
                        for: day.date,
                        isFocused: isFocused
                    ))

                if MonthTimeline.isMonthStart(
                    day.date,
                    calendar: appState.calendar
                ) {
                    Text(CalendarEventDateFormatting.monthName(
                        day.date,
                        calendar: appState.calendar
                    ))
                    .font(.system(
                        size: 24,
                        weight: .bold,
                        design: .rounded
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(BriefCalTheme.accent.opacity(0.14))
                    .padding(.horizontal, 7)
                    .padding(.bottom, 4)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottomLeading
                    )
                    .accessibilityHidden(true)
                }

                Text(
                    CalendarEventDateFormatting.dayNumber(
                        day.date,
                        calendar: appState.calendar
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    isFocused
                        ? Color.white
                        : day.isInDisplayedMonth
                            ? Color.primary
                            : Color.secondary
                )
                .frame(width: 22, height: 22)
                .background {
                    if isFocused {
                        Circle().fill(BriefCalTheme.accent)
                    }
                }
                .overlay {
                    if isToday {
                        Circle()
                            .stroke(
                                isFocused ? Color.white : BriefCalTheme.accent,
                                lineWidth: 1.25
                            )
                            .padding(1)
                    }
                }
                .padding(.top, 2)
                .padding(.trailing, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(day.isInDisplayedMonth ? 1 : 0.66)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BriefCalTheme.subtleDivider)
                .frame(width: 1)
                .accessibilityHidden(true)
        }
        .overlay {
            if isKeyboardFocused {
                Rectangle()
                    .stroke(BriefCalTheme.accent, lineWidth: 2)
                    .padding(1)
                    .allowsHitTesting(false)
            }
        }
        .focused($keyboardFocusedDayID, equals: dayID)
        .onMoveCommand { direction in
            moveKeyboardFocus(from: day.date, direction: direction)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                openDay(day.date)
            }
        )
        .contextMenu {
            Button("Show in Day") {
                openDay(day.date)
            }
            Button("New Event on This Date") {
                focusDate(day.date)
                appState.beginCreatingEvent()
            }
        }
        .help(
            "\(CalendarEventDateFormatting.longDate(day.date, calendar: appState.calendar)) · "
                + (eventCount == 1 ? "1 event" : "\(eventCount) events")
        )
        .accessibilityLabel(
            "\(CalendarEventDateFormatting.weekday(day.date, calendar: appState.calendar)), "
                + CalendarEventDateFormatting.longDate(
                    day.date,
                    calendar: appState.calendar
                )
        )
        .accessibilityValue(dayAccessibilityValue(
            day: day,
            isFocused: isFocused,
            isToday: isToday,
            eventCount: eventCount
        ))
        .accessibilityHint(
            "Select this date. Double-click or use Show in Day to open Day view."
        )
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityIdentifier("month.day.\(dayID)")
    }

    private func eventButton(
        _ segment: MonthEventSegment,
        availableWidth: CGFloat
    ) -> some View {
        Button {
            selectEvent(segment.event)
        } label: {
            MonthEventChip(
                segment: segment,
                availableWidth: availableWidth,
                isSelected: appState.selectedEventID == segment.event.id,
                restriction: appState.calendarWriteRestriction(
                    for: segment.event
                ),
                hasDuplicateCandidates: appState.hasDuplicateCandidates(
                    for: segment.event
                ),
                calendar: appState.calendar
            )
        }
        .buttonStyle(.plain)
        .help(eventAccessibilityText(segment))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(eventAccessibilityText(segment))
        .accessibilityValue(
            appState.selectedEventID == segment.event.id ? "Selected" : ""
        )
        .accessibilityAddTraits(
            appState.selectedEventID == segment.event.id ? .isSelected : []
        )
        .accessibilityIdentifier(
            "month.event.\(segment.event.id).week.\(segment.weekIndex)"
        )
        .monthCalendarEventDragSource(
            event: segment.event,
            enabled: appState.calendarWriteRestriction(
                for: segment.event
            ) == nil
        )
        .calendarEventContextMenu(
            appState: appState,
            event: segment.event
        )
    }

    private func moreButton(
        date: Date,
        events: [DisplayEvent]
    ) -> some View {
        Button("+\(events.count) more") {
            overflowSelection = MonthOverflowSelection(
                date: date,
                events: events
            )
        }
        .buttonStyle(.plain)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color(nsColor: .linkColor))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help("Show all events on \(CalendarEventDateFormatting.longDate(date, calendar: appState.calendar))")
        .accessibilityLabel(
            "\(events.count) more events on "
                + CalendarEventDateFormatting.longDate(
                    date,
                    calendar: appState.calendar
                )
        )
        .accessibilityIdentifier(
            "month.more.\(MonthGrid.dayIdentifier(for: date, calendar: appState.calendar))"
        )
    }

    private func visibleLaneCount(for weekHeight: CGFloat) -> Int {
        max(
            1,
            Int(
                max(
                    0,
                    weekHeight - dateHeaderHeight - overflowRowHeight - 3
                ) / eventRowHeight
            )
        )
    }

    private func dayBackground(
        for date: Date,
        isFocused: Bool
    ) -> Color {
        if isFocused {
            return BriefCalTheme.accentSoft.opacity(0.52)
        }
        if appState.calendar.isDateInWeekend(date) {
            return Color.secondary.opacity(0.035)
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    private func weekdaySymbol(for ordinal: Int) -> String {
        let symbols = appState.calendar.shortStandaloneWeekdaySymbols
        let index = ordinal - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private var anchorWeekIdentifier: String {
        MonthTimeline.identifier(
            for: MonthTimeline.anchorWeekStart(
                containing: appState.focusedDate,
                calendar: appState.calendar
            ),
            calendar: appState.calendar
        )
    }

    private func weekIdentifier(_ week: [MonthGridDay]) -> String {
        guard let start = week.first?.date else { return "empty-week" }
        return MonthTimeline.identifier(
            for: start,
            calendar: appState.calendar
        )
    }

    private func extendTimelineIfNeeded(after visibleWeekIndex: Int) {
        guard visibleWeekIndex == weekCount - 1,
              !isExtendingTimeline else {
            return
        }
        isExtendingTimeline = true
        weekCount += MonthTimeline.pageWeekCount
        let requestedGrid = MonthTimeline.grid(
            containing: appState.focusedDate,
            weekCount: weekCount,
            calendar: appState.calendar
        )
        Task {
            _ = await appState.ensureCalendarDataCovers(
                requestedGrid.visibleInterval
            )
            isExtendingTimeline = false
        }
    }

    private func focusDate(_ date: Date) {
        appState.selectMiniMonthDate(date)
    }

    private func openDay(_ date: Date) {
        appState.selectMiniMonthDate(date)
        appState.select(.day)
    }

    private func selectEvent(_ event: DisplayEvent) {
        appState.userSelectEvent(event.id)
    }

    private func moveKeyboardFocus(
        from date: Date,
        direction: MoveCommandDirection
    ) {
        let offset: Int
        switch direction {
        case .left: offset = -1
        case .right: offset = 1
        case .up: offset = -7
        case .down: offset = 7
        @unknown default: return
        }
        guard let target = appState.calendar.date(
            byAdding: .day,
            value: offset,
            to: date
        ) else { return }
        focusDate(target)
        keyboardFocusedDayID = MonthGrid.dayIdentifier(
            for: target,
            calendar: appState.calendar
        )
    }

    private func dayAccessibilityValue(
        day: MonthGridDay,
        isFocused: Bool,
        isToday: Bool,
        eventCount: Int
    ) -> String {
        var values: [String] = []
        if isFocused { values.append("Focused date") }
        if isToday { values.append("Today") }
        if MonthTimeline.isMonthStart(
            day.date,
            calendar: appState.calendar
        ) {
            values.append(
                "Start of " + CalendarEventDateFormatting.monthName(
                    day.date,
                    calendar: appState.calendar
                )
            )
        }
        if !day.isInDisplayedMonth { values.append("Adjacent month") }
        values.append(eventCount == 1 ? "1 event" : "\(eventCount) events")
        return values.joined(separator: ", ")
    }

    private func eventAccessibilityText(
        _ segment: MonthEventSegment
    ) -> String {
        let event = segment.event
        var parts = [
            event.title,
            CalendarEventDateFormatting.agendaText(
                for: event,
                calendar: appState.calendar
            ),
            "\(appState.calendarRole(for: event).title) role",
            event.calendarTitle,
            event.sourceTitle,
            event.accountType.title
        ]
        if event.isCancelled { parts.append("cancelled") }
        if event.isDeclinedByCurrentUser { parts.append("declined") }
        if event.availability == .tentative { parts.append("tentative") }
        if event.availability == .free { parts.append("free") }
        if event.isRecurring { parts.append("recurring") }
        if let restriction = appState.calendarWriteRestriction(for: event) {
            parts.append("\(restriction.title), \(restriction.message)")
        } else {
            parts.append("original event editable")
        }
        if appState.hasDuplicateCandidates(for: event) {
            parts.append("possible duplicate calendar event")
        }
        if segment.continuesBefore {
            parts.append("continues from the previous week")
        }
        if segment.continuesAfter {
            parts.append("continues into the next week")
        }
        return parts.joined(separator: ", ")
    }
}

private struct MonthOverflowSelection: Identifiable {
    let date: Date
    let events: [DisplayEvent]

    var id: Date { date }
}

private struct MonthEventChip: View {
    let segment: MonthEventSegment
    let availableWidth: CGFloat
    let isSelected: Bool
    let restriction: CalendarWriteRestriction?
    let hasDuplicateCandidates: Bool
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 3) {
            if segment.continuesBefore {
                Image(systemName: "chevron.left")
                    .font(.system(size: 6, weight: .bold))
                    .accessibilityHidden(true)
            }

            RoundedRectangle(cornerRadius: 1)
                .fill(calendarColor)
                .frame(width: 3)

            if showsTime {
                Text(CalendarEventDateFormatting.shortTime(
                    segment.startDate,
                    calendar: calendar
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Text(segment.event.title)
                .font(.caption2.weight(.semibold))
                .strikethrough(
                    segment.event.isCancelled
                        || segment.event.isDeclinedByCurrentUser
                )
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 0)
            if showsStatusIcons {
                statusIcons
            }

            if segment.continuesAfter {
                Image(systemName: "chevron.right")
                    .font(.system(size: 6, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(calendarColor.opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isSelected ? BriefCalTheme.accent : borderColor,
                    style: StrokeStyle(
                        lineWidth: isSelected ? 2 : 1,
                        dash: isTentativeOrFree ? [3, 2] : []
                    )
                )
        }
        .opacity(
            segment.event.isCancelled
                || segment.event.isDeclinedByCurrentUser ? 0.58 : 1
        )
        .contentShape(RoundedRectangle(cornerRadius: 4))
    }

    private var showsTime: Bool {
        !segment.event.isAllDay
            && !CalendarEventDateFormatting.spansMultipleDates(
                segment.event,
                calendar: calendar
            )
            && availableWidth >= 132
    }

    private var showsStatusIcons: Bool {
        availableWidth >= 96
    }

    private var calendarColor: Color {
        BriefCalTheme.calendarColor(
            segment.event.calendarColor,
            accountType: segment.event.accountType
        )
    }

    private var isTentativeOrFree: Bool {
        segment.event.availability == .tentative
            || segment.event.availability == .free
    }

    private var backgroundOpacity: Double {
        segment.event.availability == .free ? 0.08 : 0.17
    }

    private var borderColor: Color {
        isTentativeOrFree
            ? calendarColor.opacity(0.75)
            : BriefCalTheme.subtleDivider
    }

    @ViewBuilder
    private var statusIcons: some View {
        if segment.event.isCancelled {
            Image(systemName: "xmark.circle")
                .font(.system(size: 7))
                .accessibilityHidden(true)
        } else if segment.event.isDeclinedByCurrentUser {
            Image(systemName: "hand.raised")
                .font(.system(size: 7))
                .accessibilityHidden(true)
        } else if segment.event.availability == .tentative {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 7))
                .accessibilityHidden(true)
        }
        if segment.event.isRecurring {
            Image(systemName: "repeat")
                .font(.system(size: 7))
                .accessibilityHidden(true)
        }
        if hasDuplicateCandidates {
            Image(systemName: "square.on.square")
                .font(.system(size: 7))
                .accessibilityHidden(true)
        }
        if restriction != nil {
            Image(systemName: "lock")
                .font(.system(size: 7))
                .accessibilityHidden(true)
        }
    }
}

private struct MonthDayOverflowView: View {
    @ObservedObject var appState: AppState
    let date: Date
    let events: [DisplayEvent]
    let openDay: () -> Void
    let selectEvent: (DisplayEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CalendarEventDateFormatting.longDate(
                        date,
                        calendar: appState.calendar
                    ))
                    .font(.headline)
                    Text(events.count == 1 ? "1 event" : "\(events.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Day", action: openDay)
                    .controlSize(.small)
                    .accessibilityIdentifier("month.overflow.openDay")
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(events) { event in
                        Button {
                            selectEvent(event)
                        } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(BriefCalTheme.calendarColor(
                                        event.calendarColor,
                                        accountType: event.accountType
                                    ))
                                    .frame(width: 3, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.callout.weight(.medium))
                                        .strikethrough(
                                            event.isCancelled
                                                || event.isDeclinedByCurrentUser
                                        )
                                        .lineLimit(2)
                                    Text(eventSummary(event))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if event.isRecurring {
                                    Image(systemName: "repeat")
                                        .accessibilityHidden(true)
                                }
                                if appState.calendarWriteRestriction(for: event) != nil {
                                    Image(systemName: "lock")
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(event.title), "
                                + CalendarEventDateFormatting.agendaText(
                                    for: event,
                                    calendar: appState.calendar
                                )
                                + ", \(event.calendarTitle)"
                        )
                        .accessibilityIdentifier("month.overflow.event.\(event.id)")
                        .calendarEventContextMenu(
                            appState: appState,
                            event: event
                        )

                        Divider()
                            .padding(.leading, 23)
                    }
                }
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 340)
        .accessibilityIdentifier("month.overflow")
    }

    private func eventSummary(_ event: DisplayEvent) -> String {
        let time = CalendarEventDateFormatting.agendaText(
            for: event,
            calendar: appState.calendar
        )
        return "\(time) · \(event.calendarTitle)"
    }
}

private struct MonthCalendarEventDragSource: ViewModifier {
    let event: DisplayEvent
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.draggable(
                AppState.calendarEventDragReference(eventID: event.id)
            )
        } else {
            content
        }
    }
}

private extension View {
    func monthCalendarEventDragSource(
        event: DisplayEvent,
        enabled: Bool
    ) -> some View {
        modifier(MonthCalendarEventDragSource(
            event: event,
            enabled: enabled
        ))
    }
}
