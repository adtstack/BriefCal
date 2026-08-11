import Foundation
import SwiftUI

private enum TaskPlanningGrouping: String, CaseIterable, Identifiable {
    case date
    case source

    var id: String { rawValue }
    var title: String { self == .date ? "Date" : "List / Source" }
}

private struct SavedTaskView: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var filterRawValue: String
    var roleRawValue: String
    var groupingRawValue: String
    var query: String
}

struct TaskCenterView: View {
    @ObservedObject var appState: AppState
    @State private var personalTaskDraftTitle = ""
    @State private var personalTaskDraftHasDueDate: Bool
    @State private var personalTaskDraftDueAt: Date
    @State private var searchText = ""
    @State private var savedViewName = ""
    @State private var showsSaveViewPrompt = false
    @AppStorage private var roleFilterStorage: String
    @AppStorage private var groupingStorage: String
    @AppStorage private var savedViewsStorage: String

    init(
        appState: AppState,
        preferences: UserDefaults = .standard
    ) {
        self.appState = appState
        let tomorrow = appState.calendar.date(
            byAdding: .day,
            value: 1,
            to: appState.calendar.startOfDay(
                for: appState.taskReferenceDate
            )
        ) ?? appState.taskReferenceDate.addingTimeInterval(86_400)
        _personalTaskDraftHasDueDate = State(
            initialValue: appState.selectedTaskFilter != .noDate
                && appState.selectedTaskFilter != .afterReview
                && appState.selectedTaskFilter != .completed
        )
        _personalTaskDraftDueAt = State(initialValue: tomorrow)
        _roleFilterStorage = AppStorage(
            wrappedValue: "",
            "tasks.center.roleFilter.v1",
            store: preferences
        )
        _groupingStorage = AppStorage(
            wrappedValue: TaskPlanningGrouping.date.rawValue,
            "tasks.center.grouping.v1",
            store: preferences
        )
        _savedViewsStorage = AppStorage(
            wrappedValue: "",
            "tasks.center.savedViews.v1",
            store: preferences
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Task views")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Local on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    savedViewsMenu
                    Button {
                        savedViewName = defaultSavedViewName
                        showsSaveViewPrompt = true
                    } label: {
                        Label("Save View", systemImage: "bookmark")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("taskCenter.saveView")
                }

                Picker("Task filter", selection: filterBinding) {
                    ForEach(TaskFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Task filter")

                planningControls
            }
            .padding(16)

            Divider()

            if let error = appState.localOperationError {
                LocalOperationErrorView(
                    message: error,
                    dismiss: appState.clearLocalOperationError
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            if let error = appState.taskCenterRefreshError {
                LocalOperationErrorView(
                    message: "Tasks could not be refreshed. The last loaded list is still shown. \(error)",
                    dismiss: appState.clearTaskCenterRefreshError
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            content
        }
        .task {
            if case .unavailable = appState.taskCenterState {
                appState.refreshTaskCenter()
            }
        }
        .onChange(of: appState.selectedTaskFilter) { _, filter in
            if filter == .noDate {
                personalTaskDraftHasDueDate = false
                return
            }
            guard filter == .today || filter == .upcoming else { return }
            personalTaskDraftHasDueDate = true
            let tomorrow = appState.calendar.date(
                byAdding: .day,
                value: 1,
                to: appState.calendar.startOfDay(
                    for: appState.taskReferenceDate
                )
            ) ?? appState.taskReferenceDate
            if personalTaskDraftDueAt < tomorrow {
                personalTaskDraftDueAt = tomorrow
            }
        }
        .alert("Save Task View", isPresented: $showsSaveViewPrompt) {
            TextField("View name", text: $savedViewName)
            Button("Save") { saveCurrentView() }
                .disabled(
                    savedViewName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The filter, role, grouping, and search text are saved only on this Mac.")
        }
        .accessibilityIdentifier("taskCenter.content")
    }

    private var filterBinding: Binding<TaskFilter> {
        Binding(
            get: { appState.selectedTaskFilter },
            set: { appState.selectTaskFilter($0) }
        )
    }

    private var planningControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Calendar and Tasks", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("taskCenter.search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear planning search")
                }
            }
            .padding(.horizontal, 9)
            .frame(minWidth: 220, maxWidth: .infinity, minHeight: 30)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 7)
            )

            Menu {
                Button("All roles") { roleFilterStorage = "" }
                Divider()
                ForEach(CalendarRole.allCases) { role in
                    Button(role.title) { roleFilterStorage = role.rawValue }
                }
            } label: {
                Label(selectedRole?.title ?? "All roles", systemImage: "tag")
            }
            .fixedSize()
            .accessibilityIdentifier("taskCenter.roleFilter")

            Picker("Group", selection: $groupingStorage) {
                ForEach(TaskPlanningGrouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping.rawValue)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("taskCenter.grouping")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.taskCenterState {
        case .unavailable:
            ContentUnavailableView(
                "Local task storage unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("BriefCal did not open its local database in this session.")
            )
        case .loading:
            ProgressView("Loading tasks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t load tasks", systemImage: "exclamationmark.circle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    appState.refreshTaskCenter()
                }
            }
        case let .loaded(items):
            loadedContent(items)
        }
    }

    private func loadedContent(_ items: [TaskCenterItem]) -> some View {
        let items = filtered(items)
        let events = matchingCalendarEvents
        let showsProviderTasks = appState.taskProviderCoordinator != nil
            && selectedRole == nil
            && appState.selectedTaskFilter != .afterReview
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !appState.recoveryBriefs.isEmpty {
                    RecoveryBriefSection(
                        appState: appState,
                        briefs: appState.recoveryBriefs
                    )
                }

                if (appState.selectedTaskFilter == .today
                    || appState.selectedTaskFilter == .upcoming
                    || appState.selectedTaskFilter == .noDate)
                    && searchText.isEmpty {
                    PersonalTaskComposer(
                        appState: appState,
                        filter: appState.selectedTaskFilter,
                        title: $personalTaskDraftTitle,
                        hasDueDate: $personalTaskDraftHasDueDate,
                        dueAt: $personalTaskDraftDueAt
                    )
                }

                if !events.isEmpty {
                    calendarSearchResults(events)
                }

                if showsProviderTasks,
                   let coordinator = appState.taskProviderCoordinator {
                    TaskCenterProviderSection(
                        coordinator: coordinator,
                        filter: appState.selectedTaskFilter,
                        query: normalizedSearchQuery,
                        referenceDate: appState.taskReferenceDate,
                        calendar: appState.calendar,
                        showsEmptyState: items.isEmpty && events.isEmpty
                    )
                }

                if items.isEmpty && events.isEmpty && !showsProviderTasks {
                    emptyContent
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                } else {
                    ForEach(grouped(items), id: \.title) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            VStack(spacing: 0) {
                                ForEach(group.items) { item in
                                    TaskCenterRow(appState: appState, item: item)
                                    if item.id != group.items.last?.id {
                                        Divider()
                                            .padding(.leading, 36)
                                    }
                                }
                            }
                            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(BriefCalTheme.subtleDivider)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch appState.selectedTaskFilter {
        case .today:
            ContentUnavailableView(
                "Nothing due today",
                systemImage: "checkmark.circle",
                description: Text("Tasks due today appear here; undated tasks stay in No Date.")
            )
        case .upcoming:
            ContentUnavailableView(
                "No upcoming tasks",
                systemImage: "calendar.badge.checkmark",
                description: Text("Add a personal task with a future date.")
            )
        case .overdue:
            ContentUnavailableView(
                "Nothing overdue",
                systemImage: "checkmark.circle",
                description: Text("Open tasks past their due time appear here.")
            )
        case .noDate:
            ContentUnavailableView(
                "No undated tasks",
                systemImage: "tray",
                description: Text("Tasks without a due date appear here.")
            )
        case .afterReview:
            ContentUnavailableView(
                "No follow-up to review",
                systemImage: "checkmark.circle",
                description: Text(
                    "Unfinished After tasks from ended events appear here."
                )
            )
        case .completed:
            ContentUnavailableView(
                "No completed tasks yet",
                systemImage: "checkmark.circle",
                description: Text("Completed event and personal tasks appear here.")
            )
        }
    }

    private func grouped(_ items: [TaskCenterItem]) -> [TaskCenterGroup] {
        if grouping == .source {
            return Dictionary(grouping: items, by: sourceGroupTitle)
                .map { TaskCenterGroup(title: $0.key, items: $0.value) }
                .sorted { $0.title < $1.title }
        }
        switch appState.selectedTaskFilter {
        case .today:
            return [TaskCenterGroup(title: "Today", items: items)]
        case .upcoming:
            return Dictionary(grouping: items) { item in
                item.dueAt.map {
                    CalendarEventDateFormatting.abbreviatedDate(
                        $0,
                        calendar: appState.calendar
                    )
                }
                    ?? "Later"
            }
            .map { TaskCenterGroup(title: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.items.compactMap(\.dueAt).min() ?? .distantFuture
                let rhsDate = rhs.items.compactMap(\.dueAt).min() ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.title < rhs.title
            }
        case .overdue:
            return [TaskCenterGroup(title: "Overdue", items: items)]
        case .noDate:
            return [TaskCenterGroup(title: "No date", items: items)]
        case .afterReview:
            return [TaskCenterGroup(
                title: "Follow-up from ended events",
                items: items
            )]
        case .completed:
            return [TaskCenterGroup(title: "Recently completed", items: items)]
        }
    }

    private var selectedRole: CalendarRole? {
        CalendarRole(rawValue: roleFilterStorage)
    }

    private var grouping: TaskPlanningGrouping {
        TaskPlanningGrouping(rawValue: groupingStorage) ?? .date
    }

    private func filtered(_ items: [TaskCenterItem]) -> [TaskCenterItem] {
        let query = normalizedSearchQuery
        return items.filter { item in
            guard selectedRole.map({ role(for: item) == $0 }) ?? true else {
                return false
            }
            guard !query.isEmpty else { return true }
            return searchableText(for: item)
                .localizedCaseInsensitiveContains(query)
        }
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func role(for item: TaskCenterItem) -> CalendarRole {
        switch item.source {
        case .personal:
            return .personal
        case let .event(_, _, _, calendarIdentifier, _, _, _, _, _):
            return appState.calendarRole(
                calendarIdentifier: calendarIdentifier
            )
        }
    }

    private func searchableText(for item: TaskCenterItem) -> String {
        var parts = [item.title, role(for: item).title]
        switch item.source {
        case .personal:
            parts.append("Personal Local")
        case let .event(
            _, section, eventTitle, _, calendarTitle, sourceTitle, _, _, _
        ):
            parts += [section.shortTitle, eventTitle, calendarTitle, sourceTitle]
        }
        if let provider = item.providerLink?.provider.title {
            parts.append(provider)
        }
        return parts.joined(separator: " ")
    }

    private func sourceGroupTitle(_ item: TaskCenterItem) -> String {
        switch item.source {
        case .personal:
            return "Personal · Local"
        case let .event(_, _, _, calendarIdentifier, calendarTitle, _, _, _, _):
            return "\(appState.calendarRole(calendarIdentifier: calendarIdentifier).title) · \(calendarTitle)"
        }
    }

    private var matchingCalendarEvents: [DisplayEvent] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else { return [] }
        return appState.events.filter { event in
            let role = appState.calendarRole(for: event)
            guard selectedRole.map({ role == $0 }) ?? true else { return false }
            return [
                event.title,
                event.location ?? "",
                event.calendarTitle,
                event.sourceTitle,
                event.originalNotes ?? "",
                role.title
            ].joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }.sorted { $0.startDate < $1.startDate }
    }

    private func calendarSearchResults(
        _ events: [DisplayEvent]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calendar results · current loaded period")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(events) { event in
                    Button {
                        appState.openCalendarSearchResult(event)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .foregroundStyle(BriefCalTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.body.weight(.medium))
                                Text(
                                    CalendarEventDateFormatting.inspectorText(
                                        for: event,
                                        calendar: appState.calendar
                                    ) + " · \(event.calendarTitle)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if event.id != events.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(
                .background.opacity(0.65),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(BriefCalTheme.subtleDivider)
            }
        }
    }

    @ViewBuilder
    private var savedViewsMenu: some View {
        Menu {
            if savedViews.isEmpty {
                Text("No saved views")
            } else {
                ForEach(savedViews) { view in
                    Button(view.name) { apply(view) }
                }
                Divider()
                Menu("Delete Saved View") {
                    ForEach(savedViews) { view in
                        Button(view.name, role: .destructive) {
                            delete(view)
                        }
                    }
                }
            }
        } label: {
            Label("Saved", systemImage: "bookmark.fill")
        }
        .fixedSize()
        .accessibilityIdentifier("taskCenter.savedViews")
    }

    private var savedViews: [SavedTaskView] {
        guard let data = savedViewsStorage.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SavedTaskView].self, from: data)) ?? []
    }

