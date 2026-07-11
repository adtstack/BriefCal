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
