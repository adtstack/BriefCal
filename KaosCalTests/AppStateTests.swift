import XCTest
@testable import KaosCal

@MainActor
final class AppStateTests: XCTestCase {
    func testHostedTestBootstrapNeverOpensDefaultDatabase() {
        var didOpenDatabase = false
        let environment = ProcessInfo.processInfo.environment

        XCTAssertNotNil(environment["XCTestConfigurationFilePath"])

        let state = AppBootstrap.makeAppState(
            environment: environment,
            openDatabase: {
                didOpenDatabase = true
                return try AppDatabase.inMemory()
            }
        )

        XCTAssertFalse(didOpenDatabase)
        XCTAssertNil(state.contextStore)
        XCTAssertEqual(state.localContextStoreState, .unavailable)
    }

    func testDefaultsToWeekAtStartOfToday() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )

        XCTAssertEqual(state.selectedSection, .week)
        XCTAssertEqual(state.focusedDate, calendar.startOfDay(for: baseline))
        XCTAssertEqual(state.calendarContentState, .disconnected)
    }

    func testMovesWeekBySevenDays() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )

        state.moveFocusedPeriod(direction: 1)

        let expected = calendar.date(
            byAdding: .day,
            value: 7,
            to: calendar.startOfDay(for: baseline)
        )
        XCTAssertEqual(state.focusedDate, expected)
    }

    func testSelectingDayChangesNavigationStep() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )

        state.select(.day)
        state.moveFocusedPeriod(direction: -1)

        let expected = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: baseline)
        )
        XCTAssertEqual(state.focusedDate, expected)
    }

    func testGoToTodayUsesInjectedClock() {
        let initial = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_172_800)
        var current = initial
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let state = AppState(
            calendar: calendar,
            now: { current },
            calendarProvider: FakeCalendarProvider()
        )

        current = later
        state.goToToday()

        XCTAssertEqual(state.focusedDate, calendar.startOfDay(for: later))
    }

    func testAgendaMovesByWeekAndTasksMoveByDay() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )

        state.select(.agenda)
        state.moveFocusedPeriod(direction: 1)
        let afterAgenda = state.focusedDate

        state.select(.tasks)
        state.moveFocusedPeriod(direction: 1)

        XCTAssertEqual(
            afterAgenda,
            calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: baseline))
        )
        XCTAssertEqual(
            state.focusedDate,
            calendar.date(byAdding: .day, value: 1, to: afterAgenda)
        )
    }
}
