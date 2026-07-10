import SwiftUI

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

                    basicFields
                    Divider()
                    timeFields
                    Divider()
                    originalNotesField

                    if case .existing = session.target {
                        Divider()
                        deleteSection
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 580, height: 700)
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
            "Delete this original calendar event?",
            isPresented: $showsDeleteConfirmation
        ) {
            Button("Delete Original Event", role: .destructive) {
                Task {
                    await appState.deleteEventEditorTarget()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the event through EventKit. KaosCal only enables this Phase 5 action when no local Event Brief is linked."
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
                .disabled(calendarMoveLocked || isBusy)
            }

            if calendarMoveLocked {
                Label(
                    "This event has a local Event Brief. Moving it to another calendar waits for the Phase 6 safe-move flow.",
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

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Delete Original Event", role: .destructive) {
                showsDeleteConfirmation = true
            }
            .disabled(deleteLocked || isBusy)

            if deleteLocked {
                Text(
                    "This event has a local Event Brief. Original deletion waits for the Phase 7 orphan review flow so local notes and tasks do not become hidden."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Recurring events and meetings with attendees stay in Calendar.app for now.")
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
                    await appState.saveEventEditor(draft)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                isBusy
                    || hasUnappliedTimeZoneChoice
                    || draft.title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            )
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

    private var calendarMoveLocked: Bool {
        guard !isNewEvent else { return false }
        if case .linked = session.mutationContext { return true }
        return false
    }

    private var deleteLocked: Bool {
        if case .linked = session.mutationContext { return true }
        return false
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
