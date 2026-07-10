import SwiftUI

struct TaskCenterView: View {
    @ObservedObject var appState: AppState
    @State private var personalTaskDraftTitle = ""
    @State private var personalTaskDraftHasDueDate: Bool
    @State private var personalTaskDraftDueAt: Date

    init(appState: AppState) {
        self.appState = appState
        let tomorrow = appState.calendar.date(
            byAdding: .day,
            value: 1,
            to: appState.calendar.startOfDay(
                for: appState.taskReferenceDate
            )
        ) ?? appState.taskReferenceDate.addingTimeInterval(86_400)
        _personalTaskDraftHasDueDate = State(
            initialValue: appState.selectedTaskFilter == .upcoming
        )
        _personalTaskDraftDueAt = State(initialValue: tomorrow)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Task filter", selection: filterBinding) {
                    ForEach(TaskFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()

                Text("Local on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            content
        }
        .task {
            appState.refreshTaskCenter()
        }
        .onChange(of: appState.selectedTaskFilter) { _, filter in
            guard filter == .upcoming else { return }
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
        .accessibilityIdentifier("taskCenter.content")
    }

    private var filterBinding: Binding<TaskFilter> {
        Binding(
            get: { appState.selectedTaskFilter },
            set: { appState.selectTaskFilter($0) }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch appState.taskCenterState {
        case .unavailable:
            ContentUnavailableView(
                "Local task storage unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("KaosCal did not open its local database in this session.")
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if appState.selectedTaskFilter != .completed {
                    PersonalTaskComposer(
                        appState: appState,
                        filter: appState.selectedTaskFilter,
                        title: $personalTaskDraftTitle,
                        hasDueDate: $personalTaskDraftHasDueDate,
                        dueAt: $personalTaskDraftDueAt
                    )
                }

                if items.isEmpty {
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
                                    .stroke(KaosCalTheme.subtleDivider)
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
                description: Text("New personal tasks without a date appear here.")
            )
        case .upcoming:
            ContentUnavailableView(
                "No upcoming tasks",
                systemImage: "calendar.badge.checkmark",
                description: Text("Add a personal task with a future date.")
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
        switch appState.selectedTaskFilter {
        case .today:
            let start = appState.calendar.startOfDay(
                for: appState.taskReferenceDate
            )
            let overdue = items.filter { $0.dueAt.map { $0 < start } ?? false }
            let dueToday = items.filter { $0.dueAt.map { $0 >= start } ?? false }
            let noDate = items.filter { $0.dueAt == nil }
            return [
                TaskCenterGroup(title: "Overdue", items: overdue),
                TaskCenterGroup(title: "Today", items: dueToday),
                TaskCenterGroup(title: "No date", items: noDate)
            ].filter { !$0.items.isEmpty }
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
        case .completed:
            return [TaskCenterGroup(title: "Recently completed", items: items)]
        }
    }
}

private struct TaskCenterGroup {
    let title: String
    let items: [TaskCenterItem]
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
        .background(KaosCalTheme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
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
    @ObservedObject var appState: AppState
    let item: TaskCenterItem

    @State private var title: String
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var showsDueEditor = false
    @State private var personalDueEnabled: Bool
    @State private var personalDueDraft: Date
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
            .foregroundStyle(item.isCompleted ? KaosCalTheme.accent : .secondary)
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

                HStack(spacing: 6) {
                    if let dueAt = item.dueAt {
                        Label(
                            dueText(dueAt),
                            systemImage: "clock"
                        )
                    } else {
                        Label(
                            appState.selectedTaskFilter == .completed
                                ? "No date"
                                : "No date · Today",
                            systemImage: "tray"
                        )
                    }

                    Text("·")
                    sourceView
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isEditablePersonalTask {
                Button {
                    guard commitTitle() else { return }
                    showsDueEditor = true
                } label: {
                    Image(systemName: "calendar.badge.clock")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Edit due date")
                .popover(isPresented: $showsDueEditor) {
                    personalDueEditor
                }
            }

            Button {
                confirmsDeletion = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Delete task")
        }
        .padding(12)
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
        .alert("Delete this local task?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                if !appState.deleteTaskCenterItem(item.id) {
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The calendar event and its original data will not be changed.")
        }
    }

    @ViewBuilder
    private var sourceView: some View {
        switch item.source {
        case let .event(
            contextID,
            section,
            eventTitle,
            calendarTitle,
            sourceTitle,
            eventStart,
            eventEnd,
            isAllDay
        ):
            Button {
                guard commitTitle() else { return }
                Task {
                    await appState.openOriginalEvent(contextID: contextID)
                }
            } label: {
                Label(
                    "\(section.shortTitle) · \(eventTitle) · "
                        + "\(eventTimeText(start: eventStart, end: eventEnd, isAllDay: isAllDay)) · "
                        + "\(calendarTitle) · \(sourceTitle)",
                    systemImage: "calendar"
                )
            }
            .buttonStyle(.plain)
            .help("Open original event")
        case .personal:
            Label("Personal · Local", systemImage: "person.crop.circle")
        }
    }

    private var isEditablePersonalTask: Bool {
        guard !item.isCompleted else { return false }
        if case .personal = item.source { return true }
        return false
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

    private func dueText(_ date: Date) -> String {
        if case let .event(_, _, _, _, _, _, _, isAllDay) = item.source,
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

private extension EventTaskSection {
    var shortTitle: String {
        switch self {
        case .before: "Before"
        case .during: "During"
        case .after: "After"
        }
    }
}
