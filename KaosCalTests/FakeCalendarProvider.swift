import Foundation
@testable import KaosCal

enum FakeCalendarProviderError: LocalizedError {
    case failed

    var errorDescription: String? { "Calendar provider failed" }
}

@MainActor
final class FakeCalendarProvider: CalendarProviding {
    var authorizationState: CalendarAuthorizationState
    var storeChangeHandler: (() -> Void)?
    var requestResult = true
    var calendars: [CalendarSource] = []
    var events: [DisplayEvent] = []
    var eventsForInterval: ((DateInterval) -> [DisplayEvent])?
    var error: Error?
    private(set) var requestCallCount = 0
    private(set) var listCallCount = 0
    private(set) var fetchCallCount = 0
    private(set) var lastFetchInterval: DateInterval?

    init(authorizationState: CalendarAuthorizationState = .notDetermined) {
        self.authorizationState = authorizationState
    }

    func requestFullAccess() async throws -> Bool {
        requestCallCount += 1
        if let error { throw error }
        authorizationState = requestResult ? .fullAccess : .denied
        return requestResult
    }

    func listCalendars() throws -> [CalendarSource] {
        listCallCount += 1
        if let error { throw error }
        return calendars
    }

    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent] {
        fetchCallCount += 1
        lastFetchInterval = interval
        if let error { throw error }
        return eventsForInterval?(interval) ?? events
    }

    func sendStoreChanged() {
        storeChangeHandler?()
    }
}
