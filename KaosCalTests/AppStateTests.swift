import AppKit
import SwiftUI
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

    func testUITestBootstrapUsesIsolatedFixtureBeforeHostedTestGuard() async throws {
        var didOpenDatabase = false
        let state = AppBootstrap.makeAppState(
            environment: ["XCTestConfigurationFilePath": "hosted-test"],
            arguments: ["KaosCal", "--ui-testing"],
            openDatabase: {
                didOpenDatabase = true
                return try AppDatabase.inMemory()
            }
        )

        XCTAssertFalse(didOpenDatabase)
        XCTAssertNotNil(state.contextStore)
        XCTAssertEqual(state.localContextStoreState, .ready)
        XCTAssertEqual(state.calendarAuthorizationState, .fullAccess)

        await state.refreshCalendarData()

        XCTAssertEqual(state.calendarSources.map(\.id), ["ui-calendar"])
        XCTAssertEqual(state.events.map(\.id), ["ui-event-planning"])
    }

    func testUITestRefreshFailurePreservesLoadedFixture() async {
        let state = AppBootstrap.makeAppState(
            environment: ["KAOSCAL_UI_TEST_SCENARIO": "refresh-failure"],
            arguments: ["KaosCal", "--ui-testing"]
        )

        await state.refreshCalendarData()
        let loadedEvents = state.events
        await state.reloadCalendarData()

        XCTAssertEqual(state.events, loadedEvents)
        XCTAssertNotNil(state.calendarRefreshError)
    }

    func testBootstrapRecoveryIsOfferedOnlyWhenNoLiveDatabaseWriterExists() throws {
        enum OpenFailure: Error { case injected }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BootstrapCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("kaoscal.sqlite")
        let database = try AppDatabase.open(at: databaseURL)

        let healthy = AppBootstrapCoordinator(
            environment: [:],
            openDatabase: { database },
            defaultDatabaseURL: databaseURL
        )
        XCTAssertEqual(
            healthy.appState.localContextStoreState,
            LocalContextStoreState.ready
        )
        XCTAssertFalse(healthy.canRecoverFromBootstrap)

        let failedBootstrap = AppBootstrapCoordinator(
            environment: [:],
            openDatabase: { throw OpenFailure.injected },
            defaultDatabaseURL: databaseURL
        )
        guard case .failed = failedBootstrap.appState.localContextStoreState else {
            return XCTFail("Expected failed bootstrap state")
        }
        XCTAssertNil(failedBootstrap.appState.contextStore)
        XCTAssertTrue(failedBootstrap.canRecoverFromBootstrap)
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

    func testMonthSectionMetadataAndNavigationOrder() {
        XCTAssertEqual(
            WorkspaceSection.allCases,
            [.day, .week, .month, .agenda, .tasks]
        )
        XCTAssertEqual(WorkspaceSection.month.title, "Month")
        XCTAssertEqual(WorkspaceSection.month.symbolName, "calendar.circle")
        XCTAssertEqual(
            WorkspaceSection.month.accessibilityIdentifier,
            "nav.month"
        )
    }

    func testMonthVisiblePeriodUsesFourToSixCompleteWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        let provider = FakeCalendarProvider()
        let scenarios = [
            (
                focus: DateComponents(year: 2021, month: 2, day: 15),
                start: DateComponents(year: 2021, month: 2, day: 1),
                end: DateComponents(year: 2021, month: 3, day: 1),
                dayCount: 28
            ),
            (
                focus: DateComponents(year: 2021, month: 3, day: 15),
                start: DateComponents(year: 2021, month: 3, day: 1),
                end: DateComponents(year: 2021, month: 4, day: 5),
                dayCount: 35
            ),
            (
                focus: DateComponents(year: 2021, month: 8, day: 15),
                start: DateComponents(year: 2021, month: 7, day: 26),
                end: DateComponents(year: 2021, month: 9, day: 6),
                dayCount: 42
            )
        ]

        for scenario in scenarios {
            let focus = try! XCTUnwrap(calendar.date(from: scenario.focus))
            let state = AppState(
                calendar: calendar,
                now: { focus },
                calendarProvider: provider
            )
            state.select(.month)

            XCTAssertEqual(state.visibleDates.count, scenario.dayCount)
            XCTAssertEqual(
                state.visibleDates.first,
                calendar.date(from: scenario.start)
            )
            XCTAssertEqual(
                state.visibleInterval.start,
                calendar.date(from: scenario.start)
            )
            XCTAssertEqual(
                state.visibleInterval.end,
                calendar.date(from: scenario.end)
            )
            XCTAssertEqual(
                calendar.dateComponents(
                    [.day],
                    from: state.visibleInterval.start,
                    to: state.visibleInterval.end
                ).day,
                scenario.dayCount
            )
        }
    }

    func testMonthMovementUsesCalendarMonthsAndClampsEndOfMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let provider = FakeCalendarProvider()
        let scenarios = [
            (2025, 1, 29, 1, 2025, 2, 28),
            (2025, 1, 30, 1, 2025, 2, 28),
            (2025, 1, 31, 1, 2025, 2, 28),
            (2024, 1, 31, 1, 2024, 2, 29),
            (2026, 3, 31, 1, 2026, 4, 30),
            (2026, 3, 31, -1, 2026, 2, 28),
            (2026, 12, 31, 1, 2027, 1, 31)
        ]

        for scenario in scenarios {
            let start = try! XCTUnwrap(calendar.date(from: DateComponents(
                year: scenario.0,
                month: scenario.1,
                day: scenario.2
            )))
            let state = AppState(
                calendar: calendar,
                now: { start },
                calendarProvider: provider
            )
            state.select(.month)
            state.moveFocusedPeriod(direction: scenario.3)

            XCTAssertEqual(
                calendar.dateComponents(
                    [.year, .month, .day],
                    from: state.focusedDate
                ),
                DateComponents(
                    year: scenario.4,
                    month: scenario.5,
                    day: scenario.6
                )
            )
            XCTAssertEqual(state.selectedSection, .month)
        }
    }

    func testMonthFocusedPeriodTitleUsesFocusedMonthAndYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let baseline = try! XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19
        )))
        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )

        state.select(.month)

        XCTAssertEqual(state.focusedPeriodTitle, "August 2026")
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

    func testMiniMonthSelectionNormalizesDatePreservesViewAndResyncsBrowse() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.locale = Locale(identifier: "ko_KR")
        let baseline = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 11, hour: 9)
        )!
        let selectedDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 19, hour: 17)
        )!
        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )

        for section in [WorkspaceSection.day, .week, .month, .agenda] {
            state.select(section)
            state.selectMiniMonthDate(selectedDate)

            XCTAssertEqual(state.selectedSection, section)
            XCTAssertEqual(
                state.focusedDate,
                calendar.startOfDay(for: selectedDate)
            )
        }

        var browseState = MiniMonthBrowseState(
            focusedDate: state.focusedDate,
            calendar: calendar
        )
        browseState.shift(by: 1, calendar: calendar)
        XCTAssertEqual(
            MiniMonthGrid.dayIdentifier(
                for: browseState.displayedMonthStart,
                calendar: calendar
            ),
            "2026-09-01"
        )

        // @Published emits for an assignment even when the Date is equal.
        // MiniMonthView forwards every emission here via onReceive so Today
        // and same-date spillover selection both leave local month browsing.
        browseState.synchronize(
            to: state.focusedDate,
            calendar: calendar
        )
        XCTAssertEqual(
            MiniMonthGrid.dayIdentifier(
                for: browseState.displayedMonthStart,
                calendar: calendar
            ),
            "2026-08-01"
        )
    }

    func testMiniMonthSelectionLeavesTasksOrNoSelectionForDayView() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let selectedDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 19, hour: 17)
        )!
        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )

        state.select(.tasks)
        state.selectMiniMonthDate(selectedDate)
        XCTAssertEqual(state.selectedSection, .day)

        state.selectedSection = nil
        state.selectMiniMonthDate(selectedDate)
        XCTAssertEqual(state.selectedSection, .day)
    }

    func testMiniMonthIntrinsicSizeFitsAndProducesOffscreenBitmap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        let baseline = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 17, hour: 9)
        )!
        let state = AppState(
            calendar: calendar,
            now: { baseline },
            calendarProvider: FakeCalendarProvider()
        )
        let hostingView = NSHostingView(rootView:
            MiniMonthView(appState: state)
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        let fittingSize = hostingView.fittingSize
        XCTAssertLessThanOrEqual(fittingSize.width, 210)
        XCTAssertLessThanOrEqual(fittingSize.height, 240)

        hostingView.frame = NSRect(x: 0, y: 0, width: 210, height: 240)
        hostingView.wantsLayer = true
        hostingView.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(
                in: hostingView.bounds
            )
        )
        hostingView.cacheDisplay(
            in: hostingView.bounds,
            to: representation
        )
        let pngData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )

        XCTAssertGreaterThanOrEqual(representation.pixelsWide, 210)
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 240)
        XCTAssertGreaterThan(pngData.count, 5_000)
    }
}

