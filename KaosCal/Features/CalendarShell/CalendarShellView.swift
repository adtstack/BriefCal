import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CalendarShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var appState: AppState
    let bootstrapRecoveryState: BootstrapRecoveryOperationState
    let bootstrapDatabaseURL: URL?
    let recoverBootstrap: ((URL) -> Void)?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var rightSidebarMode: RightSidebarMode = .eventDetails

    init(
        appState: AppState,
        bootstrapRecoveryState: BootstrapRecoveryOperationState = .idle,
        bootstrapDatabaseURL: URL? = nil,
        recoverBootstrap: ((URL) -> Void)? = nil
    ) {
        self.appState = appState
        self.bootstrapRecoveryState = bootstrapRecoveryState
        self.bootstrapDatabaseURL = bootstrapDatabaseURL
        self.recoverBootstrap = recoverBootstrap
    }

    var body: some View {
        Group {
            if case let .failed(message) = appState.localContextStoreState {
                if appState.contextStore == nil {
                    BootstrapLocalDataRecoveryView(
                        message: message,
                        operationState: bootstrapRecoveryState,
                        databaseURL: bootstrapDatabaseURL,
                        recover: recoverBootstrap
                    )
                } else {
                    RuntimeLocalDataFailureView(message: message)
                }
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
            RightSidebarView(
                appState: appState,
                mode: $rightSidebarMode
            )
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
                        appState.taskProviderCoordinator?.requestProviderSync()
                    } label: {
                        Label("Reload tasks", systemImage: "arrow.clockwise")
                    }
                } else {
                    Button {
                        Task {
                            await appState.reloadCalendarData()
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
                    appState.taskProviderCoordinator?.refresh()
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

struct BootstrapLocalDataRecoveryView: View {
    let message: String
    let operationState: BootstrapRecoveryOperationState
    let databaseURL: URL?
    let recover: ((URL) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(
                "Local data needs recovery",
                systemImage: "externaldrive.badge.exclamationmark"
            )
            .font(.title2.weight(.semibold))

            Text(
                "KaosCal stopped before loading or changing local data. The existing SQLite database and sidecars have not been deleted. Choose a backup created by this KaosCal schema to restore local Event Briefs and tasks. Calendar and Exchange events are never changed by this recovery."
            )
            .fixedSize(horizontal: false, vertical: true)

            GroupBox("Startup error") {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            if case let .failed(recoveryMessage) = operationState {
                Label(recoveryMessage, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bootstrapRecovery.error")
            }

            if let databaseURL {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Preserved database location")
                        .font(.caption.weight(.semibold))
                    Text(databaseURL.path(percentEncoded: false))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack {
                if let databaseURL {
                    Button("Show Folder in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: databaseURL
                                .deletingLastPathComponent().path
                        )
                    }
                }
                Spacer()
                Button {
                    selectBackup()
                } label: {
                    if operationState == .recovering {
                        Label {
                            Text("Restoring…")
                        } icon: {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Label(
                            "Restore From Backup…",
                            systemImage: "arrow.counterclockwise.circle"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(operationState == .recovering || recover == nil)
                .accessibilityIdentifier("bootstrapRecovery.restore")
            }

            Text(
                "Before replacement, KaosCal moves the failed database file family into a private Recovery folder. If installation of the validated backup fails, it attempts to put every original file back."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
        .accessibilityIdentifier("bootstrapRecovery.view")
    }

    private func selectBackup() {
        let panel = NSOpenPanel()
        panel.title = "Restore KaosCal After Startup Failure"
        panel.prompt = "Validate and Restore"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let archiveURL = panel.url else { return }
        recover?(archiveURL)
    }
}

private struct RuntimeLocalDataFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(
                "Local data is locked for this session",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        } description: {
            Text(
                "KaosCal already opened its local database before this failure, so bootstrap file replacement is disabled while that database writer is alive. Calendar and local changes remain blocked. Preserve the displayed database and Backups folder, quit KaosCal, then follow the startup recovery screen if the next launch cannot open the database.\n\n\(message)"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityIdentifier("runtimeLocalDataFailure.view")
    }
}

private struct SidebarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

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
                    HStack(spacing: 6) {
                        Picker(
                            "Active Calendar Set",
                            selection: calendarSetSelection
                        ) {
                            Label(
                                "All Calendars",
                                systemImage: CalendarSetFilter.all.symbolName
                            )
                            .tag(CalendarSetFilter.all)

                            if !appState.savedCalendarSets.isEmpty {
                                Section("Saved Sets") {
                                    ForEach(appState.savedCalendarSets) { set in
                                        Label(
                                            set.name,
                                            systemImage: "calendar.badge.checkmark"
                                        )
                                        .tag(CalendarSetFilter.saved(set.id))
                                    }
                                }
                            }

                            Section("Smart Role Filters") {
                                ForEach(CalendarRole.allCases) { role in
                                    Label(
                                        role.title,
                                        systemImage: role.symbolName
                                    )
                                    .tag(CalendarSetFilter.role(role))
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("sidebar.calendarSet")
                        .help(
                            "Switch between saved calendar combinations and role-based Smart Filters"
                        )

                        Button {
                            appState.selectedSettingsPane = .calendarSets
                            openSettings()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .help("Manage Calendar Sets in Settings")
                        .accessibilityLabel("Manage Calendar Sets")
                        .accessibilityIdentifier("sidebar.calendarSet.manage")
                    }
                }

                Section("Calendars") {
                    if appState.calendarSources.isEmpty {
                        Label("No calendars loaded", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.calendarSources) { source in
                            let role = appState.calendarRole(for: source)
                            let usage = appState.calendarUsagePolicy(for: source)
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

                                Button {
                                    _ = appState.setCalendarVisibility(
                                        !usage.isVisible,
                                        for: source
                                    )
                                } label: {
                                    Image(
                                        systemName: usage.isVisible
                                            ? "eye.fill"
                                            : "eye.slash"
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(
                                    usage.isVisible
                                        ? KaosCalTheme.accent
                                        : .secondary
                                )
                                .help(
                                    usage.isVisible
                                        ? "Disable this calendar in every Calendar Set"
                                        : "Enable this calendar for Calendar Sets"
                                )
                                .accessibilityLabel(
                                    usage.isVisible
                                        ? "Disable \(source.title) calendar in every Calendar Set"
                                        : "Enable \(source.title) calendar for Calendar Sets"
                                )
                                .accessibilityIdentifier(
                                    "sidebar.calendar.\(source.id).visibility"
                                )

                                Image(
                                    systemName: usage.blocksAvailability
                                        ? "clock.fill"
                                        : "clock"
                                )
                                .foregroundStyle(.secondary)
                                .help(
                                    usage.blocksAvailability
                                        ? "Events in this calendar can block available time"
                                        : "Events in this calendar do not block available time"
                                )
                                .accessibilityLabel(
                                    usage.blocksAvailability
                                        ? "Blocks available time"
                                        : "Does not block available time"
                                )

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

    func coverageInterval(calendar: Calendar) -> DateInterval? {
        guard let first = days.first?.date,
              let last = days.last?.date,
              let end = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: last)
              ) else {
            return nil
        }
        return DateInterval(
            start: calendar.startOfDay(for: first),
            end: end
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

private struct MiniMonthSummaryRequest: Hashable {
    let monthStart: Date
    let canReadEvents: Bool
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
        .task(id: summaryRequest) {
            guard let interval = grid.coverageInterval(
                calendar: appState.calendar
            ) else { return }
            await appState.loadMiniMonthEventSummary(in: interval)
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

    private var summaryRequest: MiniMonthSummaryRequest {
        MiniMonthSummaryRequest(
            monthStart: grid.monthStart,
            canReadEvents: appState.calendarAuthorizationState.canReadEvents
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
        let eventSummary = appState.miniMonthEventSummary(for: day.date)
        let eventCount = eventSummary.eventCount ?? 0

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
                .offset(y: eventCount > 0 ? -2 : 0)

                if eventCount > 0 {
                    Circle()
                        .fill(isFocused ? Color.white : KaosCalTheme.accent)
                        .frame(width: 3, height: 3)
                        .offset(y: 8)
                        .opacity(day.isInDisplayedMonth ? 1 : 0.55)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
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
                isToday: isToday,
                eventSummary: eventSummary
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
        isToday: Bool,
        eventSummary: MiniMonthDayEventSummary
    ) -> String {
        var values: [String] = []
        if isFocused { values.append("Focused date") }
        if isToday { values.append("Today") }
        if !day.isInDisplayedMonth { values.append("Adjacent month") }
        values.append(eventSummary.accessibilityDescription)
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

            if let message = appState.calendarSetTemporaryDisplayMessage,
               appState.selectedSection != .tasks {
                HStack(spacing: 10) {
                    Label(message, systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Return to \(appState.selectedCalendarSetTitle)") {
                        appState.endTemporaryCalendarSetDisplay()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("calendarSet.temporaryDisplay.end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(KaosCalTheme.accentSoft)
                .accessibilityIdentifier("calendarSet.temporaryDisplay")

                Divider()
            }

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
                HStack(spacing: 6) {
                    Text("\(items.count) tasks")
                    if appState.isTaskCenterRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing tasks")
                    }
                }
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
                .overlay(alignment: .top) {
                    if appState.visibleEvents.isEmpty {
                        Label(
                            appState.calendarWorkspaceEmptyMessage,
                            systemImage: appState.calendarWorkspaceEmptySymbolName
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("calendar.emptyPeriod")
                    }
                }
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
                appState.calendarWorkspaceEmptyMessage,
                systemImage: appState.calendarWorkspaceEmptySymbolName,
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

private enum RightSidebarMode: String, CaseIterable, Identifiable {
    case eventDetails
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eventDetails: "Details"
        case .tasks: "Tasks"
        }
    }
}

private struct RightSidebarView: View {
    @ObservedObject var appState: AppState
    @Binding var mode: RightSidebarMode

    var body: some View {
        VStack(spacing: 0) {
            Picker("Right sidebar", selection: $mode) {
                ForEach(RightSidebarMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch mode {
            case .eventDetails:
                EventInspectorView(appState: appState)
            case .tasks:
                if let coordinator = appState.taskProviderCoordinator {
                    ProviderTaskSidebarView(
                        appState: appState,
                        coordinator: coordinator
                    )
                } else {
                    ContentUnavailableView(
                        "Task storage unavailable",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text(
                            "KaosCal could not open local task data in this session."
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("rightSidebar.\(mode.rawValue)")
    }
}

enum ProviderTaskSidebarStatusFilter: String, CaseIterable, Identifiable {
    case open
    case completed
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .completed: "Completed"
        case .all: "All"
        }
    }
}

struct ProviderTaskSidebarListIdentity: Hashable, Codable {
    let provider: TaskProviderKind
    let accountKey: String
    let listID: String

    var storageValue: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return data.base64EncodedString()
    }

    init(
        provider: TaskProviderKind,
        accountKey: String,
        listID: String
    ) {
        self.provider = provider
        self.accountKey = accountKey
        self.listID = listID
    }

    init?(storageValue: String) {
        guard let data = Data(base64Encoded: storageValue),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = value
    }
}

struct ProviderTaskSidebarListOption: Equatable, Identifiable {
    let identity: ProviderTaskSidebarListIdentity
    let listTitle: String
    let accountTitle: String

    var id: ProviderTaskSidebarListIdentity { identity }
    var provider: TaskProviderKind { identity.provider }
}

enum ProviderTaskSidebarFiltering {
    static let supportedProviders: Set<TaskProviderKind> = [
        .appleReminders,
        .googleTasks,
        .todoist,
        .microsoftToDo
    ]

    static func listOptions(
        from lists: [RemoteTaskList],
        fallbackItems: [ProviderTaskListItem] = [],
        fallbackProviders: Set<TaskProviderKind> = supportedProviders
    ) -> [ProviderTaskSidebarListOption] {
        var options = [
            ProviderTaskSidebarListIdentity: ProviderTaskSidebarListOption
        ]()
        for list in lists where supportedProviders.contains(list.provider) {
            let identity = ProviderTaskSidebarListIdentity(
                provider: list.provider,
                accountKey: list.accountKey,
                listID: list.id
            )
            options[identity] = ProviderTaskSidebarListOption(
                identity: identity,
                listTitle: list.title,
                accountTitle: list.sourceTitle
            )
        }
        for item in fallbackItems
        where supportedProviders.contains(item.provider)
            && fallbackProviders.contains(item.provider) {
            let identity = listIdentity(for: item)
            guard options[identity] == nil else { continue }
            options[identity] = ProviderTaskSidebarListOption(
                identity: identity,
                listTitle: item.listTitle,
                accountTitle: item.accountTitle
            )
        }
        return options.values.sorted(by: optionPrecedes)
    }

    static func items(
        _ items: [ProviderTaskListItem],
        list selectedList: ProviderTaskSidebarListIdentity?,
        status: ProviderTaskSidebarStatusFilter,
        query: String
    ) -> [ProviderTaskListItem] {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return items.filter { item in
            if let selectedList,
               listIdentity(for: item) != selectedList {
                return false
            }
            switch status {
            case .open where item.isCompleted:
                return false
            case .completed where !item.isCompleted:
                return false
            case .open, .completed, .all:
                break
            }
            guard !normalizedQuery.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(normalizedQuery)
                || (item.details?.localizedCaseInsensitiveContains(
                    normalizedQuery
                ) ?? false)
        }
    }

    static func availableItems(
        _ items: [ProviderTaskListItem],
        lists: [RemoteTaskList],
        fallbackProviders: Set<TaskProviderKind>
    ) -> [ProviderTaskListItem] {
        let knownLists = Set(
            lists.lazy
                .filter { supportedProviders.contains($0.provider) }
                .map {
                    ProviderTaskSidebarListIdentity(
                        provider: $0.provider,
                        accountKey: $0.accountKey,
                        listID: $0.id
                    )
                }
        )
        return items.filter { item in
            fallbackProviders.contains(item.provider)
                || knownLists.contains(listIdentity(for: item))
        }
    }

    static func normalizedSelection(
        _ selection: ProviderTaskSidebarListIdentity?,
        available options: [ProviderTaskSidebarListOption],
        isLoading: Bool
    ) -> ProviderTaskSidebarListIdentity? {
        guard let selection else { return nil }
        guard !isLoading else { return selection }
        return options.contains { $0.identity == selection }
            ? selection
            : nil
    }

    static func listIdentity(
        for item: ProviderTaskListItem
    ) -> ProviderTaskSidebarListIdentity {
        ProviderTaskSidebarListIdentity(
            provider: item.provider,
            accountKey: item.accountKey,
            listID: item.listID
        )
    }

    static func providerRank(_ provider: TaskProviderKind) -> Int {
        switch provider {
        case .appleReminders: 0
        case .microsoftToDo: 1
        case .googleTasks: 2
        case .todoist: 3
        }
    }

    private static func optionPrecedes(
        _ lhs: ProviderTaskSidebarListOption,
        _ rhs: ProviderTaskSidebarListOption
    ) -> Bool {
        if lhs.provider != rhs.provider {
            return providerRank(lhs.provider) < providerRank(rhs.provider)
        }
        let listOrder = lhs.listTitle.localizedCaseInsensitiveCompare(
            rhs.listTitle
        )
        if listOrder != .orderedSame {
            return listOrder == .orderedAscending
        }
        let accountOrder = lhs.accountTitle.localizedCaseInsensitiveCompare(
            rhs.accountTitle
        )
        if accountOrder != .orderedSame {
            return accountOrder == .orderedAscending
        }
        if lhs.identity.accountKey != rhs.identity.accountKey {
            return lhs.identity.accountKey < rhs.identity.accountKey
        }
        return lhs.identity.listID < rhs.identity.listID
    }
}

enum ProviderTaskSidebarSort: String, CaseIterable, Identifiable {
    case dueDate
    case priority
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueDate: "Due date"
        case .priority: "Priority"
        case .title: "Title"
        }
    }
}

enum ProviderTaskSidebarOrdering {
    static func precedes(
        _ lhs: ProviderTaskListItem,
        _ rhs: ProviderTaskListItem,
        by sort: ProviderTaskSidebarSort
    ) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted
        }
        switch sort {
        case .dueDate:
            switch (lhs.dueAt, rhs.dueAt) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
        case .priority:
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
        case .title:
            break
        }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

struct ProviderTaskEditorPresentation: Identifiable {
    enum Mode {
        case create(preferredList: RemoteTaskList?)
        case edit(ProviderTaskListItem)
    }

    let id = UUID()
    let mode: Mode

    var editingTaskID: String? {
        guard case let .edit(item) = mode else { return nil }
        return item.id
    }

    var targetKey: String {
        editingTaskID.map { "edit:\($0)" } ?? "create"
    }
}

struct ProviderTaskSidebarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var coordinator: TaskProviderCoordinator
    @AppStorage private var statusFilterStorage: String
    @AppStorage private var sortStorage: String
    @AppStorage private var selectedListStorage: String
    @AppStorage private var calendarSetOnly: Bool
    @State private var searchText = ""
    @State private var isRequestingRemindersAccess = false
    @State private var editorPresentation: ProviderTaskEditorPresentation?
    @State private var pendingEditorPresentation: ProviderTaskEditorPresentation?
    @State private var editorHasUnsavedChanges = false
    @State private var showsEditorTransitionPrompt = false
    @State private var isSelectingTasks = false
    @State private var selectedTaskIDs = Set<String>()
    @State private var isPerformingBulkAction = false
    @State private var bulkErrorMessage: String?
    @State private var isUndoing = false
    @State private var undoErrorMessage: String?
    @FocusState private var focusedTaskID: String?

    init(
        appState: AppState,
        coordinator: TaskProviderCoordinator,
        preferences: UserDefaults = .standard
    ) {
        _appState = ObservedObject(wrappedValue: appState)
        _coordinator = ObservedObject(wrappedValue: coordinator)
        _statusFilterStorage = AppStorage(
            wrappedValue: ProviderTaskSidebarStatusFilter.open.rawValue,
            "tasks.sidebar.statusFilter",
            store: preferences
        )
        _sortStorage = AppStorage(
            wrappedValue: ProviderTaskSidebarSort.dueDate.rawValue,
            "tasks.sidebar.sort",
            store: preferences
        )
        _selectedListStorage = AppStorage(
            wrappedValue: "",
            "tasks.sidebar.selectedList.v1",
            store: preferences
        )
        _calendarSetOnly = AppStorage(
            wrappedValue: false,
            "tasks.sidebar.currentCalendarSetOnly.v1",
            store: preferences
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if showsTaskControls {
                taskControls
                Divider()
            }

            if isSelectingTasks {
                bulkActionBar
                Divider()
            }

            if coordinator.sidebarUndoState != nil || undoErrorMessage != nil {
                undoBar
                Divider()
            }

            taskContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            coordinator.refreshIfNeeded()
            if remindersAuthorizationState == .notDetermined {
                await connectAppleReminders()
            }
        }
        .onChange(of: listOptions.map(\.identity)) { _, _ in
            normalizeListSelection()
        }
        .onChange(of: isLoading) { _, _ in
            normalizeListSelection()
        }
        .onChange(of: combinedItems.map(\.id)) { _, availableIDs in
            selectedTaskIDs.formIntersection(Set(availableIDs))
            if selectedTaskIDs.isEmpty && displayedItems.isEmpty {
                isSelectingTasks = false
            }
            if let editingTaskID = editorPresentation?.editingTaskID,
               !availableIDs.contains(editingTaskID) {
                closeEditorImmediately()
            }
        }
        .onChange(of: coordinator.sidebarUndoState?.id) { _, _ in
            undoErrorMessage = nil
        }
        .onChange(of: calendarSetOnly) { _, _ in
            selectedTaskIDs.formIntersection(Set(displayedItems.map(\.id)))
        }
        .accessibilityIdentifier("rightSidebar.tasks")
    }

    @ViewBuilder
    private var taskContent: some View {
        if let presentation = editorPresentation {
            VSplitView {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 120)
                    .layoutPriority(1)

                editorDrawer(presentation)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 240,
                        idealHeight: 340,
                        maxHeight: 560
                    )
            }
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
    }

    private func editorDrawer(
        _ presentation: ProviderTaskEditorPresentation
    ) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 36, height: 4)
                .padding(.top, 7)
                .padding(.bottom, 5)
                .accessibilityHidden(true)

            if showsEditorTransitionPrompt {
                editorTransitionPrompt
                Divider()
            }

            ProviderTaskEditorSheet(
                coordinator: coordinator,
                mode: presentation.mode,
                writableLists: writableTaskLists,
                presentationStyle: .drawer,
                onCancel: requestEditorClose,
                onComplete: finishEditorOperation,
                onDirtyChange: { editorHasUnsavedChanges = $0 }
            )
            .id(presentation.id)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("tasks.drawer")
    }

    private var editorTransitionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unsaved changes", systemImage: "pencil.and.list.clipboard")
                .font(.subheadline.weight(.semibold))
            Text(editorTransitionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Keep Editing") {
                    pendingEditorPresentation = nil
                    showsEditorTransitionPrompt = false
                }
                Button("Discard", role: .destructive) {
                    discardCurrentEditor()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .accessibilityIdentifier("tasks.drawer.unsavedChanges")
    }

    private var editorTransitionMessage: String {
        if let pendingEditorPresentation {
            return "Save below to continue to \(editorTargetTitle(pendingEditorPresentation)), or discard the current draft."
        }
        return "Save below to keep this draft, or discard it to close the editor."
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Tasks", systemImage: "checklist")
                .font(.headline)
            Spacer()
            if remindersAuthorizationState == .authorized {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Apple Reminders connected")
                    .help("Apple Reminders connected")
            }
            Button {
                toggleSelectionMode()
            } label: {
                Image(systemName: isSelectingTasks ? "checkmark" : "checkmark.circle")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .disabled(combinedItems.isEmpty || isPerformingBulkAction)
            .help(isSelectingTasks ? "Finish selecting tasks" : "Select multiple tasks")
            .accessibilityLabel(isSelectingTasks ? "Finish selecting tasks" : "Select multiple tasks")
            .accessibilityIdentifier("tasks.selectionMode")
            Button {
                presentEditor(
                    ProviderTaskEditorPresentation(
                        mode: .create(preferredList: preferredCreationList)
                    )
                )
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .disabled(!canCreateTask)
            .help(createTaskHelp)
            .accessibilityLabel("New task")
            .accessibilityIdentifier("tasks.create")
            Button {
                coordinator.requestProviderSync()
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .disabled(isLoading)
            .accessibilityLabel(
                isLoading ? "Refreshing tasks" : "Refresh tasks"
            )
            .help(
                coordinator.hasDeferredOAuthCredentialAccess
                    ? "Refresh tasks. macOS may ask to access saved provider credentials."
                    : "Refresh tasks"
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var taskControls: some View {
        VStack(spacing: 10) {
            if !listOptions.isEmpty {
                listFilterMenu
            }
            searchField
            Picker("Task status", selection: $statusFilterStorage) {
                ForEach(ProviderTaskSidebarStatusFilter.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("tasks.statusFilter")

            viewControls

            Toggle(isOn: $calendarSetOnly) {
                Label(
                    "Only tasks linked to \(appState.selectedCalendarSetTitle)",
                    systemImage: "calendar.badge.checkmark"
                )
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .help("Unlinked tasks are hidden because KaosCal cannot safely infer which Calendar Set they belong to.")
            .accessibilityIdentifier("tasks.currentCalendarSetOnly")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var listFilterMenu: some View {
        Menu {
            Button {
                selectedList = nil
            } label: {
                Label(
                    "All Lists (\(listOptions.count))",
                    systemImage: selectedList == nil
                        ? "checkmark"
                        : "rectangle.stack"
                )
            }
            Divider()
            ForEach(supportedSidebarProviders, id: \.self) { provider in
                let options = listOptions.filter { $0.provider == provider }
                if !options.isEmpty {
                    Section(provider.title) {
                        ForEach(options) { option in
                            Button {
                                selectedList = option.identity
                            } label: {
                                Label(
                                    "\(displayListTitle(for: option)) — \(option.accountTitle) (\(taskCount(for: option.identity)))",
                                    systemImage: selectedList == option.identity
                                        ? "checkmark"
                                        : "list.bullet"
                                )
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(KaosCalTheme.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedListOption.map { displayListTitle(for: $0) }
                         ?? "All Lists (\(listOptions.count))")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(selectedListSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Task list filter")
        .accessibilityValue(listFilterAccessibilityValue)
        .accessibilityIdentifier("tasks.listFilter")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search tasks", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("tasks.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear task search")
                .accessibilityIdentifier("tasks.search.clear")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var viewControls: some View {
        if !combinedItems.isEmpty {
            HStack(spacing: 8) {
                Text(taskResultSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing tasks")
                } else if !coordinator.activeSidebarMutationIDs.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Syncing task changes")
                } else if let lastSync = coordinator.lastSidebarSyncAt {
                    Text("Updated \(lastSync.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Menu {
                    Picker("Sort by", selection: $sortStorage) {
                        ForEach(ProviderTaskSidebarSort.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Task list options")
                .accessibilityIdentifier("tasks.listOptions")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !displayedItems.isEmpty {
            taskList(displayedItems)
        } else if isInitialContentLoading {
            ProgressView("Refreshing tasks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let contentFailureMessage {
            failureContent(contentFailureMessage)
        } else if hasSearchQuery {
            noSearchResultsContent
        } else if coordinator.hasDeferredOAuthCredentialAccess {
            oauthSyncContent
        } else if shouldShowStandaloneRemindersConnection {
            remindersConnectionContent
        } else if relevantProvidersUnavailable {
            unavailableContent
        } else {
            emptyContent
        }
    }

    private var combinedItems: [ProviderTaskListItem] {
        ProviderTaskSidebarFiltering.availableItems(
            coordinator.allSidebarTaskItems,
            lists: coordinator.taskLists,
            fallbackProviders: fallbackListProviders
        )
    }

    private var statusFilter: ProviderTaskSidebarStatusFilter {
        ProviderTaskSidebarStatusFilter(rawValue: statusFilterStorage) ?? .open
    }

    private var sort: ProviderTaskSidebarSort {
        ProviderTaskSidebarSort(rawValue: sortStorage) ?? .dueDate
    }

    private var selectedList: ProviderTaskSidebarListIdentity? {
        get {
            ProviderTaskSidebarListIdentity(
                storageValue: selectedListStorage
            )
        }
        nonmutating set {
            selectedListStorage = newValue?.storageValue ?? ""
        }
    }

    private var supportedSidebarProviders: [TaskProviderKind] {
        [.appleReminders, .microsoftToDo, .googleTasks, .todoist]
    }

    private var listOptions: [ProviderTaskSidebarListOption] {
        ProviderTaskSidebarFiltering.listOptions(
            from: coordinator.taskLists,
            fallbackItems: combinedItems,
            fallbackProviders: fallbackListProviders
        )
    }

    private var fallbackListProviders: Set<TaskProviderKind> {
        var providers = coordinator.taskListRefreshFailures
        if case .loading = coordinator.appleRemindersTaskState {
            providers.insert(.appleReminders)
        }
        if case .loading = coordinator.microsoftToDoTaskState {
            providers.insert(.microsoftToDo)
        }
        if case .loading = coordinator.googleTasksTaskState {
            providers.insert(.googleTasks)
        }
        if case .loading = coordinator.todoistTaskState {
            providers.insert(.todoist)
        }
        if coordinator.isRefreshingOAuthTaskLists {
            providers.insert(.microsoftToDo)
            providers.insert(.googleTasks)
            providers.insert(.todoist)
        }
        return providers
    }

    private var selectedListOption: ProviderTaskSidebarListOption? {
        guard let selectedList else { return nil }
        return listOptions.first { $0.identity == selectedList }
    }

    private var writableTaskLists: [RemoteTaskList] {
        coordinator.taskLists
            .filter {
                coordinator.isSidebarListWritable($0)
            }
            .sorted {
                if $0.sourceTitle == $1.sourceTitle {
                    return $0.title.localizedCaseInsensitiveCompare($1.title)
                        == .orderedAscending
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare(
                    $1.sourceTitle
                ) == .orderedAscending
            }
    }

    private var preferredCreationList: RemoteTaskList? {
        guard let selectedList else {
            return writableTaskLists.count == 1
                ? writableTaskLists.first
                : nil
        }
        return writableTaskLists.first {
            $0.provider == selectedList.provider
                && $0.accountKey == selectedList.accountKey
                && $0.id == selectedList.listID
        }
    }

    private var canCreateTask: Bool {
        guard !writableTaskLists.isEmpty else { return false }
        guard selectedList != nil else { return true }
        return preferredCreationList != nil
    }

    private var createTaskHelp: String {
        if let provider = selectedList?.provider,
           coordinator.taskListRefreshFailures.contains(provider) {
            return "Refresh \(provider.title) lists before creating a task."
        }
        if writableTaskLists.isEmpty {
            return "No writable task list is available."
        }
        return "Create a task"
    }

    private var selectedListSubtitle: String {
        guard let selectedListOption else {
            let providers = Set(listOptions.map(\.provider))
            if providers.count == 1, let provider = providers.first {
                return provider.title
            }
            return "All connected providers"
        }
        return "\(selectedListOption.provider.title) · \(selectedListOption.accountTitle)"
    }

    private var listFilterAccessibilityValue: String {
        guard let selectedListOption else {
            return "All \(listOptions.count) lists"
        }
        return "\(displayListTitle(for: selectedListOption)), \(selectedListOption.provider.title), \(selectedListOption.accountTitle)"
    }

    private func displayListTitle(
        for option: ProviderTaskSidebarListOption
    ) -> String {
        let duplicates = listOptions.filter {
            $0.provider == option.provider
                && $0.identity.accountKey == option.identity.accountKey
                && $0.listTitle == option.listTitle
        }
        guard duplicates.count > 1 else { return option.listTitle }
        let ordered = duplicates.sorted { $0.identity.listID < $1.identity.listID }
        guard let index = ordered.firstIndex(where: { $0.id == option.id }) else {
            return option.listTitle
        }
        return "\(option.listTitle) · List \(index + 1)"
    }

    private var showsTaskControls: Bool {
        !listOptions.isEmpty || !combinedItems.isEmpty
    }

    private var displayedItems: [ProviderTaskListItem] {
        ProviderTaskSidebarFiltering.items(
            calendarScopedItems,
            list: selectedList,
            status: statusFilter,
            query: searchText
        )
    }

    private var calendarScopedItems: [ProviderTaskListItem] {
        guard calendarSetOnly else { return combinedItems }
        return combinedItems.filter { item in
            guard let link = coordinator.calendarLink(for: item) else {
                return false
            }
            return appState.currentCalendarSetIncludes(
                calendarIdentifier: link.calendarIdentifier
            )
        }
    }

    private var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var taskResultSummary: String {
        let count = displayedItems.count
        return hasSearchQuery
            ? "\(count) \(count == 1 ? "result" : "results")"
            : "\(count) \(count == 1 ? "task" : "tasks")"
    }

    private func taskCount(
        for identity: ProviderTaskSidebarListIdentity
    ) -> Int {
        combinedItems.lazy.filter {
            ProviderTaskSidebarFiltering.listIdentity(for: $0) == identity
                && (!calendarSetOnly || coordinator.calendarLink(for: $0).map {
                    appState.currentCalendarSetIncludes(
                        calendarIdentifier: $0.calendarIdentifier
                    )
                } == true)
        }.count
    }

    private func normalizeListSelection() {
        selectedList = ProviderTaskSidebarFiltering.normalizedSelection(
            selectedList,
            available: listOptions,
            isLoading: shouldDeferListSelectionNormalization
        )
    }

    private var shouldDeferListSelectionNormalization: Bool {
        guard let provider = selectedList?.provider else { return isLoading }
        return isLoading
            || coordinator.taskListRefreshFailures.contains(provider)
    }

    private var remindersAuthorizationState: TaskProviderAuthorizationState {
        coordinator.authorizationState(for: .appleReminders)
    }

    private var isLoading: Bool {
        if coordinator.isRefreshingOAuthTaskLists { return true }
        if case .loading = coordinator.appleRemindersTaskState { return true }
        if case .loading = coordinator.googleTasksTaskState { return true }
        if case .loading = coordinator.todoistTaskState { return true }
        if case .loading = coordinator.microsoftToDoTaskState { return true }
        return false
    }

    private var isContentLoading: Bool {
        guard let provider = selectedList?.provider else { return isLoading }
        switch provider {
        case .appleReminders:
            if case .loading = coordinator.appleRemindersTaskState { return true }
        case .microsoftToDo:
            if coordinator.isRefreshingOAuthTaskLists { return true }
            if case .loading = coordinator.microsoftToDoTaskState { return true }
        case .googleTasks:
            if coordinator.isRefreshingOAuthTaskLists { return true }
            if case .loading = coordinator.googleTasksTaskState { return true }
        case .todoist:
            if coordinator.isRefreshingOAuthTaskLists { return true }
            if case .loading = coordinator.todoistTaskState { return true }
        }
        return false
    }

    private var isInitialContentLoading: Bool {
        guard isContentLoading else { return false }
        if let provider = selectedList?.provider {
            return !coordinator.hasSidebarTaskSnapshot(for: provider)
        }
        return !supportedSidebarProviders.contains {
            coordinator.hasSidebarTaskSnapshot(for: $0)
        }
    }

    private var shouldShowStandaloneRemindersConnection: Bool {
        guard remindersAuthorizationState != .authorized,
              combinedItems.isEmpty,
              listOptions.isEmpty,
              !coordinator.isRefreshingOAuthTaskLists,
              case .unavailable = coordinator.microsoftToDoTaskState,
              case .unavailable = coordinator.googleTasksTaskState,
              case .unavailable = coordinator.todoistTaskState else {
            return false
        }
        return true
    }

    private var relevantProvidersUnavailable: Bool {
        if let provider = selectedList?.provider {
            switch provider {
            case .appleReminders:
                if case .unavailable = coordinator.appleRemindersTaskState {
                    return true
                }
            case .microsoftToDo:
                if case .unavailable = coordinator.microsoftToDoTaskState {
                    return true
                }
            case .googleTasks:
                if case .unavailable = coordinator.googleTasksTaskState {
                    return true
                }
            case .todoist:
                if case .unavailable = coordinator.todoistTaskState {
                    return true
                }
            }
            return false
        }
        guard case .unavailable = coordinator.appleRemindersTaskState,
              case .unavailable = coordinator.microsoftToDoTaskState,
              case .unavailable = coordinator.googleTasksTaskState,
              case .unavailable = coordinator.todoistTaskState else {
            return false
        }
        return true
    }

    private var failureMessage: String? {
        var messages: [String] = []
        if case let .failed(message) = coordinator.appleRemindersTaskState {
            messages.append("Apple Reminders: \(message)")
        }
        if case let .failed(message) = coordinator.microsoftToDoTaskState {
            messages.append("Microsoft To Do: \(message)")
        }
        if case let .failed(message) = coordinator.googleTasksTaskState {
            messages.append("Google Tasks: \(message)")
        }
        if case let .failed(message) = coordinator.todoistTaskState {
            messages.append("Todoist: \(message)")
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private var contentFailureMessage: String? {
        guard let provider = selectedList?.provider else { return failureMessage }
        switch provider {
        case .appleReminders:
            if case let .failed(message) = coordinator.appleRemindersTaskState {
                return "Apple Reminders: \(message)"
            }
        case .microsoftToDo:
            if case let .failed(message) = coordinator.microsoftToDoTaskState {
                return "Microsoft To Do: \(message)"
            }
        case .googleTasks:
            if case let .failed(message) = coordinator.googleTasksTaskState {
                return "Google Tasks: \(message)"
            }
        case .todoist:
            if case let .failed(message) = coordinator.todoistTaskState {
                return "Todoist: \(message)"
            }
        }
        return nil
    }

    private var noSearchResultsContent: some View {
        ContentUnavailableView {
            Label("No matching tasks", systemImage: "magnifyingglass")
        } description: {
            Text("Try another search or clear the current text.")
        } actions: {
            Button("Clear Search") {
                searchText = ""
            }
            .accessibilityIdentifier("tasks.search.empty.clear")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableContent: some View {
        ContentUnavailableView {
            Label(
                "No task provider available",
                systemImage: "checklist"
            )
        } description: {
            Text(
                "Grant Reminders access or connect a task provider in Settings."
            )
        }
    }

    private var oauthSyncContent: some View {
        ContentUnavailableView {
            Label("Sync connected providers", systemImage: "key.horizontal")
        } description: {
            Text(
                "KaosCal will use the provider credentials already saved in your macOS Keychain. macOS may ask you to allow access."
            )
        } actions: {
            Button("Sync Tasks") {
                coordinator.requestProviderSync()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("tasks.syncConnectedProviders")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("tasks.oauthSyncPrompt")
    }

    private var remindersConnectionContent: some View {
        ContentUnavailableView {
            Label(remindersConnectionTitle, systemImage: "checklist")
        } description: {
            VStack(spacing: 6) {
                Text(remindersConnectionDescription)
                if let message = coordinator.lastErrorMessage,
                   !message.isEmpty {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        } actions: {
            switch remindersAuthorizationState {
            case .notConfigured, .notDetermined:
                Button("Connect Apple Reminders") {
                    beginRemindersAccessRequest()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequestingRemindersAccess)
                .accessibilityIdentifier("tasks.connectAppleReminders")
            case .denied:
                Button("Open System Settings") {
                    openRemindersPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("tasks.openRemindersSettings")
            case .restricted:
                EmptyView()
            case .unknown:
                Button("Check Again") {
                    coordinator.refresh()
                }
                .accessibilityIdentifier("tasks.checkRemindersAccess")
            case .authorized:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("tasks.appleRemindersConnection")
    }

    private var remindersConnectionTitle: String {
        switch remindersAuthorizationState {
        case .notConfigured, .notDetermined:
            "Connect Apple Reminders"
        case .denied:
            "Apple Reminders access is off"
        case .restricted:
            "Apple Reminders access is restricted"
        case .unknown:
            "Check Apple Reminders access"
        case .authorized:
            "Apple Reminders connected"
        }
    }

    private var remindersConnectionDescription: String {
        switch remindersAuthorizationState {
        case .notConfigured, .notDetermined:
            "Allow KaosCal to show your existing reminders here."
        case .denied:
            "Allow KaosCal in System Settings → Privacy & Security → Reminders, then return and refresh Tasks."
        case .restricted:
            "This Mac currently prevents apps from accessing Reminders."
        case .unknown:
            "KaosCal could not determine the current Reminders permission."
        case .authorized:
            "Your Reminders lists are available in Tasks."
        }
    }

    private func beginRemindersAccessRequest() {
        Task {
            await connectAppleReminders()
        }
    }

    private func connectAppleReminders() async {
        guard !isRequestingRemindersAccess else { return }
        isRequestingRemindersAccess = true
        await coordinator.requestAccess()
        isRequestingRemindersAccess = false
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func failureContent(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn’t refresh tasks", systemImage: "exclamationmark.circle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                coordinator.requestProviderSync()
            }
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: "checkmark.circle")
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if selectedList != nil {
                Button("Show All Lists") {
                    selectedList = nil
                }
                .accessibilityIdentifier("tasks.empty.showAllLists")
            }
            remindersRecoveryAction
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var remindersRecoveryAction: some View {
        switch remindersAuthorizationState {
        case .notConfigured, .notDetermined:
            Button("Connect Apple Reminders") {
                beginRemindersAccessRequest()
            }
            .disabled(isRequestingRemindersAccess)
            .accessibilityIdentifier("tasks.empty.connectAppleReminders")
        case .denied:
            Button("Allow Apple Reminders") {
                openRemindersPrivacySettings()
            }
            .accessibilityIdentifier("tasks.empty.openRemindersSettings")
        case .authorized, .restricted, .unknown:
            EmptyView()
        }
    }

    private var emptyStateTitle: String {
        if listOptions.isEmpty {
            return "No task lists"
        }
        let suffix = selectedListOption.map {
            " in \(displayListTitle(for: $0))"
        } ?? ""
        switch statusFilter {
        case .open:
            return "No open tasks\(suffix)"
        case .completed:
            return "No completed tasks\(suffix)"
        case .all:
            return "No tasks\(suffix)"
        }
    }

    private var emptyStateDescription: String {
        if listOptions.isEmpty {
            return "Create a list in a connected task provider, then refresh."
        }
        if let selectedListOption {
            return "\(selectedListOption.provider.title) · \(selectedListOption.accountTitle)"
        }
        switch statusFilter {
        case .open:
            return "Choose Completed or All to see finished tasks."
        case .completed:
            return "Completed tasks from the selected sources will appear here."
        case .all:
            return "Create a task in a connected provider, then refresh."
        }
    }

    private func taskList(_ items: [ProviderTaskListItem]) -> some View {
        let taskGroups = groups(for: items)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if hasProviderStatusNotice {
                    VStack(alignment: .leading, spacing: 8) {
                        providerStatusRows
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }

                if selectedList != nil {
                    taskRows(items.sorted(by: taskSort))
                } else {
                    ForEach(taskGroups) { group in
                        Section {
                            taskRows(group.items)
                        } header: {
                            groupHeader(group)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .overlay(alignment: .bottom) {
                                    Divider()
                                }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onMoveCommand(perform: moveTaskFocus)
    }

    @ViewBuilder
    private func taskRows(_ items: [ProviderTaskListItem]) -> some View {
        ForEach(items) { item in
            ProviderTaskSidebarRow(
                appState: appState,
                coordinator: coordinator,
                item: item,
                isSelectionMode: isSelectingTasks,
                isSelected: selectedTaskIDs.contains(item.id),
                isDetailSelected: editorPresentation?.editingTaskID == item.id,
                toggleSelection: {
                    toggleSelection(of: item)
                }
            ) {
                presentEditor(
                    ProviderTaskEditorPresentation(mode: .edit(item))
                )
            }
                .focusable()
                .focused($focusedTaskID, equals: item.id)
                .padding(.horizontal, 14)
            if item.id != items.last?.id {
                Divider()
                    .padding(.leading, 42)
            }
        }
    }

    private func groupHeader(
        _ group: ProviderTaskSidebarGroup
    ) -> some View {
        let listTitle = displayListTitle(for: group)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(listTitle, systemImage: "list.bullet")
                    .font(.callout.weight(.semibold))
                Text("\(group.provider.title) · \(group.accountTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(group.items.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(listTitle), \(group.provider.title), \(group.accountTitle), \(group.items.count) tasks"
        )
    }

    private func displayListTitle(
        for group: ProviderTaskSidebarGroup
    ) -> String {
        let option = listOptions.first { $0.id == group.identity }
            ?? ProviderTaskSidebarListOption(
                identity: group.identity,
                listTitle: group.listTitle,
                accountTitle: group.accountTitle
            )
        return displayListTitle(for: option)
    }

    private var hasProviderStatusNotice: Bool {
        if remindersAuthorizationState != .authorized { return true }
        if case .failed = coordinator.appleRemindersTaskState { return true }
        if case .failed = coordinator.microsoftToDoTaskState { return true }
        if case .failed = coordinator.googleTasksTaskState { return true }
        if case .failed = coordinator.todoistTaskState { return true }
        return false
    }

    @ViewBuilder
    private var providerStatusRows: some View {
        switch remindersAuthorizationState {
        case .authorized:
            EmptyView()
        case .notConfigured, .notDetermined:
            Button("Connect Apple Reminders") {
                beginRemindersAccessRequest()
            }
            .disabled(isRequestingRemindersAccess)
            .accessibilityIdentifier("tasks.connectAppleReminders")
        case .denied:
            Button("Allow Apple Reminders in System Settings") {
                openRemindersPrivacySettings()
            }
            .accessibilityIdentifier("tasks.openRemindersSettings")
        case .restricted:
            Label("Apple Reminders access restricted", systemImage: "lock.circle")
                .foregroundStyle(.secondary)
        case .unknown:
            Label("Apple Reminders access unknown", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        if remindersAuthorizationState == .authorized {
            switch coordinator.appleRemindersTaskState {
            case .loading:
                EmptyView()
            case let .failed(message):
                Label("Apple Reminders: \(message)", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            case .unavailable, .loaded:
                EmptyView()
            }
        }
        switch coordinator.microsoftToDoTaskState {
        case .loading:
            EmptyView()
        case let .failed(message):
            Label("Microsoft To Do: \(message)", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .unavailable, .loaded:
            EmptyView()
        }
        switch coordinator.googleTasksTaskState {
        case .loading:
            EmptyView()
        case let .failed(message):
            Label("Google Tasks: \(message)", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .unavailable, .loaded:
            EmptyView()
        }
        switch coordinator.todoistTaskState {
        case .loading:
            EmptyView()
        case let .failed(message):
            Label("Todoist: \(message)", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .unavailable, .loaded:
            EmptyView()
        }
    }

    private func groups(
        for items: [ProviderTaskListItem]
    ) -> [ProviderTaskSidebarGroup] {
        Dictionary(grouping: items) {
            ProviderTaskSidebarFiltering.listIdentity(for: $0)
        }
        .compactMap { identity, items in
            guard let first = items.first else { return nil }
            return ProviderTaskSidebarGroup(
                identity: identity,
                accountTitle: first.accountTitle,
                listTitle: first.listTitle,
                items: items.sorted(by: taskSort)
            )
        }
        .sorted { lhs, rhs in
            if lhs.provider != rhs.provider {
                return ProviderTaskSidebarFiltering.providerRank(lhs.provider)
                    < ProviderTaskSidebarFiltering.providerRank(rhs.provider)
            }
            let listOrder = lhs.listTitle.localizedCaseInsensitiveCompare(
                rhs.listTitle
            )
            if listOrder != .orderedSame {
                return listOrder == .orderedAscending
            }
            let accountOrder = lhs.accountTitle.localizedCaseInsensitiveCompare(
                rhs.accountTitle
            )
            if accountOrder != .orderedSame {
                return accountOrder == .orderedAscending
            }
            if lhs.identity.accountKey != rhs.identity.accountKey {
                return lhs.identity.accountKey < rhs.identity.accountKey
            }
            return lhs.identity.listID < rhs.identity.listID
        }
    }

    private func taskSort(
        _ lhs: ProviderTaskListItem,
        _ rhs: ProviderTaskListItem
    ) -> Bool {
        ProviderTaskSidebarOrdering.precedes(lhs, rhs, by: sort)
    }

    private var selectedTasks: [ProviderTaskListItem] {
        combinedItems.filter { selectedTaskIDs.contains($0.id) }
    }

    private var selectedTasksAreWritable: Bool {
        !selectedTasks.isEmpty
            && selectedTasks.allSatisfy {
                coordinator.isSidebarTaskWritable($0)
                    && coordinator.capabilities(for: $0.provider)?
                        .supportsCompletion == true
            }
    }

    private var selectedTasksCanMove: Bool {
        guard let first = selectedTasks.first,
              coordinator.capabilities(for: first.provider)?
                .supportsListMove == true else {
            return false
        }
        return selectedTasks.allSatisfy {
            $0.provider == first.provider
                && (first.provider == .appleReminders
                    || $0.accountKey == first.accountKey)
                && coordinator.isSidebarTaskWritable($0)
        } && !bulkMoveLists.isEmpty
    }

    private var bulkMoveLists: [RemoteTaskList] {
        guard let first = selectedTasks.first else { return [] }
        return writableTaskLists.filter {
            $0.provider == first.provider
                && (first.provider == .appleReminders
                    || $0.accountKey == first.accountKey)
        }
    }

    private var bulkActionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(selectedTaskIDs.count) selected")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Menu("Status") {
                    Button("Mark Complete") {
                        performBulkCompletion(true)
                    }
                    Button("Mark Incomplete") {
                        performBulkCompletion(false)
                    }
                }
                .disabled(!selectedTasksAreWritable || isPerformingBulkAction)
                Menu("Move") {
                    ForEach(
                        bulkMoveLists,
                        id: \.destinationSelectionKey
                    ) { list in
                        Button(createListTitle(list)) {
                            performBulkMove(to: list)
                        }
                    }
                }
                .disabled(!selectedTasksCanMove || isPerformingBulkAction)
                if isPerformingBulkAction {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Changing selected tasks")
                }
            }
            if let bulkErrorMessage {
                Label(bulkErrorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !selectedTaskIDs.isEmpty && !selectedTasksAreWritable {
                Text("Bulk status changes require writable tasks whose provider supports completion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("tasks.bulkActions")
    }

    private var undoBar: some View {
        HStack(spacing: 10) {
            if isUndoing {
                ProgressView()
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let state = coordinator.sidebarUndoState {
                    Text(state.message)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                if let undoErrorMessage {
                    Text(undoErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if coordinator.sidebarUndoState != nil {
                Button("Undo") { performUndo() }
                    .disabled(isUndoing)
                    .keyboardShortcut("z", modifiers: [.command])
                    .accessibilityIdentifier("tasks.undo")
            }
            Button {
                coordinator.dismissSidebarUndo()
                undoErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss task change")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(KaosCalTheme.accent.opacity(0.08))
    }

    private func toggleSelectionMode() {
        isSelectingTasks.toggle()
        bulkErrorMessage = nil
        if !isSelectingTasks {
            selectedTaskIDs.removeAll()
        }
    }

    private func presentEditor(
        _ presentation: ProviderTaskEditorPresentation
    ) {
        guard let current = editorPresentation else {
            activateEditor(presentation)
            return
        }
        if current.targetKey == presentation.targetKey {
            requestEditorClose()
        } else if editorHasUnsavedChanges {
            pendingEditorPresentation = presentation
            showsEditorTransitionPrompt = true
        } else {
            activateEditor(presentation)
        }
    }

    private func activateEditor(
        _ presentation: ProviderTaskEditorPresentation
    ) {
        editorHasUnsavedChanges = false
        pendingEditorPresentation = nil
        showsEditorTransitionPrompt = false
        editorPresentation = presentation
    }

    private func requestEditorClose() {
        if editorHasUnsavedChanges {
            pendingEditorPresentation = nil
            showsEditorTransitionPrompt = true
        } else {
            closeEditorImmediately()
        }
    }

    private func finishEditorOperation() {
        let pending = pendingEditorPresentation
        closeEditorImmediately()
        if let pending {
            activateEditor(pending)
        }
    }

    private func discardCurrentEditor() {
        let pending = pendingEditorPresentation
        closeEditorImmediately()
        if let pending {
            activateEditor(pending)
        }
    }

    private func closeEditorImmediately() {
        editorPresentation = nil
        pendingEditorPresentation = nil
        editorHasUnsavedChanges = false
        showsEditorTransitionPrompt = false
    }

    private func editorTargetTitle(
        _ presentation: ProviderTaskEditorPresentation
    ) -> String {
        switch presentation.mode {
        case .create:
            return "a new task"
        case let .edit(item):
            return "‘\(item.title)’"
        }
    }

    private func toggleSelection(of item: ProviderTaskListItem) {
        if selectedTaskIDs.contains(item.id) {
            selectedTaskIDs.remove(item.id)
        } else {
            selectedTaskIDs.insert(item.id)
        }
        focusedTaskID = item.id
    }

    private func performBulkCompletion(_ completed: Bool) {
        let tasks = selectedTasks
        guard selectedTasksAreWritable, !isPerformingBulkAction else { return }
        isPerformingBulkAction = true
        bulkErrorMessage = nil
        Task {
            do {
                _ = try await coordinator.setSidebarTasksCompleted(
                    tasks,
                    isCompleted: completed
                )
                selectedTaskIDs.removeAll()
                isSelectingTasks = false
            } catch {
                bulkErrorMessage = error.localizedDescription
            }
            isPerformingBulkAction = false
        }
    }

    private func performBulkMove(to list: RemoteTaskList) {
        let tasks = selectedTasks
        guard selectedTasksCanMove, !isPerformingBulkAction else { return }
        isPerformingBulkAction = true
        bulkErrorMessage = nil
        Task {
            do {
                _ = try await coordinator.moveSidebarTasks(tasks, to: list)
                selectedTaskIDs.removeAll()
                isSelectingTasks = false
            } catch {
                bulkErrorMessage = error.localizedDescription
            }
            isPerformingBulkAction = false
        }
    }

    private func performUndo() {
        guard !isUndoing else { return }
        isUndoing = true
        undoErrorMessage = nil
        Task {
            do {
                try await coordinator.undoLastSidebarMutation()
            } catch {
                undoErrorMessage = error.localizedDescription
            }
            isUndoing = false
        }
    }

    private func moveTaskFocus(_ direction: MoveCommandDirection) {
        let ids = displayedItems.map(\.id)
        guard !ids.isEmpty else { return }
        guard let focusedTaskID,
              let index = ids.firstIndex(of: focusedTaskID) else {
            self.focusedTaskID = direction == .down ? ids.first : ids.last
            return
        }
        switch direction {
        case .down:
            self.focusedTaskID = ids[min(index + 1, ids.count - 1)]
        case .up:
            self.focusedTaskID = ids[max(index - 1, 0)]
        default:
            break
        }
    }

    private func createListTitle(_ list: RemoteTaskList) -> String {
        "\(list.title) — \(list.sourceTitle)"
    }
}

private struct ProviderTaskSidebarRow: View {
    @ObservedObject var appState: AppState
    @ObservedObject var coordinator: TaskProviderCoordinator
    let item: ProviderTaskListItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let isDetailSelected: Bool
    let toggleSelection: () -> Void
    let openEditor: () -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                leadingControl

                Button(action: isSelectionMode ? toggleSelection : openEditor) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(
                                item.isCompleted
                                    ? Color.secondary
                                    : Color.primary
                            )
                            .strikethrough(item.isCompleted)
                            .lineLimit(2)

                        if let details = item.details {
                            Text(details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let dueAt = item.dueAt {
                            Label(
                                dueText(dueAt),
                                systemImage: isOverdue(dueAt)
                                    ? "exclamationmark.circle"
                                    : "calendar"
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                isOverdue(dueAt)
                                    ? Color.red
                                    : Color.secondary
                            )
                        }

                        if item.priority != .none {
                            Label(item.priority.title, systemImage: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(
                                    item.priority == .high
                                        ? Color.orange
                                        : Color.secondary
                                )
                        }

                        if let link = calendarLink {
                            Label(
                                "\(link.eventTitle) · \(link.calendarTitle)",
                                systemImage: link.linkStatus == .active
                                    ? "calendar.badge.checkmark"
                                    : "calendar.badge.exclamationmark"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }

                        if !canOpenDetails {
                            Label(viewOnlyMessage, systemImage: "lock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if !canWrite {
                            Label("View only", systemImage: "lock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canOpenDetails || isWorking)
                .accessibilityLabel(taskAccessibilityLabel)
                .accessibilityHint(
                    canWrite
                        ? (isSelectionMode ? "Selects this task" : "Opens task details for editing")
                        : (isSelectionMode ? "Selects this task" : "Opens read-only task details")
                )
                .accessibilityAddTraits(
                    isDetailSelected ? .isSelected : []
                )

                if let originalURL = item.originalURL {
                    Button {
                        NSWorkspace.shared.open(originalURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .disabled(isWorking)
                    .help("Open in \(item.provider.title)")
                    .accessibilityLabel("Open ‘\(item.title)’ in \(item.provider.title)")
                    .accessibilityIdentifier("task.\(item.id).openOriginal")
                }
                if let link = calendarLink {
                    Button {
                        Task {
                            await appState.openOriginalEvent(
                                contextID: link.contextID
                            )
                        }
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .disabled(isWorking)
                    .help("Open linked event “\(link.eventTitle)”")
                    .accessibilityLabel("Open event linked to ‘\(item.title)’")
                    .accessibilityIdentifier("task.\(item.id).openLinkedEvent")
                }
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("task.\(item.id).error")
                    HStack(spacing: 12) {
                        Button("Refresh") {
                            self.errorMessage = nil
                            coordinator.requestProviderSync()
                        }
                        if item.provider == .appleReminders,
                           coordinator.authorizationState(
                            for: .appleReminders
                           ) != .authorized {
                            Button("Open Settings") {
                                openRemindersPrivacySettings()
                            }
                        }
                    }
                    .font(.caption)
                }
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            isDetailSelected
                ? KaosCalTheme.accent.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .help(item.details ?? item.title)
        .accessibilityIdentifier("task.\(item.id)")
        .draggable("kaoscal-task:\(item.id)") {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                Text(item.title)
                    .lineLimit(1)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            if !item.isCompleted {
                Button("Reschedule for Tomorrow") {
                    reschedule(daysFromToday: 1)
                }
                .disabled(!canWrite || isWorking)
                Button("Reschedule One Week Later") {
                    reschedule(daysFromToday: 7)
                }
                .disabled(!canWrite || isWorking)
                if item.dueAt != nil {
                    Button("Remove Due Date") {
                        reschedule(to: nil)
                    }
                    .disabled(!canWrite || isWorking)
                }
                Divider()
            }
            if let link = calendarLink {
                Button("Open Linked Event") {
                    Task {
                        await appState.openOriginalEvent(
                            contextID: link.contextID
                        )
                    }
                }
            }
            if let originalURL = item.originalURL {
                Button("Open in \(item.provider.title)") {
                    NSWorkspace.shared.open(originalURL)
                }
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if isSelectionMode {
            Button(action: toggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? KaosCalTheme.accent : .secondary)
            .padding(.top, 2)
            .accessibilityLabel(isSelected ? "Deselect task" : "Select task")
        } else if isWorking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
                .padding(.top, 2)
                .accessibilityLabel("Saving task")
        } else if canWrite {
            Button {
                toggleCompletion()
            } label: {
                Image(
                    systemName: item.isCompleted
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.body)
                .frame(width: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                item.isCompleted ? KaosCalTheme.accent : .secondary
            )
            .padding(.top, 2)
            .accessibilityLabel(
                item.isCompleted ? "Mark incomplete" : "Mark complete"
            )
            .accessibilityIdentifier("task.\(item.id).completion")
        } else {
            Image(
                systemName: item.isCompleted
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .foregroundStyle(
                item.isCompleted ? KaosCalTheme.accent : Color.secondary
            )
            .font(.body)
            .frame(width: 18)
            .padding(.top, 2)
            .accessibilityLabel(item.isCompleted ? "Completed" : "Open")
        }
    }

    private var canWrite: Bool {
        coordinator.isSidebarTaskWritable(item)
    }

    private var calendarLink: ProviderTaskCalendarLink? {
        coordinator.calendarLink(for: item)
    }

    private var canOpenDetails: Bool {
        isSelectionMode
            || coordinator.authorizationState(for: item.provider)
                == .authorized
    }

    private var isWorking: Bool {
        isSubmitting || coordinator.isMutatingSidebarTask(item)
    }

    private var viewOnlyMessage: String {
        coordinator.authorizationState(for: item.provider) == .authorized
            ? "\(item.provider.title) list is read only"
            : "\(item.provider.title) unavailable"
    }

    private var taskAccessibilityLabel: String {
        var parts = [item.isCompleted ? "Completed" : "Open", item.title]
        if let details = item.details { parts.append(details) }
        if let dueAt = item.dueAt { parts.append(dueText(dueAt)) }
        parts.append("\(item.provider.title), \(item.accountTitle), \(item.listTitle)")
        return parts.joined(separator: ", ")
    }

    private func toggleCompletion() {
        guard !isWorking else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                _ = try await coordinator.setSidebarTaskCompleted(
                    item,
                    isCompleted: !item.isCompleted
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func reschedule(daysFromToday days: Int) {
        let day = appState.calendar.date(
            byAdding: .day,
            value: days,
            to: appState.calendar.startOfDay(for: appState.taskReferenceDate)
        ) ?? appState.taskReferenceDate.addingTimeInterval(
            TimeInterval(days * 86_400)
        )
        let hour = item.dueAt.map {
            appState.calendar.component(.hour, from: $0)
        } ?? 9
        let minute = item.dueAt.map {
            appState.calendar.component(.minute, from: $0)
        } ?? 0
        let date = appState.calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        ) ?? day
        reschedule(to: date)
    }

    private func reschedule(to dueAt: Date?) {
        guard !isWorking else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let baseline = try await coordinator.loadSidebarTask(item)
                _ = try await coordinator.updateSidebarTask(
                    item,
                    baseline: baseline,
                    title: baseline.title,
                    notes: baseline.notes,
                    dueAt: dueAt,
                    isCompleted: baseline.isCompleted
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func isOverdue(_ date: Date) -> Bool {
        date < appState.calendar.startOfDay(for: appState.taskReferenceDate)
    }

    private func dueText(_ date: Date) -> String {
        let dateText = CalendarEventDateFormatting.abbreviatedDate(
            date,
            calendar: appState.calendar
        )
        if appState.calendar.isDateInToday(date) {
            return "Today · \(dateText)"
        }
        if appState.calendar.isDateInTomorrow(date) {
            return "Tomorrow · \(dateText)"
        }
        if isOverdue(date) {
            return "Overdue · \(dateText)"
        }
        return dateText
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum ProviderTaskEditorPresentationStyle {
    case sheet
    case drawer
}

struct ProviderTaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: TaskProviderCoordinator
    let mode: ProviderTaskEditorPresentation.Mode
    let writableLists: [RemoteTaskList]
    let presentationStyle: ProviderTaskEditorPresentationStyle
    let onCancel: (() -> Void)?
    let onComplete: (() -> Void)?
    let onDirtyChange: ((Bool) -> Void)?
    private let initialSelectedListKey: String

    @State private var selectedListKey: String
    @State private var baseline: RemoteTaskSnapshot?
    @State private var title: String
    @State private var notes: String
    @State private var dueEnabled: Bool
    @State private var dueDraft: Date
    @State private var reminderEnabled: Bool
    @State private var reminderDraft: Date
    @State private var isCompleted: Bool
    @State private var priority: TaskPriority
    @State private var isLoading: Bool
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var hasConflict = false
    @State private var confirmsDeletion = false

    init(
        coordinator: TaskProviderCoordinator,
        mode: ProviderTaskEditorPresentation.Mode,
        writableLists: [RemoteTaskList],
        presentationStyle: ProviderTaskEditorPresentationStyle = .sheet,
        onCancel: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil,
        onDirtyChange: ((Bool) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.mode = mode
        self.writableLists = writableLists
        self.presentationStyle = presentationStyle
        self.onCancel = onCancel
        self.onComplete = onComplete
        self.onDirtyChange = onDirtyChange

        let defaultDue = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: 1,
            to: Date()
        ) ?? Date().addingTimeInterval(86_400)
        switch mode {
        case let .create(preferredList):
            let initialList = preferredList
                ?? (writableLists.count == 1 ? writableLists.first : nil)
            initialSelectedListKey = initialList?.destinationSelectionKey ?? ""
            _selectedListKey = State(
                initialValue: initialSelectedListKey
            )
            _baseline = State(initialValue: nil)
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _dueEnabled = State(initialValue: false)
            _dueDraft = State(initialValue: defaultDue)
            _reminderEnabled = State(initialValue: false)
            _reminderDraft = State(initialValue: defaultDue)
            _isCompleted = State(initialValue: false)
            _priority = State(initialValue: .none)
            _isLoading = State(initialValue: false)
        case let .edit(item):
            initialSelectedListKey = writableLists.first {
                $0.provider == item.provider
                    && $0.accountKey == item.accountKey
                    && $0.id == item.listID
            }?.destinationSelectionKey ?? ""
            _selectedListKey = State(
                initialValue: initialSelectedListKey
            )
            _baseline = State(initialValue: nil)
            _title = State(initialValue: item.title)
            _notes = State(initialValue: item.details ?? "")
            _dueEnabled = State(initialValue: item.dueAt != nil)
            _dueDraft = State(initialValue: item.dueAt ?? defaultDue)
            _reminderEnabled = State(initialValue: item.reminderAt != nil)
            _reminderDraft = State(
                initialValue: item.reminderAt ?? item.dueAt ?? defaultDue
            )
            _isCompleted = State(initialValue: item.isCompleted)
            _priority = State(initialValue: item.priority)
            _isLoading = State(initialValue: true)
        }
    }

    var body: some View {
        Group {
            if presentationStyle == .sheet {
                editorContent
                    .frame(
                        minWidth: 520,
                        idealWidth: 560,
                        minHeight: 500
                    )
            } else {
                editorContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if case .edit = mode {
                await reloadLatest()
            }
        }
        .onAppear {
            onDirtyChange?(hasDraftChanges)
        }
        .onChange(of: hasDraftChanges) { _, hasChanges in
            onDirtyChange?(hasChanges)
        }
        .alert("Delete this task?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive) {
                deleteTask()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .accessibilityIdentifier(
            presentationStyle == .drawer ? "tasks.drawer.editor" : "tasks.editor"
        )
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            HStack {
                Label(sheetTitle, systemImage: "checklist")
                    .font(.title3.weight(.semibold))
                Spacer()
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving task")
                }
                if presentationStyle == .drawer {
                    Button {
                        cancelEditing()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .disabled(isSubmitting)
                    .help("Close task editor")
                    .accessibilityLabel("Close task editor")
                    .accessibilityIdentifier("tasks.drawer.close")
                }
            }
            .padding(presentationStyle == .drawer ? 14 : 20)

            Divider()

            if isLoading {
                ProgressView("Loading the latest task…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sourceSection
                        editorFields
                        statusMessage
                    }
                    .padding(presentationStyle == .drawer ? 14 : 20)
                }
            }

            Divider()
            actionBar
                .padding(presentationStyle == .drawer ? 12 : 16)
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination")
                .font(.headline)
            switch mode {
            case .create:
                Picker("Task list", selection: $selectedListKey) {
                    Text("Choose a writable list").tag("")
                    ForEach(
                        writableLists,
                        id: \.destinationSelectionKey
                    ) { list in
                        Text(createListTitle(list))
                            .tag(list.destinationSelectionKey)
                    }
                }
                .accessibilityIdentifier("tasks.editor.list")
            case let .edit(item):
                LabeledContent("Provider", value: item.provider.title)
                LabeledContent("Account", value: item.accountTitle)
                if coordinator.isSidebarTaskWritable(item),
                   activeCapabilities?.supportsListMove == true {
                    Picker("List", selection: $selectedListKey) {
                        ForEach(
                            editableDestinationLists,
                            id: \.destinationSelectionKey
                        ) { list in
                            Text(createListTitle(list))
                                .tag(list.destinationSelectionKey)
                        }
                    }
                    .help("Moving a task keeps its Event Brief link when one exists.")
                    .accessibilityIdentifier("tasks.editor.destinationList")
                } else if coordinator.isSidebarTaskWritable(item) {
                    LabeledContent("List", value: item.listTitle)
                } else {
                    LabeledContent("List", value: item.listTitle)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "This list is currently view only. Refresh list metadata or check its permissions before editing.",
                            systemImage: "lock"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Button("Refresh List Metadata") {
                            coordinator.requestProviderSync()
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var editorFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.headline)
                TextField("Task title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("tasks.editor.title")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.headline)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 100)
                    .padding(6)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                Color(nsColor: .separatorColor),
                                lineWidth: 0.5
                            )
                    }
                    .accessibilityIdentifier("tasks.editor.notes")
                    .disabled(activeCapabilities?.supportsNotes != true)
                if activeCapabilities?.supportsNotes == false {
                    Text("\(activeProvider?.title ?? "This provider") does not support editable notes through KaosCal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Set a due date", isOn: $dueEnabled)
                .accessibilityIdentifier("tasks.editor.dueEnabled")
            if dueEnabled {
                if activeCapabilities?.supportsTimedDue == false {
                    DatePicker(
                        "Due",
                        selection: $dueDraft,
                        displayedComponents: [.date]
                    )
                    .accessibilityIdentifier("tasks.editor.due")
                    Text("This provider stores a date-only deadline; the time is not sent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker(
                        "Due",
                        selection: $dueDraft,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("tasks.editor.due")
                }
            }
            if activeCapabilities?.supportsReminder == true {
                Toggle("Set a reminder", isOn: $reminderEnabled)
                    .accessibilityIdentifier("tasks.editor.reminderEnabled")
                if reminderEnabled {
                    DatePicker(
                        "Reminder",
                        selection: $reminderDraft,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("tasks.editor.reminder")
                    Text("Microsoft To Do will deliver this alert using its own notification settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Completed", isOn: $isCompleted)
                .accessibilityIdentifier("tasks.editor.completed")
                .disabled(activeCapabilities?.supportsCompletion != true)
            if activeCapabilities?.supportsPriority == true {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("tasks.editor.priority")
            }
        }
        .disabled(!canEditFields || isSubmitting)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if hasConflict {
                    Button("Reload Latest") {
                        Task { await reloadLatest() }
                    }
                    .accessibilityIdentifier("tasks.editor.reloadLatest")
                } else if editingItem != nil {
                    Button("Refresh") {
                        Task { await refreshAndReload() }
                    }
                }
                if editingItem?.provider == .appleReminders,
                   coordinator.authorizationState(for: .appleReminders)
                    != .authorized {
                    Button("Open Reminders Privacy Settings") {
                        openRemindersPrivacySettings()
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if editingItem != nil && !hasConflict {
                Button("Delete", role: .destructive) {
                    confirmsDeletion = true
                }
                .disabled(!canSaveEdit || isSubmitting)
                .accessibilityIdentifier("tasks.editor.delete")
            }
            Spacer()
            Button("Cancel") { cancelEditing() }
                .keyboardShortcut(.cancelAction)
            if !hasConflict {
                Button("Save") { saveTask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
                    .accessibilityIdentifier("tasks.editor.save")
            }
        }
    }

    private var sheetTitle: String {
        editingItem == nil ? "New Task" : "Task Details"
    }

    private var editingItem: ProviderTaskListItem? {
        guard case let .edit(item) = mode else { return nil }
        return item
    }

    private var selectedCreateList: RemoteTaskList? {
        writableLists.first {
            $0.destinationSelectionKey == selectedListKey
        }
    }

    private var selectedEditList: RemoteTaskList? {
        guard editingItem != nil else { return nil }
        return writableLists.first {
            $0.destinationSelectionKey == selectedListKey
        }
    }

    private var activeProvider: TaskProviderKind? {
        editingItem?.provider ?? selectedCreateList?.provider
    }

    private var activeCapabilities: TaskProviderCapabilities? {
        activeProvider.flatMap { coordinator.capabilities(for: $0) }
    }

    private var editableDestinationLists: [RemoteTaskList] {
        guard let item = editingItem else { return writableLists }
        return writableLists.filter {
            $0.provider == item.provider
                && (item.provider == .appleReminders
                    || $0.accountKey == item.accountKey)
        }
    }

    private var canEditFields: Bool {
        if let editingItem {
            return coordinator.isSidebarTaskWritable(editingItem)
                && baseline != nil
                && !hasConflict
        }
        return true
    }

    private var canSaveEdit: Bool {
        guard let editingItem else { return false }
        return coordinator.isSidebarTaskWritable(editingItem)
            && baseline != nil
            && !hasConflict
            && selectedEditList != nil
    }

    private var saveDisabled: Bool {
        isLoading
            || isSubmitting
            || hasConflict
            || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (editingItem == nil && selectedCreateList == nil)
            || (editingItem != nil && !canSaveEdit)
    }

    private var hasDraftChanges: Bool {
        if let baseline {
            return selectedListKey != initialSelectedListKey
                || title != baseline.title
                || notes != baseline.notes
                || (dueEnabled ? dueDraft : nil) != baseline.dueAt
                || (reminderEnabled ? reminderDraft : nil)
                    != baseline.reminderAt
                || isCompleted != baseline.isCompleted
                || priority != baseline.priority
        }
        guard editingItem == nil else { return false }
        return selectedListKey != initialSelectedListKey
            || !title.isEmpty
            || !notes.isEmpty
            || dueEnabled
            || reminderEnabled
            || isCompleted
            || priority != .none
    }

    private var deleteConfirmationMessage: String {
        guard let item = editingItem else { return "" }
        return "Delete ‘\(item.title)’ from \(item.provider.title) · \(item.accountTitle) · \(item.listTitle)? A linked KaosCal task will be kept and marked as needing attention."
    }

    private func createListTitle(_ list: RemoteTaskList) -> String {
        let duplicateLists = writableLists.filter {
            $0.sourceTitle == list.sourceTitle && $0.title == list.title
        }.sorted { $0.id < $1.id }
        guard duplicateLists.count > 1,
              let index = duplicateLists.firstIndex(where: {
                  $0.accountKey == list.accountKey && $0.id == list.id
              }) else {
            return "\(list.provider.title) · \(list.title) — \(list.sourceTitle)"
        }
        return "\(list.provider.title) · \(list.title) — \(list.sourceTitle) · List \(index + 1)"
    }

    private func reloadLatest() async {
        guard let item = editingItem else { return }
        isLoading = baseline == nil
        isSubmitting = true
        errorMessage = nil
        hasConflict = false
        do {
            let remote = try await coordinator.loadSidebarTask(item)
            baseline = remote
            title = remote.title
            notes = remote.notes
            dueEnabled = remote.dueAt != nil
            if let dueAt = remote.dueAt { dueDraft = dueAt }
            reminderEnabled = remote.reminderAt != nil
            if let reminderAt = remote.reminderAt {
                reminderDraft = reminderAt
            }
            isCompleted = remote.isCompleted
            priority = remote.priority
        } catch {
            baseline = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
        isSubmitting = false
    }

    private func refreshAndReload() async {
        coordinator.requestProviderSync()
        await reloadLatest()
    }

    private func saveTask() {
        guard !saveDisabled else { return }
        isSubmitting = true
        errorMessage = nil
        hasConflict = false
        Task {
            do {
                if let item = editingItem, let baseline {
                    _ = try await coordinator.updateSidebarTask(
                        item,
                        baseline: baseline,
                        title: title,
                        notes: notes,
                        dueAt: dueEnabled ? dueDraft : nil,
                        reminderAt: reminderEnabled ? reminderDraft : nil,
                        isCompleted: isCompleted,
                        priority: priority,
                        destination: selectedEditList
                    )
                } else if let list = selectedCreateList {
                    _ = try await coordinator.createSidebarTask(
                        in: list,
                        title: title,
                        notes: notes,
                        dueAt: dueEnabled ? dueDraft : nil,
                        reminderAt: reminderEnabled ? reminderDraft : nil,
                        priority: priority
                    )
                }
                completeEditing()
            } catch {
                errorMessage = error.localizedDescription
                hasConflict = (error as? TaskProviderError) == .conflict
                isSubmitting = false
            }
        }
    }

    private func deleteTask() {
        guard let item = editingItem, let baseline, !isSubmitting else {
            return
        }
        isSubmitting = true
        errorMessage = nil
        hasConflict = false
        Task {
            do {
                try await coordinator.deleteSidebarTask(
                    item,
                    baseline: baseline
                )
                completeEditing()
            } catch {
                errorMessage = error.localizedDescription
                hasConflict = (error as? TaskProviderError) == .conflict
                isSubmitting = false
            }
        }
    }

    private func cancelEditing() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func completeEditing() {
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ProviderTaskSidebarGroup: Identifiable {
    let identity: ProviderTaskSidebarListIdentity
    let accountTitle: String
    let listTitle: String
    let items: [ProviderTaskListItem]

    var id: ProviderTaskSidebarListIdentity { identity }
    var provider: TaskProviderKind { identity.provider }
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
