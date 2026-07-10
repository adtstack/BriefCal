import Combine
import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable, Identifiable {
    case day
    case week
    case agenda
    case tasks

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .agenda: "Agenda"
        case .tasks: "Tasks"
        }
    }

    var symbolName: String {
        switch self {
        case .day: "calendar"
        case .week: "calendar.badge.clock"
        case .agenda: "list.bullet"
        case .tasks: "checklist"
        }
    }

    var accessibilityIdentifier: String { "nav.\(rawValue)" }
}

enum TaskFilter: String, CaseIterable, Hashable, Identifiable {
    case today
    case upcoming
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        }
    }
}

enum CalendarContentState: Equatable {
    case disconnected
    case loading
    case empty
    case loaded
    case permissionDenied
    case failed(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: WorkspaceSection? = .week
    @Published var selectedTaskFilter: TaskFilter = .today
    @Published var focusedDate: Date
    @Published var selectedEventID: String?
    @Published var calendarContentState: CalendarContentState = .disconnected

    let calendar: Calendar
    private let now: () -> Date

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now
        focusedDate = calendar.startOfDay(for: now())
    }

    func select(_ section: WorkspaceSection) {
        selectedSection = section
    }

    func goToToday() {
        focusedDate = calendar.startOfDay(for: now())
    }

    func moveFocusedPeriod(direction: Int) {
        let dayCount: Int
        switch selectedSection ?? .week {
        case .day, .tasks:
            dayCount = 1
        case .week, .agenda:
            dayCount = 7
        }

        focusedDate = calendar.date(
            byAdding: .day,
            value: dayCount * direction,
            to: focusedDate
        ) ?? focusedDate
    }
}
