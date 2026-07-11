import SwiftUI

struct EventBriefView: View {
    @ObservedObject var appState: AppState
    let event: DisplayEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            localEditingBadge

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

    private var localEditingBadge: some View {
        Label("Event Brief · Local editable", systemImage: "macbook")
            .font(.caption.weight(.medium))
            .foregroundStyle(KaosCalTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KaosCalTheme.accentSoft, in: Capsule())
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

                Text(dueDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Menu {
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
                if !appState.deleteSelectedEventTask(id: task.id) {
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The calendar event will not be changed.")
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