@MainActor
final class Phase6AppStateTests: XCTestCase {
    func testDraggingProviderTaskCreatesSnappedTimeBlockAndLinkedDuringTask() async throws {
        let store = ContextStore(database: try AppDatabase.inMemory())
        let reminderList = RemoteTaskList(
            provider: .appleReminders,
            id: "reminders-work",
            accountKey: "icloud",
            title: "Work",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "schedule-me",
            parentID: reminderList.id,
            parentAccountKey: reminderList.accountKey,
            title: "Write launch brief",
            notes: "Remote notes stay transient",
            dueAt: nil,
            isCompleted: false,
            version: "schedule-v1",
            deepLink: nil
        )
        let taskProvider = StubAppleTaskListingProvider(
            lists: [reminderList],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: store,
            provider: taskProvider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let calendarProvider = makeProvider(events: [])
        calendarProvider.defaultNewEventCalendarIdentifier = "calendar"
        let state = AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 10, 8) },
            calendarProvider: calendarProvider,
            contextStore: store,
            taskProviderCoordinator: coordinator,
            localContextStoreState: .ready
        )
        await state.loadCalendarStatus()
        for _ in 0..<30 {
            if case .loaded = coordinator.appleRemindersTaskState { break }
            await Task.yield()
        }
        let sidebarID = TaskProviderCoordinator.sidebarTaskItemID(
            provider: .appleReminders,
            accountKey: reminderList.accountKey,
            listID: reminderList.id,
            taskID: remote.id
        )

        XCTAssertTrue(state.beginCreatingTaskTimeBlock(
            sidebarTaskReference: "kaoscal-task:\(sidebarID)",
            startAt: date(2026, 7, 10, 10, 7)
        ))
        let session = try XCTUnwrap(state.eventEditorSession)
        XCTAssertEqual(session.initialDraft.title, remote.title)
        XCTAssertEqual(session.initialDraft.startDate, date(2026, 7, 10, 10))
        XCTAssertEqual(session.initialDraft.endDate, date(2026, 7, 10, 11))
        XCTAssertNotNil(session.taskBlockSourceTitle)

        let didSave = await state.saveEventEditor(session.initialDraft)
        XCTAssertTrue(didSave)

        XCTAssertEqual(calendarProvider.createCallCount, 1)
        let binding = try XCTUnwrap(store.taskProviders.fetchBindings().first)
        XCTAssertEqual(binding.syncState, .linked)
        let cached = try XCTUnwrap(
            store.taskProviders.fetchProviderItem(id: binding.providerItemID)
        )
        XCTAssertEqual(cached.remoteID, remote.id)
        let eventTaskID = try XCTUnwrap(binding.eventTaskID)
        let eventTask = try XCTUnwrap(store.eventTasks.fetch(id: eventTaskID))
        XCTAssertEqual(eventTask.section, .during)
        XCTAssertEqual(eventTask.title, remote.title)
        let linkedSidebarItem = try XCTUnwrap(
            coordinator.sidebarTaskItem(id: sidebarID)
        )
        let calendarLink = try XCTUnwrap(
            coordinator.calendarLink(for: linkedSidebarItem)
        )
        XCTAssertEqual(calendarLink.eventTaskID, eventTask.id)
        XCTAssertEqual(calendarLink.contextID, eventTask.contextID)
        XCTAssertEqual(calendarLink.calendarIdentifier, "calendar")
        XCTAssertEqual(calendarLink.eventTitle, remote.title)
        XCTAssertNil(state.eventEditorError)
    }

    func testSelectedEventTaskSupportsRelativeAndFixedDuePolicies() async throws {
        let event = makeEvent(
            id: "relative-due",
            start: date(2026, 7, 10, 10)
        )
        let provider = makeProvider(events: [event])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let task = try store.appendEventTask(
            for: event,
            section: .before,
            title: "Prepare room"
        )
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)

        XCTAssertTrue(state.setSelectedEventTaskDue(
            id: task.id,
            due: .relative(anchor: .beforeStart, offsetMinutes: 30)
        ))
        let relative = try XCTUnwrap(store.eventTasks.fetch(id: task.id))
        XCTAssertEqual(
            relative.due,
            .relative(anchor: .beforeStart, offsetMinutes: 30)
        )
        XCTAssertEqual(
            relative.effectiveDueDate(
                eventStart: event.startDate,
                eventEnd: event.endDate
            ),
            date(2026, 7, 10, 9, 30)
        )

        let fixed = date(2026, 7, 11, 15)
        XCTAssertTrue(state.setSelectedEventTaskDue(
            id: task.id,
            due: .fixed(fixed)
        ))
        XCTAssertEqual(
            try XCTUnwrap(store.eventTasks.fetch(id: task.id)).due,
            .fixed(fixed)
        )
    }

    func testTaskDeepLinkUsesLocalBindingThenStrongCalendarLookup() async throws {
        let event = makeEvent(id: "deep-link")
        let provider = makeProvider(events: [event])
        let store = ContextStore(database: try AppDatabase.inMemory())
        _ = try store.saveNotes(for: event, notes: "Deep link fixture")
        let task = try store.appendEventTask(
            for: event,
            section: .after,
            title: "Open from To Do"
        )
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        await state.openTaskDeepLink(
            try XCTUnwrap(URL(string: "kaoscal://task/\(task.id)"))
        )

        XCTAssertEqual(provider.lookupCallCount, 1)
        XCTAssertEqual(state.selectedEventID, event.id)
        XCTAssertEqual(state.selectedSection, .day)
        XCTAssertNil(state.localOperationError)
    }

    func testLinkedCalendarMoveCancelPerformsNoWriteOrLocalMutation() async throws {
        let event = makeEvent()
        let provider = makeProvider(events: [event])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(
            try store.saveNotes(for: event, notes: "Keep this Brief")
        )
        _ = try store.appendEventTask(
            for: event,
            section: .before,
            title: "Keep this task"
        )
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.beginEditingSelectedEvent()
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        let session = try XCTUnwrap(state.eventEditorSession)
        var draft = session.initialDraft
        draft.calendarIdentifier = "destination"

        let didSave = await state.saveEventEditor(draft)
        XCTAssertFalse(didSave)
        XCTAssertNotNil(state.pendingEventMutation)
        XCTAssertEqual(provider.updateCallCount, 0)

        state.cancelPendingEventMutation()

        XCTAssertNil(state.pendingEventMutation)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            before
        )
        XCTAssertTrue(
            try store.changeHistory(contextID: context.id).isEmpty
        )
    }

    func testConfirmedLinkedMoveLogsPreservesContextAndSupportsOneUndo() async throws {
        let event = makeEvent()
        let provider = makeProvider(events: [event])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(
            try store.saveNotes(for: event, notes: "Persistent Brief")
        )
        let task = try store.appendEventTask(
            for: event,
            section: .after,
            title: "Follow up"
        )
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.calendarIdentifier = "destination"

        let didSaveBeforeConfirmation = await state.saveEventEditor(draft)
        XCTAssertFalse(didSaveBeforeConfirmation)
        let didConfirm = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirm)

        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertEqual(provider.lastUpdateScope, .thisEvent)
        let moved = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(moved.context.id, context.id)
        XCTAssertEqual(moved.context.notes, "Persistent Brief")
        XCTAssertEqual(moved.tasks.map(\.id), [task.id])
        XCTAssertEqual(moved.link.calendarIdentifier, "destination")
        let moveLog = try XCTUnwrap(
            try store.changeHistory(contextID: context.id).first
        )
        XCTAssertEqual(moveLog.changeType, .moved)
        XCTAssertEqual(moveLog.scope, .single)
        XCTAssertEqual(moveLog.undoState, .available)
        XCTAssertTrue(state.lastEventMutationUndoAvailable)

        let didUndo = await state.undoLastEventMutation()
        XCTAssertTrue(didUndo)

        XCTAssertEqual(provider.updateCallCount, 2)
        let restored = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(restored.context.id, context.id)
        XCTAssertEqual(restored.context.notes, "Persistent Brief")
        XCTAssertEqual(restored.tasks.map(\.id), [task.id])
        XCTAssertEqual(restored.link.calendarIdentifier, "calendar")
        let history = try store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.changeType), [.restored, .moved])
        XCTAssertEqual(history.last?.undoState, .undone)
        XCTAssertFalse(state.lastEventMutationUndoAvailable)
    }

    func testRecurringUpdateRequiresExplicitScopeThenConfirmsBeforeWrite() async throws {
        let recurrence = CalendarEventRecurrence.basic(
            BasicRecurrenceRule(
                frequency: .weekly,
                weekdays: [.friday]
            )
        )
        let event = makeEvent(id: "recurring", recurrence: recurrence)
        let provider = makeProvider(events: [event])
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.title = "Changed occurrence"

        let didSaveWithoutScope = await state.saveEventEditor(draft)
        XCTAssertFalse(didSaveWithoutScope)
        XCTAssertEqual(
            state.eventEditorError,
            CalendarEventWriteError.recurringScopeRequired
                .localizedDescription
        )
        XCTAssertEqual(provider.updateCallCount, 0)

        state.clearEventEditorError()
        let didSaveBeforeConfirmation = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(didSaveBeforeConfirmation)
        XCTAssertEqual(state.pendingEventMutation?.scope, .thisEvent)
        XCTAssertEqual(provider.updateCallCount, 0)

        let didConfirm = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirm)
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertEqual(provider.lastUpdateScope, .thisEvent)
    }

    func testPostWriteFocusPrefersExactIDAcrossRecurringSiblings() async throws {
        let recurrence = CalendarEventRecurrence.basic(
            BasicRecurrenceRule(frequency: .daily)
        )
        let earlier = makeEvent(
            id: "series-earlier",
            recurrence: recurrence,
            start: date(2026, 7, 9, 9),
            identifierSeed: "shared-series"
        )
        let original = makeEvent(
            id: "series-original",
            recurrence: recurrence,
            start: date(2026, 7, 10, 9),
            identifierSeed: "shared-series"
        )
        let exactRefetched = makeEvent(
            id: "series-exact-refetched",
            recurrence: recurrence,
            title: "Changed occurrence",
            start: date(2026, 7, 10, 9),
            identifierSeed: "shared-series"
        )
        let provider = makeProvider(events: [earlier, original])
        provider.updateMutationHandler = { _, _, scope in
            provider.events = [earlier, exactRefetched]
            return CalendarEventMutationReceipt(
                event: exactRefetched,
                didWrite: true,
                scope: scope,
                changedFields: [.title]
            )
        }
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.title = "Changed occurrence"

        let didPrepare = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(didPrepare)
        let didConfirm = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirm)

        XCTAssertEqual(state.selectedEventID, exactRefetched.id)
        XCTAssertEqual(state.selectedEvent?.startDate, exactRefetched.startDate)
    }

    func testPostWriteRecurringFallbackRequiresCalendarAndOccurrence() async throws {
        let recurrence = CalendarEventRecurrence.basic(
            BasicRecurrenceRule(frequency: .daily)
        )
        let original = makeEvent(
            id: "fallback-original",
            recurrence: recurrence,
            start: date(2026, 7, 10, 9),
            identifierSeed: "shared-fallback-series"
        )
        let wrongCalendar = makeEvent(
            id: "fallback-wrong-calendar",
            recurrence: recurrence,
            title: "Changed occurrence",
            start: date(2026, 7, 10, 9),
            identifierSeed: "shared-fallback-series",
            calendarIdentifier: "destination"
        )
        let earlierSibling = makeEvent(
            id: "fallback-earlier",
            recurrence: recurrence,
            title: "Changed occurrence",
            start: date(2026, 7, 9, 9),
            identifierSeed: "shared-fallback-series"
        )
        let matchingOccurrence = makeEvent(
            id: "fallback-refetched-target",
            recurrence: recurrence,
            title: "Changed occurrence",
            start: date(2026, 7, 10, 9),
            identifierSeed: "shared-fallback-series"
        )
        let unseenReceipt = makeEvent(
            id: "fallback-unseen-receipt",
            recurrence: recurrence,
            title: "Changed occurrence",
            start: date(2026, 7, 10, 9),
            identifierSeed: "shared-fallback-series"
        )
        let provider = makeProvider(events: [original])
        provider.updateMutationHandler = { _, _, scope in
            provider.events = [
                wrongCalendar,
                earlierSibling,
                matchingOccurrence
            ]
            return CalendarEventMutationReceipt(
                event: unseenReceipt,
                didWrite: true,
                scope: scope,
                changedFields: [.title]
            )
        }
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.title = "Changed occurrence"

        let didPrepare = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(didPrepare)
        let didConfirm = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirm)

        XCTAssertEqual(state.selectedEventID, matchingOccurrence.id)
        XCTAssertEqual(
            state.selectedEvent?.occurrenceDate,
            matchingOccurrence.occurrenceDate
        )
    }

    func testPostWriteAllDayFallbackUsesLocalOccurrenceAnchor() async throws {
        let original = makeCivilRecurringEvent(
            id: "all-day-original",
            localDay: 10,
            identifierSeed: "shared-all-day",
            isAllDay: true
        )
        let wrongSibling = makeCivilRecurringEvent(
            id: "all-day-wrong-sibling",
            localDay: 9,
            identifierSeed: "shared-all-day",
            isAllDay: true
        )
        let matchingOccurrence = makeCivilRecurringEvent(
            id: "all-day-refetched",
            localDay: 10,
            identifierSeed: "shared-all-day",
            isAllDay: true,
            rawStart: date(2026, 7, 9, 15)
        )
        let unseenReceipt = makeCivilRecurringEvent(
            id: "all-day-unseen-receipt",
            localDay: 10,
            identifierSeed: "shared-all-day",
            isAllDay: true,
            rawStart: date(2026, 7, 10, 6)
        )
        let provider = makeProvider(events: [original])
        provider.updateMutationHandler = { _, _, scope in
            provider.events = [wrongSibling, matchingOccurrence]
            return CalendarEventMutationReceipt(
                event: unseenReceipt,
                didWrite: true,
                scope: scope,
                changedFields: [.title]
            )
        }
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.title = "Changed all-day occurrence"

        let didPrepare = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(didPrepare)
        let didConfirm = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirm)

        XCTAssertEqual(state.selectedEventID, matchingOccurrence.id)
    }

    func testPostWriteFloatingFallbackUsesLocalOccurrenceAnchor() async throws {
        let original = makeCivilRecurringEvent(
            id: "floating-original",
            localDay: 10,
            identifierSeed: "shared-floating",
            isAllDay: false
        )
        let wrongSibling = makeCivilRecurringEvent(
            id: "floating-wrong-sibling",
            localDay: 9,
            identifierSeed: "shared-floating",
            isAllDay: false
        )
        let matchingOccurrence = makeCivilRecurringEvent(
            id: "floating-refetched",
            localDay: 10,
            identifierSeed: "shared-floating",
            isAllDay: false,
            rawStart: date(2026, 7, 10)
        )
        let unseenReceipt = makeCivilRecurringEvent(
            id: "floating-unseen-receipt",
            localDay: 10,
            identifierSeed: "shared-floating",
            isAllDay: false,
            rawStart: date(2026, 7, 9, 15)
        )
        let provider = makeProvider(events: [original])
        provider.updateMutationHandler = { _, _, scope in
            provider.events = [wrongSibling, matchingOccurrence]
            return CalendarEventMutationReceipt(
                event: unseenReceipt,
                didWrite: true,
                scope: scope,
                changedFields: [.title]
            )
        }
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.title = "Changed floating occurrence"

        let didPrepare = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(didPrepare)
        let didConfirm = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirm)

        XCTAssertEqual(state.selectedEventID, matchingOccurrence.id)
    }

    func testPostWriteSingleEventKeepsStrongIdentifierFallback() async throws {
        let original = makeEvent(
            id: "single-original",
            identifierSeed: "shared-single"
        )
        let refetched = makeEvent(
            id: "single-refetched",
            title: "Changed single event",
            identifierSeed: "shared-single"
        )
        let unseenReceipt = makeEvent(
            id: "single-unseen-receipt",
            title: "Changed single event",
            identifierSeed: "shared-single"
        )
        let provider = makeProvider(events: [original])
        provider.updateMutationHandler = { _, _, scope in
            provider.events = [refetched]
            return CalendarEventMutationReceipt(
                event: unseenReceipt,
                didWrite: true,
                scope: scope,
                changedFields: [.title]
            )
        }
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.title = "Changed single event"

        let didSave = await state.saveEventEditor(draft)
        XCTAssertTrue(didSave)

        XCTAssertEqual(state.selectedEventID, refetched.id)
        XCTAssertEqual(state.selectedEvent?.title, "Changed single event")
    }

    func testLinkedFutureSeriesAndUnsupportedRuleStopBeforeProvider() async throws {
        let basic = CalendarEventRecurrence.basic(
            BasicRecurrenceRule(frequency: .daily)
        )
        let linkedEvent = makeEvent(id: "linked-series", recurrence: basic)
        let linkedProvider = makeProvider(events: [linkedEvent])
        let store = ContextStore(database: try AppDatabase.inMemory())
        _ = try store.saveNotes(for: linkedEvent, notes: "Occurrence Brief")
        let linkedState = makeState(
            provider: linkedProvider,
            store: store
        )
        await linkedState.loadCalendarStatus()
        linkedState.selectEvent(linkedEvent.id)
        linkedState.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(
            linkedState.eventEditorSession
        ).initialDraft
        draft.title = "Future title"

        let didSaveLinkedFuture = await linkedState.saveEventEditor(
            draft,
            scope: .futureEvents
        )
        XCTAssertFalse(didSaveLinkedFuture)
        XCTAssertNil(linkedState.pendingEventMutation)
        XCTAssertEqual(linkedProvider.updateCallCount, 0)

        let unsupported = CalendarEventRecurrence.unsupported(
            UnsupportedRecurrenceSnapshot(
                summary: "Complex recurrence rule",
                signature: "complex-v1"
            )
        )
        let complexEvent = makeEvent(
            id: "complex-series",
            recurrence: unsupported
        )
        let complexProvider = makeProvider(events: [complexEvent])
        let complexState = makeState(provider: complexProvider)
        await complexState.loadCalendarStatus()
        complexState.selectEvent(complexEvent.id)

        complexState.beginEditingSelectedEvent()
        var complexDraft = try XCTUnwrap(
            complexState.eventEditorSession
        ).initialDraft
        complexDraft.title = "Complex occurrence"

        let didSaveComplexFuture = await complexState.saveEventEditor(
            complexDraft,
            scope: .futureEvents
        )
        XCTAssertFalse(didSaveComplexFuture)
        XCTAssertNotNil(complexState.eventEditorSession)
        XCTAssertNil(complexState.pendingEventMutation)
        XCTAssertEqual(
            complexState.eventEditorError,
            CalendarEventWriteError.unsupportedRecurrence
                .localizedDescription
        )
        XCTAssertEqual(complexProvider.updateCallCount, 0)
    }

    func testRecurringDeleteRequiresAndForwardsScope() async throws {
        let event = makeEvent(
            id: "delete-series",
            recurrence: .basic(
                BasicRecurrenceRule(frequency: .monthly)
            )
        )
        let provider = makeProvider(events: [event])
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.beginEditingSelectedEvent()

        let didDeleteWithoutScope = await state.deleteEventEditorTarget()
        XCTAssertFalse(didDeleteWithoutScope)
        XCTAssertEqual(provider.deleteCallCount, 0)

        let didDeleteFuture = await state.deleteEventEditorTarget(
            scope: .futureEvents
        )
        XCTAssertTrue(didDeleteFuture)
        XCTAssertEqual(provider.deleteCallCount, 1)
        XCTAssertEqual(provider.lastDeleteScope, .futureEvents)
    }

    func testPostSaveReceiptFailureClosesPreviewAndPreventsRetry() async throws {
        let event = makeEvent(id: "receipt-partial")
        let provider = makeProvider(events: [event])
        provider.updateMutationHandler = { original, _, _ in
            throw CalendarEventMutationPartialSuccess(
                provisionalEvent: original,
                underlyingDescription: "Identifier churn"
            )
        }
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(
            try store.saveNotes(for: event, notes: "Keep after partial")
        )
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.startDate = draft.startDate.addingTimeInterval(3_600)
        draft.endDate = draft.endDate.addingTimeInterval(3_600)

        let didPrepare = await state.saveEventEditor(draft)
        XCTAssertFalse(didPrepare)
        XCTAssertNotNil(state.pendingEventMutation)

        let didConfirm = await state.confirmPendingEventMutation()

        XCTAssertFalse(didConfirm)
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertNil(state.pendingEventMutation)
        XCTAssertNil(state.eventEditorSession)
        XCTAssertTrue(
            state.eventEditorError?.contains("Do not retry") == true
        )
        XCTAssertTrue(
            try store.changeHistory(contextID: context.id).isEmpty
        )
        let brief = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(brief.context.notes, "Keep after partial")

        let didConfirmAgain = await state.confirmPendingEventMutation()
        XCTAssertFalse(didConfirmAgain)
        XCTAssertEqual(provider.updateCallCount, 1)
    }

    func testDetachedOccurrenceWithEarlierSeriesEndCanEditThisEvent() async throws {
        let recurrence = CalendarEventRecurrence.basic(
            BasicRecurrenceRule(
                frequency: .daily,
                end: .onDate(date(2026, 7, 1))
            )
        )
        let event = makeEvent(
            id: "detached-after-end",
            recurrence: recurrence,
            isDetached: true
        )
        let provider = makeProvider(events: [event])
        let state = makeState(provider: provider)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.beginEditingSelectedEvent()
        var draft = try XCTUnwrap(state.eventEditorSession).initialDraft
        draft.title = "Detached detail edit"

        let didPrepare = await state.saveEventEditor(
            draft,
            scope: .thisEvent
        )
        XCTAssertFalse(didPrepare)
        XCTAssertNotNil(state.pendingEventMutation)

        let didConfirm = await state.confirmPendingEventMutation()
        XCTAssertTrue(didConfirm)
        XCTAssertEqual(provider.updateCallCount, 1)
        XCTAssertEqual(provider.lastUpdateScope, .thisEvent)
        XCTAssertEqual(provider.lastUpdatedDraft?.recurrence, recurrence)
    }

    func testCivilRecurrenceEndRebasesWithDraftReferenceZone() throws {
        var oldCalendar = Calendar(identifier: .gregorian)
        oldCalendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Los_Angeles")
        )
        var newCalendar = Calendar(identifier: .gregorian)
        newCalendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "Asia/Seoul")
        )
        let start = try XCTUnwrap(oldCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10
        )))
        let end = try XCTUnwrap(
            oldCalendar.date(byAdding: .day, value: 1, to: start)
        )
        let recurrenceEnd = try XCTUnwrap(
            oldCalendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 31
            ))
        )
        let draft = CalendarEventDraft(
            title: "Civil recurrence",
            calendarIdentifier: "calendar",
            startDate: start,
            endDate: end,
            isAllDay: true,
            timeZoneIdentifier: nil,
            referenceTimeZoneIdentifier: oldCalendar.timeZone.identifier,
            recurrence: .basic(BasicRecurrenceRule(
                frequency: .daily,
                end: .onDate(recurrenceEnd)
            ))
        )

        let normalized = try draft.validated(calendar: newCalendar)
        guard case let .basic(rule) = normalized.recurrence,
              case let .onDate(normalizedEnd) = rule.end else {
            return XCTFail("Expected a basic recurrence end date")
        }
        let components = newCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: normalizedEnd
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
    }

    func testExistingCivilRecurrenceDoesNotBecomeARecurrenceEditAfterZoneDrift() throws {
        var oldCalendar = Calendar(identifier: .gregorian)
        oldCalendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Los_Angeles")
        )
        var newCalendar = Calendar(identifier: .gregorian)
        newCalendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "Asia/Seoul")
        )
        let start = try XCTUnwrap(oldCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10
        )))
        let end = try XCTUnwrap(
            oldCalendar.date(byAdding: .day, value: 1, to: start)
        )
        let recurrence = CalendarEventRecurrence.basic(
            BasicRecurrenceRule(
                frequency: .daily,
                end: .onDate(try XCTUnwrap(oldCalendar.date(
                    from: DateComponents(
                        year: 2026,
                        month: 7,
                        day: 31
                    )
                )))
            )
        )
        var draft = CalendarEventDraft(
            title: "Existing civil recurrence",
            calendarIdentifier: "calendar",
            startDate: start,
            endDate: end,
            isAllDay: true,
            timeZoneIdentifier: nil,
            referenceTimeZoneIdentifier: oldCalendar.timeZone.identifier,
            recurrence: recurrence
        )
        draft.title = "Ordinary occurrence edit"

        let normalized = try draft.validated(
            calendar: newCalendar,
            enforceRecurrenceEndBoundary: false,
            rebaseRecurrenceEndDate: false
        )
        var current = normalized
        current.title = "Existing civil recurrence"

        XCTAssertEqual(normalized.recurrence, recurrence)
        XCTAssertEqual(
            normalized.changedFields(comparedTo: current),
            [.title]
        )
    }

    func testCalendarRolePersistsLocallyWithoutCalendarProviderWrites() async throws {
        let event = makeEvent(id: "role-event")
        let provider = makeProvider(events: [event])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        let source = try XCTUnwrap(
            state.calendarSources.first(where: { $0.id == "calendar" })
        )
        XCTAssertEqual(state.calendarRole(for: source), .other)
        XCTAssertTrue(state.setCalendarRole(.work, for: source))
        XCTAssertEqual(state.calendarRole(for: event), .work)
        XCTAssertEqual(try store.calendarRoles.count(), 1)
        XCTAssertEqual(provider.createCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)

        let reopened = makeState(provider: provider, store: store)
        await reopened.loadCalendarStatus()
        XCTAssertEqual(reopened.calendarRole(for: event), .work)

        provider.authorizationState = .denied
        await reopened.loadCalendarStatus()
        XCTAssertEqual(
            reopened.calendarRole(calendarIdentifier: event.calendarIdentifier),
            .work
        )
    }

    func testRoleCalendarSetFiltersViewsAndFlushesHiddenSelectionNotes() async throws {
        let work = makeEvent(
            id: "work-event",
            title: "Work focus",
            calendarIdentifier: "calendar"
        )
        let personal = makeEvent(
            id: "personal-event",
            title: "Personal focus",
            calendarIdentifier: "destination"
        )
        let provider = makeProvider(events: [work, personal])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        let workSource = try XCTUnwrap(
            state.calendarSources.first(where: { $0.id == "calendar" })
        )
        let personalSource = try XCTUnwrap(
            state.calendarSources.first(where: { $0.id == "destination" })
        )
        XCTAssertTrue(state.setCalendarRole(.work, for: workSource))
        XCTAssertTrue(state.setCalendarRole(.personal, for: personalSource))

        state.selectEvent(work.id)
        state.updateSelectedEventNotes("Preserve before role filter")
        state.selectCalendarSet(.personal)

        XCTAssertNil(state.selectedEventID)
        XCTAssertEqual(state.visibleEvents.map(\.id), [personal.id])
        guard case let .loaded(brief, _) = try store.loadBrief(for: work) else {
            return XCTFail("Expected flushed work Event Brief")
        }
        XCTAssertEqual(brief.context.notes, "Preserve before role filter")
        XCTAssertEqual(provider.createCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    func testSavedCalendarSetsSupportPartialRolesMixedRolesAndOverlappingMemberships() async throws {
        let primaryWorkSource = makeCalendarSource(
            id: "calendar",
            title: "Primary Work"
        )
        let secondaryWorkSource = makeCalendarSource(
            id: "secondary-work",
            title: "Secondary Work"
        )
        let personalSource = makeCalendarSource(
            id: "destination",
            title: "Personal"
        )
        let primaryWork = makeEvent(
            id: "primary-work",
            start: date(2026, 7, 10, 9),
            calendarIdentifier: primaryWorkSource.id
        )
        let secondaryWork = makeEvent(
            id: "secondary-work",
            start: date(2026, 7, 10, 10),
            calendarIdentifier: secondaryWorkSource.id
        )
        let personal = makeEvent(
            id: "personal",
            start: date(2026, 7, 10, 11),
            calendarIdentifier: personalSource.id
        )
        let provider = makeProvider(
            events: [primaryWork, secondaryWork, personal]
        )
        provider.calendars = [
            primaryWorkSource,
            secondaryWorkSource,
            personalSource
        ]
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        XCTAssertTrue(state.setCalendarRole(.work, for: primaryWorkSource))
        XCTAssertTrue(state.setCalendarRole(.work, for: secondaryWorkSource))
        XCTAssertTrue(state.setCalendarRole(.personal, for: personalSource))

        let partialWorkSet = try XCTUnwrap(state.createCalendarSet(
            name: "Primary Work Only",
            calendarIdentifiers: Set([primaryWorkSource.id])
        ))
        let mixedSet = try XCTUnwrap(state.createCalendarSet(
            name: "Work and Personal",
            calendarIdentifiers: Set([
                primaryWorkSource.id,
                personalSource.id
            ])
        ))

        XCTAssertEqual(
            partialWorkSet.calendarIdentifiers,
            Set([primaryWorkSource.id])
        )
        XCTAssertFalse(
            partialWorkSet.calendarIdentifiers.contains(secondaryWorkSource.id)
        )
        XCTAssertEqual(
            mixedSet.calendarIdentifiers,
            Set([primaryWorkSource.id, personalSource.id])
        )
        XCTAssertTrue(
            partialWorkSet.calendarIdentifiers.contains(primaryWorkSource.id)
        )
        XCTAssertTrue(
            mixedSet.calendarIdentifiers.contains(primaryWorkSource.id)
        )

        XCTAssertTrue(state.selectCalendarSet(.saved(partialWorkSet.id)))
        XCTAssertEqual(state.visibleEvents.map(\.id), [primaryWork.id])

        XCTAssertTrue(state.selectCalendarSet(.saved(mixedSet.id)))
        XCTAssertEqual(
            state.visibleEvents.map(\.id),
            [primaryWork.id, personal.id]
        )
        XCTAssertFalse(state.visibleEvents.contains(where: {
            $0.id == secondaryWork.id
        }))
        XCTAssertEqual(provider.createCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    func testMiniMonthSummaryUsesSeparateSnapshotAndExactVisibleSetOverlap() async throws {
        let includedSource = makeCalendarSource(
            id: "calendar",
            title: "Included"
        )
        let outsideSetSource = makeCalendarSource(
            id: "destination",
            title: "Outside Set"
        )
        let globallyHiddenSource = makeCalendarSource(
            id: "hidden",
            title: "Disabled"
        )
        let bodyEvent = makeEvent(
            id: "body-snapshot",
            start: date(2026, 7, 10, 9)
        )
        let provider = makeProvider(events: [bodyEvent])
        provider.calendars = [
            includedSource,
            outsideSetSource,
            globallyHiddenSource
        ]
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        let selectedSet = try XCTUnwrap(state.createCalendarSet(
            name: "Mini Month",
            calendarIdentifiers: [includedSource.id]
        ))
        XCTAssertTrue(state.selectCalendarSet(.saved(selectedSet.id)))
        XCTAssertTrue(state.setCalendarVisibility(
            false,
            for: globallyHiddenSource
        ))
        XCTAssertTrue(state.setCalendarBlocksAvailability(
            false,
            for: includedSource
        ))
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2026, 7, 8)),
            .unavailable
        )

        provider.events = [
            makeEvent(
                id: "overnight",
                start: date(2026, 7, 7, 23),
                end: date(2026, 7, 8, 1)
            ),
            makeEvent(
                id: "two-day-all-day",
                start: date(2026, 7, 8),
                end: date(2026, 7, 10),
                isAllDay: true
            ),
            makeEvent(
                id: "ends-at-midnight",
                start: date(2026, 7, 7, 23),
                end: date(2026, 7, 8)
            ),
            makeEvent(
                id: "outside-selected-set",
                start: date(2026, 7, 8, 12),
                calendarIdentifier: outsideSetSource.id
            ),
            makeEvent(
                id: "globally-disabled",
                start: date(2026, 7, 8, 13),
                calendarIdentifier: globallyHiddenSource.id
            )
        ]
        let grid = MiniMonthGrid(
            containing: date(2026, 7, 10),
            calendar: calendar
        )
        let interval = try XCTUnwrap(
            grid.coverageInterval(calendar: calendar)
        )
        await state.loadMiniMonthEventSummary(in: interval)

        XCTAssertEqual(provider.fetchCallCount, 2)
        XCTAssertEqual(provider.fetchIntervals.last, interval)
        XCTAssertEqual(state.events.map(\.id), [bodyEvent.id])
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2026, 7, 7)),
            .loaded(2)
        )
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2026, 7, 8)),
            .loaded(2)
        )
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2026, 7, 9)),
            .loaded(1)
        )
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2026, 7, 10)),
            .loaded(0)
        )
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2027, 7, 8)),
            .unavailable
        )

        provider.error = FakeCalendarProviderError.failed
        await state.loadMiniMonthEventSummary(in: interval, force: true)

        XCTAssertEqual(state.events.map(\.id), [bodyEvent.id])
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2026, 7, 8)),
            .failed
        )
        XCTAssertEqual(
            state.miniMonthEventSummary(for: date(2026, 7, 8))
                .accessibilityDescription,
            "Events unavailable"
        )
    }

    func testSavedCalendarSetSelectionRestoresAfterRelaunchAndActiveDeletionFallsBackToAll() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CalendarSetAppStateTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("calendar-sets.sqlite")
        let member = makeEvent(
            id: "member",
            calendarIdentifier: "calendar"
        )
        let nonmember = makeEvent(
            id: "nonmember",
            start: date(2026, 7, 10, 10),
            calendarIdentifier: "destination"
        )

        let firstProvider = makeProvider(events: [member, nonmember])
        let firstStore = ContextStore(
            database: try AppDatabase.open(at: databaseURL)
        )
        let firstState = makeState(provider: firstProvider, store: firstStore)
        await firstState.loadCalendarStatus()
        let savedSet = try XCTUnwrap(firstState.createCalendarSet(
            name: "Persisted Focus",
            calendarIdentifiers: Set(["calendar"])
        ))
        XCTAssertTrue(firstState.selectCalendarSet(.saved(savedSet.id)))
        XCTAssertEqual(
            try firstStore.calendarSets.fetchSelection(),
            .saved(savedSet.id)
        )

        let reopenedProvider = makeProvider(events: [member, nonmember])
        let reopenedStore = ContextStore(
            database: try AppDatabase.open(at: databaseURL)
        )
        let reopenedState = makeState(
            provider: reopenedProvider,
            store: reopenedStore
        )
        await reopenedState.loadCalendarStatus()

        XCTAssertEqual(reopenedState.selectedCalendarSet, .saved(savedSet.id))
        XCTAssertEqual(reopenedState.visibleEvents.map(\.id), [member.id])
        XCTAssertTrue(reopenedState.deleteCalendarSet(id: savedSet.id))
        XCTAssertEqual(reopenedState.selectedCalendarSet, .all)
        XCTAssertEqual(
            reopenedState.visibleEvents.map(\.id),
            [member.id, nonmember.id]
        )
        XCTAssertEqual(try reopenedStore.calendarSets.fetchSelection(), .all)

        let finalStore = ContextStore(
            database: try AppDatabase.open(at: databaseURL)
        )
        let finalState = makeState(
            provider: makeProvider(events: [member, nonmember]),
            store: finalStore
        )
        XCTAssertEqual(finalState.selectedCalendarSet, .all)
        XCTAssertNil(finalState.savedCalendarSet(id: savedSet.id))
    }

    func testSavedCalendarSetVisibilityUsesGlobalEnableAndMembershipWhileBlockingStaysIndependent() async throws {
        let member = makeEvent(
            id: "member-busy",
            start: date(2026, 7, 10, 9),
            calendarIdentifier: "calendar",
            availability: .busy
        )
        let nonmember = makeEvent(
            id: "nonmember-busy",
            start: date(2026, 7, 10, 11),
            calendarIdentifier: "destination",
            availability: .busy
        )
        let provider = makeProvider(events: [member, nonmember])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        let memberSource = try XCTUnwrap(
            state.calendarSources.first(where: { $0.id == "calendar" })
        )
        let savedSet = try XCTUnwrap(state.createCalendarSet(
            name: "Member Only",
            calendarIdentifiers: Set([memberSource.id])
        ))

        XCTAssertTrue(state.selectCalendarSet(.saved(savedSet.id)))
        XCTAssertEqual(state.visibleEvents.map(\.id), [member.id])
        XCTAssertEqual(
            state.blockingEvents.map(\.id),
            [member.id, nonmember.id]
        )

        XCTAssertTrue(state.setCalendarVisibility(false, for: memberSource))
        XCTAssertTrue(state.visibleEvents.isEmpty)
        XCTAssertEqual(
            state.calendarWorkspaceEmptyMessage,
            "All calendars in Member Only are disabled in KaosCal"
        )
        XCTAssertEqual(
            state.blockingEvents.map(\.id),
            [member.id, nonmember.id]
        )

        XCTAssertTrue(state.setCalendarBlocksAvailability(
            false,
            for: memberSource
        ))
        XCTAssertEqual(state.blockingEvents.map(\.id), [nonmember.id])
        XCTAssertTrue(state.setCalendarVisibility(true, for: memberSource))
        XCTAssertEqual(state.visibleEvents.map(\.id), [member.id])
        XCTAssertEqual(state.blockingEvents.map(\.id), [nonmember.id])
    }

    func testSavedCalendarSetKeepsUnavailableAndEmptyMembershipSelections() async throws {
        let store = ContextStore(database: try AppDatabase.inMemory())
        let unavailableSet = try store.calendarSets.create(
            name: "Unavailable",
            calendars: [
                makeCalendarSource(
                    id: "missing-calendar",
                    title: "Missing Calendar"
                )
            ]
        )
        let emptySet = try store.calendarSets.create(
            name: "Empty",
            calendars: []
        )
        try store.calendarSets.saveSelection(.saved(unavailableSet.id))

        let provider = makeProvider(events: [])
        let state = makeState(provider: provider, store: store)
        let initiallyLoadedUnavailableSet = try XCTUnwrap(
            state.savedCalendarSet(id: unavailableSet.id)
        )
        XCTAssertFalse(state.canDetermineCalendarSetMembershipAvailability)
        XCTAssertTrue(
            state.unavailableMemberships(in: initiallyLoadedUnavailableSet)
                .isEmpty
        )
        await state.loadCalendarStatus()

        XCTAssertTrue(state.canDetermineCalendarSetMembershipAvailability)
        XCTAssertEqual(state.selectedCalendarSet, .saved(unavailableSet.id))
        let loadedUnavailableSet = try XCTUnwrap(
            state.savedCalendarSet(id: unavailableSet.id)
        )
        XCTAssertEqual(
            state.unavailableMemberships(in: loadedUnavailableSet)
                .map(\.calendarIdentifier),
            ["missing-calendar"]
        )
        XCTAssertTrue(state.visibleEvents.isEmpty)
        XCTAssertEqual(
            state.calendarWorkspaceEmptyMessage,
            "Calendars in Unavailable are currently unavailable"
        )

        XCTAssertTrue(state.selectCalendarSet(.saved(emptySet.id)))
        XCTAssertEqual(state.selectedCalendarSet, .saved(emptySet.id))
        XCTAssertTrue(state.visibleEvents.isEmpty)
        XCTAssertEqual(
            state.calendarWorkspaceEmptyMessage,
            "Empty has no calendars"
        )
        XCTAssertEqual(
            try store.calendarSets.fetchSelection(),
            .saved(emptySet.id)
        )
    }

    func testCalendarVisibilityAndBlockingAreIndependentAndPersist() async throws {
        let hiddenBusy = makeEvent(
            id: "hidden-busy",
            title: "Private focus",
            start: date(2026, 7, 10, 9),
            calendarIdentifier: "calendar",
            availability: .busy
        )
        let visibleBusy = makeEvent(
            id: "visible-busy",
            title: "Shared focus",
            start: date(2026, 7, 10, 9, 30),
            calendarIdentifier: "destination",
            availability: .tentative
        )
        let free = makeEvent(
            id: "free",
            title: "FYI",
            start: date(2026, 7, 10, 11),
            calendarIdentifier: "destination",
            availability: .free
        )
        let provider = makeProvider(events: [hiddenBusy, visibleBusy, free])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        XCTAssertEqual(state.calendarAccounts.count, 1)
        XCTAssertEqual(
            Set(state.calendarAccounts.first?.calendars.map(\.id) ?? []),
            Set(["calendar", "destination"])
        )
        XCTAssertEqual(
            state.blockingEvents.map(\.id),
            ["hidden-busy", "visible-busy"]
        )
        XCTAssertEqual(state.blockedIntervals(in: state.visibleInterval).count, 1)

        let hiddenSource = try XCTUnwrap(
            state.calendarSources.first(where: { $0.id == "calendar" })
        )
        XCTAssertTrue(state.setCalendarVisibility(false, for: hiddenSource))
        XCTAssertFalse(state.calendarUsagePolicy(for: hiddenSource).isVisible)
        XCTAssertEqual(
            state.visibleEvents.map(\.id),
            ["visible-busy", "free"]
        )
        XCTAssertEqual(
            state.blockingEvents.map(\.id),
            ["hidden-busy", "visible-busy"]
        )

        XCTAssertTrue(state.setCalendarBlocksAvailability(
            false,
            for: hiddenSource
        ))
        XCTAssertEqual(state.blockingEvents.map(\.id), ["visible-busy"])
        XCTAssertEqual(try store.calendarUsage.count(), 1)

        let reopened = makeState(provider: provider, store: store)
        await reopened.loadCalendarStatus()
        XCTAssertFalse(reopened.calendarUsagePolicy(for: hiddenSource).isVisible)
        XCTAssertFalse(
            reopened.calendarUsagePolicy(for: hiddenSource).blocksAvailability
        )

        XCTAssertTrue(reopened.resetCalendarUsage(for: hiddenSource))
        XCTAssertTrue(reopened.calendarUsagePolicy(for: hiddenSource).isVisible)
        XCTAssertTrue(
            reopened.calendarUsagePolicy(for: hiddenSource).blocksAvailability
        )
        XCTAssertEqual(try store.calendarUsage.count(), 0)
        XCTAssertEqual(provider.createCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    func testCancelledDeclinedAndFreeEventsNeverBlockAvailability() async throws {
        let busy = makeEvent(
            id: "busy",
            start: date(2026, 7, 10, 9),
            availability: .notSupported
        )
        let free = makeEvent(
            id: "free",
            start: date(2026, 7, 10, 10),
            availability: .free
        )
        let cancelled = makeEvent(
            id: "cancelled",
            start: date(2026, 7, 10, 11),
            availability: .busy,
            isCancelled: true
        )
        let declined = makeEvent(
            id: "declined",
            start: date(2026, 7, 10, 13),
            availability: .busy,
            isDeclinedByCurrentUser: true
        )
        let provider = makeProvider(events: [busy, free, cancelled, declined])
        let state = makeState(
            provider: provider,
            store: ContextStore(database: try AppDatabase.inMemory())
        )
        await state.loadCalendarStatus()

        XCTAssertEqual(state.blockingEvents.map(\.id), ["busy"])
    }

    func testPossibleDuplicateTemporarilyRevealsCandidateWithoutChangingCalendarSet() async throws {
        let work = makeEvent(
            id: "duplicate-work",
            title: "Team Sync",
            start: date(2026, 7, 10, 9),
            calendarIdentifier: "calendar"
        )
        let personal = makeEvent(
            id: "duplicate-personal",
            title: "  team   sync  ",
            start: date(2026, 7, 10, 9).addingTimeInterval(10 * 60),
            calendarIdentifier: "destination"
        )
        let provider = makeProvider(events: [work, personal])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        XCTAssertTrue(state.setCalendarRole(
            .work,
            for: try XCTUnwrap(state.calendarSources.first(where: {
                $0.id == "calendar"
            }))
        ))
        XCTAssertTrue(state.setCalendarRole(
            .personal,
            for: try XCTUnwrap(state.calendarSources.first(where: {
                $0.id == "destination"
            }))
        ))
        XCTAssertTrue(state.selectCalendarSet(.work))

        let candidate = try XCTUnwrap(
            state.duplicateCandidates(for: work).first
        )
        XCTAssertEqual(candidate.event.id, personal.id)
        state.selectDuplicateCandidate(candidate)

        XCTAssertEqual(state.selectedCalendarSet, .work)
        XCTAssertEqual(state.selectedEventID, personal.id)
        XCTAssertEqual(state.temporarilyRevealedEventID, personal.id)
        XCTAssertEqual(
            state.visibleEvents.map(\.id),
            [work.id, personal.id]
        )
        XCTAssertNotNil(state.calendarSetTemporaryDisplayMessage)

        state.endTemporaryCalendarSetDisplay()

        XCTAssertEqual(state.selectedCalendarSet, .work)
        XCTAssertNil(state.temporarilyRevealedEventID)
        XCTAssertNil(state.selectedEventID)
        XCTAssertEqual(state.visibleEvents.map(\.id), [work.id])

        XCTAssertTrue(state.selectCalendarSet(.all))
        state.selectDuplicateCandidate(candidate)
        XCTAssertEqual(state.selectedCalendarSet, .all)
        XCTAssertEqual(state.selectedEventID, personal.id)
        XCTAssertNil(state.temporarilyRevealedEventID)
        XCTAssertNil(state.calendarSetTemporaryDisplayMessage)
        XCTAssertEqual(provider.createCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    func testCalendarSearchResultFocusesOccurrenceAndTemporarilyRevealsIt() async throws {
        let visible = makeEvent(
            id: "search-work",
            title: "Visible event",
            start: date(2026, 7, 10, 9),
            calendarIdentifier: "calendar"
        )
        let result = makeEvent(
            id: "search-personal",
            title: "Search target",
            start: date(2026, 7, 18, 15),
            calendarIdentifier: "destination"
        )
        let provider = makeProvider(events: [visible, result])
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        XCTAssertTrue(state.setCalendarRole(
            .work,
            for: try XCTUnwrap(state.calendarSources.first { $0.id == "calendar" })
        ))
        XCTAssertTrue(state.setCalendarRole(
            .personal,
            for: try XCTUnwrap(state.calendarSources.first { $0.id == "destination" })
        ))
        XCTAssertTrue(state.selectCalendarSet(.work))

        state.openCalendarSearchResult(result)

        XCTAssertEqual(state.selectedSection, .agenda)
        XCTAssertEqual(state.focusedDate, date(2026, 7, 18))
        XCTAssertEqual(state.selectedEventID, result.id)
        XCTAssertEqual(state.temporarilyRevealedEventID, result.id)
        XCTAssertTrue(state.visibleEvents.contains { $0.id == result.id })
        XCTAssertEqual(state.selectedCalendarSet, .work)
    }

    func testMonthCalendarSixWeekLayoutFitsMinimumWorkspaceAndProducesOffscreenBitmap() async throws {
        let events = [
            makeEvent(
                id: "month-all-day",
                title: "Product launch window",
                start: date(2026, 8, 3),
                end: date(2026, 8, 8),
                isAllDay: true
            ),
            makeEvent(
                id: "month-week-boundary",
                title: "Customer migration",
                start: date(2026, 8, 8, 18),
                end: date(2026, 8, 10, 10)
            ),
            makeEvent(
                id: "month-timed-1",
                title: "Design review",
                start: date(2026, 8, 12, 9),
                end: date(2026, 8, 12, 10)
            ),
            makeEvent(
                id: "month-timed-2",
                title: "Tentative partner call",
                start: date(2026, 8, 12, 10),
                end: date(2026, 8, 12, 11),
                availability: .tentative
            ),
            makeEvent(
                id: "month-timed-3",
                recurrence: .basic(BasicRecurrenceRule(frequency: .weekly)),
                title: "Weekly planning",
                start: date(2026, 8, 12, 11),
                end: date(2026, 8, 12, 12)
            ),
            makeEvent(
                id: "month-timed-4",
                title: "Cancelled interview",
                start: date(2026, 8, 12, 13),
                end: date(2026, 8, 12, 14),
                isCancelled: true
            )
        ]
        let provider = makeProvider(events: events)
        var renderCalendar = calendar
        renderCalendar.locale = Locale(identifier: "en_US_POSIX")
        renderCalendar.firstWeekday = 1
        let focusedDate = date(2026, 8, 15, 12)
        let state = AppState(
            calendar: renderCalendar,
            now: { focusedDate },
            calendarProvider: provider
        )
        state.select(.month)
        await state.loadCalendarStatus()

        XCTAssertEqual(
            MonthGrid(containing: focusedDate, calendar: renderCalendar).rowCount,
            6
        )
        XCTAssertEqual(Set(state.visibleEvents.map(\.id)), Set(events.map(\.id)))

        let hostingView = NSHostingView(rootView:
            MonthCalendarView(appState: state)
                .frame(width: 560, height: 520)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 520)
        hostingView.wantsLayer = true
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let pngData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )

        XCTAssertGreaterThanOrEqual(representation.pixelsWide, 560)
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 520)
        XCTAssertGreaterThan(pngData.count, 10_000)
        if let snapshotPath = ProcessInfo.processInfo.environment[
            "KAOSCAL_MONTH_SNAPSHOT_PATH"
        ] {
            try pngData.write(to: URL(fileURLWithPath: snapshotPath))
        }
        window.contentView = nil
        XCTAssertEqual(provider.createCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var writableCalendars: [CalendarSource] {
        [
            CalendarSource(
                id: "calendar",
                title: "KAOS-TEST",
                sourceTitle: "Exchange QA",
                sourceIdentifier: "exchange-qa",
                accountType: .exchange,
                isWritable: true,
                color: nil
            ),
            CalendarSource(
                id: "destination",
                title: "일정",
                sourceTitle: "Exchange QA",
                sourceIdentifier: "exchange-qa",
                accountType: .exchange,
                isWritable: true,
                color: nil
            )
        ]
    }

    private func makeCalendarSource(
        id: String,
        title: String
    ) -> CalendarSource {
        CalendarSource(
            id: id,
            title: title,
            sourceTitle: "Exchange QA",
            sourceIdentifier: "exchange-qa",
            accountType: .exchange,
            isWritable: true,
            color: nil
        )
    }

    private func makeProvider(
        events: [DisplayEvent]
    ) -> FakeCalendarProvider {
        let provider = FakeCalendarProvider(
            authorizationState: .fullAccess
        )
        provider.calendars = writableCalendars
        provider.events = events
        return provider
    }

    private func makeState(
        provider: FakeCalendarProvider,
        store: ContextStore? = nil
    ) -> AppState {
        AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 10, 12) },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: store == nil ? .unavailable : .ready
        )
    }

    private func makeEvent(
        id: String = "event",
        recurrence: CalendarEventRecurrence = .none,
        isDetached: Bool = false,
        title: String = "Phase 6 fixture",
        start requestedStart: Date? = nil,
        end requestedEnd: Date? = nil,
        isAllDay: Bool = false,
        identifierSeed requestedIdentifierSeed: String? = nil,
        calendarIdentifier: String = "calendar",
        availability: CalendarEventAvailability = .notSupported,
        isCancelled: Bool = false,
        isDeclinedByCurrentUser: Bool = false
    ) -> DisplayEvent {
        let start = requestedStart ?? date(2026, 7, 10, 9)
        let end = requestedEnd ?? start.addingTimeInterval(3_600)
        let identifierSeed = requestedIdentifierSeed ?? id
        let timeSemantics: EventTimeSemantics
        if isAllDay {
            timeSemantics = .allDay(
                start: LocalDateTimeComponents(
                    date: start,
                    calendar: calendar
                ),
                endExclusive: LocalDateTimeComponents(
                    date: end,
                    calendar: calendar
                )
            )
        } else {
            timeSemantics = .zoned(
                timeZoneIdentifier: calendar.timeZone.identifier
            )
        }
        return DisplayEvent(
            id: id,
            eventIdentifier: "event-\(identifierSeed)",
            calendarItemIdentifier: "item-\(identifierSeed)",
            calendarItemExternalIdentifier: "external-\(identifierSeed)",
            calendarIdentifier: calendarIdentifier,
            calendarTitle: calendarIdentifier == "destination"
                ? "일정"
                : "KAOS-TEST",
            sourceTitle: "Exchange QA",
            accountType: .exchange,
            calendarColor: nil,
            title: title,
            location: nil,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            timeZoneIdentifier: calendar.timeZone.identifier,
            timeSemantics: timeSemantics,
            isRecurring: recurrence.isRecurring,
            occurrenceDate: recurrence.isRecurring ? start : nil,
            occurrenceLocalComponents: nil,
            isDetached: isDetached,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil,
            recurrence: recurrence,
            availability: availability,
            isCancelled: isCancelled,
            isDeclinedByCurrentUser: isDeclinedByCurrentUser
        )
    }

    private func makeCivilRecurringEvent(
        id: String,
        localDay: Int,
        identifierSeed: String,
        isAllDay: Bool,
        rawStart requestedRawStart: Date? = nil
    ) -> DisplayEvent {
        let localHour = isAllDay ? 0 : 9
        let localStartDate = date(2026, 7, localDay, localHour)
        let localEndDate = isAllDay
            ? date(2026, 7, localDay + 1)
            : date(2026, 7, localDay, localHour + 1)
        let localStart = LocalDateTimeComponents(
            date: localStartDate,
            calendar: calendar
        )
        let localEnd = LocalDateTimeComponents(
            date: localEndDate,
            calendar: calendar
        )
        let rawStart = requestedRawStart ?? localStartDate
        let rawEnd = rawStart.addingTimeInterval(
            isAllDay ? 86_400 : 3_600
        )
        let timeSemantics: EventTimeSemantics = isAllDay
            ? .allDay(start: localStart, endExclusive: localEnd)
            : .floating(start: localStart, end: localEnd)

        return DisplayEvent(
            id: id,
            eventIdentifier: "event-\(identifierSeed)",
            calendarItemIdentifier: "item-\(identifierSeed)",
            calendarItemExternalIdentifier: "external-\(identifierSeed)",
            calendarIdentifier: "calendar",
            calendarTitle: "KAOS-TEST",
            sourceTitle: "Exchange QA",
            accountType: .exchange,
            calendarColor: nil,
            title: "Civil recurring fixture",
            location: nil,
            startDate: rawStart,
            endDate: rawEnd,
            isAllDay: isAllDay,
            timeZoneIdentifier: nil,
            timeSemantics: timeSemantics,
            isRecurring: true,
            occurrenceDate: rawStart,
            occurrenceLocalComponents: localStart,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil,
            recurrence: .basic(
                BasicRecurrenceRule(frequency: .daily)
            )
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

@MainActor
final class Phase9AppStateTests: XCTestCase {
    func testExportFlushesPendingSelectedNotesWithoutCalendarWrites() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try AppDatabase.open(
            at: directory.appendingPathComponent("live.sqlite")
        )
        let store = ContextStore(database: database)
        let event = makeEvent()
        let provider = makeProvider(events: [event])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.updateSelectedEventNotes("Include this pending export note")
        XCTAssertEqual(state.notesSaveState, .pending)

        let archiveURL = directory.appendingPathComponent("manual-export.zip")
        let optionalResult = await state.exportLocalDataBackup(to: archiveURL)
        let result = try XCTUnwrap(optionalResult)
        let inspection = try store.localDataBackups.inspectBackup(at: archiveURL)

        XCTAssertEqual(result.archiveURL, archiveURL.standardizedFileURL)
        XCTAssertEqual(inspection.manifest, result.manifest)
        XCTAssertEqual(state.localDataOperationState, .idle)
        XCTAssertEqual(state.notesSaveState, .saved)
        guard case let .loaded(brief, _) = try store.loadBrief(for: event) else {
            return XCTFail("Expected the pending note to be flushed before export")
        }
        XCTAssertEqual(brief.context.notes, "Include this pending export note")
        assertNoCalendarWrites(provider)
    }

    func testImportReplacesLocalProjectionsAndKeepsPreImportBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let event = makeEvent()
        let sourceDatabase = try AppDatabase.open(
            at: directory.appendingPathComponent("source.sqlite")
        )
        let sourceStore = ContextStore(database: sourceDatabase)
        let sourceContext = try XCTUnwrap(
            try sourceStore.saveNotes(
                for: event,
                notes: "Imported source notes"
            )
        )
        let sourceEventTask = try sourceStore.appendEventTask(
            for: event,
            section: .before,
            title: "Imported source checklist"
        )
        let sourcePersonalTask = try sourceStore.personalTasks.create(
            title: "Imported personal task"
        )
        _ = try sourceStore.calendarRoles.upsert(
            source: calendarSource,
            role: .work
        )
        try sourceStore.calendarUsage.setVisibility(
            false,
            for: [calendarSource]
        )
        try sourceStore.calendarUsage.setBlocksAvailability(
            false,
            for: [calendarSource]
        )
        let sourceArchiveURL = directory.appendingPathComponent("source.zip")
        _ = try sourceStore.localDataBackups.exportBackup(
            to: sourceArchiveURL,
            now: date(2026, 7, 12, 9),
            appVersion: "phase9-test"
        )

        let targetDatabase = try AppDatabase.open(
            at: directory.appendingPathComponent("target.sqlite")
        )
        let targetStore = ContextStore(database: targetDatabase)
        let targetContext = try XCTUnwrap(
            try targetStore.saveNotes(
                for: event,
                notes: "Replace these target notes"
            )
        )
        _ = try targetStore.appendEventTask(
            for: event,
            section: .after,
            title: "Replace this target checklist"
        )
        let targetPersonalTask = try targetStore.personalTasks.create(
            title: "Replace this personal task"
        )
        _ = try targetStore.calendarRoles.upsert(
            source: calendarSource,
            role: .personal
        )
        try targetStore.calendarUsage.setVisibility(
            true,
            for: [calendarSource]
        )
        try targetStore.calendarUsage.setBlocksAvailability(
            true,
            for: [calendarSource]
        )

        let provider = makeProvider(events: [event])
        let state = makeState(provider: provider, store: targetStore)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        XCTAssertEqual(state.selectedEventNotes, "Replace these target notes")
        XCTAssertEqual(
            state.recoveryBriefs.map(\.context.id),
            [targetContext.id]
        )

        let optionalResult = await state.importLocalDataBackup(
            from: sourceArchiveURL
        )
        let result = try XCTUnwrap(optionalResult)

        XCTAssertEqual(state.localDataOperationState, .idle)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.automaticBackupURL.path
            )
        )
        XCTAssertNoThrow(
            try targetStore.localDataBackups.inspectBackup(
                at: result.automaticBackupURL
            )
        )
        XCTAssertNil(try targetStore.eventContexts.fetch(id: targetContext.id))
        XCTAssertNil(
            try targetStore.personalTasks.fetch(id: targetPersonalTask.id)
        )

        let importedBrief = try XCTUnwrap(
            targetStore.eventContexts.fetchBrief(
                contextID: sourceContext.id
            )
        )
        XCTAssertEqual(importedBrief.context.notes, "Imported source notes")
        XCTAssertEqual(importedBrief.tasks.map(\.id), [sourceEventTask.id])
        XCTAssertEqual(
            try targetStore.personalTasks.fetch(id: sourcePersonalTask.id)?.title,
            "Imported personal task"
        )
        XCTAssertEqual(
            try targetStore.calendarRoles.fetch(
                calendarIdentifier: calendarSource.id
            )?.role,
            .work
        )
        XCTAssertEqual(
            try targetStore.calendarUsage.fetch(
                calendarIdentifier: calendarSource.id
            )?.visibilityOverride,
            false
        )
        XCTAssertEqual(
            try targetStore.calendarUsage.fetch(
                calendarIdentifier: calendarSource.id
            )?.blockingOverride,
            false
        )
        XCTAssertNil(state.selectedEventID)
        XCTAssertEqual(state.selectedEventNotes, "")
        XCTAssertEqual(state.calendarRole(for: event), .work)
        XCTAssertFalse(state.calendarUsagePolicy(for: calendarSource).isVisible)
        XCTAssertFalse(
            state.calendarUsagePolicy(for: calendarSource).blocksAvailability
        )
        XCTAssertEqual(
            state.recoveryBriefs.map(\.context.id),
            [sourceContext.id]
        )
        XCTAssertNil(state.eventEditorSession)
        XCTAssertNil(state.pendingEventMutation)
        XCTAssertNil(state.linkedEventRecoverySession)
        XCTAssertFalse(state.lastEventMutationUndoAvailable)

        let recoveredDatabase = try AppDatabase.open(
            at: directory.appendingPathComponent("pre-import-recovered.sqlite")
        )
        let recoveredStore = ContextStore(database: recoveredDatabase)
        _ = try recoveredStore.localDataBackups.importBackup(
            from: result.automaticBackupURL,
            automaticBackupDirectory: directory.appendingPathComponent(
                "Recovery-Safety",
                isDirectory: true
            ),
            now: date(2026, 7, 12, 10),
            appVersion: "phase9-test"
        )
        XCTAssertEqual(
            try recoveredStore.eventContexts.fetchBrief(
                contextID: targetContext.id
            )?.context.notes,
            "Replace these target notes"
        )
        XCTAssertEqual(
            try recoveredStore.calendarRoles.fetch(
                calendarIdentifier: calendarSource.id
            )?.role,
            .personal
        )
        XCTAssertEqual(
            try recoveredStore.calendarUsage.fetch(
                calendarIdentifier: calendarSource.id
            )?.visibilityOverride,
            true
        )
        XCTAssertEqual(
            try recoveredStore.calendarUsage.fetch(
                calendarIdentifier: calendarSource.id
            )?.blockingOverride,
            true
        )
        assertNoCalendarWrites(provider)
    }

    func testResetClearsLocalDataKeepsCalendarEventAndCreatesRestorableBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try AppDatabase.open(
            at: directory.appendingPathComponent("reset.sqlite")
        )
        let store = ContextStore(database: database)
        let event = makeEvent()
        let context = try XCTUnwrap(
            try store.saveNotes(for: event, notes: "Recover after reset")
        )
        let eventTask = try store.appendEventTask(
            for: event,
            section: .during,
            title: "Recover reset checklist"
        )
        let personalTask = try store.personalTasks.create(
            title: "Recover reset personal task"
        )
        _ = try store.calendarRoles.upsert(
            source: calendarSource,
            role: .family
        )
        try store.calendarUsage.setVisibility(
            false,
            for: [calendarSource]
        )
        try store.calendarUsage.setBlocksAvailability(
            false,
            for: [calendarSource]
        )

        let provider = makeProvider(events: [event])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        let optionalResult = await state.resetLocalData()
        let result = try XCTUnwrap(optionalResult)

        XCTAssertGreaterThan(result.deletedRowCounts.total, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.automaticBackupURL.path
            )
        )
        XCTAssertNoThrow(
            try store.localDataBackups.inspectBackup(
                at: result.automaticBackupURL
            )
        )
        XCTAssertTrue(try store.eventContexts.fetchAll().isEmpty)
        XCTAssertEqual(try store.eventTasks.count(), 0)
        XCTAssertEqual(try store.personalTasks.count(), 0)
        XCTAssertEqual(try store.calendarRoles.count(), 0)
        XCTAssertEqual(try store.calendarUsage.count(), 0)
        XCTAssertEqual(state.events.map(\.id), [event.id])
        XCTAssertEqual(provider.events.map(\.id), [event.id])
        XCTAssertEqual(state.selectedEventID, event.id)
        XCTAssertEqual(state.eventBriefState, .empty)
        XCTAssertEqual(state.calendarRole(for: event), .other)
        XCTAssertTrue(state.calendarUsagePolicy(for: calendarSource).isVisible)
        XCTAssertTrue(
            state.calendarUsagePolicy(for: calendarSource).blocksAvailability
        )
        XCTAssertTrue(state.recoveryBriefs.isEmpty)

        let recoveredDatabase = try AppDatabase.open(
            at: directory.appendingPathComponent("reset-recovered.sqlite")
        )
        let recoveredStore = ContextStore(database: recoveredDatabase)
        _ = try recoveredStore.localDataBackups.importBackup(
            from: result.automaticBackupURL,
            automaticBackupDirectory: directory.appendingPathComponent(
                "Reset-Recovery-Safety",
                isDirectory: true
            ),
            now: date(2026, 7, 12, 11),
            appVersion: "phase9-test"
        )
        let recoveredBrief = try XCTUnwrap(
            recoveredStore.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(recoveredBrief.context.notes, "Recover after reset")
        XCTAssertEqual(recoveredBrief.tasks.map(\.id), [eventTask.id])
        XCTAssertEqual(
            try recoveredStore.personalTasks.fetch(id: personalTask.id)?.title,
            "Recover reset personal task"
        )
        XCTAssertEqual(
            try recoveredStore.calendarRoles.fetch(
                calendarIdentifier: calendarSource.id
            )?.role,
            .family
        )
        XCTAssertEqual(
            try recoveredStore.calendarUsage.fetch(
                calendarIdentifier: calendarSource.id
            )?.visibilityOverride,
            false
        )
        XCTAssertEqual(
            try recoveredStore.calendarUsage.fetch(
                calendarIdentifier: calendarSource.id
            )?.blockingOverride,
            false
        )
        assertNoCalendarWrites(provider)
    }

    func testImportRollbackFailureQuarantinesMutationsAndRefreshForSession() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("quarantine.sqlite")
        let database = try AppDatabase.open(at: databaseURL)
        let store = ContextStore(database: database)
        let existingTask = try store.personalTasks.create(
            title: "Keep this local task"
        )
        let event = makeEvent()
        let provider = makeProvider(events: [event])
        let state = AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 12, 12) },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: .ready,
            localDataImportOperation: { _, _, _, _, _ in
                throw LocalDataBackupError.importFailed(
                    reason: "forced restore and rollback failure",
                    rollbackSucceeded: false
                )
            }
        )
        await state.loadCalendarStatus()
        let fetchCountBeforeImport = provider.fetchCallCount

        let result = await state.importLocalDataBackup(
            from: directory.appendingPathComponent("forced-import.zip")
        )

        XCTAssertNil(result)
        XCTAssertEqual(state.localDataOperationState, .quarantined)
        let message = try XCTUnwrap(state.localDataOperationMessage)
        let backupDirectory = directory.appendingPathComponent(
            "Backups",
            isDirectory: true
        )
        XCTAssertTrue(message.contains("could not restore the previous local database"))
        XCTAssertTrue(message.contains("locked for this session"))
        XCTAssertTrue(message.contains("Quit KaosCal before recovery"))
        XCTAssertTrue(message.contains(backupDirectory.path))
        guard case let .failed(storeMessage) = state.localContextStoreState else {
            return XCTFail("A rollback failure must quarantine the local store")
        }
        XCTAssertEqual(storeMessage, message)

        state.clearLocalDataOperationMessage()
        XCTAssertEqual(state.localDataOperationMessage, message)

        XCTAssertFalse(state.createPersonalTask(title: "Must not write", dueAt: nil))
        XCTAssertNotNil(try store.personalTasks.fetch(id: existingTask.id))
        XCTAssertEqual(try store.personalTasks.count(), 1)
        XCTAssertFalse(state.setCalendarRole(.work, for: calendarSource))
        XCTAssertEqual(try store.calendarRoles.count(), 0)

        provider.events = []
        await state.refreshCalendarData()
        provider.storeChangeHandler?()
        await Task.yield()
        XCTAssertEqual(provider.fetchCallCount, fetchCountBeforeImport)
        XCTAssertEqual(state.events.map(\.id), [event.id])

        state.beginCreatingEvent()
        XCTAssertNil(state.eventEditorSession)
        XCTAssertTrue(
            state.eventEditorError?.contains("locked for this session") == true
        )
        assertNoCalendarWrites(provider)
    }

    func testResetRollbackFailureUsesTheSameQuarantineBoundary() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try AppDatabase.open(
            at: directory.appendingPathComponent("reset-quarantine.sqlite")
        )
        let store = ContextStore(database: database)
        let provider = makeProvider(events: [])
        let state = AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 12, 12) },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: .ready,
            localDataResetOperation: { _, _, _, _ in
                throw LocalDataBackupError.resetFailed(
                    reason: "forced reset rollback failure",
                    rollbackSucceeded: false
                )
            }
        )

        let result = await state.resetLocalData()

        XCTAssertNil(result)
        XCTAssertEqual(state.localDataOperationState, .quarantined)
        let message = try XCTUnwrap(state.localDataOperationMessage)
        XCTAssertTrue(message.contains("Reset failed"))
        XCTAssertTrue(message.contains("automatic pre-reset recovery ZIP"))
        XCTAssertTrue(message.contains("Backups"))
        guard case let .failed(storeMessage) = state.localContextStoreState else {
            return XCTFail("A reset rollback failure must quarantine the local store")
        }
        XCTAssertEqual(storeMessage, message)
        assertNoCalendarWrites(provider)
    }

    func testLocalDataSettingsFileBackedHealthyStateFitsAndProducesOffscreenBitmap() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("settings.sqlite")
        try autoreleasepool {
            let database = try AppDatabase.open(at: databaseURL)
            let store = ContextStore(database: database)
            let provider = makeProvider(events: [])
            let state = makeState(provider: provider, store: store)
            XCTAssertEqual(
                state.localDataDatabaseURL,
                databaseURL.standardizedFileURL
            )
            XCTAssertEqual(state.localContextStoreState, .ready)
            let hostingView = NSHostingView(rootView:
                LocalDataSettingsView(appState: state)
                    .background(Color(nsColor: .windowBackgroundColor))
            )

            let fittingSize = hostingView.fittingSize
            XCTAssertLessThanOrEqual(fittingSize.width, 620.5)
            XCTAssertLessThanOrEqual(fittingSize.height, 620.5)

            hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 620)
            hostingView.wantsLayer = true
            hostingView.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(
                in: hostingView.bounds,
                to: representation
            )
            let pngData = try XCTUnwrap(
                representation.representation(using: .png, properties: [:])
            )

            XCTAssertGreaterThanOrEqual(representation.pixelsWide, 620)
            XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 620)
            XCTAssertGreaterThan(pngData.count, 10_000)
            assertNoCalendarWrites(provider)
        }
    }

    func testCalendarUsageSettingsFitsAndProducesOffscreenBitmap() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await assertCalendarUsageSettingsBitmap(in: directory)
    }

    func testCalendarSetSettingsFitsAndProducesOffscreenBitmap() async throws {
        var store: ContextStore? = ContextStore(
            database: try AppDatabase.inMemory()
        )
        var provider: FakeCalendarProvider? = makeProvider(events: [makeEvent()])
        let personalSource = CalendarSource(
            id: "personal-calendar",
            title: "Personal Calendar With A Long Name",
            sourceTitle: "iCloud Personal Account",
            sourceIdentifier: "icloud-personal",
            accountType: .local,
            isWritable: true,
            color: nil
        )
        provider?.calendars.append(personalSource)
        var state: AppState? = makeState(
            provider: try XCTUnwrap(provider),
            store: try XCTUnwrap(store)
        )
        defer {
            provider?.storeChangeHandler = nil
            state = nil
            store = nil
            provider = nil
        }
        await state?.loadCalendarStatus()

        try autoreleasepool {
            let state = try XCTUnwrap(state)
            let savedSet = try XCTUnwrap(state.createCalendarSet(
                name: "Work and Personal Focus",
                calendarIdentifiers: Set([calendarSource.id, personalSource.id])
            ))
            XCTAssertTrue(state.selectCalendarSet(.saved(savedSet.id)))
            state.selectedSettingsPane = .calendarSets
            XCTAssertEqual(state.selectedSettingsPane, .calendarSets)

            let hostingView = NSHostingView(rootView:
                CalendarSetSettingsView(appState: state)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            let fittingSize = hostingView.fittingSize
            XCTAssertLessThanOrEqual(fittingSize.width, 780)
            XCTAssertLessThanOrEqual(fittingSize.height, 680)

            hostingView.frame = NSRect(x: 0, y: 0, width: 780, height: 680)
            hostingView.wantsLayer = true
            let window = NSWindow(
                contentRect: hostingView.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            let representation = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
            let pngData = try XCTUnwrap(
                representation.representation(using: .png, properties: [:])
            )

            XCTAssertGreaterThanOrEqual(representation.pixelsWide, 780)
            XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 680)
            XCTAssertGreaterThan(pngData.count, 10_000)
            if let snapshotPath = ProcessInfo.processInfo.environment[
                "KAOSCAL_CALENDAR_SET_SNAPSHOT_PATH"
            ] {
                try pngData.write(to: URL(fileURLWithPath: snapshotPath))
            }
            window.contentView = nil
        }
        assertNoCalendarWrites(try XCTUnwrap(provider))
    }

    private func assertCalendarUsageSettingsBitmap(
        in directory: URL
    ) async throws {
        var store: ContextStore? = ContextStore(
            database: try AppDatabase.open(
                at: directory.appendingPathComponent("calendar-settings.sqlite")
            )
        )
        var provider: FakeCalendarProvider? = makeProvider(events: [makeEvent()])
        var state: AppState? = makeState(
            provider: try XCTUnwrap(provider),
            store: try XCTUnwrap(store)
        )
        defer {
            provider?.storeChangeHandler = nil
            state = nil
            store = nil
            provider = nil
        }
        await state?.loadCalendarStatus()

        try autoreleasepool {
            let state = try XCTUnwrap(state)
            let provider = try XCTUnwrap(provider)
            let hostingView = NSHostingView(rootView:
                SettingsRootView(appState: state)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            let fittingSize = hostingView.fittingSize
            XCTAssertLessThanOrEqual(fittingSize.width, 630)
            XCTAssertLessThanOrEqual(fittingSize.height, 650)

            hostingView.frame = NSRect(x: 0, y: 0, width: 630, height: 650)
            hostingView.wantsLayer = true
            hostingView.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
            let pngData = try XCTUnwrap(
                representation.representation(using: .png, properties: [:])
            )

            XCTAssertGreaterThanOrEqual(representation.pixelsWide, 630)
            XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 650)
            XCTAssertGreaterThan(pngData.count, 10_000)
            assertNoCalendarWrites(provider)
        }
    }

    func testPhase10OnboardingFitsAndProducesOffscreenBitmap() throws {
        let hostingView = NSHostingView(rootView:
            PaidBetaOnboardingView(complete: {})
                .background(Color(nsColor: .windowBackgroundColor))
        )
        let fittingSize = hostingView.fittingSize
        XCTAssertLessThanOrEqual(fittingSize.width, 680.5)
        XCTAssertLessThanOrEqual(fittingSize.height, 560)

        hostingView.frame = NSRect(x: 0, y: 0, width: 680, height: 560)
        hostingView.wantsLayer = true
        hostingView.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let pngData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        XCTAssertGreaterThanOrEqual(representation.pixelsWide, 680)
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 560)
        XCTAssertGreaterThan(pngData.count, 10_000)
    }

    func testBootstrapRecoveryStateFitsAndProducesOffscreenBitmap() throws {
        let hostingView = NSHostingView(rootView:
            BootstrapLocalDataRecoveryView(
                message: "database disk image is malformed",
                operationState: .idle,
                databaseURL: URL(fileURLWithPath: "/private/example/KaosCal/kaoscal.sqlite"),
                recover: { _ in }
            )
            .frame(width: 620, height: 520)
            .background(Color(nsColor: .windowBackgroundColor))
        )
        let fittingSize = hostingView.fittingSize
        XCTAssertLessThanOrEqual(fittingSize.width, 620.5)
        XCTAssertLessThanOrEqual(fittingSize.height, 520.5)

        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 520)
        hostingView.wantsLayer = true
        hostingView.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let pngData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        XCTAssertGreaterThanOrEqual(representation.pixelsWide, 620)
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 520)
        XCTAssertGreaterThan(pngData.count, 10_000)
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var calendarSource: CalendarSource {
        CalendarSource(
            id: "calendar",
            title: "KAOS-TEST",
            sourceTitle: "Exchange QA",
            sourceIdentifier: "exchange-qa",
            accountType: .exchange,
            isWritable: true,
            color: nil
        )
    }

    private func makeProvider(events: [DisplayEvent]) -> FakeCalendarProvider {
        let provider = FakeCalendarProvider(
            authorizationState: .fullAccess
        )
        provider.calendars = [calendarSource]
        provider.events = events
        return provider
    }

    private func makeState(
        provider: FakeCalendarProvider,
        store: ContextStore
    ) -> AppState {
        AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 12, 12) },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: .ready
        )
    }

    private func makeEvent() -> DisplayEvent {
        let start = date(2026, 7, 12, 9)
        return DisplayEvent(
            id: "phase9-event",
            eventIdentifier: "event-phase9",
            calendarItemIdentifier: "item-phase9",
            calendarItemExternalIdentifier: "external-phase9",
            calendarIdentifier: calendarSource.id,
            calendarTitle: calendarSource.title,
            sourceTitle: calendarSource.sourceTitle,
            accountType: calendarSource.accountType,
            calendarColor: nil,
            title: "Phase 9 backup fixture",
            location: nil,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: calendar.timeZone.identifier,
            timeSemantics: .zoned(
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            isRecurring: false,
            occurrenceDate: nil,
            occurrenceLocalComponents: nil,
            isDetached: false,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil,
            recurrence: .none
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Phase9AppStateTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }

    private func assertNoCalendarWrites(
        _ provider: FakeCalendarProvider,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(provider.createCallCount, 0, file: file, line: line)
        XCTAssertEqual(provider.updateCallCount, 0, file: file, line: line)
        XCTAssertEqual(provider.deleteCallCount, 0, file: file, line: line)
    }
}