    private var defaultSavedViewName: String {
        [
            selectedRole?.title,
            appState.selectedTaskFilter.title,
            normalizedSearchQuery.isEmpty ? nil : normalizedSearchQuery
        ].compactMap { $0 }.joined(separator: " + ")
    }

    private func saveCurrentView() {
        let name = savedViewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var views = savedViews
        if let index = views.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            views[index] = makeSavedView(id: views[index].id, name: name)
        } else {
            views.append(makeSavedView(id: UUID().uuidString, name: name))
        }
        persist(views)
    }

    private func makeSavedView(id: String, name: String) -> SavedTaskView {
        SavedTaskView(
            id: id,
            name: name,
            filterRawValue: appState.selectedTaskFilter.rawValue,
            roleRawValue: roleFilterStorage,
            groupingRawValue: groupingStorage,
            query: searchText
        )
    }

    private func apply(_ view: SavedTaskView) {
        guard let filter = TaskFilter(rawValue: view.filterRawValue) else {
            return
        }
        appState.selectTaskFilter(filter)
        roleFilterStorage = CalendarRole(rawValue: view.roleRawValue) == nil
            ? ""
            : view.roleRawValue
        groupingStorage = TaskPlanningGrouping(
            rawValue: view.groupingRawValue
        )?.rawValue ?? TaskPlanningGrouping.date.rawValue
        searchText = view.query
    }

    private func delete(_ view: SavedTaskView) {
        persist(savedViews.filter { $0.id != view.id })
    }

    private func persist(_ views: [SavedTaskView]) {
        guard let data = try? JSONEncoder().encode(views),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        savedViewsStorage = string
    }
}

