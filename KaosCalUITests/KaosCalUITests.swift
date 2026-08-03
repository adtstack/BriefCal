import XCTest

final class KaosCalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "KaosCal UI"
            attachment.lifetime = .deleteOnSuccess
            add(attachment)
            app.terminate()
        }
        app = nil
    }

    func testNavigatesAcrossCalendarAndTaskWorkspaces() {
        launch()

        XCTAssertTrue(element("calendar.grid.week").waitForExistence(timeout: 10))

        element("nav.month").click()
        XCTAssertTrue(element("calendar.grid.month").waitForExistence(timeout: 5))

        element("nav.tasks").click()
        XCTAssertTrue(element("taskCenter.content").waitForExistence(timeout: 5))

        element("nav.day").click()
        XCTAssertTrue(element("calendar.grid.day").waitForExistence(timeout: 5))
    }

    func testOpensFixtureEventBriefAndNewEventEditor() {
        launch()

        element("nav.agenda").click()
        let event = element("agenda.event.ui-event-planning")
        XCTAssertTrue(event.waitForExistence(timeout: 10))
        event.click()

        XCTAssertTrue(element("inspector.event").waitForExistence(timeout: 5))
        XCTAssertTrue(element("eventBrief.content").waitForExistence(timeout: 5))

        element("toolbar.newEvent").click()
        XCTAssertTrue(element("eventEditor.title").waitForExistence(timeout: 5))
    }

    func testTransientRefreshFailureKeepsLoadedCalendarVisible() {
        launch(scenario: "refresh-failure")

        element("nav.agenda").click()
        let event = element("agenda.event.ui-event-planning")
        XCTAssertTrue(event.waitForExistence(timeout: 10))

        app.typeKey("r", modifierFlags: .command)

        XCTAssertTrue(element("calendar.refresh.warning").waitForExistence(timeout: 5))
        XCTAssertTrue(element("calendar.refresh.retry").exists)
        XCTAssertTrue(event.exists)
    }

    private func launch(scenario: String = "baseline") {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launchEnvironment["KAOSCAL_UI_TEST_SCENARIO"] = scenario
        app.launch()
        app.activate()
        XCTAssertTrue(element("calendar.content").waitForExistence(timeout: 10))
        XCTAssertFalse(element("onboarding.phase10").exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
