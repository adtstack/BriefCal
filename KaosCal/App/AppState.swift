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
    private var rangeLoadTask: Task<Void, Never>?
    private var loadedEventInterval: DateInterval?

    init(
        calendar: Calendar = .autoupdatingCurrent,
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

    var visibleDates: [Date] {
        let section = selectedSection ?? .week
        let focusedDay = calendar.startOfDay(for: focusedDate)
        let start: Date
        let dayCount: Int

        switch section {
        case .day, .tasks:
            start = focusedDay
            dayCount = 1
        case .week, .agenda:
            start = calendar.dateInterval(
                of: .weekOfYear,
                for: focusedDay
            )?.start ?? focusedDay
            dayCount = 7
        }

        return (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    var visibleInterval: DateInterval {
        let start = visibleDates.first ?? calendar.startOfDay(for: focusedDate)
        let finalDate = visibleDates.last ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: finalDate)
            ?? finalDate.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    var visibleEvents: [DisplayEvent] {
        let interval = visibleInterval
        return events.filter {
            let range = CalendarEventDateFormatting.effectiveDateRange(
                for: $0,
                calendar: calendar
            )
            return range.start < interval.end && range.end > interval.start
        }.sorted { lhs, rhs in
            let lhsRange = CalendarEventDateFormatting.effectiveDateRange(
                for: lhs,
                calendar: calendar
            )
            let rhsRange = CalendarEventDateFormatting.effectiveDateRange(
                for: rhs,
                calendar: calendar
            )
            if lhsRange.start != rhsRange.start {
                return lhsRange.start < rhsRange.start
            }
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay
            }
            return lhs.id < rhs.id
        }
    }

    var focusedPeriodTitle: String {
        switch selectedSection ?? .week {
        case .day, .tasks:
            return CalendarEventDateFormatting.longDate(
                focusedDate,
                calendar: calendar
            )
        case .week, .agenda:
            guard let start = visibleDates.first,
                  let end = visibleDates.last else {
                return CalendarEventDateFormatting.longDate(
                    focusedDate,
                    calendar: calendar
                )
            }
            return "\(CalendarEventDateFormatting.abbreviatedDate(start, calendar: calendar)) – \(CalendarEventDateFormatting.abbreviatedDate(end, calendar: calendar))"
        }
    }

    func select(_ section: WorkspaceSection) {
        selectedSection = section
        visiblePeriodDidChange()
    }

    func goToToday() {
        focusedDate = calendar.startOfDay(for: now())
        visiblePeriodDidChange()
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
        visiblePeriodDidChange()
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

    func refreshCalendarData(in requestedInterval: DateInterval? = nil) async {
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
            let interval = requestedInterval
                ?? loadedEventInterval
                ?? initialFetchInterval()
            let sources = try calendarProvider.listCalendars()
            let fetchedEvents = try calendarProvider.fetchEvents(in: interval)
            calendarSources = sources
            events = fetchedEvents
            loadedEventInterval = interval

            if let selectedEventID, !fetchedEvents.contains(where: { $0.id == selectedEventID }) {
                self.selectedEventID = nil
            }
            clearSelectionOutsideVisiblePeriod()
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
            guard let self else { return }
            await self.refreshCalendarData(in: self.loadedEventInterval)
        }
    }

    private func visiblePeriodDidChange() {
        clearSelectionOutsideVisiblePeriod()
        scheduleVisiblePeriodLoadIfNeeded()
    }

    private func clearSelectionOutsideVisiblePeriod() {
        guard let selectedEventID else { return }
        if !visibleEvents.contains(where: { $0.id == selectedEventID }) {
            self.selectedEventID = nil
        }
    }

    private func scheduleVisiblePeriodLoadIfNeeded() {
        rangeLoadTask?.cancel()
        rangeLoadTask = nil
        guard calendarAuthorizationState.canReadEvents else { return }
        let visible = visibleInterval
        if let loadedEventInterval,
           loadedEventInterval.start <= visible.start,
           loadedEventInterval.end >= visible.end {
            return
        }

        let interval = expandedFetchInterval(around: visible)
        rangeLoadTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await self?.refreshCalendarData(in: interval)
        }
    }

    private func clearCalendarData() {
        rangeLoadTask?.cancel()
        calendarSources = []
        events = []
        selectedEventID = nil
        loadedEventInterval = nil
    }

    private func initialFetchInterval() -> DateInterval {
        let today = calendar.startOfDay(for: now())
        let start = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 90, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    private func expandedFetchInterval(around visible: DateInterval) -> DateInterval {
        let start = calendar.date(
            byAdding: .day,
            value: -30,
            to: visible.start
        ) ?? visible.start
        let end = calendar.date(
            byAdding: .day,
            value: 90,
            to: visible.end
        ) ?? visible.end
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
