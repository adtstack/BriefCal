import SwiftUI

struct EventBriefView: View {
    @ObservedObject var appState: AppState
    let event: DisplayEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            storageAndDestinationBadges

            if let error = appState.localOperationError {
                LocalOperationErrorView(
                    message: error,
                    dismiss: appState.clearLocalOperationError
                )
            }

            switch appState.eventBriefState {
            case .noSelection:
                EmptyView()
            case .unavailable:
                Label(
                    "Local Event Brief storage is unavailable",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
                .foregroundStyle(.secondary)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn’t load Event Brief", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        appState.reloadSelectedEventBrief()
                    }
                }
            case let .confirmationRequired(contextIDs):
                identityBlockedContent(contextIDs: contextIDs)
            case .empty:
                editableContent(
                    tasks: [],
                    lifecycleStatus: inferredLifecycleStatus,
                    hasStoredBrief: false
                )
            case let .loaded(snapshot):
                editableContent(
                    tasks: snapshot.tasks,
                    lifecycleStatus: snapshot.context.lifecycleStatus,
                    hasStoredBrief: true
                )
            }
        }
        .onDisappear {
            appState.flushPendingEventNotes()
        }
        .accessibilityIdentifier("eventBrief.content")
    }

    private var storageAndDestinationBadges: some View {
        VStack(alignment: .leading, spacing: 6) {
            localEditingBadge
            taskDestinationBadge
        }
    }

    private var localEditingBadge: some View {
        Label("Event Brief notes · On this Mac", systemImage: "macbook")
            .font(.caption.weight(.medium))
            .foregroundStyle(KaosCalTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KaosCalTheme.accentSoft, in: Capsule())
            .accessibilityIdentifier("eventBrief.notesStorage")
    }

    @ViewBuilder
    private var taskDestinationBadge: some View {
        if let destination = appState.taskDestinationSummary(
            calendarIdentifier: event.calendarIdentifier
        ) {
            let title = appState.taskDestinationTitle(for: destination)
            let isAuthorized = destination.authorizationState == .authorized
            Label(
                isAuthorized
                    ? "New tasks · \(title)"
                    : "New tasks · \(title) · \(destination.authorizationState.title)",
                systemImage: isAuthorized
                    ? destination.provider.settingsIcon
                    : "exclamationmark.triangle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(
                isAuthorized ? KaosCalTheme.accent : Color.orange
            )
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isAuthorized
                    ? KaosCalTheme.accentSoft
                    : Color.orange.opacity(0.12),
                in: Capsule()
            )
            .accessibilityIdentifier("eventBrief.taskDestination")
        } else {
            Label("New tasks · Local only", systemImage: "link.slash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.45), in: Capsule())
                .accessibilityIdentifier("eventBrief.taskDestination")
        }
    }

    private func identityBlockedContent(
        contextIDs: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Similar local Event Brief found",
                systemImage: "link.badge.plus"
            )
            .font(.headline)
            Text(
                "Editing is paused so KaosCal does not attach local notes or tasks "
                    + "to the wrong occurrence. The calendar event was not changed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(contextIDs.enumerated()), id: \.element) { index, contextID in
                Button("Review Relink Candidate \(index + 1)") {
                    appState.reviewSelectedEventRelinkCandidate(
                        contextID: contextID
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func editableContent(
        tasks: [EventTask],
        lifecycleStatus: EventLifecycleStatus,
        hasStoredBrief: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if lifecycleStatus == .completed {
                endedEventBanner(hasStoredBrief: hasStoredBrief)
            } else if lifecycleStatus == .cancelled {
                cancelledEventBanner
            }

            ForEach(EventTaskSection.allCases, id: \.self) { section in
                EventTaskSectionView(
                    appState: appState,
                    event: event,
                    section: section,
                    tasks: tasks.filter { $0.section == section }
                )
            }

            Divider()

            notesEditor

            ContextReferenceSection(appState: appState)
        }
    }

    private var cancelledEventBanner: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Calendar event cancelled", systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
            Text(
                "The calendar provider reported this status. Local notes and tasks were kept; KaosCal did not delete or change the calendar event."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityIdentifier("eventBrief.eventCancelled")
    }

    private var inferredLifecycleStatus: EventLifecycleStatus {
        let eventEnd = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: appState.calendar
        ).end
        return appState.taskReferenceDate >= eventEnd
            ? .completed
            : .scheduled
    }

    private func endedEventBanner(hasStoredBrief: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Event ended", systemImage: "calendar.badge.clock")
                .font(.headline)
            Text(hasStoredBrief ? storedBriefEndedCopy : emptyBriefEndedCopy)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            KaosCalTheme.accentSoft.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityIdentifier("eventBrief.eventEnded")
    }

    private var storedBriefEndedCopy: String {
        "This Event Brief stays on this Mac. Unfinished After tasks remain "
            + "in Today or Upcoming. They are also collected in After Review."
    }

    private var emptyBriefEndedCopy: String {
        "Add an After task or note to create a local Event Brief. "
            + "Follow-up tasks are collected in After Review."
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            TextEditor(text: notesBinding)
                .font(.body)
                .frame(minHeight: 88)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.75),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(KaosCalTheme.subtleDivider)
                }
                .accessibilityIdentifier("eventBrief.notes")

            HStack(spacing: 6) {
                notesStatus
                Spacer()
                if case .failed = appState.notesSaveState {
                    Button("Retry") {
                        appState.retrySelectedEventNotes()
                    }
                    .controlSize(.small)
                }
            }
            .font(.caption)
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { appState.selectedEventNotes },
            set: { appState.updateSelectedEventNotes($0) }
        )
    }

    @ViewBuilder
    private var notesStatus: some View {
        switch appState.notesSaveState {
        case .idle:
            Text("Changes save locally on this Mac")
                .foregroundStyle(.secondary)
        case .pending:
            Text("Waiting to save…")
                .foregroundStyle(.secondary)
        case .saving:
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .saved:
            Label("Saved on this Mac", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case let .failed(message):
            Label("Not saved · \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

private struct ContextReferenceSection: View {
    @ObservedObject var appState: AppState
    @State private var urlString = ""
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("References", systemImage: "link")
                .font(.headline)
            Text("Links stay local to this Event Brief. KaosCal does not copy remote page content.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(appState.selectedReferences) { reference in
                HStack(spacing: 8) {
                    Link(reference.titleCache.isEmpty ? reference.url.absoluteString : reference.titleCache, destination: reference.url)
                        .lineLimit(1)
                    Spacer()
                    Text(reference.state.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        _ = appState.deleteSelectedReference(id: reference.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("https://…", text: $urlString)
                TextField("Title (optional)", text: $title)
                Button("Add") {
                    if appState.addSelectedReference(urlString: urlString, title: title) {
                        urlString = ""
                        title = ""
                    }
                }
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .accessibilityIdentifier("eventBrief.references")
    }
}

private struct EventTaskSectionView: View {
    @ObservedObject var appState: AppState
    let event: DisplayEvent
    let section: EventTaskSection
    let tasks: [EventTask]

    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(section.title, systemImage: section.symbolName)
                .font(.headline)

            ForEach(tasks) { task in
                EventTaskRow(
                    appState: appState,
                    event: event,
                    task: task
                )
            }

            HStack(spacing: 8) {
                TextField("Add \(section.title.lowercased()) task", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                    .accessibilityIdentifier("eventBrief.\(section.rawValue).newTask")
                Button(action: addTask) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add \(section.title) task")
            }
        }
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        appState.addSelectedEventTask(section: section, title: title)
        if appState.localOperationError == nil {
            newTitle = ""
        }
    }
}

private struct EventTaskRow: View {
    @ObservedObject var appState: AppState
    let event: DisplayEvent
    let task: EventTask

    @State private var title: String
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var showsProviderLinkPicker = false
    @State private var showsDueEditor = false
    @FocusState private var isEditing: Bool

    init(appState: AppState, event: DisplayEvent, task: EventTask) {
        self.appState = appState
        self.event = event
        self.task = task
        _title = State(initialValue: task.title)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                guard commitTitle() else { return }
                appState.setSelectedEventTaskCompleted(
                    id: task.id,
                    isCompleted: !task.isCompleted
                )
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(task.isCompleted ? KaosCalTheme.accent : .secondary)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                TextField("Task title", text: $title)
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .onSubmit {
                        _ = commitTitle()
                    }
                    .strikethrough(task.isCompleted)

                Button {
                    guard commitTitle() else { return }
                    showsDueEditor = true
                } label: {
                    Label(dueDescription, systemImage: "calendar.badge.clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit this task’s fixed or event-relative due time")
                .accessibilityIdentifier("eventBrief.task.\(task.id).due")

                providerStatus
            }

            Spacer(minLength: 4)

            Menu {
                Button("Link Existing Provider Task…") {
                    guard commitTitle() else { return }
                    showsProviderLinkPicker = true
                }
                Button("Edit Due…") {
                    guard commitTitle() else { return }
                    showsDueEditor = true
                }
                Section("Move to") {
                    ForEach(EventTaskSection.allCases, id: \.self) { section in
                        Button(section.title) {
                            guard commitTitle() else { return }
                            appState.moveSelectedEventTask(id: task.id, to: section)
                        }
                        .disabled(section == task.section)
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmsDeletion = true
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 2)
        .onChange(of: isEditing) { wasEditing, isEditing in
            if wasEditing && !isEditing {
                commitTitle()
            }
        }
        .onChange(of: task.title) { _, newValue in
            guard !isEditing else { return }
            title = newValue
        }
        .onDisappear {
            if !isDeleting {
                _ = commitTitle()
            }
        }
        .alert("Delete this local task?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    if !(await appState.deleteSelectedEventTaskAfterRemoteDelete(id: task.id)) {
                        isDeleting = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The calendar event will not be changed.")
        }
        .sheet(isPresented: $showsProviderLinkPicker) {
            TaskProviderRelinkPicker(
                appState: appState,
                itemID: .eventTask(
                    taskID: task.id,
                    contextID: task.contextID
                )
            )
        }
        .sheet(isPresented: $showsDueEditor) {
            EventTaskDueEditor(
                appState: appState,
                event: event,
                task: task
            )
        }
    }

    private var providerStatus: some View {
        Group {
            providerStatusContent
        }
        .accessibilityIdentifier(
            "eventBrief.task.\(task.id).providerStatus"
        )
    }

    @ViewBuilder
    private var providerStatusContent: some View {
        if let status = appState.eventTaskProviderStatus(
            eventTaskID: task.id
        ) {
            if let link = status.providerLink {
                HStack(spacing: 4) {
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
                    .foregroundStyle(
                        link.needsAttention ? Color.orange : Color.secondary
                    )
                }
                .font(.caption2)
                .lineLimit(2)
                .help(
                    link.recoveryMessage
                        ?? "This Event Brief task is linked to \(link.provider.title)."
                )
            } else if status.isLocalOnly {
                Label(
                    "Local only · provider sync disabled for this task",
                    systemImage: "link.slash"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if let destination = appState.taskDestinationSummary(
                calendarIdentifier: event.calendarIdentifier
            ) {
                Label(
                    "\(appState.taskDestinationTitle(for: destination)) · Not linked",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .help(
                    "This task has not been linked to the calendar’s configured destination. Use the task menu to link an existing provider task."
                )
            } else {
                Label(
                    "Local only · no task destination",
                    systemImage: "link.slash"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        } else {
            Label(
                "Provider status unavailable",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var dueDescription: String {
        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: appState.calendar
        )
        let due = task.effectiveDueDate(
            eventStart: range.start,
            eventEnd: range.end
        )
        let value = due.map {
            event.isAllDay
                ? CalendarEventDateFormatting.abbreviatedDate(
                    $0,
                    calendar: appState.calendar
                )
                : CalendarEventDateFormatting.abbreviatedDateTime(
                    $0,
                    calendar: appState.calendar
                )
        } ?? "Unscheduled"

        switch task.dueKind {
        case .none:
            return "Follows event · \(value)"
        case .relative:
            return "Relative · \(value)"
        case .fixed:
            return "Fixed · \(value)"
        }
    }

    @discardableResult
    private func commitTitle() -> Bool {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            title = task.title
            return false
        }
        guard cleaned != task.title else { return true }
        return appState.renameTaskCenterItem(
            .eventTask(taskID: task.id, contextID: task.contextID),
            title: cleaned
        )
    }
}

private struct EventTaskDueEditor: View {
    private enum Schedule: String, CaseIterable, Identifiable {
        case followsEvent
        case fixed
        case beforeStart
        case atStart
        case atEnd
        case afterEnd

        var id: String { rawValue }

        var title: String {
            switch self {
            case .followsEvent: "Follows task section"
            case .fixed: "Fixed date and time"
            case .beforeStart: "Before event starts"
            case .atStart: "When event starts"
            case .atEnd: "When event ends"
            case .afterEnd: "After event ends"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    let event: DisplayEvent
    let task: EventTask

    @State private var schedule: Schedule
    @State private var fixedDate: Date
    @State private var offsetMinutes: Int
    @State private var validationMessage: String?

    init(appState: AppState, event: DisplayEvent, task: EventTask) {
        self.appState = appState
        self.event = event
        self.task = task
        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: appState.calendar
        )
        switch task.due {
        case .none:
            _schedule = State(initialValue: .followsEvent)
            _fixedDate = State(initialValue: range.start)
            _offsetMinutes = State(initialValue: 30)
        case let .fixed(date):
            _schedule = State(initialValue: .fixed)
            _fixedDate = State(initialValue: date)
            _offsetMinutes = State(initialValue: 30)
        case let .relative(anchor, offset):
            switch anchor {
            case .beforeStart:
                _schedule = State(initialValue: .beforeStart)
            case .atStart:
                _schedule = State(initialValue: .atStart)
            case .atEnd:
                _schedule = State(initialValue: .atEnd)
            case .afterEnd:
                _schedule = State(initialValue: .afterEnd)
            }
            _fixedDate = State(initialValue: range.start)
            _offsetMinutes = State(initialValue: max(1, offset))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Task Due", systemImage: "calendar.badge.clock")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Picker("Schedule", selection: $schedule) {
                    ForEach(Schedule.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                if schedule == .fixed {
                    DatePicker(
                        "Due",
                        selection: $fixedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if schedule == .beforeStart || schedule == .afterEnd {
                    HStack {
                        TextField(
                            "Minutes",
                            value: $offsetMinutes,
                            format: .number
                        )
                        .frame(width: 90)
                        Text("minutes")
                        Spacer()
                        Menu("Presets") {
                            Button("15 minutes") { offsetMinutes = 15 }
                            Button("30 minutes") { offsetMinutes = 30 }
                            Button("1 hour") { offsetMinutes = 60 }
                            Button("1 day") { offsetMinutes = 1_440 }
                        }
                    }
                }

                LabeledContent("Result", value: previewText)

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 4)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 390)
        .accessibilityIdentifier("eventBrief.taskDueEditor")
    }

    private var due: EventTaskDue? {
        switch schedule {
        case .followsEvent:
            return EventTaskDue.none
        case .fixed:
            return .fixed(fixedDate)
        case .beforeStart:
            guard offsetMinutes > 0, offsetMinutes <= 525_600 else {
                return nil
            }
            return .relative(
                anchor: .beforeStart,
                offsetMinutes: offsetMinutes
            )
        case .atStart:
            return .relative(anchor: .atStart, offsetMinutes: 0)
        case .atEnd:
            return .relative(anchor: .atEnd, offsetMinutes: 0)
        case .afterEnd:
            guard offsetMinutes > 0, offsetMinutes <= 525_600 else {
                return nil
            }
            return .relative(
                anchor: .afterEnd,
                offsetMinutes: offsetMinutes
            )
        }
    }

    private var previewText: String {
        guard let due else { return "Enter 1–525600 minutes" }
        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: appState.calendar
        )
        let date: Date?
        switch due {
        case .none:
            date = task.section == .after ? range.end : range.start
        case let .fixed(value):
            date = value
        case let .relative(anchor, offset):
            switch anchor {
            case .beforeStart:
                date = range.start.addingTimeInterval(TimeInterval(-offset * 60))
            case .atStart:
                date = range.start
            case .atEnd:
                date = range.end
            case .afterEnd:
                date = range.end.addingTimeInterval(TimeInterval(offset * 60))
            }
        }
        guard let date else { return "Unscheduled" }
        return CalendarEventDateFormatting.abbreviatedDateTime(
            date,
            calendar: appState.calendar
        )
    }

    private func save() {
        guard let due else {
            validationMessage = "Enter an offset from 1 minute to 365 days."
            return
        }
        validationMessage = nil
        if appState.setSelectedEventTaskDue(id: task.id, due: due) {
            dismiss()
        } else {
            validationMessage = appState.localOperationError
                ?? "The due time could not be saved."
        }
    }
}

private extension EventTaskSection {
    var title: String {
        switch self {
        case .before: "Before"
        case .during: "During"
        case .after: "After"
        }
    }

    var symbolName: String {
        switch self {
        case .before: "arrow.up.circle"
        case .during: "circle"
        case .after: "arrow.down.circle"
        }
    }
}

struct LocalOperationErrorView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
