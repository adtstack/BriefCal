import SwiftUI

@main
struct KaosCalApp: App {
    @StateObject private var bootstrap: AppBootstrapCoordinator

    init() {
        _bootstrap = StateObject(wrappedValue: AppBootstrapCoordinator())
    }

    var body: some Scene {
        WindowGroup("KaosCal") {
            KaosCalRootView(bootstrap: bootstrap)
                .frame(minWidth: 1_080, minHeight: 680)
                .onOpenURL { url in
                    Task {
                        await bootstrap.appState.openTaskDeepLink(url)
                    }
                }
        }
        .defaultSize(width: 1_360, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Event") {
                    bootstrap.appState.beginCreatingEvent()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(
                    !bootstrap.appState.calendarAuthorizationState.canReadEvents
                        || bootstrap.appState.eventEditorSession != nil
                        || bootstrap.appState.eventEditorOperationState != .idle
                )
            }
            CommandMenu("Navigate") {
                navigationCommand("Day", section: .day, key: "1")
                navigationCommand("Week", section: .week, key: "2")
                navigationCommand("Agenda", section: .agenda, key: "3")
                navigationCommand("Tasks", section: .tasks, key: "4")
                Divider()
                Button("Today") {
                    bootstrap.appState.goToToday()
                }
                .keyboardShortcut("t", modifiers: [.command])
                Divider()
                Button("Reload Current View") {
                    if bootstrap.appState.selectedSection == .tasks {
                        bootstrap.appState.refreshTaskCenter()
                    } else {
                        Task {
                            await bootstrap.appState.refreshCalendarData()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            if case let .failed(message) = bootstrap.appState.localContextStoreState,
               bootstrap.canRecoverFromBootstrap {
                BootstrapLocalDataRecoveryView(
                    message: message,
                    operationState: bootstrap.recoveryOperationState,
                    databaseURL: bootstrap.defaultDatabaseURL,
                    recover: bootstrap.recover
                )
                .frame(width: 620, height: 520)
            } else {
                SettingsRootView(appState: bootstrap.appState)
            }
        }
    }

    private func navigationCommand(
        _ title: String,
        section: WorkspaceSection,
        key: KeyEquivalent
    ) -> some View {
        Button(title) {
            bootstrap.appState.select(section)
        }
        .keyboardShortcut(key, modifiers: [.command])
    }
}

private struct KaosCalRootView: View {
    @ObservedObject var bootstrap: AppBootstrapCoordinator
    @AppStorage("onboarding.phase10.completed") private var completedOnboarding = false

    var body: some View {
        CalendarShellView(
            appState: bootstrap.appState,
            bootstrapRecoveryState: bootstrap.recoveryOperationState,
            bootstrapDatabaseURL: bootstrap.defaultDatabaseURL,
            recoverBootstrap: bootstrap.recover
        )
        .sheet(isPresented: onboardingPresentation) {
            PaidBetaOnboardingView {
                completedOnboarding = true
            }
        }
        .alert(
            "Local data restored",
            isPresented: Binding(
                get: { bootstrap.recoveryNotice != nil },
                set: { if !$0 { bootstrap.recoveryNotice = nil } }
            )
        ) {
            Button("OK") {
                bootstrap.recoveryNotice = nil
            }
        } message: {
            Text(bootstrap.recoveryNotice ?? "Recovery completed.")
        }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: {
                guard !completedOnboarding else { return false }
                if case .ready = bootstrap.appState.localContextStoreState {
                    return true
                }
                return false
            },
            // Completion is intentionally written only by the explicit
            // Continue button. Scene teardown must not silently skip first-run
            // guidance on the next launch.
            set: { _ in }
        )
    }
}

struct PaidBetaOnboardingView: View {
    let complete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 42))
                    .foregroundStyle(KaosCalTheme.accent)
                    .accessibilityHidden(true)
                Text("Welcome to KaosCal")
                    .font(.largeTitle.weight(.semibold))
                Text("Calendar context that stays under your control.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            onboardingRow(
                icon: "lock.shield",
                title: "Uses macOS Calendar access",
                detail: "KaosCal never asks for your Exchange password or MFA code. Full Calendar access is requested by macOS after this introduction."
            )
            onboardingRow(
                icon: "checklist",
                title: "Keep preparation and follow-up local",
                detail: "Select an event, add Before/During/After tasks and notes, then use Task Center to finish the work."
            )
            onboardingRow(
                icon: "externaldrive",
                title: "Back up local data explicitly",
                detail: "Settings can export Event Briefs and tasks. Backup ZIP files are plaintext, so store them somewhere you trust."
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Shortcuts: ⌘1–⌘4 switch views · ⌘N creates an event · ⌘R reloads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Continue to Calendar Access", action: complete)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding.continue")
                }
            }
        }
        .padding(32)
        .frame(width: 680)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("onboarding.phase10")
    }

    private func onboardingRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(KaosCalTheme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum BootstrapRecoveryOperationState: Equatable {
    case idle
    case recovering
    case failed(String)
}

@MainActor
final class AppBootstrapCoordinator: ObservableObject {
    @Published private(set) var appState: AppState
    @Published private(set) var recoveryOperationState: BootstrapRecoveryOperationState = .idle
    @Published var recoveryNotice: String?

    private let environment: [String: String]
    private let openDatabase: () throws -> AppDatabase
    let defaultDatabaseURL: URL?

    var canRecoverFromBootstrap: Bool {
        guard appState.contextStore == nil,
              defaultDatabaseURL != nil,
              case .failed = appState.localContextStoreState else {
            return false
        }
        return true
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        openDatabase: @escaping () throws -> AppDatabase = { try AppDatabase.openDefault() },
        defaultDatabaseURL: URL? = try? AppDatabase.defaultDatabaseURL()
    ) {
        self.environment = environment
        self.openDatabase = openDatabase
        self.defaultDatabaseURL = defaultDatabaseURL
        appState = AppBootstrap.makeAppState(
            environment: environment,
            openDatabase: openDatabase
        )
    }

    func recover(from archiveURL: URL) {
        guard recoveryOperationState != .recovering,
              case .failed = appState.localContextStoreState,
              appState.contextStore == nil,
              let defaultDatabaseURL else { return }
        recoveryOperationState = .recovering

        Task {
            let hasSecurityScope = archiveURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    archiveURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try BootstrapLocalDataRecoveryService(
                        liveDatabaseURL: defaultDatabaseURL
                    ).recover(from: archiveURL)
                }.value
                let recoveredState = AppBootstrap.makeAppState(
                    environment: environment,
                    openDatabase: openDatabase
                )
                guard case .ready = recoveredState.localContextStoreState else {
                    throw BootstrapLocalDataRecoveryError.recoveryFailed(
                        reason: "the restored database still could not bootstrap",
                        rollbackSucceeded: false
                    )
                }
                appState = recoveredState
                recoveryOperationState = .idle
                recoveryNotice = "The selected backup was restored. The database files that failed to open were preserved privately at \(result.quarantinedDatabaseDirectory.path(percentEncoded: false)). Calendar and Exchange events were not changed."
            } catch {
                recoveryOperationState = .failed(
                    error.localizedDescription.isEmpty
                        ? String(describing: error)
                        : error.localizedDescription
                )
            }
        }
    }
}

@MainActor
enum AppBootstrap {
    static func makeAppState(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        openDatabase: () throws -> AppDatabase = {
            try AppDatabase.openDefault()
        }
    ) -> AppState {
        if environment["XCTestConfigurationFilePath"] != nil {
            return AppState(localContextStoreState: .unavailable)
        }

        do {
            let contextStore = ContextStore(
                database: try openDatabase()
            )
            let taskProviderCoordinator = TaskProviderCoordinator(
                contextStore: contextStore
            )
            return AppState(
                contextStore: contextStore,
                taskProviderCoordinator: taskProviderCoordinator,
                localContextStoreState: .ready
            )
        } catch {
            return AppState(
                localContextStoreState: .failed(
                    error.localizedDescription
                )
            )
        }
    }
}
