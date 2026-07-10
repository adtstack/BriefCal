import SwiftUI

@main
struct KaosCalApp: App {
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(wrappedValue: AppBootstrap.makeAppState())
    }

    var body: some Scene {
        WindowGroup("KaosCal") {
            CalendarShellView(appState: appState)
                .frame(minWidth: 1_080, minHeight: 680)
        }
        .defaultSize(width: 1_360, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Event") {
                    appState.beginCreatingEvent()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(
                    !appState.calendarAuthorizationState.canReadEvents
                        || appState.eventEditorSession != nil
                        || appState.eventEditorOperationState != .idle
                )
            }
            CommandMenu("Navigate") {
                navigationCommand("Day", section: .day, key: "1")
                navigationCommand("Week", section: .week, key: "2")
                navigationCommand("Agenda", section: .agenda, key: "3")
                navigationCommand("Tasks", section: .tasks, key: "4")
                Divider()
                Button("Today") {
                    appState.goToToday()
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
    }

    private func navigationCommand(
        _ title: String,
        section: WorkspaceSection,
        key: KeyEquivalent
    ) -> some View {
        Button(title) {
            appState.select(section)
        }
        .keyboardShortcut(key, modifiers: [.command])
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
            return AppState(
                contextStore: contextStore,
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
