import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
                "Included: Event Brief checklists and notes, personal tasks, calendar role preferences, and local change history.",
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
                "Remove KaosCal checklists, personal tasks, notes, role preferences, and change history from the active database. An automatic recovery backup remains on this Mac, and its location appears in the result. Original calendar events remain in their calendar accounts."
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