private struct TaskCenterGroup {
    let title: String
    let items: [TaskCenterItem]
}

private struct RecoveryBriefSection: View {
    @ObservedObject var appState: AppState
    let briefs: [EventBriefSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Local Event Briefs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(briefs, id: \.context.id) { brief in
                    let role = appState.calendarRole(
                        calendarIdentifier: brief.link.calendarIdentifier
                    )

                    Button {
                        Task {
                            await appState.openOriginalEvent(
                                contextID: brief.context.id
                            )
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: recoveryIcon(
                                brief.link.linkStatus
                            ))
                                .foregroundStyle(BriefCalTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(brief.context.titleSnapshot)
                                    .font(.body.weight(.medium))
                                Text(
                                    recoveryStatus(brief)
                                        + " · \(brief.tasks.count) tasks"
                                        + (brief.context.notes.isEmpty ? "" : " · Notes")
                                        + " · \(role.title)"
                                        + " · \(brief.link.calendarTitleSnapshot)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Review")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "taskCenter.recoveryBrief.\(brief.context.id)"
                    )
                    if brief.context.id != briefs.last?.context.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(BriefCalTheme.subtleDivider)
            }
        }
    }

    private func recoveryStatus(_ brief: EventBriefSnapshot) -> String {
        if brief.hasRecordedOriginalDeletion,
           brief.context.lifecycleStatus == .cancelled,
           brief.link.linkStatus == .orphaned {
            return "Original deleted · Local Brief kept"
        }
        return switch brief.link.linkStatus {
        case .active: "Linked"
        case .missing: "Original not found yet"
        case .orphaned: "Local orphan"
        }
    }

    private func recoveryIcon(_ status: EventLinkStatus) -> String {
        switch status {
        case .active: "link"
        case .missing: "questionmark.circle"
        case .orphaned: "archivebox"
        }
    }
}

private struct TaskCenterProviderSection: View {
    @ObservedObject var coordinator: TaskProviderCoordinator
    let filter: TaskFilter
    let query: String
    let referenceDate: Date
    let calendar: Calendar
    let showsEmptyState: Bool

