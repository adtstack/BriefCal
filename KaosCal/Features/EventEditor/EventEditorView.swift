import SwiftUI

private enum RecurrenceEndMode: String, CaseIterable, Identifiable {
    case never
    case onDate
    case afterOccurrences

    var id: Self { self }

    var title: String {
        switch self {
        case .never: "Never"
        case .onDate: "On date"
        case .afterOccurrences: "After count"
        }
    }
}

private extension CalendarRecurrenceFrequency {
    var editorTitle: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    func intervalUnit(count: Int) -> String {
        let singular: String = switch self {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
        return count == 1 ? singular : "\(singular)s"
    }
}

private extension CalendarRecurrenceWeekday {
    var shortTitle: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        }
    }
}

private extension CalendarEventMutationScope {
    var editorTitle: String {
        switch self {
        case .thisEvent: "This event"
        case .futureEvents: "This and future"
        }
    }
}

private extension CalendarEventRecurrence {
    var editorSummary: String {
        switch self {
        case .none:
            return "Does not repeat"
        case let .unsupported(snapshot):
            return snapshot.summary
        case let .basic(rule):
            var summary = "Every \(rule.interval) \(rule.frequency.intervalUnit(count: rule.interval))"
            if rule.frequency == .weekly, !rule.weekdays.isEmpty {
                let days = rule.weekdays
                    .sorted { $0.rawValue < $1.rawValue }
                    .map(\.shortTitle)
                    .joined(separator: ", ")
                summary += " on \(days)"
            }
            switch rule.end {
            case .never:
                break
            case let .onDate(date):
                summary += " until \(date.formatted(date: .abbreviated, time: .omitted))"
            case let .afterOccurrences(count):
                summary += " for \(count) occurrences"
            }
            return summary
        }
    }
}

private extension EventTaskSection {
    var editorTitle: String {
        switch self {
        case .before: "Before"
        case .during: "During"
        case .after: "After"
        }
    }
}

private extension EventChangeType {
    var editorTitle: String {
        switch self {
        case .created: "Created"
        case .detailsUpdated: "Details updated"
        case .moved: "Moved"
        case .recurrenceChanged: "Repeat changed"
        case .cancelled: "Cancelled"
        case .completed: "Completed"
        case .restored: "Restored"
        case .relinked: "Relinked"
        }
    }
}

struct EventEditorView: View {
    @ObservedObject var appState: AppState
    let session: CalendarEventEditorSession

    @State private var draft: CalendarEventDraft
    @State private var timeZoneInput: String
    @State private var wantsFloatingTime: Bool
    @State private var pendingTimeZoneIdentifier: String?
    @State private var showsTimeZoneChoice = false
    @State private var showsDeleteConfirmation = false
    @State private var validationMessage: String?
    @State private var mutationScope: CalendarEventMutationScope?
    @FocusState private var titleIsFocused: Bool

