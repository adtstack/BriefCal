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
    @Published private(set) var calendarAuthorizationState: CalendarAuthorizationState
    @Published private(set) var calendarSources: [CalendarSource] = []
    @Published private(set) var events: [DisplayEvent] = []

    let calendar: Calendar
    private let now: () -> Date
    private let calendarProvider: CalendarProviding
    private var storeRefreshTask: Task<Void, Never>?

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        calendarProvider: CalendarProviding? = nil
    ) {
        let calendarProvider = calendarProvider ?? EventKitProvider()
        self.calendar = calendar
        self.now = now
        self.calendarProvider = calendarProvider
        calendarAuthorizationState = calendarProvider.authorizationState
        focusedDate = calendar.startOfDay(for: now())

        calendarProvider.storeChangeHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleStoreRefresh()
            }
        }
    }

    var selectedEvent: DisplayEvent? {
        guard let selectedEventID else { return nil }
        return events.first { $0.id == selectedEventID }
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

    func loadCalendarStatus() async {
        calendarAuthorizationState = calendarProvider.authorizationState
        switch calendarAuthorizationState {
        case .notDetermined:
            clearCalendarData()
            calendarContentState = .disconnected
        case .fullAccess:
            await refreshCalendarData()
        case .denied, .restricted, .writeOnly:
            clearCalendarData()
            calendarContentState = .permissionDenied
        case .unknown:
            clearCalendarData()
            calendarContentState = .failed("Unknown calendar permission state")
        }
    }

    func requestCalendarAccess() async {
        calendarContentState = .loading
        do {
            let granted = try await calendarProvider.requestFullAccess()
            calendarAuthorizationState = calendarProvider.authorizationState
            guard granted, calendarAuthorizationState.canReadEvents else {
                clearCalendarData()
                calendarContentState = .permissionDenied
                return
            }
            await refreshCalendarData()
        } catch {
            calendarAuthorizationState = calendarProvider.authorizationState
            if !calendarAuthorizationState.canReadEvents {
                clearCalendarData()
            }
            switch calendarAuthorizationState {
            case .denied, .restricted, .writeOnly:
                calendarContentState = .permissionDenied
            default:
                calendarContentState = .failed(Self.message(for: error))
            }
        }
    }

    func refreshCalendarData() async {
        calendarAuthorizationState = calendarProvider.authorizationState
        guard calendarAuthorizationState.canReadEvents else {
            clearCalendarData()
            switch calendarAuthorizationState {
            case .notDetermined:
                calendarContentState = .disconnected
            case .denied, .restricted, .writeOnly:
                calendarContentState = .permissionDenied
            case .unknown:
                calendarContentState = .failed("Unknown calendar permission state")
            case .fullAccess:
                break
            }
            return
        }

        calendarContentState = .loading
        do {
            let sources = try calendarProvider.listCalendars()
            let fetchedEvents = try calendarProvider.fetchEvents(in: fetchInterval())
            calendarSources = sources
            events = fetchedEvents

            if let selectedEventID, !fetchedEvents.contains(where: { $0.id == selectedEventID }) {
                self.selectedEventID = nil
            }
            calendarContentState = fetchedEvents.isEmpty ? .empty : .loaded
        } catch {
            calendarContentState = .failed(Self.message(for: error))
        }
    }

    private func scheduleStoreRefresh() {
        storeRefreshTask?.cancel()
        storeRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            await self?.refreshCalendarData()
        }
    }

    private func clearCalendarData() {
        calendarSources = []
        events = []
        selectedEventID = nil
    }

    private func fetchInterval() -> DateInterval {
        let today = calendar.startOfDay(for: now())
        let start = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 90, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