    @State private var editorPresentation: ProviderTaskEditorPresentation?
    @State private var activeTaskIDs = Set<String>()
    @State private var errorMessages = [String: String]()

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Provider tasks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Refreshing provider tasks")
                        }
                        Text("Not yet linked to an Event Brief")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Label(
                                    group.title,
                                    systemImage: group.provider.settingsIcon
                                )
                                .font(.caption.weight(.semibold))
                                Spacer()
                                Text("\(group.items.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .controlBackgroundColor))

                            ForEach(group.items) { item in
                                providerRow(item)
                                if item.id != group.items.last?.id {
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                        .background(
                            .background.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(BriefCalTheme.subtleDivider)
                        }
                    }
                }
            } else if showsEmptyState && (!isLoading || hasLoadedSnapshot) {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "checkmark.circle",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            ProviderTaskEditorSheet(
                coordinator: coordinator,
                mode: presentation.mode,
                writableLists: coordinator.taskLists.filter {
                    coordinator.isSidebarListWritable($0)
                }
            )
        }
    }

    private func providerRow(_ item: ProviderTaskListItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if activeTaskIDs.contains(item.id)
                || coordinator.isMutatingSidebarTask(item) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Button {
                    toggleCompletion(item)
                } label: {
                    Image(
                        systemName: item.isCompleted
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .frame(width: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    item.isCompleted ? BriefCalTheme.accent : Color.secondary
                )
                .disabled(!coordinator.isSidebarTaskWritable(item))
                .accessibilityLabel(
                    item.isCompleted ? "Mark incomplete" : "Mark complete"
                )
            }

            Button {
                editorPresentation = ProviderTaskEditorPresentation(
                    mode: .edit(item)
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(
                            item.isCompleted ? Color.secondary : Color.primary
                        )
                    HStack(spacing: 6) {
                        if let dueAt = item.dueAt {
                            Label(
                                CalendarEventDateFormatting.abbreviatedDate(
                                    dueAt,
                                    calendar: calendar
                                ),
                                systemImage: "calendar"
                            )
                        } else {
                            Label("No date", systemImage: "tray")
                        }
                        if item.priority != .none {
                            Text("·")
                            Label(item.priority.title, systemImage: "flag.fill")
                        }
                        Text("· \(item.provider.title) · \(item.listTitle)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let error = errorMessages[item.id] {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let url = item.originalURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open in \(item.provider.title)")
            }
        }
        .padding(12)
        .draggable("briefcal-task:\(item.id)") {
            Label(item.title, systemImage: "checklist")
                .padding(8)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .accessibilityIdentifier("taskCenter.providerTask.\(item.id)")
    }

    private var items: [ProviderTaskListItem] {
        let today = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: today
        ) ?? referenceDate
        return coordinator.allSidebarTaskItems.filter { item in
            guard coordinator.calendarLink(for: item) == nil else {
                return false
            }
            let matchesFilter: Bool = switch filter {
            case .today:
                !item.isCompleted && item.dueAt.map {
                    $0 >= today && $0 < tomorrow
                } == true
            case .upcoming:
                !item.isCompleted && item.dueAt.map { $0 >= tomorrow } == true
            case .overdue:
                !item.isCompleted && item.dueAt.map { $0 < today } == true
            case .noDate:
                !item.isCompleted && item.dueAt == nil
            case .completed:
                item.isCompleted
            case .afterReview:
                false
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return [
                item.title,
                item.details ?? "",
                item.provider.title,
                item.accountTitle,
                item.listTitle
            ].joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }.sorted {
            if $0.priority != $1.priority {
                return $0.priority.rawValue > $1.priority.rawValue
            }
            if $0.dueAt != $1.dueAt {
                return ($0.dueAt ?? .distantFuture)
                    < ($1.dueAt ?? .distantFuture)
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title)
                == .orderedAscending
        }
    }

    private var groups: [TaskCenterProviderGroup] {
        Dictionary(grouping: items) {
            ProviderTaskSidebarListIdentity(
                provider: $0.provider,
                accountKey: $0.accountKey,
                listID: $0.listID
            )
        }.compactMap { identity, items in
            guard let first = items.first else { return nil }
            return TaskCenterProviderGroup(
                id: identity,
                provider: identity.provider,
                title: "\(first.listTitle) · \(first.accountTitle)",
                items: items
            )
        }.sorted {
            if $0.provider != $1.provider {
                return ProviderTaskSidebarFiltering.providerRank($0.provider)
                    < ProviderTaskSidebarFiltering.providerRank($1.provider)
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title)
                == .orderedAscending
        }
    }

    private var isLoading: Bool {
        if coordinator.isRefreshingOAuthTaskLists { return true }
        for state in [
            coordinator.appleRemindersTaskState,
            coordinator.googleTasksTaskState,
            coordinator.todoistTaskState,
            coordinator.microsoftToDoTaskState
        ] {
            if case .loading = state { return true }
        }
        return false
    }

    private var hasLoadedSnapshot: Bool {
        [
            TaskProviderKind.appleReminders,
            .googleTasks,
            .todoist,
            .microsoftToDo
        ].contains {
            coordinator.hasSidebarTaskSnapshot(for: $0)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .today: "Nothing due today"
        case .upcoming: "No upcoming tasks"
        case .overdue: "Nothing overdue"
        case .noDate: "No undated tasks"
        case .completed: "No completed tasks yet"
        case .afterReview: "No follow-up to review"
        }
    }

    private var emptyDescription: String {
        query.isEmpty
            ? "No local or connected-provider tasks match this view."
            : "No calendar event or task matches the current search."
    }

    private func toggleCompletion(_ item: ProviderTaskListItem) {
        guard activeTaskIDs.insert(item.id).inserted else { return }
        errorMessages[item.id] = nil
        Task {
            do {
                _ = try await coordinator.setSidebarTaskCompleted(
                    item,
                    isCompleted: !item.isCompleted
                )
            } catch {
                errorMessages[item.id] = error.localizedDescription
            }
            activeTaskIDs.remove(item.id)
        }
    }
}

private struct TaskCenterProviderGroup: Identifiable {
    let id: ProviderTaskSidebarListIdentity
    let provider: TaskProviderKind
    let title: String
    let items: [ProviderTaskListItem]
}

private struct PersonalTaskComposer: View {
    @ObservedObject var appState: AppState
    let filter: TaskFilter
    @Binding var title: String
    @Binding var hasDueDate: Bool
    @Binding var dueAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New personal task")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("What needs doing?", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                    .accessibilityIdentifier("taskCenter.newPersonalTask")

                Toggle("Due", isOn: $hasDueDate)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                if hasDueDate {
                    DatePicker(
                        "Due",
                        selection: $dueAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .fixedSize()
                }

                Button("Add", action: addTask)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (filter == .upcoming && !hasDueDate)
                    )
            }

            Text("A due date controls Task Center grouping; it does not create a reminder notification.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(BriefCalTheme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private func addTask() {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard filter != .upcoming || hasDueDate else { return }
        if appState.createPersonalTask(
            title: cleaned,
            dueAt: hasDueDate ? dueAt : nil
        ) {
            title = ""
        }
    }
}

private struct TaskCenterRow: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var appState: AppState
    let item: TaskCenterItem

    @State private var title: String
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var showsDueEditor = false
    @State private var personalDueEnabled: Bool
    @State private var personalDueDraft: Date
    @State private var isResolvingProvider = false
    @State private var showsRelinkPicker = false
    @State private var showsPlanningEditor = false
    @FocusState private var isEditing: Bool

    init(appState: AppState, item: TaskCenterItem) {
        self.appState = appState
        self.item = item
        _title = State(initialValue: item.title)
        _personalDueEnabled = State(initialValue: item.dueAt != nil)
        let tomorrow = appState.calendar.date(
            byAdding: .day,
            value: 1,
            to: appState.calendar.startOfDay(
                for: appState.taskReferenceDate
            )
        ) ?? appState.taskReferenceDate.addingTimeInterval(86_400)
        _personalDueDraft = State(initialValue: item.dueAt ?? tomorrow)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                guard commitTitle() else { return }
                appState.setTaskCenterItemCompleted(
                    item.id,
                    isCompleted: !item.isCompleted
                )
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isCompleted ? BriefCalTheme.accent : .secondary)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                TextField("Task title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .focused($isEditing)
                    .onSubmit {
                        _ = commitTitle()
                    }
                    .strikethrough(item.isCompleted)

                dueSummary
                sourceView

                if let providerLink = item.providerLink {
                    providerLinkView(providerLink)
                } else if item.isProviderLocalOnly {
                    Label("Local only · provider sync disabled for this task", systemImage: "macbook")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                planningSummary
            }

            Spacer(minLength: 8)

            rowActionsMenu
        }
        .padding(12)
        .accessibilityIdentifier(taskRowAccessibilityIdentifier)
        .popover(isPresented: $showsDueEditor) {
            personalDueEditor
        }
        .onChange(of: isEditing) { wasEditing, isEditing in
            if wasEditing && !isEditing {
                commitTitle()
            }
        }
        .onChange(of: item.title) { _, newValue in
            guard !isEditing else { return }
            title = newValue
        }
        .onChange(of: item.dueAt) { _, newValue in
            guard !showsDueEditor else { return }
            personalDueEnabled = newValue != nil
            if let newValue {
                personalDueDraft = newValue
            }
        }
        .onDisappear {
            if !isDeleting {
                _ = commitTitle()
            }
        }
        .alert(deleteConfirmationTitle, isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    if !(await appState.deleteTaskCenterItemAfterRemoteDelete(item.id)) {
                        isDeleting = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(isPresented: $showsRelinkPicker) {
            TaskProviderRelinkPicker(
                appState: appState,
                itemID: item.id
            )
        }
        .sheet(isPresented: $showsPlanningEditor) {
            TaskPlanningEditorSheet(
                appState: appState,
                item: item
            )
        }
    }

    @ViewBuilder
    private var planningSummary: some View {
        if hasPlanningAttributes || hasPlanningProgress {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    planningAttributeLabels
                    planningProgressLabels
                }

                VStack(alignment: .leading, spacing: 4) {
                    if hasPlanningAttributes {
                        HStack(spacing: 8) {
                            planningAttributeLabels
                        }
                    }
                    if hasPlanningProgress {
                        HStack(spacing: 8) {
                            planningProgressLabels
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var hasPlanningAttributes: Bool {
        item.planning.isImportant
            || item.planning.priority != .none
            || item.planning.repeatFrequency != .none
    }

    private var hasPlanningProgress: Bool {
        !item.checklistItems.isEmpty
            || item.planning.estimatedMinutes != nil
            || item.planning.actualSeconds > 0
            || item.planning.isTimerRunning
    }

    @ViewBuilder
    private var planningAttributeLabels: some View {
        if item.planning.isImportant {
            Label("Important", systemImage: "star.fill")
                .foregroundStyle(.orange)
        }
        if item.planning.priority != .none {
            Label(
                item.planning.priority.title,
                systemImage: "flag.fill"
            )
        }
        if item.planning.repeatFrequency != .none {
            Label(
                repeatSummary,
                systemImage: "repeat"
            )
        }
    }

    @ViewBuilder
    private var planningProgressLabels: some View {
        if !item.checklistItems.isEmpty {
            Label(
                "\(item.checklistItems.filter(\.isCompleted).count)/\(item.checklistItems.count)",
                systemImage: "checklist"
            )
        }
        if item.planning.estimatedMinutes != nil
            || item.planning.actualSeconds > 0
            || item.planning.isTimerRunning {
            Button {
                _ = appState.toggleTaskTimer(item.id)
            } label: {
                Label {
                    TaskElapsedTimeText(planning: item.planning)
                } icon: {
                    Image(
                        systemName: item.planning.isTimerRunning
                            ? "pause.circle.fill"
                            : "play.circle"
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(item.isCompleted)
            .help(
                item.planning.isTimerRunning
                    ? "Stop actual-time tracking"
                    : "Start actual-time tracking"
            )
        }
    }

    private var repeatSummary: String {
        let frequency = item.planning.repeatFrequency.title
        return item.planning.repeatInterval == 1
            ? frequency
            : "Every \(item.planning.repeatInterval) \(frequency.lowercased())"
    }

    @ViewBuilder
    private func providerLinkView(
        _ link: TaskCenterProviderLink
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label(
                    appState.taskProviderSourceTitle(for: link),
                    systemImage: link.provider.settingsIcon
                )
                .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Label(
                    link.needsAttention
                        ? "Needs attention · \(link.statusTitle)"
                        : link.statusTitle,
                    systemImage: link.needsAttention
                        ? "exclamationmark.triangle.fill"
                        : link.syncState == .pendingCreate
                            ? "arrow.triangle.2.circlepath"
                            : "checkmark.circle.fill"
                )
                .foregroundStyle(link.needsAttention ? .orange : .secondary)

                Spacer(minLength: 6)

                if link.needsAttention {
                    providerRecoveryMenu(link)
                }
            }
            .font(.caption)

            if let recoveryMessage = link.recoveryMessage {
                Text(recoveryMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(
            "taskCenter.providerLink.\(link.bindingID)"
        )
    }

    @ViewBuilder
    private func providerRecoveryMenu(
        _ link: TaskCenterProviderLink
    ) -> some View {
        Menu {
            if link.pendingOperation != nil {
                Button(link.pendingOperation?.retryTitle ?? "Retry Sync") {
                    retryPendingProviderOperation()
                }
                .disabled(!link.canRetryPendingOperation)
                Button("Cancel Pending Change and Keep Local") {
                    resolveProviderLink {
                        appState.keepTaskLocalOnly(item.id)
                    }
                }
            } else {
                switch link.syncState {
                case .missing:
                    Button("Check Provider Again") {
                        resolveProviderLink {
                            appState.checkTaskProviderLink(item.id)
                        }
                    }
                    Button("Recreate Remote from Local Task") {
                        resolveProviderLinkUsingLocal()
                    }
                case .conflict:
                    Button("Use Remote Version") {
                        resolveProviderLinkUsingRemote()
                    }
                    Button("Replace Remote with Local Version") {
                        resolveProviderLinkUsingLocal()
                    }
                case .disconnected:
                    Button("Open Task Provider Settings") {
                        appState.selectedSettingsPane = .taskProviders
                        openSettings()
                    }
                    Button("Check Provider Again") {
                        resolveProviderLink {
                            appState.checkTaskProviderLink(item.id)
                        }
                    }
                case .pendingCreate, .linked:
                    EmptyView()
                }
            }
            Divider()
            Button("Link to Existing Remote Task…") {
                showsRelinkPicker = true
            }
            if link.pendingOperation == nil {
                Button("Keep Local Only") {
                    resolveProviderLink {
                        appState.keepTaskLocalOnly(item.id)
                    }
                }
            }
        } label: {
            Label("Resolve", systemImage: "wrench.and.screwdriver")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isResolvingProvider)
        .accessibilityLabel(
            "Resolve \(link.provider.title) task connection"
        )
        .accessibilityIdentifier(
            "taskCenter.providerResolve.\(link.bindingID)"
        )
    }

    private var rowActionsMenu: some View {
        Menu {
            Button {
                _ = appState.toggleTaskImportant(item.id)
            } label: {
                Label(
                    item.planning.isImportant
                        ? "Remove Important"
                        : "Mark Important",
                    systemImage: item.planning.isImportant
                        ? "star.slash"
                        : "star"
                )
            }

            Button {
                guard commitTitle() else { return }
                showsPlanningEditor = true
            } label: {
                Label(
                    "Edit Planning…",
                    systemImage: "slider.horizontal.3"
                )
            }

            if isEditablePersonalTask {
                Button {
                    guard commitTitle() else { return }
                    showsDueEditor = true
                } label: {
                    Label("Edit Due Date…", systemImage: "calendar.badge.clock")
                }
            }

            if isEventTask, item.providerLink?.needsAttention != true {
                Divider()

                Button {
                    showsRelinkPicker = true
                } label: {
                    Label(
                        "Link to Existing Remote Task…",
                        systemImage: "link.badge.plus"
                    )
                }

                if item.providerLink != nil {
                    Button("Keep Local Only") {
                        _ = appState.keepTaskLocalOnly(item.id)
                    }
                } else {
                    Button("Use Calendar Default Provider") {
                        _ = appState.useCalendarDefaultTaskProvider(item.id)
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                confirmsDeletion = true
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Task actions")
        .accessibilityLabel("Task actions for \(item.title)")
    }

    @ViewBuilder
    private var dueSummary: some View {
        if let dueAt = item.dueAt {
            Label(
                dueText(dueAt),
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Label(
                appState.selectedTaskFilter == .completed
                    ? "No date"
                    : "No date · Today",
                systemImage: "tray"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sourceView: some View {
        switch item.source {
        case let .event(
            contextID,
            section,
            eventTitle,
            calendarIdentifier,
            calendarTitle,
            sourceTitle,
            eventStart,
            eventEnd,
            isAllDay
        ):
            let role = appState.calendarRole(
                calendarIdentifier: calendarIdentifier
            )
            let timeText = eventTimeText(
                start: eventStart,
                end: eventEnd,
                isAllDay: isAllDay
            )
            let sourceMetadata = "\(role.title) · \(section.shortTitle) · "
                + "\(timeText) · \(calendarTitle) · \(sourceTitle)"
            Button {
                guard commitTitle() else { return }
                Task {
                    await appState.openOriginalEvent(contextID: contextID)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        eventLinkPrefix + eventTitle,
                        systemImage: "calendar"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                    Text(sourceMetadata)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                "\(eventSourceHelp). \(role.title) role · "
                    + "\(calendarTitle) · \(sourceTitle)"
            )
            .accessibilityLabel(
                "\(eventLinkPrefix)\(eventTitle), \(sourceMetadata)"
            )
            .accessibilityIdentifier(
                "taskCenter.eventSource.\(contextID)"
            )
        case .personal:
            Label(
                "Personal task · Local",
                systemImage: "person.crop.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var isEditablePersonalTask: Bool {
        guard !item.isCompleted else { return false }
        if case .personal = item.source { return true }
        return false
    }

    private var isEventTask: Bool {
        if case .eventTask = item.id { return true }
        return false
    }

    private var deleteConfirmationTitle: String {
        item.providerLink == nil
            ? "Delete this local task?"
            : "Delete this local and remote task?"
    }

    private var deleteConfirmationMessage: String {
        if let providerLink = item.providerLink {
            return "The linked \(providerLink.provider.title) task will be deleted first. The calendar event and its original data will not be changed."
        }
        return "The calendar event and its original data will not be changed."
    }

    private var eventLinkPrefix: String {
        if item.wasOriginalDeletedByBriefCal,
           item.eventLifecycleStatus == .cancelled,
           item.eventLinkStatus == .orphaned {
            return "Deleted original · "
        }
        return switch item.eventLinkStatus {
        case .missing: "Missing · "
        case .orphaned: "Orphan · "
        case .active, .none: ""
        }
    }

    private var eventSourceHelp: String {
        if item.wasOriginalDeletedByBriefCal,
           item.eventLifecycleStatus == .cancelled,
           item.eventLinkStatus == .orphaned {
            return "Review the kept local Brief for the deleted original"
        }
        return switch item.eventLinkStatus {
        case .missing: "Review the missing original event"
        case .orphaned: "Review the local orphan Event Brief"
        case .active, .none: "Open original event"
        }
    }

    private var taskRowAccessibilityIdentifier: String {
        switch item.id {
        case let .eventTask(taskID, contextID):
            return "taskCenter.item.event.\(contextID).\(taskID)"
        case let .personalTask(taskID):
            return "taskCenter.item.personal.\(taskID)"
        }
    }

    private var personalDueEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal task due date")
                .font(.headline)
            Toggle("Set due date", isOn: $personalDueEnabled)
            if personalDueEnabled {
                DatePicker(
                    "Due",
                    selection: $personalDueDraft,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    showsDueEditor = false
                }
                Button("Save") {
                    savePersonalDue()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    @discardableResult
    private func commitTitle() -> Bool {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            title = item.title
            return false
        }
        guard cleaned != item.title else { return true }
        return appState.renameTaskCenterItem(item.id, title: cleaned)
    }

    private func savePersonalDue() {
        guard commitTitle() else { return }
        if appState.updatePersonalTaskDue(
            item.id,
            dueAt: personalDueEnabled ? personalDueDraft : nil
        ) {
            showsDueEditor = false
        }
    }

    private func resolveProviderLink(
        _ operation: () -> Bool
    ) {
        guard !isResolvingProvider else { return }
        isResolvingProvider = true
        _ = operation()
        isResolvingProvider = false
    }

    private func resolveProviderLinkUsingRemote() {
        guard !isResolvingProvider else { return }
        isResolvingProvider = true
        Task {
            _ = await appState.useRemoteTaskProviderVersion(item.id)
            isResolvingProvider = false
        }
    }

    private func resolveProviderLinkUsingLocal() {
        guard !isResolvingProvider else { return }
        isResolvingProvider = true
        Task {
            _ = await appState.useLocalTaskProviderVersion(item.id)
            isResolvingProvider = false
        }
    }

    private func retryPendingProviderOperation() {
        guard !isResolvingProvider else { return }
        isResolvingProvider = true
        Task {
            _ = await appState.retryTaskProviderOperation(item.id)
            isResolvingProvider = false
        }
    }

    private func dueText(_ date: Date) -> String {
        if case let .event(_, _, _, _, _, _, _, _, isAllDay) = item.source,
           isAllDay {
            return CalendarEventDateFormatting.abbreviatedDate(
                date,
                calendar: appState.calendar
            )
        }
        return CalendarEventDateFormatting.abbreviatedDateTime(
            date,
            calendar: appState.calendar
        )
    }

    private func eventTimeText(
        start: Date,
        end: Date,
        isAllDay: Bool
    ) -> String {
        if isAllDay {
            return "All-day · " + CalendarEventDateFormatting.abbreviatedDate(
                start,
                calendar: appState.calendar
            )
        }
        return CalendarEventDateFormatting.abbreviatedDateTime(
            start,
            calendar: appState.calendar
        ) + "–" + CalendarEventDateFormatting.shortTime(
            end,
            calendar: appState.calendar
        )
    }
}

private struct TaskElapsedTimeText: View {
    let planning: TaskPlanningMetadata

    var body: some View {
        if planning.isTimerRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(duration(at: context.date))
                    .monospacedDigit()
            }
        } else {
            Text(duration(at: nil))
                .monospacedDigit()
        }
    }

    private func duration(at date: Date?) -> String {
        let running = date.flatMap { date in
            planning.startedAt.map {
                max(0, Int(date.timeIntervalSince($0)))
            }
        } ?? 0
        let seconds = planning.actualSeconds + running
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let actual = hours > 0
            ? "\(hours)h \(remainingMinutes)m"
            : (minutes > 0 ? "\(minutes)m" : "<1m")
        if let estimate = planning.estimatedMinutes {
            return "\(actual) / \(estimate)m"
        }
        return actual
    }
}

private struct TaskPlanningEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    let item: TaskCenterItem

    @State private var priority: TaskPriority
    @State private var isImportant: Bool
    @State private var repeatFrequency: TaskRepeatFrequency
    @State private var repeatInterval: Int
    @State private var hasEstimate: Bool
    @State private var estimatedMinutes: Int
    @State private var checklist: [TaskChecklistItem]
    @State private var checklistDraft = ""
    @State private var errorMessage: String?

    init(appState: AppState, item: TaskCenterItem) {
        self.appState = appState
        self.item = item
        _priority = State(initialValue: item.planning.priority)
        _isImportant = State(initialValue: item.planning.isImportant)
        _repeatFrequency = State(
            initialValue: item.planning.repeatFrequency
        )
        _repeatInterval = State(
            initialValue: item.planning.repeatInterval
        )
        _hasEstimate = State(
            initialValue: item.planning.estimatedMinutes != nil
        )
        _estimatedMinutes = State(
            initialValue: item.planning.estimatedMinutes ?? 30
        )
        _checklist = State(initialValue: item.checklistItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Task Planning", systemImage: "checklist")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Planning for")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(item.title)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Label(
                        "Save applies priority, importance, repeat, and estimate. Checklist and timer actions are saved immediately.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Priority")
                            .font(.headline)
                        Picker("Priority", selection: $priority) {
                            ForEach(TaskPriority.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Important", isOn: $isImportant)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Repeat")
                            .font(.headline)
                        Picker("Repeat", selection: $repeatFrequency) {
                            ForEach(TaskRepeatFrequency.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        if repeatFrequency != .none {
                            Stepper(
                                "Every \(repeatInterval) \(repeatFrequency.title.lowercased())",
                                value: $repeatInterval,
                                in: 1...365
                            )
                            Text("Completing this task creates the next local occurrence. Provider-native recurrence is left unchanged.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Time")
                            .font(.headline)
                        Toggle("Estimated duration", isOn: $hasEstimate)
                        if hasEstimate {
                            HStack {
                                TextField(
                                    "Minutes",
                                    value: $estimatedMinutes,
                                    format: .number
                                )
                                .frame(width: 90)
                                Text("minutes planned")
                            }
                        }
                        HStack {
                            Text("Actual")
                            Spacer()
                            TaskElapsedTimeText(planning: item.planning)
                        }
                        Button(
                            item.planning.isTimerRunning
                                ? "Stop Timer"
                                : "Start Timer"
                        ) {
                            if appState.toggleTaskTimer(item.id) {
                                dismiss()
                            }
                        }
                        .disabled(item.isCompleted)
                        Text("Timer changes are saved immediately and close this window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    checklistSection

                    Label(
                        "Priority, repeat, checklist, and time stay in BriefCal on this Mac. Only common title, completion, and due fields use the provider sync route.",
                        systemImage: "internaldrive"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            if let errorMessage {
                Divider()
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.06))
                    .accessibilityIdentifier("taskCenter.planningEditor.error")
            }

            Divider()

            HStack {
                Button("Cancel Staged Changes", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Planning") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 620)
        .accessibilityIdentifier("taskCenter.planningEditor")
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Checklist")
                    .font(.headline)
                Spacer()
                Text("Saved immediately")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(checklist) { checklistItem in
                HStack(spacing: 8) {
                    Button {
                        let completed = !checklistItem.isCompleted
                        if appState.setTaskChecklistItemCompleted(
                            id: checklistItem.id,
                            isCompleted: completed
                        ), let index = checklist.firstIndex(where: {
                            $0.id == checklistItem.id
                        }) {
                            checklist[index].isCompleted = completed
                        }
                    } label: {
                        Image(
                            systemName: checklistItem.isCompleted
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                    .buttonStyle(.plain)
                    Text(checklistItem.title)
                        .strikethrough(checklistItem.isCompleted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(role: .destructive) {
                        if appState.deleteTaskChecklistItem(
                            id: checklistItem.id
                        ) {
                            checklist.removeAll { $0.id == checklistItem.id }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete checklist item")
                }
            }
            HStack {
                TextField("Add checklist item", text: $checklistDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addChecklistItem)
                Button(action: addChecklistItem) {
                    Image(systemName: "plus")
                }
                .disabled(
                    checklistDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
    }

    private func addChecklistItem() {
        let title = checklistDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !title.isEmpty else { return }
        if appState.addTaskChecklistItem(item.id, title: title),
           let snapshot = try? appState.contextStore?.taskPlanning.snapshot(
            for: item.id
           ) {
            checklist = snapshot.1
            checklistDraft = ""
        } else {
            errorMessage = appState.localOperationError
                ?? "The checklist item could not be added."
        }
    }

    private func save() {
        guard !hasEstimate || (1...525_600).contains(estimatedMinutes) else {
            errorMessage = "Estimated duration must be between 1 minute and 365 days."
            return
        }
        if appState.saveTaskPlanning(
            item.id,
            priority: priority,
            isImportant: isImportant,
            repeatFrequency: repeatFrequency,
            repeatInterval: repeatInterval,
            estimatedMinutes: hasEstimate ? estimatedMinutes : nil
        ) {
            dismiss()
        } else {
            errorMessage = appState.localOperationError
                ?? "Task planning could not be saved."
        }
    }
}

struct TaskProviderRelinkPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    let itemID: TaskCenterItemID

    @State private var candidates = [TaskProviderLinkCandidate]()
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var selectedCandidateID: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading provider tasks…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn’t load provider tasks", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { loadCandidates() }
                    }
                } else if filteredCandidates.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty
                            ? "No remote tasks available"
                            : "No matching remote tasks",
                        systemImage: "checklist",
                        description: Text(
                            searchText.isEmpty
                                ? "Connect a provider and make sure at least one list contains a task that is not linked elsewhere."
                                : "Try a task title, description, list, account, or provider name."
                        )
                    )
                } else {
                    List(filteredCandidates) { candidate in
                        Button {
                            link(to: candidate)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(candidate.title)
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    if selectedCandidateID == candidate.id {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                if let details = candidate.details {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Label(
                                    "\(candidate.provider.title) · \(candidate.accountTitle) · \(candidate.listTitle)",
                                    systemImage: candidate.provider.settingsIcon
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let dueAt = candidate.dueAt {
                                    Label(
                                        CalendarEventDateFormatting.abbreviatedDateTime(
                                            dueAt,
                                            calendar: appState.calendar
                                        ),
                                        systemImage: "clock"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedCandidateID != nil)
                        .accessibilityLabel(
                            "Use \(candidate.title) from \(candidate.provider.title), \(candidate.listTitle), \(candidate.accountTitle)"
                        )
                    }
                }
            }
            .navigationTitle("Link Existing Remote Task")
            .searchable(text: $searchText, prompt: "Search tasks, lists, or accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
        .task { await fetchCandidates() }
    }

    private var filteredCandidates: [TaskProviderLinkCandidate] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            [$0.title, $0.details ?? "", $0.provider.title,
             $0.accountTitle, $0.listTitle]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func loadCandidates() {
        guard !isLoading else { return }
        Task { await fetchCandidates() }
    }

    @MainActor
    private func fetchCandidates() async {
        isLoading = true
        errorMessage = nil
        do {
            candidates = try await appState.taskProviderRelinkCandidates(
                for: itemID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func link(to candidate: TaskProviderLinkCandidate) {
        guard selectedCandidateID == nil else { return }
        selectedCandidateID = candidate.id
        Task {
            if await appState.relinkTaskProvider(itemID, to: candidate) {
                dismiss()
            } else {
                selectedCandidateID = nil
                errorMessage = appState.localOperationError
                    ?? "The remote task could not be linked."
            }
        }
    }
}

private extension EventTaskSection {
    var shortTitle: String {
        switch self {
        case .before: "Before"
        case .during: "During"
        case .after: "After"
        }
    }
}