    init(appState: AppState, session: CalendarEventEditorSession) {
        self.appState = appState
        self.session = session
        _draft = State(initialValue: session.initialDraft)
        _timeZoneInput = State(
            initialValue: session.initialDraft.timeZoneIdentifier
                ?? session.initialDraft.referenceTimeZoneIdentifier
        )
        _wantsFloatingTime = State(
            initialValue: session.initialDraft.timeZoneIdentifier == nil
        )
        if case let .existing(event) = session.target,
           event.isRecurring {
            _mutationScope = State(initialValue: nil)
        } else {
            _mutationScope = State(initialValue: .thisEvent)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message = validationMessage {
                        editorError(message) {
                            validationMessage = nil
                        }
                    }
                    if let message = appState.eventEditorError {
                        editorError(
                            message,
                            dismiss: appState.clearEventEditorError
                        )
                    }

                    if let deletion = appState.pendingLinkedOriginalDeletion {
                        linkedOriginalDeletionReview(deletion)
                    } else if let preview = appState.pendingEventMutation {
                        mutationImpactReview(preview)
                    } else {
                        basicFields
                        Divider()
                        timeFields
                        Divider()
                        recurrenceFields
                        Divider()
                        originalNotesField

                        if case .existing = session.target {
                            Divider()
                            deleteSection
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(isBusy)
        .onAppear {
            titleIsFocused = true
        }
        .confirmationDialog(
            "How should the time zone change?",
            isPresented: $showsTimeZoneChoice,
            titleVisibility: .visible
        ) {
            Button(TimeZoneChangeBehavior.preserveLocalTime.title) {
                applyPendingTimeZone(.preserveLocalTime)
            }
            Button(TimeZoneChangeBehavior.preserveInstant.title) {
                applyPendingTimeZone(.preserveInstant)
            }
            Button("Cancel", role: .cancel) {
                restoreTimeZoneControls()
            }
        } message: {
            Text(timeZonePreviewMessage)
        }
        .alert(
            linkedDelete ? "Review original event deletion?" : "Delete this original calendar event?",
            isPresented: $showsDeleteConfirmation
        ) {
            if linkedDelete {
                Button("Review Deletion Impact") {
                    appState.prepareLinkedOriginalDeletion(
                        scope: mutationScope
                    )
                }
            } else {
                Button("Delete Original Event", role: .destructive) {
                    Task {
                        await appState.deleteEventEditorTarget(
                            scope: mutationScope
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                deleteConfirmationMessage
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isNewEvent ? "calendar.badge.plus" : "calendar.badge.clock")
                .foregroundStyle(KaosCalTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(isNewEvent ? "New Event" : "Edit Original Event")
                    .font(.title3.weight(.semibold))
                Text("Saved through macOS EventKit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
    }

    private var basicFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Event title", text: $draft.title)
                .font(.title3)
                .textFieldStyle(.roundedBorder)
                .focused($titleIsFocused)
                .accessibilityIdentifier("eventEditor.title")

            LabeledContent("Calendar") {
                Picker("Calendar", selection: $draft.calendarIdentifier) {
                    ForEach(session.writableCalendars) { calendar in
                        Text("\(calendar.title) · \(calendar.sourceTitle)")
                            .tag(calendar.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                .disabled(isBusy)
            }

            if case .linked = session.mutationContext {
                Label(
                    "A calendar move will show the linked Event Brief impact before EventKit is called. Its local notes and tasks keep the same context.",
                    systemImage: "link"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            TextField("Location", text: $draft.location)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("eventEditor.location")
        }
    }

    private var timeFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("All-day", isOn: allDayBinding)
                .disabled(isBusy)

            if draft.isAllDay {
                LabeledContent("Starts") {
                    DatePicker(
                        "Starts",
                        selection: allDayStartBinding,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.timeZone, draftCalendar.timeZone)
                }
                LabeledContent("Ends") {
                    DatePicker(
                        "Ends",
                        selection: allDayInclusiveEndBinding,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.timeZone, draftCalendar.timeZone)
                }
                Text("The end date shown here is inclusive; EventKit receives an exclusive next-day boundary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Starts") {
                    DatePicker(
                        "Starts",
                        selection: timedStartBinding,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .environment(\.timeZone, editorTimeZone)
                }
                LabeledContent("Ends") {
                    DatePicker(
                        "Ends",
                        selection: $draft.endDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .environment(\.timeZone, editorTimeZone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Floating time", isOn: $wantsFloatingTime)
                        .disabled(isBusy)

                    HStack(spacing: 8) {
                        TextField(
                            "IANA time zone, for example Asia/Seoul",
                            text: $timeZoneInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(wantsFloatingTime || isBusy)
                        Button("Apply") {
                            requestTimeZoneChange()
                        }
                        .disabled(isBusy || !hasUnappliedTimeZoneChoice)
                    }

                    if hasUnappliedTimeZoneChoice {
                        Text("Apply the time-zone choice before saving the event.")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }

                    Text(
                        draft.timeZoneIdentifier.map {
                            "Current meaning: fixed to \($0)"
                        } ?? "Current meaning: floating local time"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recurrenceFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Repeat", systemImage: "repeat")
                .font(.headline)

            if isExistingRecurring {
                LabeledContent("Apply changes") {
                    Picker("Apply changes", selection: $mutationScope) {
                        Text("Choose scope")
                            .tag(nil as CalendarEventMutationScope?)
                        Text("This event")
                            .tag(
                                CalendarEventMutationScope.thisEvent
                                    as CalendarEventMutationScope?
                            )
                        Text("This and future")
                            .tag(
                                CalendarEventMutationScope.futureEvents
                                    as CalendarEventMutationScope?
                            )
                            .disabled(futureScopeDisabled)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .disabled(isBusy)
                }

                Text(scopeHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch draft.recurrence {
            case let .unsupported(snapshot):
                Label(snapshot.summary, systemImage: "lock")
                    .font(.callout)
                Text(
                    "KaosCal preserves this complex rule without rewriting it. This occurrence may change ordinary fields; future-series and rule changes stay in Calendar.app."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            case .none, .basic:
                if recurrenceControlsVisible {
                    LabeledContent("Frequency") {
                        Picker(
                            "Frequency",
                            selection: recurrenceFrequencyBinding
                        ) {
                            Text("Does not repeat")
                                .tag(nil as CalendarRecurrenceFrequency?)
                            ForEach(CalendarRecurrenceFrequency.allCases, id: \.self) {
                                frequency in
                                Text(frequency.editorTitle)
                                    .tag(frequency as CalendarRecurrenceFrequency?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                        .disabled(!recurrenceRuleEditable || isBusy)
                    }

                    if case let .basic(rule) = draft.recurrence {
                        Stepper(
                            "Every \(rule.interval) \(rule.frequency.intervalUnit(count: rule.interval))",
                            value: recurrenceIntervalBinding,
                            in: 1...999
                        )
                        .disabled(!recurrenceRuleEditable || isBusy)

                        if rule.frequency == .weekly {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Weekdays")
                                    .font(.caption.weight(.medium))
                                HStack(spacing: 6) {
                                    ForEach(
                                        CalendarRecurrenceWeekday.allCases,
                                        id: \.self
                                    ) { weekday in
                                        Button(weekday.shortTitle) {
                                            toggleWeekday(weekday)
                                        }
                                        .buttonStyle(
                                            .borderedProminent
                                        )
                                        .tint(
                                            rule.weekdays.contains(weekday)
                                                ? KaosCalTheme.accent
                                                : Color.secondary.opacity(0.35)
                                        )
                                        .disabled(
                                            !recurrenceRuleEditable || isBusy
                                        )
                                    }
                                }
                            }
                        }

                        LabeledContent("Ends") {
                            Picker("Ends", selection: recurrenceEndModeBinding) {
                                ForEach(RecurrenceEndMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 180)
                            .disabled(!recurrenceRuleEditable || isBusy)
                        }

                        switch rule.end {
                        case .never:
                            EmptyView()
                        case .onDate:
                            LabeledContent("Last start") {
                                DatePicker(
                                    "Last start",
                                    selection: recurrenceEndDateBinding,
                                    in: draft.startDate...,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .environment(\.timeZone, draftCalendar.timeZone)
                                .disabled(!recurrenceRuleEditable || isBusy)
                            }
                        case .afterOccurrences:
                            Stepper(
                                "After \(recurrenceOccurrenceCount) occurrences",
                                value: recurrenceOccurrenceCountBinding,
                                in: 1...999
                            )
                            .disabled(!recurrenceRuleEditable || isBusy)
                        }
                    }
                } else {
                    Text(recurrenceSummary)
                        .font(.callout)
                    Text(
                        "An existing non-repeating event keeps its recurrence state in this editor. Create a repeating event here, or use Calendar.app to convert an existing single event into a series."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var originalNotesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Original event notes", systemImage: "calendar.badge.clock")
                .font(.headline)
            TextEditor(text: $draft.originalNotes)
                .frame(minHeight: 100)
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
                .accessibilityIdentifier("eventEditor.originalNotes")
            Text(
                "This field belongs to the Calendar.app event. Event Brief notes and tasks stay in KaosCal’s local database."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func mutationImpactReview(
        _ change: CalendarEventMutationPreview
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Review before writing", systemImage: "checkmark.shield")
                .font(.title3.weight(.semibold))
                .foregroundStyle(KaosCalTheme.accent)
            Text(
                "Nothing has been written to EventKit or the local database yet. Confirm applies this exact preview; Back returns to the editor."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                impactRow(
                    title: "Scope",
                    before: change.original.isRecurring
                        ? "Recurring occurrence"
                        : "Single event",
                    after: change.scope.editorTitle
                )

                if change.changedFields.contains(.calendar) {
                    impactRow(
                        title: "Calendar",
                        before: "\(change.original.calendarTitle) · \(change.original.sourceTitle)",
                        after: calendarLabel(
                            identifier: change.draft.calendarIdentifier
                        )
                    )
                }

                if change.changedFields.contains(.time) {
                    impactRow(
                        title: "Time",
                        before: CalendarEventDateFormatting.inspectorText(
                            for: change.original,
                            calendar: appState.calendar
                        ),
                        after: preview(change.draft)
                    )
                }

                if change.changedFields.contains(.recurrence) {
                    impactRow(
                        title: "Repeat",
                        before: change.original.recurrence.editorSummary,
                        after: change.draft.recurrence.editorSummary
                    )
                }
            }
            .padding(14)
            .background(
                KaosCalTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: 12)
            )

            if change.scope == .futureEvents {
                Label(
                    "EventKit may split the series and change identifiers for this and later occurrences.",
                    systemImage: "point.forward.to.point.capsulepath"
                )
                .font(.callout)
                .foregroundStyle(Color.orange)
            } else if change.original.isRecurring {
                Label(
                    "EventKit may detach this occurrence from its series and store it as an exception.",
                    systemImage: "arrow.triangle.branch"
                )
                .font(.callout)
                .foregroundStyle(Color.orange)
            }

            if let impact = change.impact {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Linked Event Brief", systemImage: "link")
                        .font(.headline)
                    Text(
                        impact.hasNotes
                            ? "Local notes: \(impact.notesCharacterCount) characters"
                            : "Local notes: none"
                    )
                    .font(.callout)
                    Text("Tasks: \(impact.taskCount)")
                        .font(.callout)

                    ForEach(impact.taskSections, id: \.section) { section in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(section.section.editorTitle) · \(section.count)")
                                .font(.caption.weight(.semibold))
                            if !section.titles.isEmpty {
                                Text(section.titles.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    if !impact.recentHistory.isEmpty {
                        Divider()
                        Text("Recent changes")
                            .font(.caption.weight(.semibold))
                        ForEach(impact.recentHistory.prefix(3)) { entry in
                            Text(
                                "\(entry.changeType.editorTitle) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
    }

    private func linkedOriginalDeletionReview(
        _ deletion: LinkedOriginalDeletionPreview
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Final deletion review", systemImage: "trash.slash")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.red)
            Text(
                "Nothing has been written yet. Back returns to the editor. The red confirmation below is the only action that deletes the original calendar event."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Original calendar event will be removed", systemImage: "calendar.badge.minus")
                    .font(.headline)
                    .foregroundStyle(Color.red)
                Text(deletion.original.title)
                    .font(.body.weight(.medium))
                Text(
                    CalendarEventDateFormatting.inspectorText(
                        for: deletion.original,
                        calendar: appState.calendar
                    )
                )
                .font(.callout)
                Text(
                    "\(deletion.original.calendarTitle) · \(deletion.original.sourceTitle)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    deletion.original.isRecurring
                        ? "Scope: This occurrence only"
                        : "Scope: Single event"
                )
                .font(.caption.weight(.semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )

            VStack(alignment: .leading, spacing: 10) {
                Label("Local Event Brief will be kept", systemImage: "archivebox")
                    .font(.headline)
                    .foregroundStyle(KaosCalTheme.accent)
                Text(
                    deletion.impact.hasNotes
                        ? "Local notes: \(deletion.impact.notesCharacterCount) characters"
                        : "Local notes: none"
                )
                .font(.callout)
                if deletion.impact.hasNotes {
                    Text(deletion.brief.context.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                Text("Local tasks: \(deletion.impact.taskCount)")
                    .font(.callout)

                ForEach(
                    deletion.impact.taskSections,
                    id: \.section
                ) { section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(section.section.editorTitle) · \(section.count)")
                            .font(.caption.weight(.semibold))
                        if !section.titles.isEmpty {
                            Text(section.titles.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                if !deletion.impact.recentHistory.isEmpty {
                    Divider()
                    Text("Recent changes")
                        .font(.caption.weight(.semibold))
                    ForEach(deletion.impact.recentHistory.prefix(3)) { entry in
                        Text(
                            "\(entry.changeType.editorTitle) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                KaosCalTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: 12)
            )

            if deletion.original.isRecurring {
                Label(
                    "Only this occurrence is removed. The series continues, and Exchange may store a deletion exception.",
                    systemImage: "arrow.triangle.branch"
                )
                .font(.callout)
                .foregroundStyle(Color.orange)
            }

            Label(
                "There is no Undo. The kept Brief will be marked Original deleted in Task Center, where its notes and tasks remain available.",
                systemImage: "arrow.uturn.backward.circle.badge.exclamationmark"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.red)
        }
        .accessibilityIdentifier("eventEditor.linkedDeletionReview")
    }

    private func impactRow(
        title: String,
        before: String,
        after: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(before)
                .font(.callout)
            Label(after, systemImage: "arrow.down")
                .font(.callout.weight(.medium))
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Delete Original Event", role: .destructive) {
                showsDeleteConfirmation = true
            }
            .disabled(deleteLocked || isBusy)

            if deleteLocked {
                Text(deleteLockMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if appState.pendingLinkedOriginalDeletion != nil {
                Text("Final confirmation deletes the original; the local Brief stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Back") {
                    appState.cancelPendingLinkedOriginalDeletion()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
                Button("Delete Original & Keep Brief", role: .destructive) {
                    Task {
                        await appState.confirmPendingLinkedOriginalDeletion()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy)
                .accessibilityIdentifier("eventEditor.confirmLinkedDeletion")
            } else if appState.pendingEventMutation != nil {
                Text("Confirm is the only action that writes this preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Back") {
                    appState.cancelPendingEventMutation()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
                Button("Confirm Change") {
                    Task {
                        await appState.confirmPendingEventMutation()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy)
            } else {
                Text(
                    "Attendee meetings and unsupported series rules stay in Calendar.app."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    appState.cancelEventEditor()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
                Button(isNewEvent ? "Create Event" : "Save Changes") {
                    validationMessage = nil
                    Task {
                        await appState.saveEventEditor(
                            draft,
                            scope: mutationScope
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
            }
        }
        .padding(20)
    }

    private var isNewEvent: Bool {
        if case .newEvent = session.target { return true }
        return false
    }

    private var isBusy: Bool {
        appState.eventEditorOperationState != .idle
    }

    private var deleteLocked: Bool {
        return isExistingRecurring && mutationScope == nil
    }

    private var linkedDelete: Bool {
        if case .linked = session.mutationContext { return true }
        return false
    }

    private var saveDisabled: Bool {
        isBusy
            || hasUnappliedTimeZoneChoice
            || draft.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            || (isExistingRecurring && mutationScope == nil)
    }

    private var existingEvent: DisplayEvent? {
        if case let .existing(event) = session.target { return event }
        return nil
    }

    private var isExistingRecurring: Bool {
        existingEvent?.isRecurring == true
    }

    private var recurrenceControlsVisible: Bool {
        isNewEvent || isExistingRecurring
    }

    private var recurrenceRuleEditable: Bool {
        isNewEvent
            || (isExistingRecurring && mutationScope == .futureEvents)
    }

    private var futureScopeDisabled: Bool {
        guard let event = existingEvent else { return false }
        if event.isDetached { return true }
        if case .unsupported = event.recurrence { return true }
        if case .linked = session.mutationContext { return true }
        return false
    }

    private var scopeHelpText: String {
        if futureScopeDisabled {
            if case .linked = session.mutationContext {
                return "This and future is disabled because future series writes can split identifiers for multiple occurrence Briefs. This event remains available."
            }
            return "This and future is unavailable for detached occurrences or complex rules. Use Calendar.app for that series change."
        }
        switch mutationScope {
        case .none:
            return "Choose a scope before Save. KaosCal does not select a series-wide default."
        case .thisEvent:
            return "Only this occurrence changes. Its recurrence rule is preserved."
        case .futureEvents:
            return "This occurrence and later occurrences may become a new series. A final impact review appears before writing."
        }
    }

    private var recurrenceSummary: String {
        draft.recurrence.editorSummary
    }

    private var deleteLockMessage: String {
        return "Choose whether to delete this occurrence or this and future occurrences."
    }

    private var deleteConfirmationMessage: String {
        if linkedDelete {
            return "This first step writes nothing. Review exactly which local notes and tasks will be kept before the separate final confirmation."
        }
        if isExistingRecurring {
            switch mutationScope {
            case .thisEvent:
                return "This removes only this occurrence through EventKit. The series continues, and Exchange may store a deletion exception."
            case .futureEvents:
                return "This removes this and future occurrences through EventKit. Earlier occurrences remain."
            case .none:
                return "Choose the recurring deletion scope before continuing."
            }
        }
        return "This removes the event through EventKit."
    }

    private var recurrenceFrequencyBinding:
        Binding<CalendarRecurrenceFrequency?> {
        Binding(
            get: {
                if case let .basic(rule) = draft.recurrence {
                    return rule.frequency
                }
                return nil
            },
            set: { frequency in
                guard recurrenceRuleEditable else { return }
                guard let frequency else {
                    draft.recurrence = .none
                    return
                }
                var rule: BasicRecurrenceRule
                if case let .basic(existing) = draft.recurrence {
                    rule = existing
                    rule.frequency = frequency
                } else {
                    rule = BasicRecurrenceRule(frequency: frequency)
                }
                if frequency == .weekly, rule.weekdays.isEmpty {
                    let rawWeekday = draftCalendar.component(
                        .weekday,
                        from: draft.startDate
                    )
                    if let weekday = CalendarRecurrenceWeekday(
                        rawValue: rawWeekday
                    ) {
                        rule.weekdays = [weekday]
                    }
                }
                if frequency != .weekly {
                    rule.weekdays = []
                }
                draft.recurrence = .basic(rule)
            }
        )
    }

    private var recurrenceIntervalBinding: Binding<Int> {
        Binding(
            get: {
                if case let .basic(rule) = draft.recurrence {
                    return rule.interval
                }
                return 1
            },
            set: { value in
                updateBasicRecurrence { $0.interval = value }
            }
        )
    }

    private var recurrenceEndModeBinding: Binding<RecurrenceEndMode> {
        Binding(
            get: {
                guard case let .basic(rule) = draft.recurrence else {
                    return .never
                }
                switch rule.end {
                case .never: return .never
                case .onDate: return .onDate
                case .afterOccurrences: return .afterOccurrences
                }
            },
            set: { mode in
                updateBasicRecurrence { rule in
                    switch mode {
                    case .never:
                        rule.end = .never
                    case .onDate:
                        let end = draftCalendar.date(
                            byAdding: .month,
                            value: 1,
                            to: draft.startDate
                        ) ?? draft.startDate
                        rule.end = .onDate(end)
                    case .afterOccurrences:
                        rule.end = .afterOccurrences(10)
                    }
                }
            }
        )
    }

    private var recurrenceEndDateBinding: Binding<Date> {
        Binding(
            get: {
                guard case let .basic(rule) = draft.recurrence,
                      case let .onDate(date) = rule.end else {
                    return draft.startDate
                }
                return date
            },
            set: { value in
                updateBasicRecurrence { $0.end = .onDate(value) }
            }
        )
    }

    private var recurrenceOccurrenceCount: Int {
        guard case let .basic(rule) = draft.recurrence,
              case let .afterOccurrences(count) = rule.end else {
            return 10
        }
        return count
    }

    private var recurrenceOccurrenceCountBinding: Binding<Int> {
        Binding(
            get: { recurrenceOccurrenceCount },
            set: { value in
                updateBasicRecurrence {
                    $0.end = .afterOccurrences(value)
                }
            }
        )
    }

    private func updateBasicRecurrence(
        _ update: (inout BasicRecurrenceRule) -> Void
    ) {
        guard recurrenceRuleEditable,
              case var .basic(rule) = draft.recurrence else {
            return
        }
        update(&rule)
        draft.recurrence = .basic(rule)
    }

    private func toggleWeekday(_ weekday: CalendarRecurrenceWeekday) {
        updateBasicRecurrence { rule in
            if rule.weekdays.contains(weekday) {
                guard rule.weekdays.count > 1 else { return }
                rule.weekdays.remove(weekday)
            } else {
                rule.weekdays.insert(weekday)
            }
        }
    }

    private func calendarLabel(identifier: String) -> String {
        guard let calendar = session.writableCalendars.first(where: {
            $0.id == identifier
        }) else {
            return "Selected calendar"
        }
        return "\(calendar.title) · \(calendar.sourceTitle)"
    }

    private var editorTimeZone: TimeZone {
        draft.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? draftCalendar.timeZone
    }

    private var draftCalendar: Calendar {
        draft.wallTimeCalendar(fallback: appState.calendar)
    }

    private var hasUnappliedTimeZoneChoice: Bool {
        if wantsFloatingTime {
            return draft.timeZoneIdentifier != nil
        }
        let cleaned = timeZoneInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return cleaned != (draft.timeZoneIdentifier ?? "")
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { draft.isAllDay },
            set: { value in
                var conversionCalendar = draftCalendar
                if value,
                   let timeZone = draft.timeZoneIdentifier.flatMap(
                    TimeZone.init(identifier:)
                   ) {
                    conversionCalendar.timeZone = timeZone
                }
                draft = draft.changingAllDay(
                    to: value,
                    calendar: conversionCalendar
                )
                timeZoneInput = draft.timeZoneIdentifier
                    ?? draft.referenceTimeZoneIdentifier
                wantsFloatingTime = draft.timeZoneIdentifier == nil
            }
        )
    }

    private var timedStartBinding: Binding<Date> {
        Binding(
            get: { draft.startDate },
            set: { value in
                let duration = max(
                    draft.endDate.timeIntervalSince(draft.startDate),
                    60
                )
                draft.startDate = value
                draft.endDate = value.addingTimeInterval(duration)
            }
        )
    }

    private var allDayStartBinding: Binding<Date> {
        Binding(
            get: { draft.startDate },
            set: { value in
                let start = draftCalendar.startOfDay(for: value)
                draft.startDate = start
                if draft.endDate <= start {
                    draft.endDate = draftCalendar.date(
                        byAdding: .day,
                        value: 1,
                        to: start
                    ) ?? start.addingTimeInterval(86_400)
                }
            }
        )
    }

    private var allDayInclusiveEndBinding: Binding<Date> {
        Binding(
            get: {
                draftCalendar.date(
                    byAdding: .day,
                    value: -1,
                    to: draft.endDate
                ) ?? draft.startDate
            },
            set: { value in
                let inclusive = max(
                    draftCalendar.startOfDay(for: value),
                    draftCalendar.startOfDay(for: draft.startDate)
                )
                draft.endDate = draftCalendar.date(
                    byAdding: .day,
                    value: 1,
                    to: inclusive
                ) ?? inclusive.addingTimeInterval(86_400)
            }
        )
    }

    private func requestTimeZoneChange() {
        validationMessage = nil
        let newIdentifier: String?
        if wantsFloatingTime {
            newIdentifier = nil
        } else {
            let cleaned = timeZoneInput.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard TimeZone(identifier: cleaned) != nil else {
                validationMessage = CalendarEventWriteError
                    .invalidTimeZone(cleaned)
                    .localizedDescription
                return
            }
            newIdentifier = cleaned
        }
        guard newIdentifier != draft.timeZoneIdentifier else { return }
        pendingTimeZoneIdentifier = newIdentifier
        showsTimeZoneChoice = true
    }

    private func applyPendingTimeZone(
        _ behavior: TimeZoneChangeBehavior
    ) {
        do {
            draft = try draft.changingTimeZone(
                to: pendingTimeZoneIdentifier,
                behavior: behavior,
                displayCalendar: draftCalendar
            )
            timeZoneInput = draft.timeZoneIdentifier
                ?? draft.referenceTimeZoneIdentifier
            wantsFloatingTime = draft.timeZoneIdentifier == nil
            pendingTimeZoneIdentifier = nil
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private var timeZonePreviewMessage: String {
        let local = try? draft.changingTimeZone(
            to: pendingTimeZoneIdentifier,
            behavior: .preserveLocalTime,
            displayCalendar: draftCalendar
        )
        let instant = try? draft.changingTimeZone(
            to: pendingTimeZoneIdentifier,
            behavior: .preserveInstant,
            displayCalendar: draftCalendar
        )
        return "Keep local time: \(preview(local))\nKeep instant: \(preview(instant))"
    }

    private func preview(_ draft: CalendarEventDraft?) -> String {
        guard let draft else { return "Unavailable" }
        var calendar = draft.wallTimeCalendar(fallback: appState.calendar)
        calendar.timeZone = draft.timeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? calendar.timeZone
        return "\(CalendarEventDateFormatting.abbreviatedDateTime(draft.startDate, calendar: calendar)) – \(CalendarEventDateFormatting.abbreviatedDateTime(draft.endDate, calendar: calendar))"
    }

    private func restoreTimeZoneControls() {
        pendingTimeZoneIdentifier = nil
        wantsFloatingTime = draft.timeZoneIdentifier == nil
        timeZoneInput = draft.timeZoneIdentifier
            ?? draft.referenceTimeZoneIdentifier
    }

    private func editorError(
        _ message: String,
        dismiss: @escaping () -> Void
    ) -> some View {
        LocalOperationErrorView(message: message, dismiss: dismiss)
    }
}
