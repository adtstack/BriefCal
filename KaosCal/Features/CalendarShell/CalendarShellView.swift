import SwiftUI

struct CalendarShellView: View {
    @ObservedObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } content: {
            WorkspaceView(appState: appState)
                .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        } detail: {
            EventBriefPlaceholderView()
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
            }

            ToolbarItem {
                Text(appState.focusedDate.formatted(date: .long, time: .omitted))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.focusedDate.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Text("Calendar access is not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            List(selection: $appState.selectedSection) {
                Section("Views") {
                    ForEach(WorkspaceSection.allCases) { section in
                        Label(section.title, systemImage: section.symbolName)
                            .tag(section)
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                }

                Section("Calendars") {
                    Label("Not connected", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
        }
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

            Group {
                switch appState.selectedSection ?? .week {
                case .day:
                    CalendarGridPlaceholder(
                        dayCount: 1,
                        focusedDate: appState.focusedDate,
                        calendar: appState.calendar
                    )
                case .week:
                    CalendarGridPlaceholder(
                        dayCount: 7,
                        focusedDate: appState.focusedDate,
                        calendar: appState.calendar
                    )
                case .agenda:
                    AgendaPlaceholderView()
                case .tasks:
                    TaskCenterPlaceholderView(filter: $appState.selectedTaskFilter)
                }
            }
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
            EmptyView()
        case .permissionDenied:
            Label("Permission required", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
        }
    }
}

private struct CalendarGridPlaceholder: View {
    let dayCount: Int
    let focusedDate: Date
    let calendar: Calendar

    private var dates: [Date] {
        (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: focusedDate)
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                dayHeader
                allDayLane

                ForEach(8..<20, id: \.self) { hour in
                    HStack(spacing: 0) {
                        Text(String(format: "%02d:00", hour))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                            .padding(.trailing, 8)

                        ForEach(0..<dayCount, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.clear)
                                .frame(minWidth: dayCount == 1 ? 560 : 112, minHeight: 48)
                                .overlay(alignment: .top) {
                                    Rectangle()
                                        .fill(KaosCalTheme.subtleDivider)
                                        .frame(height: 1)
                                }
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(KaosCalTheme.subtleDivider)
                                        .frame(width: 1)
                                }
                        }
                    }
                }
            }
        }
        .overlay {
            disconnectedMessage
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 72, height: 44)
            ForEach(dates, id: \.self) { date in
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(date.formatted(.dateTime.day()))
                        .font(.headline.monospacedDigit())
                }
                .frame(minWidth: dayCount == 1 ? 560 : 112, maxWidth: .infinity)
                .frame(height: 44)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(KaosCalTheme.subtleDivider)
                        .frame(width: 1)
                }
            }
        }
        .background(.bar)
    }

    private var allDayLane: some View {
        HStack(spacing: 0) {
            Text("All-day")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
                .padding(.trailing, 8)

            ForEach(0..<dayCount, id: \.self) { _ in
                Rectangle()
                    .fill(KaosCalTheme.accentSoft.opacity(0.35))
                    .frame(minWidth: dayCount == 1 ? 560 : 112, minHeight: 36)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(KaosCalTheme.subtleDivider)
                            .frame(width: 1)
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KaosCalTheme.subtleDivider)
                .frame(height: 1)
        }
    }

    private var disconnectedMessage: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(KaosCalTheme.accent)
            Text("Calendar access is not connected")
                .font(.headline)
            Text("Exchange events will appear here after Phase 1 permission setup.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AgendaPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "No agenda yet",
            systemImage: "list.bullet.rectangle",
            description: Text("Exchange events will appear here after calendar access is connected.")
        )
    }
}

private struct TaskCenterPlaceholderView: View {
    @Binding var filter: TaskFilter

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

            ContentUnavailableView(
                "No \(filter.title.lowercased()) tasks",
                systemImage: "checklist",
                description: Text("Event tasks and personal tasks will be stored locally on this Mac.")
            )
        }
    }
}

private struct EventBriefPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(KaosCalTheme.accent)
                    Text("Select an event")
                        .font(.title3.weight(.semibold))
                    Text("일정을 선택하면 준비·진행·후속 작업과 메모가 여기에 표시됩니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                briefSection("Before", symbol: "arrow.up.circle")
                briefSection("During", symbol: "circle")
                briefSection("After", symbol: "arrow.down.circle")

                Divider()

                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                Text("KaosCal notes stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("inspector.empty")
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

#Preview("Calendar shell") {
    CalendarShellView(appState: AppState())
        .frame(width: 1_360, height: 840)
}
