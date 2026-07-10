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
        .toolbar {
            ToolbarItemGroup {
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

            ToolbarItem {
                Text(appState.focusedPeriodTitle)
                    .font(.headline)
                    .monospacedDigit()
            }

            ToolbarItem {
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
        .task {
            await appState.loadCalendarStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await appState.loadCalendarStatus()
            }
        }
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
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    CalendarEventDateFormatting.monthAndYear(
                        appState.focusedDate,
                        calendar: appState.calendar
                    )
                )
                    .font(.headline)
                Text(appState.calendarAuthorizationState.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            List(selection: sectionSelection) {
                Section("Views") {
                    ForEach(WorkspaceSection.allCases) { section in
                        Label(section.title, systemImage: section.symbolName)
                            .tag(section)
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                }

                Section("Calendars") {
                    if appState.calendarSources.isEmpty {
                        Label("No calendars loaded", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.calendarSources) { source in
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
                                    Text("\(source.sourceTitle) · \(source.accountType.title)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                if !source.isWritable {
                                    Image(systemName: "lock")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Read-only calendar")
                                }
                            }
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

    @ViewBuilder
    private var content: some View {
        if appState.selectedSection == .tasks {
            TaskCenterPlaceholderView(
                filter: $appState.selectedTaskFilter,
                storeState: appState.localContextStoreState
            )
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
            TaskCenterPlaceholderView(
                filter: $appState.selectedTaskFilter,
                storeState: appState.localContextStoreState
            )
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
            List(selection: $appState.selectedEventID) {
                ForEach(appState.visibleEvents) { event in
                    AgendaEventRow(event: event, calendar: appState.calendar)
                        .tag(event.id)
                        .accessibilityIdentifier("agenda.event.\(event.id)")
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct AgendaEventRow: View {
    let event: DisplayEvent
    let calendar: Calendar

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
                    Text(event.calendarTitle)
                    if event.accountType == .exchange {
                        Text("· Exchange")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if event.isRecurring {
                Image(systemName: "repeat")
                    .help("Recurring event")
            }
            if event.isReadOnly || event.isInvitation {
                Image(systemName: "lock")
                    .help(event.isInvitation ? "Invitation: original editing disabled" : "Read-only event")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var timeText: String {
        CalendarEventDateFormatting.agendaText(for: event, calendar: calendar)
    }

    private var accessibilityText: String {
        let permission = event.isReadOnly || event.isInvitation ? "read-only" : "editable"
        return "\(event.title), \(timeText), \(event.calendarTitle), \(permission)"
    }
}

private struct TaskCenterPlaceholderView: View {
    @Binding var filter: TaskFilter
    let storeState: LocalContextStoreState

    var body: some View {
        VStack(spacing: 0) {
            Picker("Task filter", selection: $filter) {
                ForEach(TaskFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(16)

            Divider()

            switch storeState {
            case let .failed(message):
                ContentUnavailableView(
                    "Local task storage unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(message)
                )
            case .ready, .unavailable:
                ContentUnavailableView(
                    "No \(filter.title.lowercased()) tasks",
                    systemImage: "checklist",
                    description: Text("Event tasks and personal tasks are stored locally on this Mac.")
                )
            }
        }
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

                HStack(spacing: 6) {
                    Text("\(event.sourceTitle) · \(event.calendarTitle)")
                    Text(event.isReadOnly || event.isInvitation ? "Read-only" : "Editable")
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(KaosCalTheme.accentSoft, in: Capsule())

                if event.isInvitation {
                    Label("Invitation editing stays in Calendar.app", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let timeZoneIdentifier = event.timeZoneIdentifier {
                    Label(timeZoneIdentifier, systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            briefSection("Before", symbol: "arrow.up.circle")
            briefSection("During", symbol: "circle")
            briefSection("After", symbol: "arrow.down.circle")

            Divider()

            Label("Notes", systemImage: "note.text")
                .font(.headline)
            Text("Event Brief editing begins in Phase 4. KaosCal data will stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func briefSection(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text("No items")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
}

#Preview("Calendar shell") {
    CalendarShellView(
        appState: AppState(calendarProvider: PreviewCalendarProvider())
    )
        .frame(width: 1_360, height: 840)
}
#endif
