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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Task views")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Local on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Task filter", selection: filterBinding) {
                    ForEach(TaskFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 540)
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
                if !appState.recoveryBriefs.isEmpty {
                    RecoveryBriefSection(
                        appState: appState,
                        briefs: appState.recoveryBriefs
                    )
                }

                if appState.selectedTaskFilter == .today
                    || appState.selectedTaskFilter == .upcoming {
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
        case .afterReview:
            return [TaskCenterGroup(
                title: "Follow-up from ended events",
                items: items
            )]
        case .completed:
            return [TaskCenterGroup(title: "Recently completed", items: items)]
        }
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
                                .foregroundStyle(KaosCalTheme.accent)
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
                    .stroke(KaosCalTheme.subtleDivider)
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

                if let providerLink = item.providerLink {
                    providerLinkView(providerLink)
                } else if item.isProviderLocalOnly {
                    Label("Local only · provider sync disabled for this task", systemImage: "link.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

            if isEventTask, item.providerLink?.needsAttention != true {
                taskProviderActionMenu
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
        .accessibilityIdentifier(taskRowAccessibilityIdentifier)
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
            Button("Keep Local Only") {
                resolveProviderLink {
                    appState.keepTaskLocalOnly(item.id)
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

    private var taskProviderActionMenu: some View {
        Menu {
            Button("Link to Existing Remote Task…") {
                showsRelinkPicker = true
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
        } label: {
            Image(systemName: item.providerLink == nil ? "link.badge.plus" : "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .accessibilityLabel("Task provider actions")
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
            Button {
                guard commitTitle() else { return }
                Task {
                    await appState.openOriginalEvent(contextID: contextID)
                }
            } label: {
                Label(
                    eventLinkPrefix
                        + "\(role.title) · \(section.shortTitle) · "
                        + "\(eventTitle) · "
                        + "\(eventTimeText(start: eventStart, end: eventEnd, isAllDay: isAllDay)) · "
                        + "\(calendarTitle) · \(sourceTitle)",
                    systemImage: "calendar"
                )
            }
            .buttonStyle(.plain)
            .help(
                "\(eventSourceHelp). \(role.title) role · "
                    + "\(calendarTitle) · \(sourceTitle)"
            )
            .accessibilityIdentifier(
                "taskCenter.eventSource.\(contextID)"
            )
        case .personal:
            Label(
                "Personal task · Local",
                systemImage: "person.crop.circle"
            )
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
        if item.wasOriginalDeletedByKaosCal,
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
        if item.wasOriginalDeletedByKaosCal,
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

private struct TaskProviderRelinkPicker: View {
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
