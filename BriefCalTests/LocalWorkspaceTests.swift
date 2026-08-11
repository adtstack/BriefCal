import XCTest
@testable import BriefCal

@MainActor
final class LocalWorkspaceTests: XCTestCase {
    func testEventSelectionIsLazyAndFlushesNotesBeforeSwitch() async throws {
        let first = makeEvent(id: "first", start: date(2026, 7, 10, 9))
        let second = makeEvent(id: "second", start: date(2026, 7, 10, 11))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [first, second], store: store)
        await state.loadCalendarStatus()

        state.selectEvent(first.id)
        XCTAssertEqual(state.eventBriefState, .empty)
        XCTAssertEqual(try store.eventContexts.count(), 0)

        state.updateSelectedEventNotes("Prepare the deck")
        XCTAssertEqual(state.notesSaveState, .pending)
        state.selectEvent(second.id)

        XCTAssertEqual(state.selectedEventID, second.id)
        XCTAssertEqual(state.selectedEventNotes, "")
        XCTAssertEqual(state.eventBriefState, .empty)
        XCTAssertEqual(try store.eventContexts.count(), 1)
        guard case let .loaded(snapshot, _) = try store.loadBrief(for: first) else {
            return XCTFail("Expected first event brief")
        }
        XCTAssertEqual(snapshot.context.notes, "Prepare the deck")
        XCTAssertEqual(try store.loadBrief(for: second), .empty)
    }

    func testNotesDebouncePersistsWithoutExplicitSave() async throws {
        let event = makeEvent(id: "debounce", start: date(2026, 7, 10, 9))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [event], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)

        state.updateSelectedEventNotes("Autosaved locally")
        try await Task.sleep(nanoseconds: 850_000_000)

        XCTAssertEqual(state.notesSaveState, .saved)
        guard case let .loaded(snapshot) = state.eventBriefState else {
            return XCTFail("Expected loaded brief")
        }
        XCTAssertEqual(snapshot.context.notes, "Autosaved locally")
    }

    func testSameEventRefreshPreservesPendingNotesDraft() async throws {
        let event = makeEvent(id: "refresh", start: date(2026, 7, 10, 9))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [event], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.updateSelectedEventNotes("Draft during refresh")

        await state.refreshCalendarData()

        XCTAssertEqual(state.selectedEventID, event.id)
        XCTAssertEqual(state.selectedEventNotes, "Draft during refresh")
        XCTAssertEqual(state.notesSaveState, .pending)
        state.flushPendingEventNotes()
        guard case let .loaded(snapshot, _) = try store.loadBrief(for: event) else {
            return XCTFail("Expected saved draft")
        }
        XCTAssertEqual(snapshot.context.notes, "Draft during refresh")
    }

    func testMovedEventRefreshUpdatesBriefAndTaskDueWithoutLosingDraft() async throws {
        let original = makeEvent(id: "moved", start: date(2026, 7, 10, 15))
        let moved = makeEvent(id: "moved", start: date(2026, 7, 10, 18))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.events = [original]
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        state.selectEvent(original.id)
        state.addSelectedEventTask(section: .before, title: "Follow event")
        state.updateSelectedEventNotes("Pending while event moves")

        provider.events = [moved]
        await state.refreshCalendarData()

        XCTAssertEqual(state.selectedEventNotes, "Pending while event moves")
        XCTAssertEqual(state.notesSaveState, .pending)
        guard case let .loaded(brief) = state.eventBriefState else {
            return XCTFail("Expected refreshed brief")
        }
        XCTAssertEqual(brief.link.startSnapshot, moved.startDate)
        guard case let .loaded(items) = state.taskCenterState else {
            return XCTFail("Expected refreshed Task Center")
        }
        XCTAssertEqual(items.first?.dueAt, moved.startDate)
    }

    func testLocalMutationFlushesPendingNotesBeforeBriefReload() async throws {
        let event = makeEvent(id: "mutation", start: date(2026, 7, 10, 9))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [event], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.updateSelectedEventNotes("Keep this draft")

        state.createPersonalTask(title: "Parallel local edit", dueAt: nil)

        XCTAssertEqual(state.selectedEventNotes, "Keep this draft")
        guard case let .loaded(snapshot) = state.eventBriefState else {
            return XCTFail("Expected loaded brief")
        }
        XCTAssertEqual(snapshot.context.notes, "Keep this draft")
        XCTAssertEqual(try store.personalTasks.count(), 1)
    }

    func testEventTaskCompletionRefreshesBriefAndTaskCenter() async throws {
        let event = makeEvent(id: "meeting", start: date(2026, 7, 10, 15))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [event], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)

        state.addSelectedEventTask(section: .before, title: "Bring notes")
        guard case let .loaded(brief) = state.eventBriefState,
              let task = brief.tasks.first else {
            return XCTFail("Expected event task")
        }
        guard case let .loaded(todayItems) = state.taskCenterState else {
            return XCTFail("Expected Today items")
        }
        XCTAssertEqual(todayItems.map(\.id), [
            .eventTask(taskID: task.id, contextID: brief.context.id)
        ])

        state.setSelectedEventTaskCompleted(id: task.id, isCompleted: true)
        guard case let .loaded(updatedBrief) = state.eventBriefState else {
            return XCTFail("Expected refreshed brief")
        }
        XCTAssertTrue(try XCTUnwrap(updatedBrief.tasks.first).isCompleted)
        guard case let .loaded(openItems) = state.taskCenterState else {
            return XCTFail("Expected refreshed Today items")
        }
        XCTAssertTrue(openItems.isEmpty)

        state.selectTaskFilter(.completed)
        guard case let .loaded(completedItems) = state.taskCenterState else {
            return XCTFail("Expected Completed items")
        }
        XCTAssertEqual(completedItems.count, 1)
        XCTAssertEqual(completedItems.first?.id, .eventTask(
            taskID: task.id,
            contextID: brief.context.id
        ))
    }

    func testPersonalTaskCreateRenameCompleteAndDeleteAcrossFilters() throws {
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [], store: store)

        state.createPersonalTask(title: "Inbox item", dueAt: nil)
        XCTAssertEqual(state.selectedTaskFilter, .noDate)
        guard case let .loaded(noDateItems) = state.taskCenterState,
              let item = noDateItems.first else {
            return XCTFail("Expected personal task")
        }
        guard case let .personalTask(taskID) = item.id else {
            return XCTFail("Expected personal task identity")
        }

        state.renameTaskCenterItem(item.id, title: "Inbox item edited")
        XCTAssertEqual(try store.personalTasks.fetch(id: taskID)?.title, "Inbox item edited")

        state.setTaskCenterItemCompleted(item.id, isCompleted: true)
        state.selectTaskFilter(.completed)
        guard case let .loaded(completedItems) = state.taskCenterState else {
            return XCTFail("Expected Completed items")
        }
        XCTAssertEqual(completedItems.first?.title, "Inbox item edited")

        state.deleteTaskCenterItem(item.id)
        guard case let .loaded(afterDelete) = state.taskCenterState else {
            return XCTFail("Expected refreshed Completed items")
        }
        XCTAssertTrue(afterDelete.isEmpty)
        XCTAssertNil(try store.personalTasks.fetch(id: taskID))
    }

    func testPersonalDueUpdateMovesBetweenTodayAndUpcoming() throws {
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [], store: store)
        XCTAssertTrue(state.createPersonalTask(title: "Move by due", dueAt: nil))
        XCTAssertEqual(state.selectedTaskFilter, .noDate)
        guard case let .loaded(noDateItems) = state.taskCenterState,
              let item = noDateItems.first else {
            return XCTFail("Expected No Date item")
        }
        let future = date(2026, 7, 12, 9)

        XCTAssertTrue(state.updatePersonalTaskDue(item.id, dueAt: future))
        XCTAssertEqual(state.selectedTaskFilter, .upcoming)
        guard case let .loaded(upcomingItems) = state.taskCenterState else {
            return XCTFail("Expected Upcoming items")
        }
        XCTAssertEqual(upcomingItems.first?.dueAt, future)

        XCTAssertTrue(state.updatePersonalTaskDue(item.id, dueAt: nil))
        XCTAssertEqual(state.selectedTaskFilter, .noDate)
        guard case let .loaded(returnedNoDateItems) = state.taskCenterState else {
            return XCTFail("Expected No Date items")
        }
        XCTAssertNil(returnedNoDateItems.first?.dueAt)
    }

    func testCompletingRepeatingTaskCreatesNextOccurrenceAndStopsTimer() throws {
        var current = date(2026, 7, 10, 12)
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { current }
        )
        let state = makeState(events: [], store: store)
        let original = try store.personalTasks.create(
            title: "Daily review",
            dueAt: date(2026, 7, 10, 18)
        )
        let id = TaskCenterItemID.personalTask(taskID: original.id)
        XCTAssertTrue(state.saveTaskPlanning(
            id,
            priority: .medium,
            isImportant: true,
            repeatFrequency: .daily,
            repeatInterval: 1,
            estimatedMinutes: 20
        ))
        XCTAssertTrue(state.addTaskChecklistItem(id, title: "Open notes"))
        XCTAssertTrue(state.toggleTaskTimer(id))
        current = date(2026, 7, 10, 12).addingTimeInterval(120)

        state.setTaskCenterItemCompleted(id, isCompleted: true)

        let originalPlanning = try store.taskPlanning.snapshot(for: id).0
        XCTAssertFalse(originalPlanning.isTimerRunning)
        XCTAssertEqual(originalPlanning.actualSeconds, 120)
        let repeated = try XCTUnwrap(
            store.personalTasks.fetch(
                list: .upcoming,
                now: date(2026, 7, 10, 12),
                calendar: testCalendar
            ).first
        )
        XCTAssertEqual(repeated.title, "Daily review")
        XCTAssertEqual(repeated.dueAt, date(2026, 7, 11, 18))
        let repeatedSnapshot = try store.taskPlanning.snapshot(
            for: .personalTask(taskID: repeated.id)
        )
        XCTAssertEqual(repeatedSnapshot.0.priority, .medium)
        XCTAssertTrue(repeatedSnapshot.0.isImportant)
        XCTAssertEqual(repeatedSnapshot.0.repeatFrequency, .daily)
        XCTAssertEqual(repeatedSnapshot.0.actualSeconds, 0)
        XCTAssertNil(repeatedSnapshot.0.startedAt)
        XCTAssertEqual(repeatedSnapshot.1.map(\.title), ["Open notes"])
        XCTAssertEqual(repeatedSnapshot.1.map(\.isCompleted), [false])
    }

    func testUpcomingQuickAddRejectsTodayDueDate() throws {
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [], store: store)
        state.selectTaskFilter(.upcoming)

        XCTAssertFalse(state.createPersonalTask(
            title: "Invalid upcoming",
            dueAt: date(2026, 7, 10, 18)
        ))
        XCTAssertEqual(try store.personalTasks.count(), 0)
        XCTAssertNotNil(state.localOperationError)
    }

    func testTaskCenterRefreshUsesInjectedClockAfterDayBoundary() throws {
        var current = date(2026, 7, 10, 12)
        let store = ContextStore(database: try AppDatabase.inMemory())
        _ = try store.personalTasks.create(
            title: "Tomorrow becomes today",
            dueAt: date(2026, 7, 11, 9)
        )
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        let state = AppState(
            calendar: testCalendar,
            now: { current },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: .ready
        )

        state.refreshTaskCenter()
        guard case let .loaded(firstDay) = state.taskCenterState else {
            return XCTFail("Expected initial Today list")
        }
        XCTAssertTrue(firstDay.isEmpty)

        current = date(2026, 7, 11, 8)
        state.refreshTaskCenter()
        guard case let .loaded(nextDay) = state.taskCenterState else {
            return XCTFail("Expected refreshed Today list")
        }
        XCTAssertEqual(nextDay.map(\.title), ["Tomorrow becomes today"])
    }

    func testTaskCenterRefreshUpdatesSelectedBriefAtEventEnd() async throws {
        var current = date(2026, 7, 10, 9)
        let event = makeEvent(
            id: "clock-crossing",
            start: date(2026, 7, 10, 9)
        )
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { current }
        )
        _ = try store.saveNotes(for: event, notes: "Keep after end")
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.events = [event]
        let state = AppState(
            calendar: testCalendar,
            now: { current },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: .ready
        )
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        guard case let .loaded(beforeEnd) = state.eventBriefState else {
            return XCTFail("Expected selected Event Brief")
        }
        XCTAssertEqual(beforeEnd.context.lifecycleStatus, .scheduled)

        current = date(2026, 7, 10, 10)
        state.refreshTaskCenter()

        guard case let .loaded(afterEnd) = state.eventBriefState else {
            return XCTFail("Expected refreshed Event Brief")
        }
        XCTAssertEqual(afterEnd.context.lifecycleStatus, .completed)
        XCTAssertEqual(state.selectedEventNotes, "Keep after end")
    }

    func testEventTaskRenameThenCompletionPreservesTitle() async throws {
        let event = makeEvent(id: "rename", start: date(2026, 7, 10, 15))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [event], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(event.id)
        state.addSelectedEventTask(section: .before, title: "Draft title")
        guard case let .loaded(brief) = state.eventBriefState,
              let task = brief.tasks.first else {
            return XCTFail("Expected event task")
        }

        XCTAssertTrue(state.renameSelectedEventTask(
            id: task.id,
            title: "Committed before complete"
        ))
        state.setSelectedEventTaskCompleted(id: task.id, isCompleted: true)

        let stored = try XCTUnwrap(store.eventTasks.fetch(id: task.id))
        XCTAssertEqual(stored.title, "Committed before complete")
        XCTAssertTrue(stored.isCompleted)
    }

    func testEventTaskTypedRenameSurvivesSelectionChange() async throws {
        let first = makeEvent(id: "rename-first", start: date(2026, 7, 10, 15))
        let second = makeEvent(id: "rename-second", start: date(2026, 7, 10, 17))
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [first, second], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(first.id)
        state.addSelectedEventTask(section: .before, title: "Draft before switch")
        guard case let .loaded(brief) = state.eventBriefState,
              let task = brief.tasks.first else {
            return XCTFail("Expected first event task")
        }

        state.selectEvent(second.id)
        XCTAssertTrue(state.renameTaskCenterItem(
            .eventTask(taskID: task.id, contextID: brief.context.id),
            title: "Saved after switch"
        ))

        XCTAssertEqual(state.selectedEventID, second.id)
        XCTAssertEqual(
            try store.eventTasks.fetch(id: task.id)?.title,
            "Saved after switch"
        )
    }

    func testOpeningTaskFetchesStoredRangeThenSelectsStrongEvent() async throws {
        let target = makeEvent(
            id: "future",
            start: date(2027, 2, 4, 13)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let task = try store.appendEventTask(
            for: target,
            section: .during,
            title: "Open me"
        )
        guard case let .eventTask(_, contextID) = TaskCenterItemID.eventTask(
            taskID: task.id,
            contextID: task.contextID
        ) else {
            return XCTFail("Expected event task identity")
        }

        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.eventsForInterval = { interval in
            interval.contains(target.startDate) ? [target] : []
        }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        XCTAssertTrue(state.events.isEmpty)

        await state.openOriginalEvent(contextID: contextID)

        XCTAssertTrue(try XCTUnwrap(provider.lastFetchInterval).contains(target.startDate))
        XCTAssertEqual(state.selectedSection, .day)
        XCTAssertEqual(state.selectedEventID, target.id)
        XCTAssertEqual(
            state.focusedDate,
            testCalendar.startOfDay(for: target.startDate)
        )
        XCTAssertNil(state.localOperationError)
    }

    func testOpeningTaskCancelsPreviouslyScheduledRangeLoad() async throws {
        let target = makeEvent(
            id: "target",
            start: date(2027, 2, 4, 13)
        )
        let stale = makeEvent(
            id: "stale",
            start: date(2028, 3, 5, 9)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(
            store.saveNotes(for: target, notes: "Target context")
        )
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.eventsForInterval = { interval in
            if interval.contains(stale.startDate) { return [stale] }
            if interval.contains(target.startDate) { return [target] }
            return []
        }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        state.focusedDate = stale.startDate
        state.select(.day)
        await state.openOriginalEvent(contextID: context.id)
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(state.selectedEventID, target.id)
        XCTAssertEqual(state.events, [target])
        XCTAssertTrue(try XCTUnwrap(provider.lastFetchInterval).contains(target.startDate))
    }

    func testEndedEventLoadsAfterReviewAndOnlyProjectsFollowUp() async throws {
        let ended = makeEvent(
            id: "ended-review",
            start: date(2026, 7, 10, 9)
        )
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) }
        )
        let before = try store.appendEventTask(
            for: ended,
            section: .before,
            title: "Prepare"
        )
        let after = try store.appendEventTask(
            for: ended,
            section: .after,
            title: "Send follow-up"
        )
        let personal = try store.personalTasks.create(title: "Personal")
        let state = makeState(events: [ended], store: store)

        await state.loadCalendarStatus()
        state.selectEvent(ended.id)

        guard case let .loaded(brief) = state.eventBriefState else {
            return XCTFail("Expected loaded Event Brief")
        }
        XCTAssertEqual(brief.context.lifecycleStatus, .completed)
        guard case let .loaded(today) = state.taskCenterState else {
            return XCTFail("Expected Today items")
        }
        XCTAssertEqual(
            Set(today.map(\.id)),
            Set([
                .eventTask(taskID: after.id, contextID: after.contextID)
            ])
        )
        state.selectTaskFilter(.noDate)
        guard case let .loaded(noDate) = state.taskCenterState else {
            return XCTFail("Expected No Date items")
        }
        XCTAssertEqual(noDate.map(\.id), [
            .personalTask(taskID: personal.id)
        ])
        XCTAssertFalse(today.contains {
            $0.id == .eventTask(
                taskID: before.id,
                contextID: before.contextID
            )
        })

        state.selectTaskFilter(.afterReview)

        XCTAssertEqual(state.selectedTaskFilter, .afterReview)
        guard case let .loaded(reviewItems) = state.taskCenterState else {
            return XCTFail("Expected After Review items")
        }
        XCTAssertEqual(reviewItems.map(\.id), [
            .eventTask(taskID: after.id, contextID: after.contextID)
        ])
    }

    func testFirstNoteOnEndedEmptyBriefKeepsCompletedLifecycle() async throws {
        let ended = makeEvent(
            id: "ended-first-note",
            start: date(2026, 7, 10, 9)
        )
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) }
        )
        let state = makeState(events: [ended], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(ended.id)
        XCTAssertEqual(state.eventBriefState, .empty)

        state.updateSelectedEventNotes("First note after the event")
        state.flushPendingEventNotes()

        guard case let .loaded(brief) = state.eventBriefState else {
            return XCTFail("Expected saved Event Brief")
        }
        XCTAssertEqual(brief.context.lifecycleStatus, .completed)
        XCTAssertEqual(brief.context.notes, "First note after the event")
    }

    func testInvitationStillAllowsLocalBriefEditing() async throws {
        let invitation = makeEvent(
            id: "invite",
            start: date(2026, 7, 10, 16),
            isReadOnly: true,
            isInvitation: true
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let state = makeState(events: [invitation], store: store)
        await state.loadCalendarStatus()
        state.selectEvent(invitation.id)

        state.addSelectedEventTask(section: .after, title: "Send follow-up")
        state.updateSelectedEventNotes("Local invitation note")
        state.flushPendingEventNotes()

        guard case let .loaded(snapshot) = state.eventBriefState else {
            return XCTFail("Expected local Event Brief")
        }
        XCTAssertEqual(snapshot.context.notes, "Local invitation note")
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Send follow-up"])
    }

    func testTaskCenterListsActiveNotesOnlyBriefForLaterRecovery() async throws {
        let event = makeEvent(
            id: "active-notes-only",
            start: date(2026, 7, 10, 14)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: event,
            notes: "A note without any tasks"
        ))
        let state = makeState(events: [event], store: store)

        await state.loadCalendarStatus()

        XCTAssertEqual(state.recoveryBriefs.map(\.context.id), [context.id])
        XCTAssertEqual(state.recoveryBriefs.first?.link.linkStatus, .active)
        XCTAssertEqual(
            state.recoveryBriefs.first?.context.notes,
            "A note without any tasks"
        )
    }

    func testFirstMissingCanEnterManualAgendaRelinkSelection() async throws {
        let event = makeEvent(
            id: "first-missing-manual",
            start: date(2026, 7, 10, 15)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: event,
            notes: "Choose manually"
        ))
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .notFound
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        await state.openOriginalEvent(contextID: context.id)

        XCTAssertEqual(state.linkedEventRecoverySession?.stage, .firstMissing)

        state.beginSelectingRelinkCandidate()

        XCTAssertNil(state.linkedEventRecoverySession)
        XCTAssertEqual(state.pendingRelinkContextID, context.id)
        XCTAssertEqual(state.selectedSection, .agenda)
        XCTAssertEqual(
            state.focusedDate,
            testCalendar.startOfDay(for: event.startDate)
        )
    }

    func testInconclusiveLookupOffersManualRelinkWithoutMissingEvidence() async throws {
        let event = makeEvent(
            id: "inconclusive-manual",
            start: date(2026, 7, 10, 15)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: event,
            notes: "Do not mark missing"
        ))
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .inconclusive(.recurringOccurrenceUnavailable)
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        await state.openOriginalEvent(contextID: context.id)

        XCTAssertEqual(state.linkedEventRecoverySession?.stage, .manualRelink)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.linkStatus,
            .active
        )
        XCTAssertNotNil(state.localOperationError)
    }

    func testDedicatedNotFoundNeedsExplicitRecheckBeforeOrphanChoice() async throws {
        let event = makeEvent(
            id: "missing-review",
            start: date(2026, 7, 10, 15)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: event,
            notes: "Notes-only recovery Brief"
        ))
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .notFound
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        await state.openOriginalEvent(contextID: context.id)

        XCTAssertEqual(provider.lookupCallCount, 1)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.linkStatus,
            .missing
        )
        XCTAssertEqual(
            state.linkedEventRecoverySession?.stage,
            .firstMissing
        )
        XCTAssertEqual(state.recoveryBriefs.map(\.context.id), [context.id])
        XCTAssertEqual(provider.deleteCallCount, 0)

        await state.refreshCalendarData()
        XCTAssertEqual(provider.lookupCallCount, 1)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.linkStatus,
            .missing
        )

        provider.error = FakeCalendarProviderError.failed
        await state.recheckMissingLinkedEvent()
        XCTAssertEqual(provider.lookupCallCount, 2)
        XCTAssertEqual(
            state.linkedEventRecoverySession?.stage,
            .firstMissing
        )
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.linkStatus,
            .missing
        )

        provider.error = nil
        await state.recheckMissingLinkedEvent()
        XCTAssertEqual(provider.lookupCallCount, 3)
        XCTAssertEqual(
            state.linkedEventRecoverySession?.stage,
            .orphanConfirmation
        )
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.linkStatus,
            .missing
        )

        XCTAssertTrue(state.keepLinkedEventAsOrphan())
        let orphan = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(orphan.link.linkStatus, .orphaned)
        XCTAssertEqual(orphan.context.lifecycleStatus, .orphaned)
        XCTAssertEqual(orphan.context.notes, "Notes-only recovery Brief")
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    func testBackgroundStrongRecoveryDismissesStaleOrphanConfirmation() async throws {
        let event = makeEvent(
            id: "background-strong-recovery",
            start: date(2026, 7, 10, 15)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: event,
            notes: "Keep while the sheet is open"
        ))
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .notFound
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        await state.openOriginalEvent(contextID: context.id)
        await state.recheckMissingLinkedEvent()
        XCTAssertEqual(
            state.linkedEventRecoverySession?.stage,
            .orphanConfirmation
        )

        provider.events = [event]
        await state.refreshCalendarData()

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.linkStatus,
            .active
        )
        XCTAssertNil(state.linkedEventRecoverySession)
        XCTAssertEqual(
            try store.eventContexts.fetch(id: context.id)?.notes,
            "Keep while the sheet is open"
        )
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    func testDeleteRecoverableLocalBriefNeverCallsCalendarDelete() async throws {
        let event = makeEvent(
            id: "local-brief-delete",
            start: date(2026, 7, 10, 15)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let task = try store.appendEventTask(
            for: event,
            section: .after,
            title: "Delete only locally"
        )
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .notFound
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        await state.openOriginalEvent(contextID: task.contextID)
        await state.recheckMissingLinkedEvent()

        XCTAssertTrue(state.deleteRecoverableLocalBrief())

        XCTAssertNil(try store.eventContexts.fetch(id: task.contextID))
        XCTAssertNil(try store.eventTasks.fetch(id: task.id))
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
        XCTAssertEqual(provider.createCallCount, 0)
    }

    func testCandidateRelinkIsExplicitAndPreservesLocalData() async throws {
        let original = makeEvent(
            id: "candidate-original",
            start: date(2026, 7, 10, 15)
        )
        let replacement = makeEvent(
            id: "candidate-replacement",
            start: original.startDate
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Relink notes"
        ))
        let task = try store.appendEventTask(
            for: original,
            section: .during,
            title: "Relink task"
        )
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .candidates([
            CalendarEventLookupMatch(
                event: replacement,
                basis: .exactSnapshot
            )
        ])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        await state.openOriginalEvent(contextID: context.id)

        guard case let .candidates(matches) = state
            .linkedEventRecoverySession?.stage else {
            return XCTFail("Expected explicit candidate review")
        }
        XCTAssertEqual(matches.map(\.event.id), [replacement.id])
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.eventIdentifier,
            original.eventIdentifier
        )

        state.chooseLinkedEventCandidate(replacement)
        provider.lookupResult = .found(CalendarEventLookupMatch(
            event: replacement,
            basis: .externalIdentifierAndOccurrence
        ))
        provider.eventsForInterval = { interval in
            interval.contains(replacement.startDate) ? [replacement] : []
        }
        let didRelink = await state.confirmLinkedEventRelink()
        XCTAssertTrue(didRelink)

        let relinked = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(relinked.link.eventIdentifier, replacement.eventIdentifier)
        XCTAssertEqual(relinked.context.notes, "Relink notes")
        XCTAssertEqual(relinked.tasks.map(\.id), [task.id])
        XCTAssertEqual(
            try store.changeHistory(contextID: context.id).first?.changeType,
            .relinked
        )
        guard case let .loaded(visibleBrief) = state.eventBriefState else {
            return XCTFail("Relink must immediately reload the Event Brief")
        }
        XCTAssertEqual(visibleBrief.context.notes, "Relink notes")
        XCTAssertEqual(visibleBrief.tasks.map(\.id), [task.id])
        XCTAssertEqual(state.selectedEventNotes, "Relink notes")
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
    }

    func testStrongRecheckReactivatesMissingAndFocusesExactEvent() async throws {
        let event = makeEvent(
            id: "strong-recovery",
            start: date(2027, 2, 4, 13)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: event,
            notes: "Strong recovery"
        ))
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .notFound
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        await state.openOriginalEvent(contextID: context.id)

        provider.lookupResult = .found(CalendarEventLookupMatch(
            event: event,
            basis: .externalIdentifierAndOccurrence
        ))
        provider.eventsForInterval = { interval in
            interval.contains(event.startDate) ? [event] : []
        }
        await state.recheckMissingLinkedEvent()

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id)?.link.linkStatus,
            .active
        )
        XCTAssertNil(state.linkedEventRecoverySession)
        XCTAssertEqual(state.selectedSection, .day)
        XCTAssertEqual(state.selectedEventID, event.id)
        XCTAssertNil(state.localOperationError)
    }

    func testFinalRelinkVerificationBlocksStaleCandidate() async throws {
        let original = makeEvent(
            id: "stale-provider-original",
            start: date(2026, 7, 10, 15)
        )
        let candidate = makeEvent(
            id: "stale-provider-candidate",
            start: date(2026, 7, 11, 15)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Keep on failed verification"
        ))
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .candidates([
            CalendarEventLookupMatch(event: candidate, basis: .exactSnapshot)
        ])
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()
        await state.openOriginalEvent(contextID: context.id)
        state.chooseLinkedEventCandidate(candidate)

        provider.lookupResult = .notFound
        let didRelink = await state.confirmLinkedEventRelink()
        XCTAssertFalse(didRelink)

        let after = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after.link, before.link)
        XCTAssertEqual(after.context.notes, "Keep on failed verification")
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)
        XCTAssertNotNil(state.linkedEventRecoverySession)
        XCTAssertEqual(provider.deleteCallCount, 0)
        XCTAssertEqual(provider.updateCallCount, 0)
    }

    func testProviderCancellationAndLaterFoundRecoveryUpdateLifecycle() async throws {
        let event = makeEvent(
            id: "provider-cancelled",
            start: date(2026, 7, 10, 15)
        )
        let store = ContextStore(database: try AppDatabase.inMemory())
        let context = try XCTUnwrap(store.saveNotes(
            for: event,
            notes: "Keep through cancellation"
        ))
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.lookupResult = .cancelled(CalendarEventLookupMatch(
            event: event,
            basis: .externalIdentifierAndOccurrence,
            isCancelled: true
        ))
        provider.eventsForInterval = { interval in
            interval.contains(event.startDate) ? [event] : []
        }
        let state = makeState(provider: provider, store: store)
        await state.loadCalendarStatus()

        await state.openOriginalEvent(contextID: context.id)
        XCTAssertEqual(
            try store.eventContexts.fetch(id: context.id)?.lifecycleStatus,
            .cancelled
        )
        XCTAssertEqual(provider.deleteCallCount, 0)

        provider.lookupResult = .found(CalendarEventLookupMatch(
            event: event,
            basis: .externalIdentifierAndOccurrence
        ))
        await state.openOriginalEvent(contextID: context.id)

        XCTAssertEqual(
            try store.eventContexts.fetch(id: context.id)?.lifecycleStatus,
            .scheduled
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: context.id)?.notes,
            "Keep through cancellation"
        )
        XCTAssertEqual(provider.deleteCallCount, 0)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) -> Date {
        testCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func makeState(
        events: [DisplayEvent],
        store: ContextStore
    ) -> AppState {
        let provider = FakeCalendarProvider(authorizationState: .fullAccess)
        provider.events = events
        return makeState(provider: provider, store: store)
    }

    private func makeState(
        provider: FakeCalendarProvider,
        store: ContextStore
    ) -> AppState {
        AppState(
            calendar: testCalendar,
            now: { self.date(2026, 7, 10, 12) },
            calendarProvider: provider,
            contextStore: store,
            localContextStoreState: .ready
        )
    }

    private func makeEvent(
        id: String,
        start: Date,
        isReadOnly: Bool = false,
        isInvitation: Bool = false
    ) -> DisplayEvent {
        DisplayEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            calendarItemIdentifier: "item-\(id)",
            calendarItemExternalIdentifier: "external-\(id)",
            calendarIdentifier: "calendar",
            calendarTitle: "KAOS-TEST",
            sourceTitle: "Work",
            accountType: .exchange,
            calendarColor: nil,
            title: "Event \(id)",
            location: nil,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: "UTC",
            timeSemantics: .zoned(timeZoneIdentifier: "UTC"),
            isRecurring: false,
            occurrenceDate: nil,
            occurrenceLocalComponents: nil,
            isDetached: false,
            isReadOnly: isReadOnly,
            isInvitation: isInvitation,
            hasAttendees: isInvitation,
            originalNotes: nil
        )
    }
}
