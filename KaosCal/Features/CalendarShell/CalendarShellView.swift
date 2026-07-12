import AppKit
import SwiftUI

struct CalendarShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if case let .failed(message) = appState.localContextStoreState {
                LocalContextStoreFailureView(message: message)
            } else {
                calendarShell
            }
        }
    }

    private var calendarShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } content: {
            WorkspaceView(appState: appState)
                .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        } detail: {
            EventInspectorView(appState: appState)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(KaosCalTheme.accent)
        .sheet(item: eventEditorBinding) { session in
            EventEditorView(appState: appState, session: session)
        }
        .sheet(item: linkedEventRecoveryBinding) { session in
            LinkedEventRecoveryView(
                appState: appState,
                initialSession: session
            )
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if appState.pendingRelinkContextID != nil {
                RelinkSelectionBanner(appState: appState)
            }
        }
        .alert(
            "Calendar event change unavailable",
            isPresented: eventEditorAlertBinding
        ) {
            Button("OK") {
                appState.clearEventEditorError()
            }
        } message: {
            Text(appState.eventEditorError ?? "Unknown calendar event error")
        }
        .toolbar {
            ToolbarItem {
                Button {
                    appState.beginCreatingEvent()
                } label: {
                    Label("New event", systemImage: "plus")
                }
                .disabled(
                    !appState.calendarAuthorizationState.canReadEvents
                        || appState.eventEditorSession != nil
                        || appState.eventEditorOperationState != .idle
                )
                .accessibilityIdentifier("toolbar.newEvent")
            }

            ToolbarItemGroup {
                if appState.selectedSection != .tasks {
                    Button {
                        appState.moveFocusedPeriod(direction: -1)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Previous period")
                    .accessibilityIdentifier("toolbar.previous")

                    Button("Today") {
                        appState.goToToday()
                    }
                    .accessibilityIdentifier("toolbar.today")

                    Button {
                        appState.moveFocusedPeriod(direction: 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .accessibilityLabel("Next period")
                    .accessibilityIdentifier("toolbar.next")
                }
            }

            ToolbarItem {
                Text(
                    appState.selectedSection == .tasks
                        ? "Task Center"
                        : appState.focusedPeriodTitle
                )
                    .font(.headline)
                    .monospacedDigit()
            }

            ToolbarItem {
                if appState.selectedSection == .tasks {
                    Button {
                        appState.refreshTaskCenter()
                    } label: {
                        Label("Reload tasks", systemImage: "arrow.clockwise")
                    }
                } else {
                    Button {
                        Task {
                            await appState.refreshCalendarData()
                        }
                    } label: {
                        Label("Reload events", systemImage: "arrow.clockwise")
                    }
                    .disabled(!appState.calendarAuthorizationState.canReadEvents)
                }
            }
        }
        .task {
            await appState.loadCalendarStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await appState.loadCalendarStatus()
                    appState.refreshTaskCenter()
                }
            } else {
                appState.flushPendingEventNotes()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification
            )
        ) { _ in
            appState.flushPendingEventNotes()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSCalendarDayChanged
            )
        ) { _ in
            appState.refreshTaskCenter()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )
        ) { _ in
            appState.refreshTaskCenter()
        }
    }

    private var eventEditorBinding: Binding<CalendarEventEditorSession?> {
        Binding(
            get: { appState.eventEditorSession },
            set: { session in
                if session == nil {
                    appState.cancelEventEditor()
                }
            }
        )
    }

    private var eventEditorAlertBinding: Binding<Bool> {
        Binding(
            get: {
                appState.eventEditorSession == nil
                    && appState.eventEditorError != nil
            },
            set: { presented in
                if !presented {
                    appState.clearEventEditorError()
                }
            }
        )
    }

    private var linkedEventRecoveryBinding: Binding<LinkedEventRecoverySession?> {
        Binding(
            get: { appState.linkedEventRecoverySession },
            set: { session in
                if session == nil {
                    appState.dismissLinkedEventRecovery()
                }
            }
        )
    }
}

private struct RelinkSelectionBanner: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Label(
                "Relink Event Brief · Select the exact replacement event",
                systemImage: "link.badge.plus"
            )
                .font(.callout.weight(.semibold))
            Text("Use Day, Week, Agenda, or the mini month to find it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                appState.cancelRelinkSelection()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(KaosCalTheme.accentSoft)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier("relink.selectionBanner")
    }
}

