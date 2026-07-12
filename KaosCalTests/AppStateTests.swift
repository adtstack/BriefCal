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

        for section in [WorkspaceSection.day, .week, .agenda] {
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

    func testPossibleDuplicateCanOpenCandidateOutsideCurrentRoleSet() async throws {
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
        state.selectCalendarSet(.work)

        let candidate = try XCTUnwrap(
            state.duplicateCandidates(for: work).first
        )
        XCTAssertEqual(candidate.event.id, personal.id)
        state.selectDuplicateCandidate(candidate)

        XCTAssertEqual(state.selectedCalendarSet, .all)
        XCTAssertEqual(state.selectedEventID, personal.id)
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
                accountType: .exchange,
                isWritable: true,
                color: nil
            ),
            CalendarSource(
                id: "destination",
                title: "일정",
                sourceTitle: "Exchange QA",
                accountType: .exchange,
                isWritable: true,
                color: nil
            )
        ]
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
        identifierSeed requestedIdentifierSeed: String? = nil,
        calendarIdentifier: String = "calendar"
    ) -> DisplayEvent {
        let start = requestedStart ?? date(2026, 7, 10, 9)
        let identifierSeed = requestedIdentifierSeed ?? id
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
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: calendar.timeZone.identifier,
            timeSemantics: .zoned(
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            isRecurring: recurrence.isRecurring,
            occurrenceDate: recurrence.isRecurring ? start : nil,
            occurrenceLocalComponents: nil,
            isDetached: isDetached,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil,
            recurrence: recurrence
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
        _ hour: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
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
        XCTAssertEqual(state.selectedEventNotes, "Imported source notes")
        XCTAssertEqual(state.calendarRole(for: event), .work)
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
        XCTAssertEqual(state.events.map(\.id), [event.id])
        XCTAssertEqual(provider.events.map(\.id), [event.id])
        XCTAssertEqual(state.selectedEventID, event.id)
        XCTAssertEqual(state.eventBriefState, .empty)
        XCTAssertEqual(state.calendarRole(for: event), .other)
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
