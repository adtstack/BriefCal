import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct CalendarUsageSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendars")
                        .font(.title2.weight(.semibold))
                    Text(
                        "Enable calendars for KaosCal views and Calendar Sets, and choose which ones reserve time when availability is calculated. These choices are independent."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if appState.calendarAccounts.isEmpty {
                    GroupBox {
                        Text(
                            "No calendars are loaded. Grant full Calendar access or refresh KaosCal, then return to this pane."
                        )
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label(
                            "Calendar Access",
                            systemImage: "calendar.badge.exclamationmark"
                        )
                    }
                } else {
                    ForEach(appState.calendarAccounts) { account in
                        accountGroup(account)
                    }
                }

                if let message = appState.localOperationError {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620, height: 620)
        .tint(KaosCalTheme.accent)
        .accessibilityIdentifier("settings.calendars")
    }

    private func accountGroup(
        _ account: CalendarAccountDescriptor
    ) -> some View {
        let enabledCount = account.calendars.filter {
            appState.calendarUsagePolicy(for: $0).isVisible
        }.count
        let blockingCount = account.calendars.filter {
            appState.calendarUsagePolicy(for: $0).blocksAvailability
        }.count

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(
                        "\(enabledCount) enabled · \(blockingCount) block time"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Menu("Account Actions") {
                        Button("Enable All") {
                            _ = appState.setCalendarVisibility(
                                true,
                                for: account.calendars
                            )
                        }
                        Button("Disable All") {
                            _ = appState.setCalendarVisibility(
                                false,
                                for: account.calendars
                            )
                        }
                        Divider()
                        Button("Block Time From All") {
                            _ = appState.setCalendarBlocksAvailability(
                                true,
                                for: account.calendars
                            )
                        }
                        Button("Do Not Block Time From Any") {
                            _ = appState.setCalendarBlocksAvailability(
                                false,
                                for: account.calendars
                            )
                        }
                    }
                    .disabled(!canEdit)
                }

                Divider()

                ForEach(account.calendars) { source in
                    calendarRow(source)
                    if source.id != account.calendars.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label(
                title: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.title)
                            .font(.headline)
                        Text(account.accountType.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                },
                icon: {
                    Image(
                        systemName: account.accountType == .exchange
                            ? "building.2"
                            : "person.crop.circle"
                    )
                }
            )
        }
    }

    private func calendarRow(_ source: CalendarSource) -> some View {
        let usage = appState.calendarUsagePolicy(for: source)

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(KaosCalTheme.calendarColor(
                    source.color,
                    accountType: source.accountType
                ))
                .frame(width: 4, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .lineLimit(1)
                Text(
                    usage.isVisibilityExplicit || usage.isBlockingExplicit
                        ? "Custom usage"
                        : "Using defaults"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Enabled", isOn: visibilityBinding(for: source))
                .toggleStyle(.checkbox)
                .frame(width: 88, alignment: .leading)
                .help("Allow this calendar to appear in KaosCal and saved Calendar Sets")

            Toggle("Block", isOn: blockingBinding(for: source))
                .toggleStyle(.checkbox)
                .frame(width: 82, alignment: .leading)
                .help("Let busy events in this calendar reserve available time")

            Picker("Role", selection: roleBinding(for: source)) {
                ForEach(CalendarRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            .labelsHidden()
            .frame(width: 122)
            .help("KaosCal role used by Smart Role Filters")

            Menu {
                Button("Use Visibility and Blocking Defaults") {
                    _ = appState.resetCalendarUsage(for: source)
                }
                .disabled(
                    !usage.isVisibilityExplicit
                        && !usage.isBlockingExplicit
                )
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More settings for \(source.title)")
        }
        .disabled(!canEdit)
        .accessibilityIdentifier("settings.calendar.\(source.id)")
    }

    private func visibilityBinding(
        for source: CalendarSource
    ) -> Binding<Bool> {
        Binding(
            get: { appState.calendarUsagePolicy(for: source).isVisible },
            set: { _ = appState.setCalendarVisibility($0, for: source) }
        )
    }

    private func blockingBinding(
        for source: CalendarSource
    ) -> Binding<Bool> {
        Binding(
            get: {
                appState.calendarUsagePolicy(for: source).blocksAvailability
            },
            set: {
                _ = appState.setCalendarBlocksAvailability($0, for: source)
            }
        )
    }

    private func roleBinding(for source: CalendarSource) -> Binding<CalendarRole> {
        Binding(
            get: { appState.calendarRole(for: source) },
            set: { _ = appState.setCalendarRole($0, for: source) }
        )
    }

    private var canEdit: Bool {
        guard appState.localDataOperationState == .idle else { return false }
        if case .ready = appState.localContextStoreState {
            return true
        }
        return false
    }
}

private enum CalendarSetSettingsSelection: Hashable {
    case all
    case saved(String)
}

private struct CalendarSetNameEditor: Identifiable {
    enum Kind: Hashable {
        case create
        case rename(String)
    }

    let kind: Kind
    let initialName: String

    var id: String {
        switch kind {
        case .create: "create"
        case let .rename(setID): "rename:\(setID)"
        }
    }
}

struct CalendarSetSettingsView: View {
    @ObservedObject var appState: AppState

    @State private var selection: CalendarSetSettingsSelection? = .all
    @State private var nameEditor: CalendarSetNameEditor?
    @State private var pendingDelete: SavedCalendarSetSnapshot?

    var body: some View {
        HSplitView {
            setList
            setDetail
        }
        .frame(width: 760, height: 620)
        .tint(KaosCalTheme.accent)
        .sheet(item: $nameEditor) { editor in
            CalendarSetNameEditorView(
                appState: appState,
                editor: editor
            ) { createdSetID in
                if let createdSetID {
                    selection = .saved(createdSetID)
                }
                nameEditor = nil
            }
        }
        .alert(
            pendingDelete.map { "Delete ‘\($0.name)’?" }
                ?? "Delete Calendar Set?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete Calendar Set", role: .destructive) {
                guard let pendingDelete else { return }
                if appState.deleteCalendarSet(id: pendingDelete.id) {
                    selection = .all
                }
                self.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(
                "This removes only the saved view and its memberships. Calendar events, accounts, roles, and availability settings are not deleted."
            )
        }
        .onAppear {
            if case let .saved(setID) = appState.selectedCalendarSet,
               appState.savedCalendarSet(id: setID) != nil {
                selection = .saved(setID)
            }
        }
        .accessibilityIdentifier("settings.calendarSets")
    }

    private var setList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                setRow(
                    title: "All Calendars",
                    systemImage: "calendar",
                    isActive: appState.selectedCalendarSet == .all
                )
                .tag(CalendarSetSettingsSelection.all)

                Section("Saved Sets") {
                    if appState.savedCalendarSets.isEmpty {
                        Text("No saved sets")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.savedCalendarSets) { set in
                            setRow(
                                title: set.name,
                                systemImage: "calendar.badge.checkmark",
                                isActive: appState.selectedCalendarSet
                                    == .saved(set.id)
                            )
                            .tag(CalendarSetSettingsSelection.saved(set.id))
                            .contextMenu {
                                Button("Rename") {
                                    beginRenaming(set)
                                }
                                Button("Delete", role: .destructive) {
                                    pendingDelete = set
                                }
                            }
                            .accessibilityIdentifier(
                                "settings.calendarSets.set.\(set.id)"
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand {
                if let selectedSavedSet {
                    pendingDelete = selectedSavedSet
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    nameEditor = CalendarSetNameEditor(
                        kind: .create,
                        initialName: ""
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create Calendar Set")
                .accessibilityLabel("Create Calendar Set")
                .accessibilityIdentifier("settings.calendarSets.create")

                Button {
                    if let selectedSavedSet {
                        pendingDelete = selectedSavedSet
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedSavedSet == nil)
                .help("Delete selected Calendar Set")
                .accessibilityLabel("Delete selected Calendar Set")

                Spacer()

                Button {
                    moveSelectedSet(by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!canMoveSelectedSet(by: -1))
                .help("Move selected Calendar Set up")
                .accessibilityLabel("Move selected Calendar Set up")

                Button {
                    moveSelectedSet(by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(!canMoveSelectedSet(by: 1))
                .help("Move selected Calendar Set down")
                .accessibilityLabel("Move selected Calendar Set down")
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(minWidth: 205, idealWidth: 220, maxWidth: 240)
    }

    @ViewBuilder
    private var setDetail: some View {
        switch selection ?? .all {
        case .all:
            allCalendarsDetail
        case let .saved(setID):
            if let set = appState.savedCalendarSet(id: setID) {
                savedSetDetail(set)
            } else {
                ContentUnavailableView(
                    "Calendar Set unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(
                        "Choose another set. Missing calendar memberships are preserved when their Set still exists."
                    )
                )
                .onAppear { selection = .all }
            }
        }
    }

    private var allCalendarsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                detailHeader(
                    title: "All Calendars",
                    subtitle: "Every calendar enabled in the Calendars settings."
                ) {
                    Button("Use All Calendars") {
                        _ = appState.selectCalendarSet(.all)
                    }
                    .disabled(appState.selectedCalendarSet == .all)
                }

                GroupBox("How Sets Work") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "Saved Sets are exact calendar combinations. A calendar may belong to more than one Set."
                        )
                        Text(
                            "Disabling a calendar in the Calendars tab hides it from All Calendars and every saved Set without deleting its memberships."
                        )
                        Text(
                            "Availability blocking remains independent, so a hidden calendar can still reserve busy time."
                        )
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                Button("Create Calendar Set…") {
                    nameEditor = CalendarSetNameEditor(
                        kind: .create,
                        initialName: ""
                    )
                }
                .buttonStyle(.borderedProminent)

                operationError
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func savedSetDetail(
        _ set: SavedCalendarSetSnapshot
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                detailHeader(
                    title: set.name,
                    subtitle: setSummary(set)
                ) {
                    Button("Use This Set") {
                        _ = appState.selectCalendarSet(.saved(set.id))
                    }
                    .disabled(appState.selectedCalendarSet == .saved(set.id))

                    Menu {
                        Button("Rename") { beginRenaming(set) }
                        Button("Delete", role: .destructive) {
                            pendingDelete = set
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("More actions for \(set.name)")
                }

                if set.memberships.isEmpty {
                    Label(
                        "This Set is empty. Include calendars below before using it, or keep it as an intentional empty view.",
                        systemImage: "calendar.badge.plus"
                    )
                    .foregroundStyle(.secondary)
                }

                if appState.calendarAccounts.isEmpty {
                    GroupBox("Available Calendars") {
                        Text(
                            appState.canDetermineCalendarSetMembershipAvailability
                                ? "No calendars are currently loaded. Existing memberships remain saved and will resolve again only when the exact calendar identifier returns."
                                : "Calendar availability cannot be verified yet. Existing memberships remain saved while access or loading recovers."
                        )
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                } else {
                    ForEach(appState.calendarAccounts) { account in
                        membershipAccountGroup(account, set: set)
                    }
                }

                let unavailable = appState.unavailableMemberships(in: set)
                if !unavailable.isEmpty {
                    unavailableMembershipGroup(unavailable, set: set)
                }

                operationError
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailHeader<Actions: View>(
        title: String,
        subtitle: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actions()
            }
            Divider()
        }
    }

    private func membershipAccountGroup(
        _ account: CalendarAccountDescriptor,
        set: SavedCalendarSetSnapshot
    ) -> some View {
        let includedCount = account.calendars.filter {
            set.calendarIdentifiers.contains($0.id)
        }.count

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(includedCount) of \(account.calendars.count) included")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu("Account Membership") {
                        Button("Include All") {
                            _ = appState.setCalendarSetMemberships(
                                true,
                                sources: account.calendars,
                                setID: set.id
                            )
                        }
                        Button("Remove All") {
                            _ = appState.setCalendarSetMemberships(
                                false,
                                sources: account.calendars,
                                setID: set.id
                            )
                        }
                    }
                }

                Divider()

                ForEach(account.calendars) { source in
                    Toggle(isOn: membershipBinding(source: source, setID: set.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title)
                                Text(appState.calendarRole(for: source).title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !appState.calendarUsagePolicy(for: source).isVisible {
                                Text("Disabled globally")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel(
                        "Include \(source.title) in \(set.name)"
                    )
                    .accessibilityValue(
                        set.calendarIdentifiers.contains(source.id)
                            ? "Included"
                            : "Not included"
                    )
                    .accessibilityIdentifier(
                        "settings.calendarSets.\(set.id).calendar.\(source.id)"
                    )
                }
            }
            .padding(.top, 4)
        } label: {
            Label(
                account.title,
                systemImage: account.accountType == .exchange
                    ? "building.2"
                    : "person.crop.circle"
            )
        }
    }

    private func unavailableMembershipGroup(
        _ memberships: [CalendarSetMembership],
        set: SavedCalendarSetSnapshot
    ) -> some View {
        let replacementSources = appState.calendarAccounts.flatMap(\.calendars)
            .filter { !set.calendarIdentifiers.contains($0.id) }

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "These exact calendar identifiers are not currently available. KaosCal does not reconnect them by name."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(memberships) { membership in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(membership.calendarTitleSnapshot)
                            Text(membership.sourceTitleSnapshot)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu("Replace…") {
                            ForEach(appState.calendarAccounts) { account in
                                Section(account.title) {
                                    ForEach(account.calendars.filter {
                                        !set.calendarIdentifiers.contains($0.id)
                                    }) { source in
                                        Button(source.title) {
                                            _ = appState.rebindCalendarSetMembership(
                                                membership,
                                                to: source
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .disabled(replacementSources.isEmpty)
                        .accessibilityLabel(
                            "Replace \(membership.calendarTitleSnapshot) in \(set.name)"
                        )
                        Button("Remove", role: .destructive) {
                            _ = appState.removeCalendarSetMembership(membership)
                        }
                        .accessibilityLabel(
                            "Remove \(membership.calendarTitleSnapshot) from \(set.name)"
                        )
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.top, 4)
        } label: {
            Label(
                "Unavailable Calendars",
                systemImage: "calendar.badge.exclamationmark"
            )
        }
    }

    private func membershipBinding(
        source: CalendarSource,
        setID: String
    ) -> Binding<Bool> {
        Binding(
            get: {
                appState.savedCalendarSet(id: setID)?
                    .calendarIdentifiers.contains(source.id) == true
            },
            set: {
                _ = appState.setCalendarSetMembership(
                    $0,
                    source: source,
                    setID: setID
                )
            }
        )
    }

    private var selectedSavedSet: SavedCalendarSetSnapshot? {
        guard case let .saved(setID) = selection ?? .all else { return nil }
        return appState.savedCalendarSet(id: setID)
    }

    private func setRow(
        title: String,
        systemImage: String,
        isActive: Bool
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(KaosCalTheme.accent)
                    .accessibilityLabel("Active")
            }
        }
    }

    @ViewBuilder
    private var operationError: some View {
        if let message = appState.localOperationError {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setSummary(_ set: SavedCalendarSetSnapshot) -> String {
        guard appState.canDetermineCalendarSetMembershipAvailability else {
            return "\(set.memberships.count) calendars · availability unknown"
        }
        let availableByID = Dictionary(
            uniqueKeysWithValues: appState.calendarSources.map { ($0.id, $0) }
        )
        let unavailableCount = set.memberships.filter {
            availableByID[$0.calendarIdentifier] == nil
        }.count
        let disabledCount = set.memberships.compactMap {
            availableByID[$0.calendarIdentifier]
        }.filter {
            !appState.calendarUsagePolicy(for: $0).isVisible
        }.count
        var parts = ["\(set.memberships.count) calendars"]
        if disabledCount > 0 { parts.append("\(disabledCount) disabled") }
        if unavailableCount > 0 {
            parts.append("\(unavailableCount) unavailable")
        }
        return parts.joined(separator: " · ")
    }

    private func beginRenaming(_ set: SavedCalendarSetSnapshot) {
        nameEditor = CalendarSetNameEditor(
            kind: .rename(set.id),
            initialName: set.name
        )
    }

    private func canMoveSelectedSet(by offset: Int) -> Bool {
        guard let selectedSavedSet,
              let index = appState.savedCalendarSets.firstIndex(where: {
                  $0.id == selectedSavedSet.id
              }) else {
            return false
        }
        return appState.savedCalendarSets.indices.contains(index + offset)
    }

    private func moveSelectedSet(by offset: Int) {
        guard let selectedSavedSet,
              let index = appState.savedCalendarSets.firstIndex(where: {
                  $0.id == selectedSavedSet.id
              }),
              appState.savedCalendarSets.indices.contains(index + offset) else {
            return
        }
        var ids = appState.savedCalendarSets.map(\.id)
        ids.swapAt(index, index + offset)
        _ = appState.reorderCalendarSets(ids)
    }
}

private struct CalendarSetNameEditorView: View {
    @ObservedObject var appState: AppState
    let editor: CalendarSetNameEditor
    let onComplete: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameIsFocused: Bool
    @State private var name: String
    @State private var startsWithEnabledCalendars = true

    init(
        appState: AppState,
        editor: CalendarSetNameEditor,
        onComplete: @escaping (String?) -> Void
    ) {
        self.appState = appState
        self.editor = editor
        self.onComplete = onComplete
        _name = State(initialValue: editor.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isCreating ? "New Calendar Set" : "Rename Calendar Set")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $name)
                .focused($nameIsFocused)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings.calendarSets.name")

            if isCreating {
                Toggle(
                    "Start with calendars currently enabled in KaosCal",
                    isOn: $startsWithEnabledCalendars
                )
                Text(
                    startsWithEnabledCalendars
                        ? "You can add or remove calendars after creating the Set."
                        : "An empty Set intentionally shows no calendars until you add them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let message = appState.localOperationError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                    onComplete(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button(isCreating ? "Create" : "Save") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
                .accessibilityIdentifier("settings.calendarSets.name.confirm")
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { nameIsFocused = true }
        .accessibilityIdentifier("settings.calendarSets.nameSheet")
    }

    private var isCreating: Bool {
        if case .create = editor.kind { return true }
        return false
    }

    private var validationMessage: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a name for this Calendar Set." }
        if trimmed.unicodeScalars.count
            > CalendarSetRepository.maximumNameLength {
            return "Calendar Set names can contain at most \(CalendarSetRepository.maximumNameLength) characters."
        }
        let editingID: String? = switch editor.kind {
        case .create: nil
        case let .rename(setID): setID
        }
        if appState.savedCalendarSets.contains(where: {
            $0.id != editingID
                && $0.name.compare(
                    trimmed,
                    options: [.caseInsensitive]
                ) == .orderedSame
        }) {
            return "A Calendar Set with this name already exists."
        }
        return nil
    }

    private func submit() {
        guard validationMessage == nil else { return }
        switch editor.kind {
        case .create:
            let identifiers: Set<String> = startsWithEnabledCalendars
                ? Set(appState.calendarSources.filter {
                    appState.calendarUsagePolicy(for: $0).isVisible
                }.map(\.id))
                : []
            guard let created = appState.createCalendarSet(
                name: name,
                calendarIdentifiers: identifiers
            ) else {
                return
            }
            dismiss()
            onComplete(created.id)
        case let .rename(setID):
            guard appState.renameCalendarSet(id: setID, name: name) else {
                return
            }
            dismiss()
            onComplete(nil)
        }
    }
}

struct LocalDataSettingsView: View {
    @ObservedObject var appState: AppState

    @State private var pendingImportURL: URL?
    @State private var showsImportConfirmation = false
    @State private var showsResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let message = appState.localDataOperationMessage {
                    operationMessage(message)
                }

                backupSection
                restoreSection
                storageSection
                privacySection
                resetSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620, height: 620)
        .tint(KaosCalTheme.accent)
        .alert(
            "Replace KaosCal local data?",
            isPresented: $showsImportConfirmation
        ) {
            Button("Replace Local Data", role: .destructive) {
                importSelectedBackup()
            }
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text(
                "KaosCal will first create an automatic backup of the current local database, then replace it with \(pendingImportURL?.lastPathComponent ?? "the selected backup"). The recovery backup remains on this Mac, and its location appears in the result. Calendar events in your connected accounts are not changed."
            )
        }
        .sheet(isPresented: $showsResetConfirmation) {
            ResetLocalDataConfirmationView(
                isOperationInProgress: isOperationInProgress,
                onCancel: {
                    showsResetConfirmation = false
                },
                onConfirm: {
                    showsResetConfirmation = false
                    Task {
                        _ = await appState.resetLocalData()
                    }
                }
            )
        }
        .accessibilityIdentifier("settings.localData")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local Data")
                .font(.title2.weight(.semibold))
            Text(
                "Back up or restore the Event Briefs, tasks, notes, and change history stored by KaosCal on this Mac."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var backupSection: some View {
        settingsGroup(
            title: "Manual Backup",
            systemImage: "archivebox"
        ) {
            Text(
                "Export a ZIP containing the KaosCal local database and a backup manifest."
            )
            .foregroundStyle(.secondary)

            Button {
                selectExportDestination()
            } label: {
                operationLabel(
                    title: "Export Backup…",
                    activeTitle: "Exporting…",
                    activeState: .exporting,
                    systemImage: "square.and.arrow.up"
                )
            }
            .disabled(isOperationInProgress || !localStoreIsAvailable)
            .accessibilityIdentifier("settings.localData.export")
        }
    }

    private var restoreSection: some View {
        settingsGroup(
            title: "Restore From Backup",
            systemImage: "arrow.counterclockwise.circle"
        ) {
            Text(
                "Import replaces the current KaosCal local database only after validating the selected ZIP. An automatic backup of the current data is created first."
            )
            .foregroundStyle(.secondary)

            Button {
                selectImportArchive()
            } label: {
                operationLabel(
                    title: "Import Backup…",
                    activeTitle: "Importing…",
                    activeState: .importing,
                    systemImage: "square.and.arrow.down"
                )
            }
            .disabled(isOperationInProgress || !localStoreIsAvailable)
            .accessibilityIdentifier("settings.localData.import")
        }
    }

    private var storageSection: some View {
        settingsGroup(
            title: "Storage",
            systemImage: "internaldrive"
        ) {
            if let databaseURL = appState.localDataDatabaseURL {
                Text(databaseURL.path(percentEncoded: false))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Local database location")
                    .accessibilityValue(databaseURL.path(percentEncoded: false))

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: databaseURL.path))
                .accessibilityIdentifier("settings.localData.revealDatabase")
            } else {
                Text("The local database is not available in this session.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        settingsGroup(
            title: "What Is Included",
            systemImage: "hand.raised"
        ) {
            Label(
                "Included: Event Brief checklists and notes, personal tasks, saved Calendar Set names and memberships, calendar role and usage preferences, the active Set selection, and local change history.",
                systemImage: "checkmark.circle"
            )
            Label(
                "Linked event metadata such as title, time, location, calendar identifiers, and change snapshots—including original notes snapshots—can be included.",
                systemImage: "info.circle"
            )
            Label(
                "Not included as dedicated fields: complete calendar event records, complete attendee lists, account credentials, or Exchange passwords.",
                systemImage: "xmark.circle"
            )
            Label(
                "Text in notes and tasks is copied verbatim and is not scanned or redacted. Any password, token, or other secret typed there will be included.",
                systemImage: "exclamationmark.shield"
            )

            Text(
                "Export, import, and reset do not create, edit, or delete events in Calendar or Exchange."
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(KaosCalTheme.accent)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                "Backup ZIP files are not encrypted by KaosCal. Their contents are stored in plaintext at the location you choose, including cloud folders, so keep them somewhere you trust."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resetSection: some View {
        settingsGroup(
            title: "Reset Local Data",
            systemImage: "trash"
        ) {
            Text(
                "Remove KaosCal checklists, personal tasks, notes, saved Calendar Sets, calendar preferences, and change history from the active database. An automatic recovery backup remains on this Mac, and its location appears in the result. Original calendar events remain in their calendar accounts."
            )
            .foregroundStyle(.secondary)

            Button(role: .destructive) {
                showsResetConfirmation = true
            } label: {
                operationLabel(
                    title: "Reset Local Data…",
                    activeTitle: "Resetting…",
                    activeState: .resetting,
                    systemImage: "trash"
                )
            }
            .disabled(isOperationInProgress || !localStoreIsAvailable)
            .accessibilityIdentifier("settings.localData.reset")
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    private func operationMessage(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(KaosCalTheme.accent)
                .accessibilityHidden(true)

            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button {
                appState.clearLocalDataOperationMessage()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss operation result")
            .accessibilityIdentifier("settings.localData.dismissMessage")
        }
        .padding(12)
        .background(
            KaosCalTheme.accentSoft,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.localData.operationMessage")
    }

    @ViewBuilder
    private func operationLabel(
        title: String,
        activeTitle: String,
        activeState: LocalDataOperationState,
        systemImage: String
    ) -> some View {
        if appState.localDataOperationState == activeState {
            Label {
                Text(activeTitle)
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private var isOperationInProgress: Bool {
        appState.localDataOperationState != .idle
    }

    private var localStoreIsAvailable: Bool {
        if case .ready = appState.localContextStoreState {
            return appState.localDataDatabaseURL != nil
        }
        return false
    }

    private func selectExportDestination() {
        let panel = NSSavePanel()
        panel.title = "Export KaosCal Backup"
        panel.prompt = "Export"
        panel.nameFieldStringValue = Self.suggestedBackupFilename
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        Task {
            _ = await appState.exportLocalDataBackup(to: destinationURL)
        }
    }

    private func selectImportArchive() {
        let panel = NSOpenPanel()
        panel.title = "Import KaosCal Backup"
        panel.prompt = "Choose Backup"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let archiveURL = panel.url else {
            return
        }

        pendingImportURL = archiveURL
        showsImportConfirmation = true
    }

    private func importSelectedBackup() {
        guard let archiveURL = pendingImportURL else { return }
        pendingImportURL = nil

        Task {
            _ = await appState.importLocalDataBackup(from: archiveURL)
        }
    }

    private static var suggestedBackupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "KaosCal-Backup-\(formatter.string(from: Date())).zip"
    }
}

struct SettingsRootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedSettingsPane) {
            CalendarUsageSettingsView(appState: appState)
                .tabItem {
                    Label("Calendars", systemImage: "calendar")
                }
                .tag(SettingsPane.calendars)
            CalendarSetSettingsView(appState: appState)
                .tabItem {
                    Label(
                        "Calendar Sets",
                        systemImage: "calendar.badge.checkmark"
                    )
                }
                .tag(SettingsPane.calendarSets)
            if let coordinator = appState.taskProviderCoordinator {
                TaskProviderSettingsView(
                    appState: appState,
                    coordinator: coordinator
                )
                .tabItem {
                    Label("Task Providers", systemImage: "checklist")
                }
                .tag(SettingsPane.taskProviders)
            }
            LocalDataSettingsView(appState: appState)
                .tabItem {
                    Label("Local Data", systemImage: "externaldrive")
                }
                .tag(SettingsPane.localData)
        }
    }
}

private struct TaskProviderSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var coordinator: TaskProviderCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Task Providers")
                        .font(.title2.weight(.semibold))
                    Text(
                        "Choose where tasks created from each calendar should be mirrored. Personal tasks remain local to KaosCal in this release."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                providerAccessSection
                destinationsSection

                if let message = coordinator.lastErrorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620, height: 620)
        .tint(KaosCalTheme.accent)
        .task {
            coordinator.refresh()
        }
        .accessibilityIdentifier("settings.taskProviders")
    }

    private var providerAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsGroup(title: "Apple Reminders", systemImage: "checklist") {
                HStack {
                    providerStateLabel(for: .appleReminders)
                    Spacer()
                    if coordinator.authorizationState != .authorized {
                        Button("Request Access") {
                            Task { await coordinator.requestAccess() }
                        }
                    } else {
                        Button("Refresh") {
                            coordinator.refresh()
                        }
                    }
                }
                Text(
                    "KaosCal uses the system Reminders permission and never uploads task data to a KaosCal service."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            settingsGroup(title: "OAuth Task Providers", systemImage: "person.badge.key") {
                ForEach([
                    TaskProviderKind.googleTasks,
                    .todoist,
                    .microsoftToDo
                ], id: \.self) { provider in
                    HStack(alignment: .firstTextBaseline) {
                        Label(provider.title, systemImage: provider.settingsIcon)
                        Spacer()
                        providerStateLabel(for: provider)
                        if coordinator.isConfigured(provider) {
                            if coordinator.authorizationState(for: provider) == .authorized {
                                Button("Disconnect", role: .destructive) {
                                    coordinator.disconnectOAuthProvider(provider)
                                }
                            } else if coordinator.supportsInAppOAuthConnection(provider) {
                                if coordinator.isConnectingOAuthProvider(provider) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityLabel("Connecting \(provider.title)")
                                    Text("Connecting…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Connect") {
                                        Task {
                                            await coordinator.connectOAuthProvider(provider)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !coordinator.isConfigured(provider) {
                        Text("This build is missing required OAuth client configuration for \(provider.title).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if coordinator.authorizationState(for: provider) != .authorized,
                              !coordinator.supportsInAppOAuthConnection(provider) {
                        Text("This provider needs its registered HTTPS callback/return-to-app deployment before it can be connected here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let message = coordinator.oauthConnectionError(
                        for: provider
                    ) {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("OAuth credentials are stored only in the macOS Keychain. Provider task descriptions are not copied to local backups.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var destinationsSection: some View {
        settingsGroup(title: "Calendar Destinations", systemImage: "calendar.badge.checkmark") {
            if appState.calendarSources.isEmpty {
                Text("No calendars are currently available.")
                .foregroundStyle(.secondary)
            } else if coordinator.taskLists.isEmpty {
                Text("Connect a task provider and refresh it to choose a destination list.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.calendarSources) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(source.title)
                            .font(.headline)
                        Text(source.sourceTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Destination", selection: destinationBinding(for: source)) {
                            Text("Local only")
                                .tag("")
                            ForEach(coordinator.taskLists.filter(\.isWritable)) { list in
                                Text("\(list.provider.title) · \(list.sourceTitle) · \(list.title)")
                                    .tag(list.destinationSelectionKey)
                            }
                        }
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func destinationBinding(for source: CalendarSource) -> Binding<String> {
        Binding(
            get: {
                coordinator.destinationSelection(for: source.id)
            },
            set: { value in
                let list = coordinator.taskLists.first {
                    $0.destinationSelectionKey == value
                }
                coordinator.saveDestination(
                    calendarIdentifier: source.id,
                    list: list
                )
            }
        )
    }

    private func providerStateLabel(for provider: TaskProviderKind) -> some View {
        let state = coordinator.authorizationState(for: provider)
        return Label(
            state.title,
            systemImage: state == .authorized
                ? "checkmark.circle.fill"
                : "lock.circle"
        )
        .foregroundStyle(state == .authorized ? .green : .secondary)
    }

    private func settingsGroup<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ResetLocalDataConfirmationView: View {
    let isOperationInProgress: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var confirmationText = ""
    @FocusState private var confirmationFieldIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Reset KaosCal Local Data", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)

            Text(
                "This removes KaosCal checklists, personal tasks, notes, role preferences, and change history from the active database. An automatic recovery backup remains on this Mac. Calendar and Exchange events are not deleted."
            )
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Type RESET to continue.")
                    .font(.callout.weight(.medium))

                TextField("RESET", text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .focused($confirmationFieldIsFocused)
                    .accessibilityLabel("Type RESET to confirm local data deletion")
                    .accessibilityIdentifier("settings.localData.resetConfirmation")
                    .onSubmit {
                        if confirmationIsValid && !isOperationInProgress {
                            onConfirm()
                        }
                    }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Delete Local Data", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!confirmationIsValid || isOperationInProgress)
                    .accessibilityIdentifier("settings.localData.confirmReset")
            }
        }
        .padding(24)
        .frame(width: 470)
        .onAppear {
            confirmationFieldIsFocused = true
        }
        .interactiveDismissDisabled(isOperationInProgress)
        .accessibilityIdentifier("settings.localData.resetSheet")
    }

    private var confirmationIsValid: Bool {
        confirmationText == "RESET"
    }
}