private struct LinkedEventRecoveryView: View {
    @ObservedObject var appState: AppState
    let initialSession: LinkedEventRecoverySession

    @State private var confirmsLocalDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Linked Event Recovery", systemImage: "link.badge.plus")
                    .font(.title2.weight(.semibold))

                briefSummary
                Divider()
                stageContent

                if let error = appState.localOperationError {
                    LocalOperationErrorView(
                        message: error,
                        dismiss: appState.clearLocalOperationError
                    )
                }
            }
            .padding(22)
        }
        .frame(width: 520)
        .frame(maxHeight: 680)
        .alert("Delete this local Event Brief?", isPresented: $confirmsLocalDeletion) {
            Button("Delete Local Brief", role: .destructive) {
                _ = appState.deleteRecoverableLocalBrief()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(localDeletionMessage)
        }
        .accessibilityIdentifier("linkedEventRecovery.content")
    }

    private var session: LinkedEventRecoverySession {
        appState.linkedEventRecoverySession ?? initialSession
    }

    private var briefSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(session.brief.context.titleSnapshot)
                .font(.headline)
            Text(
                CalendarEventDateFormatting.abbreviatedDateTime(
                    session.brief.link.startSnapshot,
                    calendar: appState.calendar
                )
                    + " · " + session.brief.link.calendarTitleSnapshot
                    + " · " + session.brief.link.sourceTitle
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label(
                    session.brief.context.notes.isEmpty
                        ? "No local notes"
                        : "\(session.brief.context.notes.count) note characters",
                    systemImage: "note.text"
                )
                Label(
                    "\(session.brief.tasks.count) local tasks",
                    systemImage: "checklist"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !session.brief.context.notes.isEmpty {
                Divider()
                Text("Local notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(session.brief.context.notes)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var stageContent: some View {
        switch session.stage {
        case .firstMissing:
            VStack(alignment: .leading, spacing: 12) {
                Label("Original event not found yet", systemImage: "questionmark.circle")
                    .font(.headline)
                Text(
                    "It may have moved or still be syncing. This first dedicated check only marked the link as missing; your local notes and tasks were kept."
                )
                .foregroundStyle(.secondary)
                actionRow {
                    Button("Not Now") {
                        appState.dismissLinkedEventRecovery()
                    }
                    Button("Choose Event to Relink") {
                        appState.beginSelectingRelinkCandidate()
                    }
                    Button("Check Again") {
                        Task {
                            await appState.recheckMissingLinkedEvent()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isCheckingLinkedEvent)
                }
            }
        case .orphanConfirmation:
            VStack(alignment: .leading, spacing: 12) {
                Label("Still not found", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(
                    "A separate check also found no strong occurrence match. Checking did not change your calendar. Choose what to do with the local Event Brief."
                )
                .foregroundStyle(.secondary)
                recoveryActions(includeKeep: true)
            }
        case .orphaned:
            VStack(alignment: .leading, spacing: 12) {
                Label("Kept as a local orphan", systemImage: "archivebox")
                    .font(.headline)
                Text(
                    "The Brief is detached from automatic calendar matching. Its notes and tasks remain on this Mac until you relink or delete it."
                )
                .foregroundStyle(.secondary)
                recoveryActions(includeKeep: false)
            }
        case .deletedOriginal:
            VStack(alignment: .leading, spacing: 12) {
                Label("Original deleted · Local Brief kept", systemImage: "calendar.badge.minus")
                    .font(.headline)
                Text(
                    "KaosCal removed the original calendar event after your final confirmation. There is no Undo. Local notes and tasks remain on this Mac until you relink or delete this Brief."
                )
                .foregroundStyle(.secondary)
                recoveryActions(includeKeep: false)
            }
        case .manualRelink:
            VStack(alignment: .leading, spacing: 12) {
                Label("Choose the exact event manually", systemImage: "hand.tap")
                    .font(.headline)
                Text(
                    "KaosCal could not prove the saved link safely, so it made no missing or orphan decision. Select the exact replacement occurrence yourself."
                )
                .foregroundStyle(.secondary)
                actionRow {
                    Button("Cancel") {
                        appState.dismissLinkedEventRecovery()
                    }
                    Button("Choose Event") {
                        appState.beginSelectingRelinkCandidate()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case let .candidates(matches):
            VStack(alignment: .leading, spacing: 12) {
                Label("Choose a matching event", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Text(
                    "KaosCal found possible matches but will never select a weak or ambiguous candidate automatically."
                )
                .foregroundStyle(.secondary)
                ForEach(matches) { match in
                    Button {
                        appState.chooseLinkedEventCandidate(match.event)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(match.event.title)
                                    .font(.body.weight(.medium))
                                Text(
                                    CalendarEventDateFormatting.abbreviatedDateTime(
                                        match.event.startDate,
                                        calendar: appState.calendar
                                    ) + " · " + match.event.calendarTitle
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if match.isCancelled {
                                    Label("Calendar reports cancelled", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                actionRow {
                    Button("Cancel") {
                        appState.dismissLinkedEventRecovery()
                    }
                    Button("Choose Another Event") {
                        appState.beginSelectingRelinkCandidate()
                    }
                }
            }
        case let .confirmRelink(event):
            VStack(alignment: .leading, spacing: 12) {
                Label("Confirm relink", systemImage: "link")
                    .font(.headline)
                Text(
                    "Attach this local Brief to “\(event.title)” in \(event.calendarTitle)? Notes and tasks stay local; the calendar event is not modified."
                )
                .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        CalendarEventDateFormatting.inspectorText(
                            for: event,
                            calendar: appState.calendar
                        ),
                        systemImage: "clock"
                    )
                    Label(
                        "\(event.sourceTitle) · \(event.calendarTitle)",
                        systemImage: "calendar"
                    )
                    if let timeZoneIdentifier = event.timeZoneIdentifier {
                        Label(timeZoneIdentifier, systemImage: "globe")
                    }
                    if event.isRecurring {
                        Label(
                            event.isDetached
                                ? "Detached recurring occurrence"
                                : "Recurring occurrence",
                            systemImage: "repeat"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                actionRow {
                    Button("Cancel") {
                        appState.dismissLinkedEventRecovery()
                    }
                    Button("Relink Brief") {
                        Task {
                            _ = await appState.confirmLinkedEventRelink()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isCheckingLinkedEvent)
                }
            }
        }
    }

    private func recoveryActions(includeKeep: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if includeKeep {
                Button("Keep as Orphan") {
                    _ = appState.keepLinkedEventAsOrphan()
                }
            }
            Button("Choose Event to Relink") {
                appState.beginSelectingRelinkCandidate()
            }
            Button("Delete Local Brief", role: .destructive) {
                confirmsLocalDeletion = true
            }
            Divider()
            Button("Cancel") {
                appState.dismissLinkedEventRecovery()
            }
        }
    }

    private func actionRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Spacer()
            content()
        }
    }

    private var localDeletionMessage: String {
        "This permanently deletes \(session.brief.tasks.count) local tasks and "
            + "\(session.brief.context.notes.count) note characters from this Mac. "
            + "The calendar event and Exchange data will not be deleted or changed."
    }
}

private struct LocalContextStoreFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(
                "Local data needs recovery",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        } description: {
            Text(
                "KaosCal stopped before loading or changing local data. "
                    + "The existing database was preserved. Quit the app, "
                    + "back up the KaosCal folder in Application Support, "
                    + "then review the error before retrying.\n\n\(message)"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct SidebarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                MiniMonthView(appState: appState)

                Text(appState.calendarAuthorizationState.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()

            List(selection: sectionSelection) {
                Section("Views") {
                    ForEach(WorkspaceSection.allCases) { section in
                        Label(section.title, systemImage: section.symbolName)
                            .tag(section)
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                }

                Section("Calendar Set") {
                    Picker("Calendar Set", selection: calendarSetSelection) {
                        ForEach(CalendarSetFilter.allCases) { filter in
                            Label(filter.title, systemImage: filter.symbolName)
                                .tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("sidebar.calendarSet")
                    .help("Show events from calendars with the selected KaosCal role")
                }

                Section("Calendars") {
                    if appState.calendarSources.isEmpty {
                        Label("No calendars loaded", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.calendarSources) { source in
                            let role = appState.calendarRole(for: source)
                            let restriction = calendarRestriction(for: source)

                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(KaosCalTheme.calendarColor(
                                        source.color,
                                        accountType: source.accountType
                                    ))
                                    .frame(width: 3, height: 24)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(source.title)
                                        .lineLimit(1)
                                    Text(
                                        "\(role.title) · \(sourceAccountText(source)) · "
                                            + (restriction == nil ? "Editable" : "Read-only")
                                    )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .help(calendarMetadataHelp(
                                            source: source,
                                            role: role,
                                            restriction: restriction
                                        ))
                                }

                                Spacer(minLength: 4)

                                if let restriction {
                                    Image(systemName: "lock")
                                        .foregroundStyle(.secondary)
                                        .help(restriction.message)
                                        .accessibilityLabel(
                                            "\(restriction.title). \(restriction.message)"
                                        )
                                }

                                Menu {
                                    ForEach(CalendarRole.allCases) { option in
                                        Button {
                                            _ = appState.setCalendarRole(
                                                option,
                                                for: source
                                            )
                                        } label: {
                                            if option == role {
                                                Label(
                                                    option.title,
                                                    systemImage: "checkmark"
                                                )
                                            } else {
                                                Label(
                                                    option.title,
                                                    systemImage: option.symbolName
                                                )
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .accessibilityLabel(
                                    "Change role for \(source.title) calendar"
                                )
                                .accessibilityHint(
                                    "Changes KaosCal grouping only. The Calendar.app calendar is not renamed."
                                )
                                .accessibilityIdentifier(
                                    "sidebar.calendar.\(source.id).role"
                                )
                            }
                            .accessibilityIdentifier(
                                "sidebar.calendar.\(source.id)"
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var sectionSelection: Binding<WorkspaceSection?> {
        Binding(
            get: { appState.selectedSection },
            set: { section in
                guard let section else {
                    appState.selectedSection = nil
                    return
                }
                appState.select(section)
            }
        )
    }

    private var calendarSetSelection: Binding<CalendarSetFilter> {
        Binding(
            get: { appState.selectedCalendarSet },
            set: { appState.selectCalendarSet($0) }
        )
    }

    private func calendarRestriction(
        for source: CalendarSource
    ) -> CalendarWriteRestriction? {
        CalendarWriteRestriction.restriction(for: source)
    }

    private func sourceAccountText(_ source: CalendarSource) -> String {
        if source.sourceTitle.compare(
            source.accountType.title,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame {
            return source.accountType.title
        }
        return "\(source.sourceTitle) · \(source.accountType.title)"
    }

    private func calendarMetadataHelp(
        source: CalendarSource,
        role: CalendarRole,
        restriction: CalendarWriteRestriction?
    ) -> String {
        let permission = restriction?.message ?? "Original events are editable."
        return "\(role.title) role · \(source.title) · \(source.sourceTitle) · "
            + "\(source.accountType.title). \(permission)"
    }
}

struct MiniMonthDay: Identifiable, Equatable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

struct MiniMonthGrid: Equatable {
    let monthStart: Date
    let weekdayOrdinals: [Int]
    let days: [MiniMonthDay]

    init(containing date: Date, calendar: Calendar) {
        let monthStart = Self.monthStart(containing: date, calendar: calendar)
        self.monthStart = monthStart

        let firstSymbolIndex = Self.normalizedWeekdayIndex(
            calendar.firstWeekday
        )
        weekdayOrdinals = (0..<7).map {
            ((firstSymbolIndex + $0) % 7) + 1
        }

        let monthStartWeekday = calendar.component(
            .weekday,
            from: monthStart
        )
        let leadingDayCount = (
            monthStartWeekday - calendar.firstWeekday + 7
        ) % 7
        let gridStart = calendar.date(
            byAdding: .day,
            value: -leadingDayCount,
            to: monthStart
        ) ?? monthStart

        days = (0..<42).map { offset in
            let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: gridStart
            ) ?? gridStart
            return MiniMonthDay(
                date: day,
                isInDisplayedMonth: calendar.isDate(
                    day,
                    equalTo: monthStart,
                    toGranularity: .month
                )
            )
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

    private static func normalizedWeekdayIndex(_ weekday: Int) -> Int {
        ((weekday - 1) % 7 + 7) % 7
    }
}

struct MiniMonthBrowseState: Equatable {
    private(set) var displayedMonthStart: Date

    init(focusedDate: Date, calendar: Calendar) {
        displayedMonthStart = MiniMonthGrid.monthStart(
            containing: focusedDate,
            calendar: calendar
        )
    }

    mutating func shift(by value: Int, calendar: Calendar) {
        displayedMonthStart = MiniMonthGrid.shiftedMonthStart(
            from: displayedMonthStart,
            by: value,
            calendar: calendar
        )
    }

    mutating func synchronize(
        to focusedDate: Date,
        calendar: Calendar
    ) {
        displayedMonthStart = MiniMonthGrid.monthStart(
            containing: focusedDate,
            calendar: calendar
        )
    }
}

struct MiniMonthView: View {
    @ObservedObject var appState: AppState
    @State private var browseState: MiniMonthBrowseState

    init(appState: AppState) {
        self.appState = appState
        _browseState = State(
            initialValue: MiniMonthBrowseState(
                focusedDate: appState.focusedDate,
                calendar: appState.calendar
            )
        )
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                monthButton(
                    title: "Previous month",
                    systemImage: "chevron.left",
                    direction: -1
                )

                Spacer(minLength: 2)

                Text(
                    CalendarEventDateFormatting.monthAndYear(
                        grid.monthStart,
                        calendar: appState.calendar
                    )
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 2)

                monthButton(
                    title: "Next month",
                    systemImage: "chevron.right",
                    direction: 1
                )
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(
                    grid.weekdayOrdinals,
                    id: \.self
                ) { weekdayOrdinal in
                    Text(weekdaySymbol(for: weekdayOrdinal))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 16)
                        .accessibilityHidden(true)
                }

                ForEach(grid.days) { day in
                    dayButton(day)
                }
            }
            .focusSection()
        }
        .onReceive(appState.$focusedDate) { focusedDate in
            browseState.synchronize(
                to: focusedDate,
                calendar: appState.calendar
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mini month")
        .accessibilityIdentifier("sidebar.miniMonth")
    }

    private var grid: MiniMonthGrid {
        MiniMonthGrid(
            containing: browseState.displayedMonthStart,
            calendar: appState.calendar
        )
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 20), spacing: 2),
            count: 7
        )
    }

    private func monthButton(
        title: String,
        systemImage: String,
        direction: Int
    ) -> some View {
        Button {
            browseState.shift(
                by: direction,
                calendar: appState.calendar
            )
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(
            direction < 0
                ? "miniMonth.previousMonth"
                : "miniMonth.nextMonth"
        )
    }

    private func dayButton(_ day: MiniMonthDay) -> some View {
        let isFocused = appState.calendar.isDate(
            day.date,
            inSameDayAs: appState.focusedDate
        )
        let isToday = appState.calendar.isDate(
            day.date,
            inSameDayAs: appState.taskReferenceDate
        )

        return Button {
            appState.selectMiniMonthDate(day.date)
        } label: {
            ZStack {
                if isFocused {
                    Circle()
                        .fill(KaosCalTheme.accent)
                }

                if isToday {
                    Circle()
                        .stroke(
                            isFocused ? Color.white : KaosCalTheme.accent,
                            lineWidth: 1.25
                        )
                        .padding(1)
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
            }
            .frame(maxWidth: .infinity, minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(day.isInDisplayedMonth ? 1 : 0.62)
        .accessibilityLabel(
            "\(CalendarEventDateFormatting.weekday(day.date, calendar: appState.calendar)), "
                + CalendarEventDateFormatting.longDate(
                    day.date,
                    calendar: appState.calendar
                )
        )
        .accessibilityValue(
            accessibilityValue(
                day: day,
                isFocused: isFocused,
                isToday: isToday
            )
        )
        .accessibilityHint(dayAccessibilityHint)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityIdentifier(
            "miniMonth.day.\(MiniMonthGrid.dayIdentifier(for: day.date, calendar: appState.calendar))"
        )
    }

    private var dayAccessibilityHint: String {
        if appState.selectedSection == .tasks
            || appState.selectedSection == nil {
            return "Show Day view for this date"
        }
        return "Show this date in \((appState.selectedSection ?? .week).title)"
    }

    private func weekdaySymbol(for weekdayOrdinal: Int) -> String {
        let symbols = appState.calendar.veryShortStandaloneWeekdaySymbols
        let index = weekdayOrdinal - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private func accessibilityValue(
        day: MiniMonthDay,
        isFocused: Bool,
        isToday: Bool
    ) -> String {
        var values: [String] = []
        if isFocused { values.append("Focused date") }
        if isToday { values.append("Today") }
        if !day.isInDisplayedMonth { values.append("Adjacent month") }
        return values.joined(separator: ", ")
    }
}

private struct WorkspaceView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: (appState.selectedSection ?? .week).symbolName)
                    .foregroundStyle(KaosCalTheme.accent)
                Text((appState.selectedSection ?? .week).title)
                    .font(.title3.weight(.semibold))
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            Divider()

            content
            .accessibilityIdentifier("calendar.content")
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if appState.selectedSection == .tasks {
            switch appState.taskCenterState {
            case .unavailable:
                Label("Local store unavailable", systemImage: "externaldrive.badge.xmark")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case let .loaded(items):
                Text("\(items.count) tasks")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("Couldn’t load tasks", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        } else {
            switch appState.calendarContentState {
            case .disconnected:
                Label("Not connected", systemImage: "link.badge.plus")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .empty:
                Text("No events")
                    .foregroundStyle(.secondary)
            case .loaded:
                Text("\(appState.visibleEvents.count) events")
                    .foregroundStyle(.secondary)
            case .permissionDenied:
                Label("Permission required", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.selectedSection == .tasks {
            TaskCenterView(appState: appState)
        } else {
            switch appState.calendarContentState {
            case .disconnected:
                CalendarAccessRequestView(appState: appState)
            case .loading:
                ProgressView("Loading calendars…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .permissionDenied:
                CalendarPermissionView(state: appState.calendarAuthorizationState)
            case let .failed(message):
                CalendarFailureView(message: message, appState: appState)
            case .empty, .loaded:
                loadedWorkspace
            }
        }
    }

    @ViewBuilder
    private var loadedWorkspace: some View {
        switch appState.selectedSection ?? .week {
        case .day, .week:
            CalendarTimelineView(appState: appState)
        case .agenda:
            AgendaView(appState: appState)
        case .tasks:
            TaskCenterView(appState: appState)
        }
    }
}

private struct CalendarAccessRequestView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ContentUnavailableView {
            Label("Connect your calendars", systemImage: "calendar.badge.plus")
        } description: {
            Text("KaosCal needs full calendar access to show Day, Week, and Agenda. Your Exchange password and MFA codes stay with macOS.")
        } actions: {
            Button("Allow Full Calendar Access") {
                Task {
                    await appState.requestCalendarAccess()
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("calendar.requestFullAccess")
        }
    }
}

private struct CalendarPermissionView: View {
    let state: CalendarAuthorizationState

    var body: some View {
        ContentUnavailableView {
            Label("Calendar permission required", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Open System Settings") {
                guard let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                ) else { return }
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var message: String {
        switch state {
        case .writeOnly:
            "KaosCal currently has write-only access. Full access is required to read your calendars."
        case .restricted:
            "Calendar access is restricted by this Mac or organization policy."
        default:
            "Allow full calendar access in System Settings, then return to KaosCal and refresh."
        }
    }
}

private struct CalendarFailureView: View {
    let message: String
    @ObservedObject var appState: AppState

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load calendars", systemImage: "exclamationmark.circle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await appState.loadCalendarStatus()
                }
            }
        }
    }
}

private struct AgendaView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.visibleEvents.isEmpty {
            ContentUnavailableView(
                "No events in this period",
                systemImage: "list.bullet.rectangle",
                description: Text(appState.focusedPeriodTitle)
            )
        } else {
            List(selection: eventSelection) {
                ForEach(appState.visibleEvents) { event in
                    AgendaEventRow(appState: appState, event: event)
                        .tag(event.id)
                        .accessibilityIdentifier("agenda.event.\(event.id)")
                }
            }
            .listStyle(.inset)
        }
    }

    private var eventSelection: Binding<String?> {
        Binding(
            get: { appState.selectedEventID },
            set: { appState.userSelectEvent($0) }
        )
    }
}

private struct AgendaEventRow: View {
    @ObservedObject var appState: AppState
    let event: DisplayEvent

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(KaosCalTheme.calendarColor(
                    event.calendarColor,
                    accountType: event.accountType
                ))
                .frame(width: 3, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(timeText)
                        .monospacedDigit()
                    Text("·")
                    Text(role.title)
                    Text("·")
                    Text(event.calendarTitle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if event.isRecurring {
                Image(systemName: "repeat")
                    .help("Recurring event")
                    .accessibilityHidden(true)
            }
            if hasDuplicateCandidates {
                Image(systemName: "square.on.square")
                    .help("Possible duplicate calendar event")
                    .accessibilityHidden(true)
            }
            if let restriction {
                Image(systemName: "lock")
                    .help(restriction.message)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var timeText: String {
        CalendarEventDateFormatting.agendaText(
            for: event,
            calendar: appState.calendar
        )
    }

    private var accessibilityText: String {
        var parts = [
            event.title,
            timeText,
            "\(role.title) role",
            event.calendarTitle,
            event.sourceTitle,
            event.accountType.title
        ]
        if let restriction {
            parts.append("\(restriction.title), \(restriction.message)")
        } else {
            parts.append("original event editable")
        }
        if event.isRecurring { parts.append("recurring") }
        if hasDuplicateCandidates {
            parts.append("possible duplicate calendar event")
        }
        return parts.joined(separator: ", ")
    }

    private var role: CalendarRole {
        appState.calendarRole(for: event)
    }

    private var restriction: CalendarWriteRestriction? {
        appState.calendarWriteRestriction(for: event)
    }

    private var hasDuplicateCandidates: Bool {
        appState.hasDuplicateCandidates(for: event)
    }
}

private struct EventInspectorView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let event = appState.selectedEvent {
                    selectedEventContent(event)
                } else {
                    emptyContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(.ultraThinMaterial)
        .accessibilityIdentifier(appState.selectedEvent == nil ? "inspector.empty" : "inspector.event")
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(KaosCalTheme.accent)
            Text("Select an event")
                .font(.title3.weight(.semibold))
            Text("Day, Week 또는 Agenda에서 일정을 선택하면 시간, 출처, 편집 가능 상태가 여기에 표시됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func selectedEventContent(_ event: DisplayEvent) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.title3.weight(.semibold))
                Text(
                    CalendarEventDateFormatting.inspectorText(
                        for: event,
                        calendar: appState.calendar
                    )
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                sourceIdentity(event)

                if let restriction = appState.calendarWriteRestriction(
                    for: event
                ) {
                    originalWriteRestriction(restriction)
                }
                if let timeZoneIdentifier = event.timeZoneIdentifier {
                    Label(timeZoneIdentifier, systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if event.isRecurring {
                    Label(
                        event.isDetached
                            ? "Detached recurring occurrence"
                            : "Recurring occurrence",
                        systemImage: "repeat"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                duplicateCandidateSection(for: event)

                if appState.calendarWriteRestriction(for: event) == nil {
                    Button("Edit Original Event") {
                        appState.beginEditingSelectedEvent()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("inspector.editOriginal")
                }

                if appState.canUndoLastEventMutation(for: event) {
                    Button {
                        Task {
                            await appState.undoLastEventMutation()
                        }
                    } label: {
                        Label("Undo Last Event Change", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.isUndoingEventMutation)
                    .accessibilityIdentifier("inspector.undoEventMutation")
                }

                if let message = appState.eventUndoError {
                    LocalOperationErrorView(
                        message: message,
                        dismiss: appState.clearEventUndoError
                    )
                }
            }

            Divider()
            EventBriefView(appState: appState, event: event)
                .id(event.id)
        }
    }

    private func sourceIdentity(_ event: DisplayEvent) -> some View {
        let role = appState.calendarRole(for: event)
        let restriction = appState.calendarWriteRestriction(for: event)

        return VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Label(role.title, systemImage: role.symbolName)
                    Text("·")
                    Text(event.accountType.title)
                    Text("·")
                    Text(restriction?.title ?? "Editable")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        "\(role.title) · \(event.accountType.title)",
                        systemImage: role.symbolName
                    )
                    Text(restriction?.title ?? "Editable")
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                KaosCalTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(role.title) role, \(event.accountType.title), "
                    + (restriction?.title ?? "original event editable")
            )
            .accessibilityIdentifier("inspector.sourceBadge")

            Text("\(event.calendarTitle) calendar · Source: \(event.sourceTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func originalWriteRestriction(
        _ restriction: CalendarWriteRestriction
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(restriction.title, systemImage: restriction.symbolName)
                .font(.caption.weight(.semibold))
            Text(restriction.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(restriction.title). \(restriction.message)")
        .accessibilityIdentifier("inspector.readOnlyReason")
    }

    @ViewBuilder
    private func duplicateCandidateSection(for event: DisplayEvent) -> some View {
        let candidates = appState.duplicateCandidates(for: event)
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Possible duplicate · \(candidates.count) similar "
                        + (candidates.count == 1 ? "event" : "events"),
                    systemImage: "square.on.square"
                )
                .font(.caption.weight(.semibold))

                Text(
                    "These are review candidates only. KaosCal will not merge, "
                        + "delete, or hide calendar events automatically."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(candidates) { candidate in
                    let candidateEvent = candidate.event
                    let candidateRole = appState.calendarRole(
                        for: candidateEvent
                    )
                    let candidateRestriction = appState
                        .calendarWriteRestriction(for: candidateEvent)

                    Button {
                        appState.selectDuplicateCandidate(candidate)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: candidateRole.symbolName)
                                .foregroundStyle(KaosCalTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidateEvent.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(
                                    CalendarEventDateFormatting.agendaText(
                                        for: candidateEvent,
                                        calendar: appState.calendar
                                    )
                                )
                                Text(duplicateMatchText(candidate.matchKind))
                                Text(
                                    "\(candidateRole.title) · "
                                        + "\(candidateEvent.calendarTitle) · "
                                        + "\(candidateEvent.accountType.title) · "
                                        + "\(candidateRestriction?.title ?? "Editable")"
                                )
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        duplicateCandidateAccessibilityLabel(candidate)
                    )
                    .accessibilityHint(
                        "Selects this candidate in Day view. No calendar event is changed."
                    )
                    .accessibilityIdentifier(
                        "inspector.duplicateCandidate.\(candidate.id)"
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.orange.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .accessibilityIdentifier("inspector.duplicateCandidates")
        }
    }

    private func duplicateMatchText(
        _ matchKind: CalendarDuplicateMatchKind
    ) -> String {
        switch matchKind {
        case .timedWithinTolerance:
            "starts and ends within fifteen minutes"
        case .sameAllDayRange:
            "same all-day date range"
        }
    }

    private func duplicateCandidateAccessibilityLabel(
        _ candidate: CalendarDuplicateCandidate
    ) -> String {
        let event = candidate.event
        let role = appState.calendarRole(for: event)
        let permission = appState.calendarWriteRestriction(for: event)?.title
            ?? "editable"
        return [
            "Possible duplicate",
            event.title,
            CalendarEventDateFormatting.agendaText(
                for: event,
                calendar: appState.calendar
            ),
            duplicateMatchText(candidate.matchKind),
            "\(role.title) role",
            event.calendarTitle,
            event.sourceTitle,
            event.accountType.title,
            permission
        ].joined(separator: ", ")
    }
}

#if DEBUG
@MainActor
private final class PreviewCalendarProvider: CalendarProviding {
    let authorizationState: CalendarAuthorizationState = .notDetermined
    var storeChangeHandler: (() -> Void)?

    func requestFullAccess() async throws -> Bool { false }
    func listCalendars() throws -> [CalendarSource] { [] }
    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent] { [] }
    func lookupEvent(
        _ query: CalendarEventLookupQuery
    ) throws -> CalendarEventLookupResult {
        throw CalendarEventLookupError.fullAccessRequired
    }
    func defaultCalendarIdentifierForNewEvents() -> String? { nil }
    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent {
        throw CalendarEventWriteError.fullAccessRequired
    }
    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent {
        throw CalendarEventWriteError.fullAccessRequired
    }
    func deleteEvent(_ original: DisplayEvent) throws {
        throw CalendarEventWriteError.fullAccessRequired
    }
}

#Preview("Calendar shell") {
    CalendarShellView(
        appState: AppState(calendarProvider: PreviewCalendarProvider())
    )
        .frame(width: 1_360, height: 840)
}
#endif
