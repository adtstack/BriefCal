import SwiftUI

@main
struct KaosCalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("KaosCal") {
            CalendarShellView(appState: appState)
                .frame(minWidth: 1_080, minHeight: 680)
        }
        .defaultSize(width: 1_360, height: 840)
        .commands {
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
