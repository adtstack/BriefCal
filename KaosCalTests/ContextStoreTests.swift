import AppKit
import Foundation
import GRDB
import SwiftUI
import XCTest
@testable import KaosCal

final class ContextStoreTests: XCTestCase {
    func testMigrationIsAppliedAndForeignKeysAreEnabled() throws {
        let database = try AppDatabase.inMemory()

        XCTAssertEqual(
            try database.appliedMigrations(),
            [
                "v1_context_store",
                "v2_event_change_log",
                "v3_calendar_clarity",
                "v4_task_provider",
                "v5_oauth_task_providers",
                "v6_context_references",
                "v7_microsoft_to_do_provider",
                "v8_calendar_usage",
                "v9_saved_calendar_sets",
                "v10_task_provider_recovery",
                "v11_local_task_planning"
            ]
        )
        XCTAssertTrue(try database.foreignKeysEnabled())
    }

    func testTaskPlanningPersistsTimerAndChecklistAndCleansUpWithTask() throws {
        var current = date(2026, 7, 10, 9)
        let database = try AppDatabase.inMemory()
        let store = ContextStore(
            database: database,
            now: { current }
        )
        let task = try store.personalTasks.create(title: "Plan locally")
        let id = TaskCenterItemID.personalTask(taskID: task.id)

        let saved = try store.taskPlanning.save(
            for: id,
            priority: .high,
            isImportant: true,
            repeatFrequency: .weekly,
            repeatInterval: 2,
            estimatedMinutes: 45
        )
        XCTAssertEqual(saved.priority, .high)
        XCTAssertTrue(saved.isImportant)
        XCTAssertEqual(saved.repeatFrequency, .weekly)
        XCTAssertEqual(saved.repeatInterval, 2)
        XCTAssertEqual(saved.estimatedMinutes, 45)

        let checklist = try store.taskPlanning.addChecklistItem(
            to: id,
            title: "  First step  "
        )
        XCTAssertEqual(checklist.title, "First step")
        try store.taskPlanning.setChecklistItemCompleted(
            id: checklist.id,
            isCompleted: true
        )
        _ = try store.taskPlanning.toggleTimer(for: id)
        current = date(2026, 7, 10, 9).addingTimeInterval(95)
        _ = try store.taskPlanning.toggleTimer(for: id)

        let snapshot = try store.taskPlanning.snapshot(for: id)
        XCTAssertEqual(snapshot.0.actualSeconds, 95)
        XCTAssertFalse(snapshot.0.isTimerRunning)
        XCTAssertEqual(snapshot.1.map(\.isCompleted), [true])

        try store.personalTasks.delete(id: task.id)
        XCTAssertEqual(
            try database.read { db in
                try TaskPlanningMetadata.fetchCount(db)
            },
            0
        )
        XCTAssertEqual(
            try database.read { db in
                try TaskChecklistItem.fetchCount(db)
            },
            0
        )
    }

    func testV10MigrationAttachesLegacyDeletePendingToItsEventTask() throws {
        let queue = try DatabaseQueue()
        try DatabaseMigrations.migrator.migrate(
            queue,
            upTo: "v9_saved_calendar_sets"
        )
        let timestamp = "2026-07-17 09:00:00.000"
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO event_contexts (
                        id, title_snapshot, start_snapshot, end_snapshot,
                        lifecycle_status, notes, created_at, updated_at
                    ) VALUES (
                        'context-v10', 'Fixture', ?, ?, 'scheduled', '', ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp, timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_links (
                        id, context_id, event_identifier,
                        calendar_identifier, source_title,
                        calendar_title_snapshot, title_snapshot,
                        start_snapshot, end_snapshot, is_all_day,
                        is_recurring, time_semantics, time_zone_identifier,
                        occurrence_identity_key, is_detached, fingerprint,
                        link_status, last_seen_at, created_at, updated_at
                    ) VALUES (
                        'link-v10', 'context-v10', 'event-v10', 'calendar-v10',
                        'Source', 'Calendar', 'Fixture', ?, ?, 0, 0, 'zoned',
                        'UTC', 'single:v1', 0, 'fingerprint-v10', 'active', ?, ?, ?
                    )
                    """,
                arguments: [
                    timestamp, timestamp, timestamp, timestamp, timestamp
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_tasks (
                        id, context_id, section, title, completed,
                        sort_order, due_kind, created_at, updated_at
                    ) VALUES (
                        'task-v10', 'context-v10', 'before', 'Task',
                        0, 0, 'none', ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO provider_accounts (
                        id, provider, account_key, display_name,
                        authorization_state, created_at, updated_at
                    ) VALUES (
                        'account-v10', 'apple_reminders', 'icloud', 'iCloud',
                        'authorized', ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO provider_items (
                        id, account_id, entity_type, remote_id,
                        remote_parent_id, remote_version, cached_title,
                        cached_notes, cached_completed, last_seen_at,
                        created_at, updated_at
                    ) VALUES (
                        'item-v10', 'account-v10', 'task', 'remote-v10',
                        'list-v10', 'etag-v10', 'Task', '', 0, ?, ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO task_bindings (
                        id, provider_item_id, event_task_id, sync_state,
                        last_synced_hash, remote_version, created_at, updated_at
                    ) VALUES (
                        'binding-v10', 'item-v10', 'task-v10', 'linked',
                        'legacy-hash', 'etag-v10', ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO provider_pending_operations (
                        id, account_id, operation, remote_id,
                        remote_parent_id, expected_version, attempt_count,
                        last_error, created_at, updated_at
                    ) VALUES (
                        'pending-v10', 'account-v10', 'delete', 'remote-v10',
                        'list-v10', 'etag-v10', 7, 'Offline', ?, ?
                    )
                    """,
                arguments: [timestamp, timestamp]
            )
        }

        let database = try AppDatabase(queue)
        let recovered = try database.read { db in
            try ProviderPendingOperationRecord.fetchOne(
                db,
                key: "pending-v10"
            )
        }
        XCTAssertEqual(recovered?.eventTaskID, "task-v10")
        XCTAssertEqual(recovered?.operation, .delete)
        XCTAssertEqual(recovered?.attemptCount, 3)
        XCTAssertEqual(recovered?.lastError, "Offline")
        XCTAssertEqual(
            try database.read { db in
                try TaskProviderPreferenceRecord.fetchCount(db)
            },
            0
        )
    }

    func testOAuthProvidersCanUseTheSameExternalAccountKey() throws {
        let database = try AppDatabase.inMemory()
        let repository = TaskProviderRepository(
            database: database,
            now: { self.date(2026, 7, 14, 9) },
            makeID: { UUID().uuidString }
        )

        let google = try repository.upsertAccount(
            provider: .googleTasks,
            accountKey: "shared-subject",
            displayName: "Google account",
            authorizationState: .authorized
        )
        let todoist = try repository.upsertAccount(
            provider: .todoist,
            accountKey: "shared-subject",
            displayName: "Todoist account",
            authorizationState: .authorized
        )
        let microsoft = try repository.upsertAccount(
            provider: .microsoftToDo,
            accountKey: "shared-subject",
            displayName: "Microsoft account",
            authorizationState: .authorized
        )

        XCTAssertNotEqual(google.id, todoist.id)
        XCTAssertNotEqual(todoist.id, microsoft.id)
        XCTAssertEqual(
            try repository.fetchAccounts().map {
                "\($0.provider.rawValue):\($0.accountKey)"
            }.sorted(),
            [
                "google_tasks:shared-subject",
                "microsoft_to_do:shared-subject",
                "todoist:shared-subject"
            ]
        )
    }

    func testMicrosoftToDoCacheUpsertsAndRemovesUnboundTasks() throws {
        let database = try AppDatabase.inMemory()
        let repository = TaskProviderRepository(
            database: database,
            now: { self.date(2026, 7, 15, 9) },
            makeID: { UUID().uuidString }
        )
        let account = try repository.upsertAccount(
            provider: .microsoftToDo,
            accountKey: "tenant:object",
            displayName: "Microsoft User",
            authorizationState: .authorized
        )
        let remote = RemoteTaskSnapshot(
            id: "remote-task",
            parentID: "tasks-list",
            title: "Draft release notes",
            notes: "Remote-only task",
            dueAt: date(2026, 7, 17, 9),
            isCompleted: false,
            version: "etag-1",
            deepLink: nil
        )

        let first = try repository.upsertProviderItem(
            accountID: account.id,
            remote: remote
        )
        let updated = RemoteTaskSnapshot(
            id: remote.id,
            parentID: remote.parentID,
            title: "Publish release notes",
            notes: remote.notes,
            dueAt: date(2026, 7, 18, 9),
            isCompleted: true,
            version: "etag-2",
            deepLink: nil
        )
        let second = try repository.upsertProviderItem(
            accountID: account.id,
            remote: updated
        )

        XCTAssertEqual(first.id, second.id)
        let cached = try repository.fetchProviderItems(provider: .microsoftToDo)
        XCTAssertEqual(cached.count, 1)
        let cachedItem = try XCTUnwrap(cached.first)
        XCTAssertEqual(cachedItem.remoteID, "remote-task")
        XCTAssertEqual(cachedItem.cachedTitle, "Publish release notes")
        XCTAssertEqual(cachedItem.cachedDueAt, date(2026, 7, 18, 9))
        XCTAssertTrue(cachedItem.cachedCompleted)

        try repository.deleteUnboundProviderItem(
            accountID: account.id,
            remoteID: remote.id
        )
        XCTAssertTrue(
            try repository.fetchProviderItems(provider: .microsoftToDo).isEmpty
        )
    }

    func testLinkingMicrosoftTaskReusesExistingCachedItem() throws {
        let harness = try makeHarness()
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "microsoft-cache-link"),
                notes: "Microsoft task fixture"
            )
        )
        let eventTask = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: "Prepare briefing",
            sortOrder: 0
        )
        let repository = harness.store.taskProviders
        let account = try repository.upsertAccount(
            provider: .microsoftToDo,
            accountKey: "tenant:object",
            displayName: "Microsoft User",
            authorizationState: .authorized
        )
        let remote = RemoteTaskSnapshot(
            id: "remote-task",
            parentID: "tasks-list",
            title: "Prepare briefing",
            notes: "",
            dueAt: nil,
            isCompleted: false,
            version: "etag-1",
            deepLink: nil
        )
        let cached = try repository.upsertProviderItem(
            accountID: account.id,
            remote: remote
        )

        let binding = try repository.insertLinkedTask(
            account: account,
            remote: remote,
            eventTaskID: eventTask.id,
            occurrenceKey: nil,
            syncHash: "sync-hash"
        )

        XCTAssertEqual(binding.eventTaskID, eventTask.id)
        XCTAssertEqual(binding.providerItemID, cached.id)
        XCTAssertEqual(
            try repository.fetchProviderItems(provider: .microsoftToDo)
                .map(\.id),
            [cached.id]
        )
    }

    @MainActor
    func testCoordinatorProjectsAppleRemindersForTheTaskSidebar() async throws {
        let harness = try makeHarness()
        let provider = StubAppleTaskListingProvider(
            lists: [
                RemoteTaskList(
                    provider: .appleReminders,
                    id: "reminders-list",
                    accountKey: "icloud-account",
                    title: "Personal",
                    sourceTitle: "iCloud",
                    isWritable: true
                ),
                RemoteTaskList(
                    provider: .appleReminders,
                    id: "reminders-list",
                    accountKey: "exchange-account",
                    title: "Work",
                    sourceTitle: "Exchange",
                    isWritable: true
                )
            ],
            tasks: [
                RemoteTaskSnapshot(
                    id: "reminder-1",
                    parentID: "reminders-list",
                    parentAccountKey: "icloud-account",
                    title: "Buy milk",
                    notes: "Stays in Reminders",
                    dueAt: date(2026, 7, 16, 18),
                    isCompleted: false,
                    version: "1",
                    deepLink: nil
                ),
                RemoteTaskSnapshot(
                    id: "reminder-1",
                    parentID: "reminders-list",
                    parentAccountKey: "exchange-account",
                    title: "Review notes",
                    notes: "Same provider and raw IDs",
                    dueAt: nil,
                    isCompleted: false,
                    version: "1",
                    deepLink: nil
                )
            ]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )

        for _ in 0..<20 {
            if case .loaded = coordinator.appleRemindersTaskState { break }
            await Task.yield()
        }

        guard case let .loaded(items) = coordinator.appleRemindersTaskState else {
            return XCTFail("Expected Apple Reminders to finish loading")
        }
        XCTAssertEqual(items.map(\.title), ["Buy milk", "Review notes"])
        XCTAssertEqual(items.map(\.accountKey), ["icloud-account", "exchange-account"])
        XCTAssertEqual(items.first?.details, "Stays in Reminders")
        XCTAssertEqual(items.map(\.remoteTaskID), ["reminder-1", "reminder-1"])
        XCTAssertEqual(items.map(\.remoteVersion), ["1", "1"])
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        XCTAssertEqual(
            items.first?.id,
            TaskProviderCoordinator.sidebarTaskItemID(
                provider: .appleReminders,
                accountKey: "icloud-account",
                listID: "reminders-list",
                taskID: "reminder-1"
            )
        )

        provider.listTaskListsError = .providerFailure("Temporary list error")
        coordinator.refresh()
        for _ in 0..<20 {
            if !coordinator.isRefreshingOAuthTaskLists { break }
            await Task.yield()
        }
        XCTAssertEqual(coordinator.taskLists.count, 2)
        XCTAssertTrue(
            coordinator.taskListRefreshFailures.contains(.appleReminders)
        )

        provider.listTaskListsError = nil
        coordinator.refresh()
        for _ in 0..<20 {
            if case .loaded = coordinator.appleRemindersTaskState,
               !coordinator.isRefreshingOAuthTaskLists {
                break
            }
            await Task.yield()
        }
        XCTAssertFalse(
            coordinator.taskListRefreshFailures.contains(.appleReminders)
        )
    }

    @MainActor
    func testCoordinatorConnectsAppleRemindersFromTaskSidebarAccessRequest() async throws {
        let harness = try makeHarness()
        let provider = StubAppleTaskListingProvider(
            lists: [
                RemoteTaskList(
                    provider: .appleReminders,
                    id: "connected-list",
                    accountKey: "icloud-account",
                    title: "Reminders",
                    sourceTitle: "iCloud",
                    isWritable: true
                )
            ],
            tasks: [
                RemoteTaskSnapshot(
                    id: "connected-reminder",
                    parentID: "connected-list",
                    title: "Visible after access",
                    notes: "",
                    dueAt: nil,
                    isCompleted: false,
                    version: "1",
                    deepLink: nil
                )
            ],
            authorizationState: .notDetermined
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )

        XCTAssertEqual(
            coordinator.authorizationState(for: .appleReminders),
            .notDetermined
        )
        XCTAssertEqual(coordinator.appleRemindersTaskState, .unavailable)

        await coordinator.requestAccess()
        for _ in 0..<20 {
            if case .loaded = coordinator.appleRemindersTaskState { break }
            await Task.yield()
        }

        XCTAssertEqual(provider.requestAccessCount, 1)
        XCTAssertEqual(
            coordinator.authorizationState(for: .appleReminders),
            .authorized
        )
        guard case let .loaded(items) = coordinator.appleRemindersTaskState else {
            return XCTFail("Expected Reminders to load after access was granted")
        }
        XCTAssertEqual(items.map(\.title), ["Visible after access"])
    }

    @MainActor
    func testCoordinatorRefreshesRemindersAuthorizationWhenAppBecomesActive() async throws {
        let harness = try makeHarness()
        let notificationCenter = NotificationCenter()
        let provider = StubAppleTaskListingProvider(
            lists: [],
            tasks: [],
            authorizationState: .denied
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore(),
            notificationCenter: notificationCenter
        )
        let refreshCountBeforeActivation = provider.refreshAuthorizationStateCount

        provider.authorizationState = .authorized
        notificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        for _ in 0..<20 {
            if coordinator.authorizationState(for: .appleReminders) == .authorized {
                break
            }
            await Task.yield()
        }

        XCTAssertGreaterThan(
            provider.refreshAuthorizationStateCount,
            refreshCountBeforeActivation
        )
        XCTAssertEqual(
            coordinator.authorizationState(for: .appleReminders),
            .authorized
        )
    }

    func testProviderTaskSidebarSortsByDueDateOrTitleAndKeepsCompletedLast() {
        func item(
            _ id: String,
            title: String,
            dueAt: Date?,
            isCompleted: Bool = false
        ) -> ProviderTaskListItem {
            ProviderTaskListItem(
                id: id,
                provider: .appleReminders,
                accountKey: "icloud",
                listID: "work",
                title: title,
                details: "Detail for \(title)",
                dueAt: dueAt,
                isCompleted: isCompleted,
                listTitle: "Work",
                accountTitle: "iCloud"
            )
        }

        let items = [
            item("undated", title: "Beta", dueAt: nil),
            item("later", title: "Zulu", dueAt: date(2026, 7, 10, 9)),
            item("earlier", title: "Alpha", dueAt: date(2026, 7, 9, 9)),
            item(
                "completed",
                title: "Aardvark",
                dueAt: date(2026, 7, 8, 9),
                isCompleted: true
            )
        ]

        XCTAssertEqual(
            items.sorted {
                ProviderTaskSidebarOrdering.precedes(
                    $0,
                    $1,
                    by: .dueDate
                )
            }.map(\.id),
            ["earlier", "later", "undated", "completed"]
        )
        XCTAssertEqual(
            items.sorted {
                ProviderTaskSidebarOrdering.precedes($0, $1, by: .title)
            }.map(\.id),
            ["earlier", "undated", "later", "completed"]
        )
    }

    func testProviderTaskSidebarFiltersByStableProviderListStatusAndSearch() {
        let appleList = ProviderTaskSidebarListIdentity(
            provider: .appleReminders,
            accountKey: "icloud",
            listID: "shared-list-id"
        )
        let microsoftList = ProviderTaskSidebarListIdentity(
            provider: .microsoftToDo,
            accountKey: "tenant:object",
            listID: "shared-list-id"
        )
        let emptyList = ProviderTaskSidebarListIdentity(
            provider: .appleReminders,
            accountKey: "icloud",
            listID: "empty-list"
        )
        let lists = [
            RemoteTaskList(
                provider: .appleReminders,
                id: appleList.listID,
                accountKey: appleList.accountKey,
                title: "Work",
                sourceTitle: "iCloud",
                isWritable: true
            ),
            RemoteTaskList(
                provider: .microsoftToDo,
                id: microsoftList.listID,
                accountKey: microsoftList.accountKey,
                title: "Work",
                sourceTitle: "Contoso",
                isWritable: true
            ),
            RemoteTaskList(
                provider: .appleReminders,
                id: emptyList.listID,
                accountKey: emptyList.accountKey,
                title: "Empty",
                sourceTitle: "iCloud",
                isWritable: true
            ),
            RemoteTaskList(
                provider: .googleTasks,
                id: "not-in-sidebar",
                accountKey: "google",
                title: "Excluded",
                sourceTitle: "Google",
                isWritable: true
            )
        ]
        func item(
            id: String,
            list: ProviderTaskSidebarListIdentity,
            title: String,
            details: String?,
            completed: Bool
        ) -> ProviderTaskListItem {
            ProviderTaskListItem(
                id: id,
                provider: list.provider,
                accountKey: list.accountKey,
                listID: list.listID,
                title: title,
                details: details,
                dueAt: nil,
                isCompleted: completed,
                listTitle: "Work",
                accountTitle: list.provider == .appleReminders
                    ? "iCloud"
                    : "Contoso"
            )
        }
        let items = [
            item(
                id: "apple-open",
                list: appleList,
                title: "Budget review",
                details: "Q3 forecast",
                completed: false
            ),
            item(
                id: "apple-completed",
                list: appleList,
                title: "Archive receipts",
                details: nil,
                completed: true
            ),
            item(
                id: "microsoft-open",
                list: microsoftList,
                title: "Prepare launch",
                details: "Release checklist",
                completed: false
            )
        ]

        let options = ProviderTaskSidebarFiltering.listOptions(from: lists)
        XCTAssertEqual(options.count, 4)
        XCTAssertTrue(options.contains { $0.identity == emptyList })
        XCTAssertTrue(options.contains { $0.provider == .googleTasks })
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.items(
                items,
                list: appleList,
                status: .open,
                query: ""
            ).map(\.id),
            ["apple-open"]
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.items(
                items,
                list: appleList,
                status: .completed,
                query: ""
            ).map(\.id),
            ["apple-completed"]
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.items(
                items,
                list: nil,
                status: .all,
                query: "forecast"
            ).map(\.id),
            ["apple-open"]
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.items(
                items,
                list: microsoftList,
                status: .open,
                query: ""
            ).map(\.id),
            ["microsoft-open"]
        )
        XCTAssertTrue(
            ProviderTaskSidebarFiltering.items(
                items,
                list: emptyList,
                status: .all,
                query: ""
            ).isEmpty
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.normalizedSelection(
                microsoftList,
                available: options,
                isLoading: false
            ),
            microsoftList
        )
        let fallbackOptions = ProviderTaskSidebarFiltering.listOptions(
            from: [],
            fallbackItems: items
        )
        XCTAssertEqual(Set(fallbackOptions.map(\.identity)), [appleList, microsoftList])
        let authoritativeAppleOnly = ProviderTaskSidebarFiltering.listOptions(
            from: lists.filter { $0.provider == .appleReminders },
            fallbackItems: items,
            fallbackProviders: [.appleReminders]
        )
        XCTAssertFalse(
            authoritativeAppleOnly.contains { $0.identity == microsoftList }
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.availableItems(
                items,
                lists: lists.filter { $0.provider == .appleReminders },
                fallbackProviders: [.appleReminders]
            ).map(\.id),
            ["apple-open", "apple-completed"]
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.availableItems(
                items,
                lists: lists.filter { $0.provider == .appleReminders },
                fallbackProviders: [.appleReminders, .microsoftToDo]
            ).map(\.id),
            ["apple-open", "apple-completed", "microsoft-open"]
        )

        let renamedLists = lists.map { list in
            guard list.provider == microsoftList.provider,
                  list.accountKey == microsoftList.accountKey,
                  list.id == microsoftList.listID else {
                return list
            }
            return RemoteTaskList(
                provider: list.provider,
                id: list.id,
                accountKey: list.accountKey,
                title: "Renamed Work",
                sourceTitle: list.sourceTitle,
                isWritable: list.isWritable
            )
        }
        let renamedOptions = ProviderTaskSidebarFiltering.listOptions(
            from: renamedLists,
            fallbackItems: items
        )
        XCTAssertEqual(
            renamedOptions.first { $0.identity == microsoftList }?.listTitle,
            "Renamed Work"
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.normalizedSelection(
                microsoftList,
                available: renamedOptions,
                isLoading: false
            ),
            microsoftList
        )
        XCTAssertEqual(
            ProviderTaskSidebarListIdentity(
                storageValue: microsoftList.storageValue
            ),
            microsoftList
        )
        XCTAssertEqual(
            ProviderTaskSidebarFiltering.normalizedSelection(
                microsoftList,
                available: [],
                isLoading: true
            ),
            microsoftList
        )
        XCTAssertNil(
            ProviderTaskSidebarFiltering.normalizedSelection(
                microsoftList,
                available: [],
                isLoading: false
            )
        )
    }

    @MainActor
    func testProviderTaskSidebarGroupedDetailsFitsAndProducesOffscreenBitmap() async throws {
        let harness = try makeHarness()
        let lists = [
            RemoteTaskList(
                provider: .appleReminders,
                id: "family-list",
                accountKey: "icloud",
                title: "Family",
                sourceTitle: "iCloud",
                isWritable: true
            ),
            RemoteTaskList(
                provider: .appleReminders,
                id: "shopping-list",
                accountKey: "icloud",
                title: "Shopping",
                sourceTitle: "iCloud",
                isWritable: true
            ),
            RemoteTaskList(
                provider: .appleReminders,
                id: "work-list",
                accountKey: "exchange",
                title: "Work",
                sourceTitle: "Exchange",
                isWritable: true
            )
        ]
        let tasks = [
            RemoteTaskSnapshot(
                id: "family-1",
                parentID: "family-list",
                title: "Book the weekend appointment",
                notes: "Confirm the available morning time with everyone.",
                dueAt: date(2026, 7, 16, 9),
                isCompleted: false,
                version: "1",
                deepLink: nil
            ),
            RemoteTaskSnapshot(
                id: "family-2",
                parentID: "family-list",
                title: "Share the travel plan",
                notes: "",
                dueAt: nil,
                isCompleted: false,
                version: "1",
                deepLink: nil
            ),
            RemoteTaskSnapshot(
                id: "shopping-1",
                parentID: "shopping-list",
                title: "Coffee beans",
                notes: "Medium roast, whole bean",
                dueAt: date(2026, 7, 17, 9),
                isCompleted: false,
                version: "1",
                deepLink: nil
            ),
            RemoteTaskSnapshot(
                id: "work-1",
                parentID: "work-list",
                title: "Review release notes",
                notes: "Check migration and accessibility sections before publishing.",
                dueAt: date(2026, 7, 18, 9),
                isCompleted: false,
                version: "1",
                deepLink: nil
            )
        ]
        let provider = StubAppleTaskListingProvider(lists: lists, tasks: tasks)
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        for _ in 0..<20 {
            if case .loaded = coordinator.appleRemindersTaskState { break }
            await Task.yield()
        }
        guard case .loaded = coordinator.appleRemindersTaskState else {
            return XCTFail("Expected Reminders fixture to finish loading")
        }

        var calendar = testCalendar
        calendar.locale = Locale(identifier: "en_US")
        let calendarProvider = FakeCalendarProvider(
            authorizationState: .fullAccess
        )
        let state = AppState(
            calendar: calendar,
            now: { self.date(2026, 7, 16, 8) },
            calendarProvider: calendarProvider,
            contextStore: harness.store,
            taskProviderCoordinator: coordinator,
            localContextStoreState: .ready
        )
        let preferenceSuiteName = "KaosCalTests.TasksSidebar.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(
            UserDefaults(suiteName: preferenceSuiteName)
        )
        defer {
            preferences.removePersistentDomain(forName: preferenceSuiteName)
        }
        func render(
            width: CGFloat,
            height: CGFloat,
            name: String
        ) async throws {
            let hostingView = NSHostingView(rootView:
                ProviderTaskSidebarView(
                    appState: state,
                    coordinator: coordinator,
                    preferences: preferences
                )
                .frame(width: width, height: height)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light)
            )
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
            hostingView.wantsLayer = true
            let window = NSWindow(
                contentRect: hostingView.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: .aqua)
            window.backgroundColor = .windowBackgroundColor
            window.contentView = hostingView
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()

            let representation = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
            let pngData = try XCTUnwrap(
                representation.representation(using: .png, properties: [:])
            )
            XCTAssertGreaterThanOrEqual(
                representation.pixelsWide,
                Int(width)
            )
            XCTAssertGreaterThanOrEqual(
                representation.pixelsHigh,
                Int(height)
            )
            XCTAssertGreaterThan(pngData.count, 8_000)
            let attachment = XCTAttachment(
                data: pngData,
                uniformTypeIdentifier: "public.png"
            )
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if width == 360,
               let snapshotPath = ProcessInfo.processInfo.environment[
                "KAOSCAL_TASKS_SIDEBAR_SNAPSHOT_PATH"
               ] {
                try pngData.write(to: URL(fileURLWithPath: snapshotPath))
            }
        }

        try await render(
            width: 360,
            height: 700,
            name: "KaosCal Tasks Sidebar 360"
        )
        try await render(
            width: 300,
            height: 600,
            name: "KaosCal Tasks Sidebar 300"
        )
    }

    @MainActor
    func testProviderTaskEditorCreateSheetFitsAndProducesOffscreenBitmap() throws {
        let harness = try makeHarness()
        let lists = [
            RemoteTaskList(
                provider: .appleReminders,
                id: "icloud-work",
                accountKey: "icloud-account",
                title: "Work",
                sourceTitle: "iCloud",
                isWritable: true
            ),
            RemoteTaskList(
                provider: .appleReminders,
                id: "local-work",
                accountKey: "local-account",
                title: "Work",
                sourceTitle: "On My Mac",
                isWritable: true
            )
        ]
        let provider = StubAppleTaskListingProvider(lists: lists, tasks: [])
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let width: CGFloat = 560
        let height: CGFloat = 620
        let hostingView = NSHostingView(rootView:
            ProviderTaskEditorSheet(
                coordinator: coordinator,
                mode: .create(preferredList: nil),
                writableLists: lists
            )
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
        hostingView.wantsLayer = true
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
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
        XCTAssertGreaterThanOrEqual(representation.pixelsWide, Int(width))
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, Int(height))
        XCTAssertGreaterThan(pngData.count, 8_000)
        let attachment = XCTAttachment(
            data: pngData,
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = "KaosCal Tasks Create Sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testProviderTaskEditorDrawerFitsNarrowSidebarAndProducesOffscreenBitmap() throws {
        let harness = try makeHarness()
        let lists = [
            RemoteTaskList(
                provider: .appleReminders,
                id: "icloud-work",
                accountKey: "icloud-account",
                title: "Work",
                sourceTitle: "iCloud",
                isWritable: true
            )
        ]
        let provider = StubAppleTaskListingProvider(lists: lists, tasks: [])
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let width: CGFloat = 340
        let height: CGFloat = 360
        let hostingView = NSHostingView(rootView:
            ProviderTaskEditorSheet(
                coordinator: coordinator,
                mode: .create(preferredList: lists[0]),
                writableLists: lists,
                presentationStyle: .drawer
            )
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
        hostingView.wantsLayer = true
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
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
        XCTAssertGreaterThanOrEqual(representation.pixelsWide, Int(width))
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, Int(height))
        XCTAssertGreaterThan(pngData.count, 5_000)
        if let snapshotPath = ProcessInfo.processInfo.environment[
            "KAOSCAL_TASK_DRAWER_SNAPSHOT_PATH"
        ] {
            try pngData.write(to: URL(fileURLWithPath: snapshotPath))
        }
        let attachment = XCTAttachment(
            data: pngData,
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = "KaosCal Tasks Bottom Drawer 340"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMicrosoftToDoSidebarQueryHidesMissingBoundTaskButKeepsRecoveryCache() throws {
        let harness = try makeHarness()
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "microsoft-missing-link"),
                notes: "Microsoft task fixture"
            )
        )
        let eventTask = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .after,
            title: "Follow up",
            sortOrder: 0
        )
        let repository = harness.store.taskProviders
        let account = try repository.upsertAccount(
            provider: .microsoftToDo,
            accountKey: "tenant:object",
            displayName: "Microsoft User",
            authorizationState: .authorized
        )
        let remote = RemoteTaskSnapshot(
            id: "remote-task",
            parentID: "tasks-list",
            title: "Follow up",
            notes: "",
            dueAt: nil,
            isCompleted: false,
            version: "etag-1",
            deepLink: nil
        )
        let binding = try repository.insertLinkedTask(
            account: account,
            remote: remote,
            eventTaskID: eventTask.id,
            occurrenceKey: nil,
            syncHash: "sync-hash"
        )
        let cachedID = try XCTUnwrap(
            repository.fetchProviderItem(
                accountID: account.id,
                remoteID: remote.id
            )?.id
        )

        try repository.markBinding(bindingID: binding.id, state: .missing)

        XCTAssertTrue(
            try repository.fetchProviderItems(provider: .microsoftToDo).isEmpty
        )
        XCTAssertNotNil(try repository.fetchProviderItem(id: cachedID))
    }

    @MainActor
    func testAppleSidebarTaskCreateCompleteEditAndDeleteUseExactRemoteIdentity() async throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "personal-list",
            accountKey: "icloud-account",
            title: "Personal",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let original = RemoteTaskSnapshot(
            id: "remote-reminder",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: "Original",
            notes: "Full remote notes",
            dueAt: date(2026, 7, 21, 9),
            isCompleted: false,
            version: "v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [original]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let item = ProviderTaskListItem(
            id: TaskProviderCoordinator.sidebarTaskItemID(
                provider: .appleReminders,
                accountKey: list.accountKey,
                listID: list.id,
                taskID: original.id
            ),
            remoteTaskID: original.id,
            remoteVersion: original.version,
            provider: .appleReminders,
            accountKey: list.accountKey,
            listID: list.id,
            title: original.title,
            details: original.notes,
            dueAt: original.dueAt,
            isCompleted: false,
            listTitle: list.title,
            accountTitle: list.sourceTitle
        )

        let completed = try await coordinator.setSidebarTaskCompleted(
            item,
            isCompleted: true
        )
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(provider.updateTaskCount, 1)

        let completedItem = ProviderTaskListItem(
            id: item.id,
            remoteTaskID: completed.id,
            remoteVersion: completed.version,
            provider: item.provider,
            accountKey: item.accountKey,
            listID: item.listID,
            title: completed.title,
            details: completed.notes,
            dueAt: completed.dueAt,
            isCompleted: completed.isCompleted,
            listTitle: item.listTitle,
            accountTitle: item.accountTitle
        )
        let baseline = try await coordinator.loadSidebarTask(completedItem)
        let updated = try await coordinator.updateSidebarTask(
            completedItem,
            baseline: baseline,
            title: "  Renamed reminder  ",
            notes: "Edited without SQLite persistence",
            dueAt: nil,
            isCompleted: false
        )
        XCTAssertEqual(updated.title, "Renamed reminder")
        XCTAssertEqual(updated.notes, "Edited without SQLite persistence")
        XCTAssertNil(updated.dueAt)
        XCTAssertFalse(updated.isCompleted)
        XCTAssertEqual(provider.updateTaskCount, 2)

        let created = try await coordinator.createSidebarTask(
            in: list,
            title: "  New reminder  ",
            notes: "Provider-owned notes",
            dueAt: date(2026, 7, 22, 15)
        )
        XCTAssertEqual(created.title, "New reminder")
        XCTAssertEqual(created.parentAccountKey, list.accountKey)
        XCTAssertEqual(provider.createTaskCount, 1)

        let updatedItem = ProviderTaskListItem(
            id: item.id,
            remoteTaskID: updated.id,
            remoteVersion: updated.version,
            provider: item.provider,
            accountKey: item.accountKey,
            listID: item.listID,
            title: updated.title,
            details: updated.notes,
            dueAt: updated.dueAt,
            isCompleted: updated.isCompleted,
            listTitle: item.listTitle,
            accountTitle: item.accountTitle
        )
        try await coordinator.deleteSidebarTask(
            updatedItem,
            baseline: updated
        )
        XCTAssertNil(
            provider.snapshots.first { $0.id == original.id }
        )
        XCTAssertEqual(provider.deleteTaskCount, 1)
    }

    @MainActor
    func testAppleSidebarTaskRejectsConflictAmbiguousAccountAndStaleListMetadata() async throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "shared-list-id",
            accountKey: "icloud-account",
            title: "Work",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "shared-task-id",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: "Remote",
            notes: "",
            dueAt: nil,
            isCompleted: false,
            version: "v2",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        func item(accountKey: String, version: String?) -> ProviderTaskListItem {
            ProviderTaskListItem(
                id: TaskProviderCoordinator.sidebarTaskItemID(
                    provider: .appleReminders,
                    accountKey: accountKey,
                    listID: list.id,
                    taskID: remote.id
                ),
                remoteTaskID: remote.id,
                remoteVersion: version,
                provider: .appleReminders,
                accountKey: accountKey,
                listID: list.id,
                title: remote.title,
                details: nil,
                dueAt: nil,
                isCompleted: false,
                listTitle: list.title,
                accountTitle: list.sourceTitle
            )
        }

        do {
            _ = try await coordinator.setSidebarTaskCompleted(
                item(accountKey: list.accountKey, version: "v1"),
                isCompleted: true
            )
            XCTFail("Expected a stale projection conflict")
        } catch {
            XCTAssertEqual(error as? TaskProviderError, .conflict)
        }
        XCTAssertEqual(provider.updateTaskCount, 0)

        do {
            _ = try await coordinator.loadSidebarTask(
                item(accountKey: "other-account", version: remote.version)
            )
            XCTFail("Expected exact account validation")
        } catch {
            XCTAssertEqual(error as? TaskProviderError, .taskNotFound)
        }

        provider.listTaskListsError = .providerFailure("Temporary metadata failure")
        coordinator.refresh()
        XCTAssertFalse(
            coordinator.isSidebarTaskWritable(
                item(accountKey: list.accountKey, version: remote.version)
            )
        )
        do {
            _ = try await coordinator.setSidebarTaskCompleted(
                item(accountKey: list.accountKey, version: remote.version),
                isCompleted: true
            )
            XCTFail("Expected writes to stop while list metadata is stale")
        } catch {
            guard let providerError = error as? TaskProviderError,
                  case .providerFailure = providerError else {
                return XCTFail("Expected provider failure, got \(error)")
            }
        }
        XCTAssertEqual(provider.updateTaskCount, 0)
    }

    @MainActor
    func testAppleSidebarTaskKeepsReadOnlyAuthorizationAndExternalDeletionNonMutating() async throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "shared-read-only-list",
            accountKey: "shared-account",
            title: "Shared",
            sourceTitle: "Shared Account",
            isWritable: false
        )
        let remote = RemoteTaskSnapshot(
            id: "shared-reminder",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: "Read-only reminder",
            notes: "Still available for detail lookup",
            dueAt: nil,
            isCompleted: false,
            version: "shared-v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let item = ProviderTaskListItem(
            id: TaskProviderCoordinator.sidebarTaskItemID(
                provider: .appleReminders,
                accountKey: list.accountKey,
                listID: list.id,
                taskID: remote.id
            ),
            remoteTaskID: remote.id,
            remoteVersion: remote.version,
            provider: .appleReminders,
            accountKey: list.accountKey,
            listID: list.id,
            title: remote.title,
            details: remote.notes,
            dueAt: remote.dueAt,
            isCompleted: remote.isCompleted,
            listTitle: list.title,
            accountTitle: list.sourceTitle
        )

        let loaded = try await coordinator.loadSidebarTask(item)
        XCTAssertEqual(loaded, remote)
        XCTAssertFalse(coordinator.isSidebarTaskWritable(item))
        do {
            _ = try await coordinator.setSidebarTaskCompleted(
                item,
                isCompleted: true
            )
            XCTFail("Expected the read-only list to reject mutations")
        } catch {
            XCTAssertEqual(error as? TaskProviderError, .listUnavailable)
        }
        XCTAssertEqual(provider.updateTaskCount, 0)

        provider.removeSnapshot(id: remote.id, parentID: remote.parentID)
        do {
            _ = try await coordinator.loadSidebarTask(item)
            XCTFail("Expected an externally deleted task to be missing")
        } catch {
            XCTAssertEqual(error as? TaskProviderError, .taskNotFound)
        }

        provider.replaceSnapshot(remote)
        provider.authorizationState = .denied
        coordinator.refresh()
        do {
            _ = try await coordinator.loadSidebarTask(item)
            XCTFail("Expected revoked Reminders access to block lookup")
        } catch {
            XCTAssertEqual(error as? TaskProviderError, .accessDenied)
        }
        XCTAssertEqual(provider.updateTaskCount, 0)
    }

    @MainActor
    func testAsyncProviderSidebarListsAndMutatesThroughCommonCommands() async throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .googleTasks,
            id: "google-list",
            accountKey: "google-account",
            title: "Work",
            sourceTitle: "Google User",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "google-task",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: "Plan launch",
            notes: "Draft",
            dueAt: date(2026, 7, 12, 9),
            isCompleted: false,
            version: "v1",
            deepLink: nil
        )
        let google = StubAsyncTaskProvider(
            provider: .googleTasks,
            lists: [list],
            tasks: [remote]
        )
        let apple = StubAppleTaskListingProvider(
            lists: [],
            tasks: [],
            authorizationState: .denied
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: apple,
            oauthCredentials: InMemoryOAuthCredentialStore(),
            asyncProviders: [.googleTasks: google]
        )

        for _ in 0..<50 {
            if case .loaded = coordinator.googleTasksTaskState { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case let .loaded(items) = coordinator.googleTasksTaskState,
              let item = items.first else {
            return XCTFail("Expected Google Tasks sidebar projection")
        }
        XCTAssertEqual(item.remoteTaskID, remote.id)
        XCTAssertTrue(coordinator.isSidebarTaskWritable(item))
        let loaded = try await coordinator.loadSidebarTask(item)
        XCTAssertEqual(loaded, remote)

        let completed = try await coordinator.setSidebarTaskCompleted(
            item,
            isCompleted: true
        )
        XCTAssertTrue(completed.isCompleted)
        let completedItem = ProviderTaskListItem(
            id: item.id,
            remoteTaskID: completed.id,
            remoteVersion: completed.version,
            provider: item.provider,
            accountKey: item.accountKey,
            listID: item.listID,
            title: completed.title,
            details: completed.notes,
            dueAt: completed.dueAt,
            isCompleted: completed.isCompleted,
            listTitle: item.listTitle,
            accountTitle: item.accountTitle
        )
        let updated = try await coordinator.updateSidebarTask(
            completedItem,
            baseline: completed,
            title: "Plan launch final",
            notes: "Ready",
            dueAt: nil,
            isCompleted: true
        )
        XCTAssertEqual(updated.title, "Plan launch final")
        XCTAssertEqual(updated.notes, "Ready")
        XCTAssertNil(updated.dueAt)

        let updatedItem = ProviderTaskListItem(
            id: item.id,
            remoteTaskID: updated.id,
            remoteVersion: updated.version,
            provider: item.provider,
            accountKey: item.accountKey,
            listID: item.listID,
            title: updated.title,
            details: updated.notes,
            dueAt: updated.dueAt,
            isCompleted: updated.isCompleted,
            listTitle: item.listTitle,
            accountTitle: item.accountTitle
        )
        try await coordinator.deleteSidebarTask(
            updatedItem,
            baseline: updated
        )
        XCTAssertTrue(google.snapshots.isEmpty)
        try await coordinator.undoLastSidebarMutation()
        XCTAssertEqual(google.snapshots.map(\.title), ["Plan launch final"])
    }

    @MainActor
    func testTodoistSidebarMoveAndUndoUseAsyncProviderIdentity() async throws {
        let harness = try makeHarness()
        let source = RemoteTaskList(
            provider: .todoist,
            id: "project:inbox",
            accountKey: "todoist-account",
            title: "Inbox",
            sourceTitle: "Todoist User",
            isWritable: true
        )
        let destination = RemoteTaskList(
            provider: .todoist,
            id: "section:launch",
            accountKey: source.accountKey,
            title: "Work › Launch",
            sourceTitle: source.sourceTitle,
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "todoist-task",
            parentID: source.id,
            parentAccountKey: source.accountKey,
            title: "Prepare launch",
            notes: "Move through the common command path",
            dueAt: date(2026, 7, 24, 10),
            isCompleted: false,
            priority: .high,
            version: "todoist-v1",
            deepLink: URL(string: "https://app.todoist.com/app/task/todoist-task")
        )
        let todoist = StubAsyncTaskProvider(
            provider: .todoist,
            lists: [source, destination],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: StubAppleTaskListingProvider(
                lists: [],
                tasks: [],
                authorizationState: .denied
            ),
            oauthCredentials: InMemoryOAuthCredentialStore(),
            asyncProviders: [.todoist: todoist]
        )

        for _ in 0..<50 {
            if case .loaded = coordinator.todoistTaskState { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case let .loaded(items) = coordinator.todoistTaskState,
              let item = items.first else {
            return XCTFail("Expected Todoist sidebar projection")
        }

        let moved = try await coordinator.moveSidebarTask(
            item,
            baseline: remote,
            to: destination
        )
        XCTAssertEqual(moved.parentID, destination.id)
        XCTAssertEqual(moved.parentAccountKey, destination.accountKey)
        XCTAssertEqual(todoist.snapshots.first?.parentID, destination.id)
        XCTAssertNotNil(coordinator.sidebarUndoState)

        try await coordinator.undoLastSidebarMutation()

        XCTAssertEqual(todoist.snapshots.first?.parentID, source.id)
        XCTAssertEqual(todoist.snapshots.first?.priority, .high)
        XCTAssertNil(coordinator.sidebarUndoState)
    }

    @MainActor
    func testAppleSidebarDeleteKeepsLinkedLocalTaskAndMarksBindingMissing() async throws {
        let harness = try makeHarness()
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "sidebar-linked-delete"),
                notes: "Keep this local context"
            )
        )
        let localTask = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .after,
            title: "Linked reminder",
            sortOrder: 0
        )
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "linked-list",
            accountKey: "icloud-account",
            title: "Work",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "linked-remote",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: localTask.title,
            notes: "",
            dueAt: nil,
            isCompleted: false,
            version: "v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let account = try XCTUnwrap(
            harness.store.taskProviders.fetchAccounts().first
        )
        _ = try harness.store.taskProviders.insertLinkedTask(
            account: account,
            remote: remote,
            eventTaskID: localTask.id,
            occurrenceKey: nil,
            syncHash: "linked-baseline"
        )
        let item = ProviderTaskListItem(
            id: TaskProviderCoordinator.sidebarTaskItemID(
                provider: .appleReminders,
                accountKey: list.accountKey,
                listID: list.id,
                taskID: remote.id
            ),
            remoteTaskID: remote.id,
            remoteVersion: remote.version,
            provider: .appleReminders,
            accountKey: list.accountKey,
            listID: list.id,
            title: remote.title,
            details: nil,
            dueAt: nil,
            isCompleted: false,
            listTitle: list.title,
            accountTitle: list.sourceTitle
        )

        try await coordinator.deleteSidebarTask(item, baseline: remote)

        XCTAssertNotNil(
            try harness.store.eventTasks.fetch(id: localTask.id)
        )
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: localTask.id
            )?.syncState,
            .missing
        )
    }

    @MainActor
    func testAppleSidebarMovePreservesLinkedTaskAcrossAccountsAndUndoRestoresIt() async throws {
        let harness = try makeHarness()
        let source = RemoteTaskList(
            provider: .appleReminders,
            id: "work-list",
            accountKey: "icloud",
            title: "Work",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let destination = RemoteTaskList(
            provider: .appleReminders,
            id: "personal-list",
            accountKey: "on-my-mac",
            title: "Personal",
            sourceTitle: "On My Mac",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "move-me",
            parentID: source.id,
            parentAccountKey: source.accountKey,
            title: "Prepare notes",
            notes: "Keep the full note",
            dueAt: date(2026, 7, 22, 10),
            isCompleted: false,
            version: "move-v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [source, destination],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "sidebar-linked-move"),
                notes: "Local brief"
            )
        )
        let localTask = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: remote.title,
            sortOrder: 0
        )
        let sourceAccount = try XCTUnwrap(
            harness.store.taskProviders.fetchAccounts().first {
                $0.accountKey == source.accountKey
            }
        )
        _ = try harness.store.taskProviders.insertLinkedTask(
            account: sourceAccount,
            remote: remote,
            eventTaskID: localTask.id,
            occurrenceKey: nil,
            syncHash: "move-baseline"
        )
        let item = ProviderTaskListItem(
            id: TaskProviderCoordinator.sidebarTaskItemID(
                provider: .appleReminders,
                accountKey: source.accountKey,
                listID: source.id,
                taskID: remote.id
            ),
            remoteTaskID: remote.id,
            remoteVersion: remote.version,
            provider: .appleReminders,
            accountKey: source.accountKey,
            listID: source.id,
            title: remote.title,
            details: remote.notes,
            dueAt: remote.dueAt,
            isCompleted: remote.isCompleted,
            listTitle: source.title,
            accountTitle: source.sourceTitle
        )

        let moved = try await coordinator.moveSidebarTask(
            item,
            baseline: remote,
            to: destination
        )
        XCTAssertEqual(moved.parentID, destination.id)
        XCTAssertEqual(moved.parentAccountKey, destination.accountKey)
        let movedBinding = try XCTUnwrap(
            harness.store.taskProviders.fetchBinding(eventTaskID: localTask.id)
        )
        let movedItem = try XCTUnwrap(
            harness.store.taskProviders.fetchProviderItem(
                id: movedBinding.providerItemID
            )
        )
        XCTAssertEqual(movedItem.remoteParentID, destination.id)
        XCTAssertEqual(
            try harness.store.taskProviders.fetchAccount(id: movedItem.accountID)?.accountKey,
            destination.accountKey
        )

        try await coordinator.undoLastSidebarMutation()

        XCTAssertEqual(provider.snapshots.first?.parentID, source.id)
        let restoredBinding = try XCTUnwrap(
            harness.store.taskProviders.fetchBinding(eventTaskID: localTask.id)
        )
        let restoredItem = try XCTUnwrap(
            harness.store.taskProviders.fetchProviderItem(
                id: restoredBinding.providerItemID
            )
        )
        XCTAssertEqual(restoredItem.remoteParentID, source.id)
        XCTAssertEqual(restoredBinding.syncState, .linked)
        XCTAssertNil(coordinator.sidebarUndoState)
    }

    @MainActor
    func testAppleSidebarDeleteUndoRecreatesRemoteAndRelinksLocalTask() async throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "undo-list",
            accountKey: "icloud",
            title: "Work",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "delete-me",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: "Recover me",
            notes: "Provider-owned note",
            dueAt: nil,
            isCompleted: true,
            version: "delete-v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(lists: [list], tasks: [remote])
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "sidebar-delete-undo"),
                notes: "Local brief"
            )
        )
        let localTask = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .after,
            title: remote.title,
            sortOrder: 0
        )
        let account = try XCTUnwrap(
            harness.store.taskProviders.fetchAccounts().first
        )
        _ = try harness.store.taskProviders.insertLinkedTask(
            account: account,
            remote: remote,
            eventTaskID: localTask.id,
            occurrenceKey: nil,
            syncHash: "delete-baseline"
        )
        let item = ProviderTaskListItem(
            id: "delete-item",
            remoteTaskID: remote.id,
            remoteVersion: remote.version,
            provider: .appleReminders,
            accountKey: list.accountKey,
            listID: list.id,
            title: remote.title,
            details: remote.notes,
            dueAt: nil,
            isCompleted: true,
            listTitle: list.title,
            accountTitle: list.sourceTitle
        )

        try await coordinator.deleteSidebarTask(item, baseline: remote)
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: localTask.id
            )?.syncState,
            .missing
        )

        try await coordinator.undoLastSidebarMutation()

        let recreated = try XCTUnwrap(provider.snapshots.first)
        XCTAssertNotEqual(recreated.id, remote.id)
        XCTAssertEqual(recreated.title, remote.title)
        XCTAssertEqual(recreated.notes, remote.notes)
        XCTAssertTrue(recreated.isCompleted)
        let binding = try XCTUnwrap(
            harness.store.taskProviders.fetchBinding(eventTaskID: localTask.id)
        )
        let cached = try XCTUnwrap(
            harness.store.taskProviders.fetchProviderItem(id: binding.providerItemID)
        )
        XCTAssertEqual(cached.remoteID, recreated.id)
        XCTAssertEqual(binding.syncState, .linked)
        XCTAssertNotNil(try harness.store.eventTasks.fetch(id: localTask.id))
    }

    @MainActor
    func testAppleSidebarBulkCompletionHasVersionAwareCompositeUndo() async throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "bulk-list",
            accountKey: "icloud",
            title: "Work",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let snapshots = ["one", "two"].map { id in
            RemoteTaskSnapshot(
                id: id,
                parentID: list.id,
                parentAccountKey: list.accountKey,
                title: id.capitalized,
                notes: "",
                dueAt: nil,
                isCompleted: false,
                version: "\(id)-v1",
                deepLink: nil
            )
        }
        let provider = StubAppleTaskListingProvider(lists: [list], tasks: snapshots)
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let items = snapshots.map { remote in
            ProviderTaskListItem(
                id: remote.id,
                remoteTaskID: remote.id,
                remoteVersion: remote.version,
                provider: .appleReminders,
                accountKey: list.accountKey,
                listID: list.id,
                title: remote.title,
                details: nil,
                dueAt: nil,
                isCompleted: false,
                listTitle: list.title,
                accountTitle: list.sourceTitle
            )
        }

        _ = try await coordinator.setSidebarTasksCompleted(
            items,
            isCompleted: true
        )
        XCTAssertTrue(provider.snapshots.allSatisfy(\.isCompleted))
        XCTAssertEqual(coordinator.sidebarUndoState?.message, "Completed 2 tasks")

        try await coordinator.undoLastSidebarMutation()

        XCTAssertTrue(provider.snapshots.allSatisfy { !$0.isCompleted })
        XCTAssertEqual(provider.updateTaskCount, 4)
    }

    @MainActor
    func testTaskCenterProjectsProviderConflictAndExplicitRecoveryChoices() async throws {
        let harness = try makeHarness()
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "provider-recovery"),
                notes: "Keep local context"
            )
        )
        let eventTask = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: "Local task title",
            sortOrder: 0
        )
        let remote = RemoteTaskSnapshot(
            id: "remote-recovery",
            parentID: "reminders-list",
            title: "Remote task title",
            notes: "Remote body stays outside KaosCal",
            dueAt: nil,
            isCompleted: true,
            version: "remote-v2",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [
                RemoteTaskList(
                    provider: .appleReminders,
                    id: remote.parentID,
                    accountKey: "icloud-account",
                    title: "Work Reminders",
                    sourceTitle: "iCloud",
                    isWritable: true
                )
            ],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let account = try XCTUnwrap(
            harness.store.taskProviders.fetchAccounts().first {
                $0.provider == .appleReminders
                    && $0.accountKey == "icloud-account"
            }
        )
        let binding = try harness.store.taskProviders.insertLinkedTask(
            account: account,
            remote: remote,
            eventTaskID: eventTask.id,
            occurrenceKey: nil,
            syncHash: "stale-local-hash"
        )
        try harness.store.taskProviders.markBinding(
            bindingID: binding.id,
            state: .conflict
        )

        let conflictedItem = try XCTUnwrap(
            harness.store.taskCenter.fetch(
                list: .today,
                now: date(2026, 7, 10, 8),
                calendar: testCalendar
            ).first { $0.id == .eventTask(
                taskID: eventTask.id,
                contextID: context.id
            ) }
        )
        XCTAssertEqual(
            conflictedItem.providerLink,
            TaskCenterProviderLink(
                bindingID: binding.id,
                provider: .appleReminders,
                accountKey: "icloud-account",
                accountTitle: "iCloud",
                remoteParentID: "reminders-list",
                syncState: .conflict,
                authorizationState: .authorized,
                pendingOperation: nil,
                pendingAttemptCount: 0,
                pendingLastError: nil
            )
        )

        try await coordinator.acceptRemoteTaskVersion(
            eventTaskID: eventTask.id,
            in: harness.store
        )
        let acceptedTask = try XCTUnwrap(
            harness.store.eventTasks.fetch(id: eventTask.id)
        )
        XCTAssertEqual(acceptedTask.title, "Remote task title")
        XCTAssertTrue(acceptedTask.isCompleted)
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: eventTask.id
            )?.syncState,
            .linked
        )

        provider.authorizationState = .denied
        coordinator.refresh()
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: eventTask.id
            )?.syncState,
            .disconnected
        )

        provider.authorizationState = .authorized
        coordinator.refresh()
        coordinator.refreshLinkedTasks(in: harness.store)
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: eventTask.id
            )?.syncState,
            .linked
        )

        let refreshedTask = try XCTUnwrap(
            harness.store.eventTasks.fetch(id: eventTask.id)
        )
        _ = try harness.store.updateEventTask(
            contextID: refreshedTask.contextID,
            taskID: refreshedTask.id,
            section: refreshedTask.section,
            title: "Local version wins",
            sortOrder: refreshedTask.sortOrder,
            due: refreshedTask.due
        )
        _ = try harness.store.setEventTaskCompleted(
            contextID: refreshedTask.contextID,
            taskID: refreshedTask.id,
            isCompleted: false
        )
        let linkedBinding = try XCTUnwrap(
            harness.store.taskProviders.fetchBinding(
                eventTaskID: eventTask.id
            )
        )
        try harness.store.taskProviders.markBinding(
            bindingID: linkedBinding.id,
            state: .conflict
        )

        try await coordinator.acceptLocalTaskVersion(
            eventTaskID: eventTask.id,
            in: harness.store
        )
        XCTAssertEqual(
            provider.snapshots.first(where: { $0.id == remote.id })?.title,
            "Local version wins"
        )
        XCTAssertEqual(
            provider.snapshots.first(where: { $0.id == remote.id })?.isCompleted,
            false
        )
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: eventTask.id
            )?.syncState,
            .linked
        )

    }

    @MainActor
    func testProviderSyncDetectsIndependentLocalAndRemoteChangesWithoutOverwrite() throws {
        let harness = try makeHarness()
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "provider-conflict-state-machine"),
                notes: "Conflict fixture"
            )
        )
        let task = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: "Initial title",
            sortOrder: 0
        )
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "work-reminders",
            accountKey: "icloud-account",
            title: "Work",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let initialRemote = RemoteTaskSnapshot(
            id: "remote-conflict",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: task.title,
            notes: "",
            dueAt: date(2026, 7, 10, 9),
            isCompleted: false,
            version: "remote-v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [initialRemote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let account = try XCTUnwrap(
            harness.store.taskProviders.fetchAccounts().first
        )
        _ = try harness.store.taskProviders.insertLinkedTask(
            account: account,
            remote: initialRemote,
            eventTaskID: task.id,
            occurrenceKey: nil,
            syncHash: "legacy-baseline"
        )
        let local = try harness.store.updateEventTask(
            contextID: context.id,
            taskID: task.id,
            section: task.section,
            title: "Local edit",
            sortOrder: task.sortOrder,
            due: task.due
        )
        provider.replaceSnapshot(RemoteTaskSnapshot(
            id: initialRemote.id,
            parentID: initialRemote.parentID,
            parentAccountKey: initialRemote.parentAccountKey,
            title: "Remote edit",
            notes: "",
            dueAt: initialRemote.dueAt,
            isCompleted: false,
            version: "remote-v2",
            deepLink: nil
        ))

        coordinator.syncEventTask(
            in: harness.store,
            contextID: context.id,
            task: local
        )

        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: task.id
            )?.syncState,
            .conflict
        )
        XCTAssertEqual(
            try harness.store.eventTasks.fetch(id: task.id)?.title,
            "Local edit"
        )
        XCTAssertEqual(provider.updateTaskCount, 0)
        XCTAssertNil(
            try harness.store.taskProviders.fetchPendingOperation(
                eventTaskID: task.id
            )
        )
    }

    @MainActor
    func testProviderSyncAppliesRemoteTitleAndDueAndDoesNotRecreateDeletion() throws {
        let harness = try makeHarness()
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "provider-remote-apply"),
                notes: "Remote apply fixture"
            )
        )
        let task = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: "Initial title",
            sortOrder: 0
        )
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "remote-apply-list",
            accountKey: "icloud-account",
            title: "Tasks",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let initialRemote = RemoteTaskSnapshot(
            id: "remote-apply",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: task.title,
            notes: "",
            dueAt: date(2026, 7, 10, 9),
            isCompleted: false,
            version: "remote-v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [initialRemote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let account = try XCTUnwrap(
            harness.store.taskProviders.fetchAccounts().first
        )
        _ = try harness.store.taskProviders.insertLinkedTask(
            account: account,
            remote: initialRemote,
            eventTaskID: task.id,
            occurrenceKey: nil,
            syncHash: "legacy-baseline"
        )
        let remoteDue = date(2026, 7, 11, 13)
        provider.replaceSnapshot(RemoteTaskSnapshot(
            id: initialRemote.id,
            parentID: initialRemote.parentID,
            parentAccountKey: initialRemote.parentAccountKey,
            title: "Remote title",
            notes: "",
            dueAt: remoteDue,
            isCompleted: true,
            version: "remote-v2",
            deepLink: nil
        ))

        coordinator.syncEventTask(
            in: harness.store,
            contextID: context.id,
            task: task
        )

        let applied = try XCTUnwrap(
            harness.store.eventTasks.fetch(id: task.id)
        )
        XCTAssertEqual(applied.title, "Remote title")
        XCTAssertEqual(applied.due, .fixed(remoteDue))
        XCTAssertTrue(applied.isCompleted)
        XCTAssertEqual(provider.updateTaskCount, 0)

        provider.removeSnapshot(
            id: initialRemote.id,
            parentID: initialRemote.parentID
        )
        coordinator.syncEventTask(
            in: harness.store,
            contextID: context.id,
            task: applied
        )
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: task.id
            )?.syncState,
            .missing
        )
        XCTAssertEqual(provider.createTaskCount, 0)
        XCTAssertNotNil(try harness.store.eventTasks.fetch(id: task.id))
    }

    @MainActor
    func testPendingCreateSurvivesCoordinatorRelaunchAndLocalOnlyClearsIt() throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "pending-list",
            accountKey: "icloud-account",
            title: "Tasks",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: []
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        coordinator.saveDestination(
            calendarIdentifier: "calendar",
            list: list
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "pending-create"),
                notes: "Pending fixture"
            )
        )
        let task = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: "Create remotely",
            sortOrder: 0
        )
        provider.createTaskError = .providerFailure("Offline fixture")

        coordinator.syncEventTask(
            in: harness.store,
            contextID: context.id,
            task: task
        )

        let pending = try XCTUnwrap(
            harness.store.taskProviders.fetchPendingOperation(
                eventTaskID: task.id
            )
        )
        XCTAssertEqual(pending.operation, .create)
        XCTAssertEqual(pending.attemptCount, 1)
        XCTAssertEqual(provider.createTaskCount, 1)

        let relaunched = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let projected = try XCTUnwrap(
            harness.store.taskCenter.fetch(
                list: .today,
                now: date(2026, 7, 10, 8),
                calendar: testCalendar
            ).first { $0.id == .eventTask(
                taskID: task.id,
                contextID: context.id
            ) }
        )
        XCTAssertEqual(projected.providerLink?.pendingOperation, .create)
        XCTAssertEqual(projected.providerLink?.pendingAttemptCount, 1)

        try relaunched.keepTaskLocalOnly(eventTaskID: task.id)
        XCTAssertTrue(
            try harness.store.taskProviders.isLocalOnly(
                eventTaskID: task.id
            )
        )
        XCTAssertNil(
            try harness.store.taskProviders.fetchPendingOperation(
                eventTaskID: task.id
            )
        )
        relaunched.syncEventTask(
            in: harness.store,
            contextID: context.id,
            task: task
        )
        XCTAssertEqual(provider.createTaskCount, 1)
    }

    @MainActor
    func testPendingDeleteSurvivesRemoteSuccessUntilLocalDeleteCommits() async throws {
        let harness = try makeHarness()
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "pending-delete-crash-window"),
                notes: "Delete fixture"
            )
        )
        let task = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: "Delete remotely",
            sortOrder: 0
        )
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "delete-list",
            accountKey: "icloud-account",
            title: "Tasks",
            sourceTitle: "iCloud",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "delete-remote",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: task.title,
            notes: "",
            dueAt: date(2026, 7, 10, 9),
            isCompleted: false,
            version: "remote-v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let account = try XCTUnwrap(
            harness.store.taskProviders.fetchAccounts().first
        )
        _ = try harness.store.taskProviders.insertLinkedTask(
            account: account,
            remote: remote,
            eventTaskID: task.id,
            occurrenceKey: nil,
            syncHash: "legacy-baseline"
        )

        try coordinator.deleteRemoteTaskIfBound(eventTaskID: task.id)

        XCTAssertEqual(provider.deleteTaskCount, 1)
        XCTAssertNil(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: task.id
            )
        )
        XCTAssertEqual(
            try harness.store.taskProviders.fetchPendingOperation(
                eventTaskID: task.id
            )?.operation,
            .delete
        )

        let relaunched = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let completedOperation = try await relaunched.retryPendingOperation(
            eventTaskID: task.id,
            in: harness.store
        )
        XCTAssertEqual(completedOperation, .delete)
        XCTAssertEqual(provider.deleteTaskCount, 1)
        XCTAssertNotNil(
            try harness.store.taskProviders.fetchPendingOperation(
                eventTaskID: task.id
            )
        )

        try harness.store.deleteEventTask(
            contextID: context.id,
            taskID: task.id
        )
        XCTAssertNil(
            try harness.store.taskProviders.fetchPendingOperation(
                eventTaskID: task.id
            )
        )
    }

    @MainActor
    func testExplicitRelinkUsesSelectedSourceAndAppliesRemoteProjection() async throws {
        let harness = try makeHarness()
        let list = RemoteTaskList(
            provider: .appleReminders,
            id: "relink-list",
            accountKey: "icloud-work",
            title: "Work Reminders",
            sourceTitle: "Work iCloud",
            isWritable: true
        )
        let remoteDue = date(2026, 7, 12, 15)
        let remote = RemoteTaskSnapshot(
            id: "selected-remote-task",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: "Selected remote title",
            notes: "Selected task details",
            dueAt: remoteDue,
            isCompleted: true,
            version: "remote-v1",
            deepLink: nil
        )
        let provider = StubAppleTaskListingProvider(
            lists: [list],
            tasks: [remote]
        )
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: provider,
            oauthCredentials: InMemoryOAuthCredentialStore()
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: makeEvent(id: "explicit-provider-relink"),
                notes: "Relink fixture"
            )
        )
        let task = try harness.store.eventTasks.create(
            contextID: context.id,
            section: .before,
            title: "Local title",
            sortOrder: 0
        )
        try coordinator.keepTaskLocalOnly(eventTaskID: task.id)

        let candidates = try await coordinator.relinkCandidates(
            eventTaskID: task.id
        )
        let candidate = try XCTUnwrap(
            candidates.first { $0.remoteTaskID == remote.id }
        )
        XCTAssertEqual(candidate.accountKey, list.accountKey)
        XCTAssertEqual(candidate.listTitle, list.title)

        try await coordinator.relinkEventTask(
            eventTaskID: task.id,
            to: candidate,
            in: harness.store
        )

        let linkedTask = try XCTUnwrap(
            harness.store.eventTasks.fetch(id: task.id)
        )
        XCTAssertEqual(linkedTask.title, remote.title)
        XCTAssertEqual(linkedTask.due, .fixed(remoteDue))
        XCTAssertTrue(linkedTask.isCompleted)
        XCTAssertFalse(
            try harness.store.taskProviders.isLocalOnly(
                eventTaskID: task.id
            )
        )
        let binding = try XCTUnwrap(
            harness.store.taskProviders.fetchBinding(eventTaskID: task.id)
        )
        let item = try XCTUnwrap(
            harness.store.taskProviders.fetchProviderItem(
                id: binding.providerItemID
            )
        )
        let account = try XCTUnwrap(
            harness.store.taskProviders.fetchAccount(id: item.accountID)
        )
        XCTAssertEqual(account.accountKey, list.accountKey)
        XCTAssertEqual(item.remoteParentID, list.id)
        XCTAssertEqual(item.remoteID, remote.id)
    }

    func testOAuthAuthorizationRequestUsesPKCEAndProviderSpecificRedirectRules() throws {
        let configuration = OAuthProviderConfiguration(
            provider: .googleTasks,
            clientID: "desktop-client.apps.googleusercontent.com",
            redirectURI: try XCTUnwrap(
                URL(string: "http://127.0.0.1:43891/oauth/callback")
            )
        )
        let request = try OAuthAuthorizationRequest.make(
            configuration: configuration,
            state: "state-for-test",
            pkce: OAuthPKCEChallenge.make(
                verifier: String(repeating: "a", count: 64)
            )
        )
        let query = try XCTUnwrap(
            URLComponents(
                url: request.url,
                resolvingAgainstBaseURL: false
            )?.queryItems
        )
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })

        XCTAssertEqual(values["state"], "state-for-test")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["redirect_uri"], configuration.redirectURI.absoluteString)
        XCTAssertTrue(
            (query.first(where: { $0.name == "scope" })?.value ?? "")
                .contains("https://www.googleapis.com/auth/tasks")
        )
        let tokenRequest = OAuthTokenExchange.authorizationCodeRequest(
            configuration: configuration,
            code: "code with reserved&characters",
            pkce: request.pkce
        )
        XCTAssertEqual(tokenRequest.url?.host, "oauth2.googleapis.com")
        let tokenBody = try XCTUnwrap(
            tokenRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )
        XCTAssertTrue(tokenBody.contains("code=code%20with%20reserved%26characters"))
        XCTAssertTrue(tokenBody.contains("code_verifier="))
        XCTAssertFalse(tokenBody.contains("client_secret"))

        let googleConfigurationWithSecret = OAuthProviderConfiguration(
            provider: .googleTasks,
            clientID: "desktop-client.apps.googleusercontent.com",
            clientSecret: "test-secret+/=",
            redirectURI: configuration.redirectURI
        )
        let secretTokenRequest = OAuthTokenExchange.authorizationCodeRequest(
            configuration: googleConfigurationWithSecret,
            code: "code",
            pkce: request.pkce
        )
        let secretTokenBody = try XCTUnwrap(
            secretTokenRequest.httpBody.flatMap {
                String(data: $0, encoding: .utf8)
            }
        )
        XCTAssertTrue(
            secretTokenBody.contains("client_secret=test-secret%2B%2F%3D")
        )
        let secretRefreshRequest = OAuthTokenExchange.refreshTokenRequest(
            configuration: googleConfigurationWithSecret,
            refreshToken: "refresh"
        )
        let secretRefreshBody = try XCTUnwrap(
            secretRefreshRequest.httpBody.flatMap {
                String(data: $0, encoding: .utf8)
            }
        )
        XCTAssertTrue(
            secretRefreshBody.contains("client_secret=test-secret%2B%2F%3D")
        )
        XCTAssertEqual(
            googleConfigurationWithSecret.replacingRedirectURI(
                try XCTUnwrap(URL(string: "http://127.0.0.1:51234"))
            ).clientSecret,
            "test-secret+/="
        )
        XCTAssertEqual(
            try OAuthAuthorizationCallback.authorizationCode(
                from: try XCTUnwrap(URL(string: "http://127.0.0.1/callback?state=state-for-test&code=returned-code")),
                expectedState: "state-for-test"
            ),
            "returned-code"
        )
        XCTAssertThrowsError(
            try OAuthAuthorizationCallback.authorizationCode(
                from: try XCTUnwrap(URL(string: "http://127.0.0.1/callback?state=wrong&code=returned-code")),
                expectedState: "state-for-test"
            )
        )
        let dynamicRedirect = try XCTUnwrap(
            OAuthLoopbackBrowserAuthorization.effectiveRedirectURI(
                try XCTUnwrap(URL(string: "http://127.0.0.1")),
                port: 51_234
            )
        )
        XCTAssertEqual(dynamicRedirect.absoluteString, "http://127.0.0.1:51234")
        let validCallbackData = Data(
            "GET /?state=state-for-test&code=returned-code HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8
        )
        XCTAssertEqual(
            OAuthLoopbackBrowserAuthorization.callbackURL(
                from: validCallbackData,
                redirectURI: dynamicRedirect
            )?.query,
            "state=state-for-test&code=returned-code"
        )
        XCTAssertNil(
            OAuthLoopbackBrowserAuthorization.callbackURL(
                from: Data(
                    "GET /wrong?state=state-for-test&code=returned-code HTTP/1.1\r\n\r\n".utf8
                ),
                redirectURI: dynamicRedirect
            )
        )
        XCTAssertThrowsError(
            try OAuthAuthorizationRequest.make(
                configuration: OAuthProviderConfiguration(
                    provider: .googleTasks,
                    clientID: "client",
                    redirectURI: try XCTUnwrap(URL(string: "kaoscal://oauth"))
                ),
                pkce: request.pkce
            )
        )

        let microsoftConfiguration = OAuthProviderConfiguration(
            provider: .microsoftToDo,
            clientID: "microsoft-public-client",
            redirectURI: try XCTUnwrap(
                URL(string: "http://localhost:43891/oauth/callback")
            )
        )
        let microsoftRequest = try OAuthAuthorizationRequest.make(
            configuration: microsoftConfiguration,
            state: "microsoft-state",
            pkce: request.pkce
        )
        XCTAssertEqual(
            microsoftRequest.url.path,
            "/common/oauth2/v2.0/authorize"
        )
        let microsoftQuery = try XCTUnwrap(
            URLComponents(
                url: microsoftRequest.url,
                resolvingAgainstBaseURL: false
            )?.queryItems
        )
        let microsoftScopes = microsoftQuery
            .first(where: { $0.name == "scope" })?.value ?? ""
        XCTAssertTrue(microsoftScopes.contains("Tasks.ReadWrite"))
        XCTAssertTrue(microsoftScopes.contains("offline_access"))
        XCTAssertTrue(microsoftScopes.contains("profile"))
        XCTAssertEqual(
            OAuthTokenExchange.authorizationCodeRequest(
                configuration: microsoftConfiguration,
                code: "microsoft-code",
                pkce: request.pkce
            ).url?.path,
            "/common/oauth2/v2.0/token"
        )
        XCTAssertTrue(
            OAuthLoopbackBrowserAuthorization
                .callbackHTTPResponse(succeeded: true)
                .contains("finishes connecting")
        )
        XCTAssertTrue(
            OAuthLoopbackBrowserAuthorization
                .callbackHTTPResponse(succeeded: false)
                .contains("not completed")
        )
        XCTAssertThrowsError(
            try OAuthAuthorizationCallback.authorizationCode(
                from: try XCTUnwrap(URL(
                    string: "http://localhost:43891/oauth/callback?state=microsoft-state&error=access_denied&error_description=Cancelled"
                )),
                expectedState: "microsoft-state"
            )
        )
    }

    @MainActor
    func testOAuthLoopbackUsesDynamicPortAndTimesOutWithoutCallback() async throws {
        let baseConfiguration = OAuthProviderConfiguration(
            provider: .googleTasks,
            clientID: "desktop-client.apps.googleusercontent.com",
            redirectURI: try XCTUnwrap(URL(string: "http://127.0.0.1"))
        )
        var openedAuthorizationURL: URL?

        do {
            _ = try await OAuthLoopbackBrowserAuthorization.authorize(
                configuration: baseConfiguration,
                timeout: 1,
                openURL: {
                    openedAuthorizationURL = $0
                    return true
                }
            )
            XCTFail("Expected loopback authorization to time out")
        } catch {
            XCTAssertEqual(
                error as? OAuthLoopbackAuthorizationError,
                .timedOut
            )
        }

        let authorizationURL = try XCTUnwrap(openedAuthorizationURL)
        let query = try XCTUnwrap(
            URLComponents(
                url: authorizationURL,
                resolvingAgainstBaseURL: false
            )?.queryItems
        )
        let redirectString = try XCTUnwrap(
            query.first(where: { $0.name == "redirect_uri" })?.value
        )
        let effectiveRedirect = try XCTUnwrap(URL(string: redirectString))
        XCTAssertEqual(effectiveRedirect.host, "127.0.0.1")
        XCTAssertNotNil(effectiveRedirect.port)

        let tokenRequest = OAuthTokenExchange.authorizationCodeRequest(
            configuration: baseConfiguration.replacingRedirectURI(
                effectiveRedirect
            ),
            code: "code",
            pkce: OAuthPKCEChallenge.make(
                verifier: String(repeating: "a", count: 64)
            )
        )
        let tokenBody = try XCTUnwrap(
            tokenRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )
        let formValues = Dictionary(uniqueKeysWithValues: tokenBody
            .split(separator: "&")
            .compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.count == 2,
                      let key = String(parts[0]).removingPercentEncoding,
                      let value = String(parts[1]).removingPercentEncoding else {
                    return nil
                }
                return (key, value)
            })
        XCTAssertEqual(formValues["redirect_uri"], redirectString)
    }

    @MainActor
    func testOAuthLoopbackCompletesOnlyOnceWhenCallbackIsDuplicated() async throws {
        let configuration = OAuthProviderConfiguration(
            provider: .googleTasks,
            clientID: "desktop-client.apps.googleusercontent.com",
            redirectURI: try XCTUnwrap(URL(string: "http://127.0.0.1"))
        )
        var callbackTask: Task<Void, Never>?

        let receipt = try await OAuthLoopbackBrowserAuthorization.authorize(
            configuration: configuration,
            timeout: 5,
            openURL: { authorizationURL in
                let queryItems = URLComponents(
                    url: authorizationURL,
                    resolvingAgainstBaseURL: false
                )?.queryItems ?? []
                guard let redirectString = queryItems.first(where: {
                    $0.name == "redirect_uri"
                })?.value,
                      let state = queryItems.first(where: {
                          $0.name == "state"
                      })?.value,
                      var callbackComponents = URLComponents(
                          string: redirectString
                      ) else {
                    return false
                }
                callbackComponents.queryItems = [
                    URLQueryItem(name: "state", value: state),
                    URLQueryItem(name: "code", value: "first-code")
                ]
                guard let callbackURL = callbackComponents.url else {
                    return false
                }
                callbackTask = Task {
                    for _ in 0..<2 {
                        _ = try? await URLSession.shared.data(from: callbackURL)
                    }
                }
                return true
            }
        )
        await callbackTask?.value

        XCTAssertEqual(receipt.code, "first-code")
        XCTAssertEqual(receipt.effectiveRedirectURI.host, "127.0.0.1")
        XCTAssertNotNil(receipt.effectiveRedirectURI.port)
    }

    func testContextReferencesStoreOnlyURLMetadataAndCascadeWithContext() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "reference-context")
        let task = try harness.store.appendEventTask(
            for: event,
            section: .before,
            title: "Create context"
        )
        let reference = try harness.store.references.add(
            contextID: task.contextID,
            provider: .web,
            url: try XCTUnwrap(URL(string: "https://example.invalid/brief")),
            title: "Project brief"
        )

        XCTAssertEqual(
            try harness.store.references.fetch(contextID: task.contextID),
            [reference]
        )
        try harness.store.eventContexts.delete(contextID: task.contextID)
        XCTAssertTrue(
            try harness.store.references.fetch(contextID: task.contextID).isEmpty
        )
    }

    func testGoogleTasksRequestsUseTasksV1ETagAndBearerBoundaries() throws {
        let request = try GoogleTasksAPI.updateTaskRequest(
            listID: "list/one",
            taskID: "task one",
            patch: RemoteTaskPatch(title: "Updated", notes: nil, dueAt: nil, isCompleted: true),
            expectedETag: "etag-value",
            accessToken: "test-token"
        )
        XCTAssertEqual(request.url?.host, "tasks.googleapis.com")
        XCTAssertTrue(request.url?.path.contains("/tasks/v1/lists/") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "etag-value")
        let nextPage = GoogleTasksAPI.taskListsRequest(
            accessToken: "test-token",
            pageToken: "cursor value"
        )
        XCTAssertEqual(
            URLComponents(url: nextPage.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first?.value,
            "cursor value"
        )
        let body = try XCTUnwrap(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["title"] as? String, "Updated")
        XCTAssertEqual(body["status"] as? String, "completed")

        var clearDuePatch = RemoteTaskPatch()
        clearDuePatch.dueAt = .some(nil)
        let clearDueRequest = try GoogleTasksAPI.updateTaskRequest(
            listID: "list",
            taskID: "task",
            patch: clearDuePatch,
            expectedETag: nil,
            accessToken: "test-token"
        )
        let clearDueBody = try XCTUnwrap(
            clearDueRequest.httpBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
        )
        XCTAssertTrue(clearDueBody["due"] is NSNull)

        let reopenRequest = try GoogleTasksAPI.updateTaskRequest(
            listID: "list",
            taskID: "task",
            patch: RemoteTaskPatch(isCompleted: false),
            expectedETag: "reopen-etag",
            accessToken: "test-token"
        )
        let reopenBody = try XCTUnwrap(
            reopenRequest.httpBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
        )
        XCTAssertEqual(reopenBody["status"] as? String, "needsAction")
        XCTAssertNil(reopenBody["due"])
    }

    func testGoogleTaskDueDateCodecPreservesCivilDayAcrossTimeZones() throws {
        for identifier in ["UTC", "Asia/Seoul", "America/New_York"] {
            let timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let original = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026,
                month: 3,
                day: 8,
                hour: 0
            )))
            let codec = GoogleTaskDueDateCodec(timeZone: timeZone)

            let encoded = try XCTUnwrap(codec.encode(original))
            XCTAssertEqual(encoded, "2026-03-08T00:00:00.000Z")
            let decoded = try XCTUnwrap(codec.decode(encoded))
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour],
                from: decoded
            )
            XCTAssertEqual(components.year, 2026)
            XCTAssertEqual(components.month, 3)
            XCTAssertEqual(components.day, 8)
            XCTAssertEqual(components.hour, 0)
        }

        XCTAssertNil(
            GoogleTaskDueDateCodec(
                timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
            ).decode("2026-02-31T00:00:00.000Z")
        )
    }

    func testTodoistV1RequestsKeepProjectSectionAndCompletionSeparate() throws {
        let create = try TodoistAPI.createTaskRequest(
            parentID: "section:section-id",
            title: "Follow up",
            description: "Local description",
            dueAt: nil,
            priority: .high,
            accessToken: "todoist-token"
        )
        XCTAssertEqual(create.url?.path, "/api/v1/tasks")
        let createBody = try XCTUnwrap(create.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(createBody["section_id"] as? String, "section-id")
        XCTAssertNil(createBody["project_id"])
        XCTAssertEqual(createBody["priority"] as? Int, 4)
        let move = try TodoistAPI.moveTaskRequest(
            id: "task-id",
            parentID: "section:destination-section",
            accessToken: "todoist-token"
        )
        XCTAssertEqual(move.url?.path, "/api/v1/tasks/task-id/move")
        XCTAssertEqual(move.httpMethod, "POST")
        let moveBody = try XCTUnwrap(move.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        XCTAssertEqual(moveBody["section_id"] as? String, "destination-section")
        XCTAssertNil(moveBody["project_id"])
        let completion = TodoistAPI.completionRequest(id: "task-id", completed: true, accessToken: "todoist-token")
        XCTAssertEqual(completion.url?.path, "/api/v1/tasks/task-id/close")
        XCTAssertEqual(completion.httpMethod, "POST")
        XCTAssertEqual(completion.value(forHTTPHeaderField: "Authorization"), "Bearer todoist-token")
        let sections = TodoistAPI.sectionsRequest(
            accessToken: "todoist-token",
            cursor: "section-cursor"
        )
        XCTAssertEqual(sections.url?.path, "/api/v1/sections")
        XCTAssertEqual(
            URLComponents(url: sections.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first?.value,
            "section-cursor"
        )
        let completed = TodoistAPI.completedTasksRequest(
            parentID: "section:section-id",
            since: Date(timeIntervalSince1970: 0),
            until: Date(timeIntervalSince1970: 3_600),
            accessToken: "todoist-token"
        )
        let completedItems = URLComponents(
            url: completed.url!,
            resolvingAgainstBaseURL: false
        )?.queryItems
        XCTAssertEqual(completed.url?.path, "/api/v1/tasks/completed/by_completion_date")
        XCTAssertEqual(
            completedItems?.first(where: { $0.name == "section_id" })?.value,
            "section-id"
        )
    }

    func testMicrosoftToDoDeltaKeepsOpaqueCursorAndUsesETagOnWrite() throws {
        let initial = MicrosoftToDoAPI.deltaRequest(
            listID: "list-id",
            deltaLink: nil,
            accessToken: "graph-token"
        )
        XCTAssertEqual(initial.url?.path, "/v1.0/me/todo/lists/list-id/tasks/delta")
        let opaque = try XCTUnwrap(URL(string: "https://graph.microsoft.com/v1.0/me/todo/lists/list-id/tasks/delta?$deltatoken=opaque%2Fcursor"))
        let next = MicrosoftToDoAPI.deltaRequest(listID: "ignored", deltaLink: opaque, accessToken: "graph-token")
        XCTAssertEqual(next.url, opaque)
        var patch = RemoteTaskPatch(
            title: "Graph task",
            notes: nil,
            dueAt: nil,
            reminderAt: nil,
            isCompleted: true,
            priority: .high
        )
        let reminderAt = date(2026, 7, 20, 8, 30)
        patch.reminderAt = .some(reminderAt)
        let update = try MicrosoftToDoAPI.updateTaskRequest(
            listID: "list-id", taskID: "task-id",
            patch: patch,
            expectedVersion: "W/\"etag\"", accessToken: "graph-token"
        )
        XCTAssertEqual(update.value(forHTTPHeaderField: "If-Match"), "W/\"etag\"")
        XCTAssertEqual(update.httpMethod, "PATCH")
        let updateBody = try XCTUnwrap(update.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        XCTAssertEqual(updateBody["importance"] as? String, "high")
        XCTAssertEqual(updateBody["isReminderOn"] as? Bool, true)
        XCTAssertNotNil(updateBody["reminderDateTime"] as? [String: String])
        patch.reminderAt = .some(nil)
        let clearReminder = try MicrosoftToDoAPI.updateTaskRequest(
            listID: "list-id",
            taskID: "task-id",
            patch: patch,
            expectedVersion: "W/\"etag\"",
            accessToken: "graph-token"
        )
        let clearBody = try XCTUnwrap(clearReminder.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        XCTAssertEqual(clearBody["isReminderOn"] as? Bool, false)
        XCTAssertTrue(clearBody["reminderDateTime"] is NSNull)
        let listNext = try XCTUnwrap(URL(string: "https://graph.microsoft.com/v1.0/me/todo/lists?$skiptoken=opaque"))
        XCTAssertEqual(
            MicrosoftToDoAPI.listsRequest(
                accessToken: "graph-token",
                nextLink: listNext
            ).url,
            listNext
        )
    }

    @MainActor
    func testProvidersFollowAllListPagesAndExposeTodoistSections() async throws {
        let googleCredential = OAuthCredential(
            provider: .googleTasks, accessToken: "google", refreshToken: nil,
            expiresAt: nil, accountKey: "google-sub", displayName: "Google", scopes: []
        )
        let googleTransport = URLStubOAuthTransport(responses: [
            "https://tasks.googleapis.com/tasks/v1/users/@me/lists": Self.httpResponse(
                host: "tasks.googleapis.com",
                json: #"{"items":[{"id":"g1","title":"First"}],"nextPageToken":"second"}"#
            ),
            "https://tasks.googleapis.com/tasks/v1/users/@me/lists?pageToken=second": Self.httpResponse(
                host: "tasks.googleapis.com",
                json: #"{"items":[{"id":"g2","title":"Second"}]}"#
            )
        ])
        let google = GoogleTasksProvider(
            session: OAuthTaskProviderSession(
                configuration: try Self.oauthConfiguration(.googleTasks),
                credentials: InMemoryOAuthCredentialStore([.googleTasks: googleCredential]),
                transport: googleTransport
            ), accountKey: googleCredential.accountKey, displayName: googleCredential.displayName
        )
        let googleLists = try await google.listTaskLists()
        XCTAssertEqual(googleLists.map { $0.id }, ["g1", "g2"])

        let todoistCredential = OAuthCredential(
            provider: .todoist, accessToken: "todoist", refreshToken: nil,
            expiresAt: nil, accountKey: "todoist-id", displayName: "Todoist", scopes: []
        )
        let todoistTransport = URLStubOAuthTransport(responses: [
            "https://api.todoist.com/api/v1/projects": Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"results":[{"id":"p1","name":"Inbox"}],"next_cursor":"project-next"}"#
            ),
            "https://api.todoist.com/api/v1/projects?cursor=project-next": Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"results":[{"id":"p2","name":"Work"}],"next_cursor":null}"#
            ),
            "https://api.todoist.com/api/v1/sections": Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"results":[{"id":"s1","project_id":"p2","name":"Today"}],"next_cursor":null}"#
            )
        ])
        let todoist = TodoistTasksProvider(
            session: OAuthTaskProviderSession(
                configuration: try Self.oauthConfiguration(.todoist),
                credentials: InMemoryOAuthCredentialStore([.todoist: todoistCredential]),
                transport: todoistTransport
            ), accountKey: todoistCredential.accountKey, displayName: todoistCredential.displayName
        )
        let todoistLists = try await todoist.listTaskLists()
        XCTAssertEqual(todoistLists.map { $0.id }, ["project:p1", "project:p2", "section:s1"])
    }

    @MainActor
    func testGoogleProviderFollowsTaskPagesAndPreservesDateOnlyCompletion() async throws {
        let credential = OAuthCredential(
            provider: .googleTasks, accessToken: "google", refreshToken: nil,
            expiresAt: nil, accountKey: "google-sub", displayName: "Google",
            scopes: ["openid", "https://www.googleapis.com/auth/tasks"]
        )
        let firstURL = GoogleTasksAPI.tasksRequest(
            listID: "list",
            accessToken: credential.accessToken
        ).url!.absoluteString
        let secondURL = GoogleTasksAPI.tasksRequest(
            listID: "list",
            pageToken: "next-page",
            accessToken: credential.accessToken
        ).url!.absoluteString
        let transport = URLStubOAuthTransport(responses: [
            firstURL: Self.httpResponse(
                host: "tasks.googleapis.com",
                json: #"{"items":[{"id":"open","title":"Open","notes":"Keep transient","due":"2026-03-08T00:00:00.000Z","status":"needsAction","etag":"one"}],"nextPageToken":"next-page"}"#
            ),
            secondURL: Self.httpResponse(
                host: "tasks.googleapis.com",
                json: #"{"items":[{"id":"done","title":"Done","status":"completed","etag":"two"}]}"#
            )
        ])
        let provider = GoogleTasksProvider(
            session: OAuthTaskProviderSession(
                configuration: try Self.oauthConfiguration(.googleTasks),
                credentials: InMemoryOAuthCredentialStore([
                    .googleTasks: credential
                ]),
                transport: transport
            ),
            accountKey: credential.accountKey,
            displayName: credential.displayName
        )
        let list = RemoteTaskList(
            provider: .googleTasks,
            id: "list",
            accountKey: credential.accountKey,
            title: "Test",
            sourceTitle: credential.displayName,
            isWritable: true
        )

        let tasks = try await provider.listTasks(in: [list])

        XCTAssertEqual(tasks.map(\.id), ["open", "done"])
        XCTAssertEqual(tasks.map(\.isCompleted), [false, true])
        XCTAssertEqual(tasks.first?.notes, "Keep transient")
        let due = try XCTUnwrap(tasks.first?.dueAt)
        let dueComponents = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day],
            from: due
        )
        XCTAssertEqual(dueComponents.year, 2026)
        XCTAssertEqual(dueComponents.month, 3)
        XCTAssertEqual(dueComponents.day, 8)
    }

    @MainActor
    func testTodoistLookupTreatsRecentRemoteCompletionAsCompletedNotMissing() async throws {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let credential = OAuthCredential(
            provider: .todoist, accessToken: "todoist", refreshToken: nil,
            expiresAt: nil, accountKey: "todoist-id", displayName: "Todoist", scopes: []
        )
        let activeURL = TodoistAPI.taskRequest(id: "done", accessToken: "todoist")
            .url!.absoluteString
        let completedURL = TodoistAPI.completedTasksRequest(
            parentID: "project:p1",
            since: Calendar(identifier: .gregorian).date(
                byAdding: .day, value: -90, to: now
            )!,
            until: now,
            accessToken: "todoist"
        ).url!.absoluteString
        let transport = URLStubOAuthTransport(responses: [
            activeURL: Self.httpResponse(
                host: "api.todoist.com", json: "{}", statusCode: 404
            ),
            completedURL: Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"items":[{"id":"done","content":"Done remotely","description":"","project_id":"p1","completed_at":"2026-07-14T00:00:00Z","updated_at":"2026-07-14T00:00:00Z"}],"next_cursor":null}"#
            )
        ])
        let provider = TodoistTasksProvider(
            session: OAuthTaskProviderSession(
                configuration: try Self.oauthConfiguration(.todoist),
                credentials: InMemoryOAuthCredentialStore([.todoist: credential]),
                transport: transport
            ),
            accountKey: credential.accountKey,
            displayName: credential.displayName,
            now: { now }
        )

        let task = try await provider.lookupTask(id: "done", parentID: "project:p1")

        XCTAssertEqual(task?.title, "Done remotely")
        XCTAssertTrue(task?.isCompleted == true)
    }

    @MainActor
    func testTodoistEditThenCompletionReturnsLatestCompletedSnapshot() async throws {
        let credential = OAuthCredential(
            provider: .todoist, accessToken: "todoist", refreshToken: nil,
            expiresAt: nil, accountKey: "todoist-id", displayName: "Todoist", scopes: []
        )
        let transport = QueuedOAuthTransport(responses: [
            Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"id":"task","content":"Edited first","description":"Notes","project_id":"p1","completed_at":null,"updated_at":"v2","priority":4}"#
            ),
            Self.httpResponse(host: "api.todoist.com", json: "{}", statusCode: 204),
            Self.httpResponse(host: "api.todoist.com", json: "{}", statusCode: 404),
            Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"items":[{"id":"task","content":"Edited first","description":"Notes","project_id":"p1","completed_at":"2026-07-20T05:00:00Z","updated_at":"v3","priority":4}],"next_cursor":null}"#
            )
        ])
        let provider = TodoistTasksProvider(
            session: OAuthTaskProviderSession(
                configuration: try Self.oauthConfiguration(.todoist),
                credentials: InMemoryOAuthCredentialStore([.todoist: credential]),
                transport: transport
            ),
            accountKey: credential.accountKey,
            displayName: credential.displayName,
            now: { Date(timeIntervalSince1970: 1_753_000_000) }
        )
        let baseline = RemoteTaskSnapshot(
            id: "task", parentID: "project:p1",
            parentAccountKey: credential.accountKey,
            title: "Before", notes: "", dueAt: nil,
            isCompleted: false, version: "v1", deepLink: nil
        )
        var patch = RemoteTaskPatch()
        patch.title = "Edited first"
        patch.notes = "Notes"
        patch.isCompleted = true
        patch.priority = .high

        let result = try await provider.updateTask(baseline, with: patch)

        XCTAssertEqual(result.title, "Edited first")
        XCTAssertTrue(result.isCompleted)
        XCTAssertEqual(result.version, "v3")
        XCTAssertEqual(
            transport.requestedPaths,
            [
                "/api/v1/tasks/task",
                "/api/v1/tasks/task/close",
                "/api/v1/tasks/task",
                "/api/v1/tasks/completed/by_completion_date"
            ]
        )
    }

    @MainActor
    func testTodoistListProjectionIncludesRecentCompletedTasks() async throws {
        let credential = OAuthCredential(
            provider: .todoist, accessToken: "todoist", refreshToken: nil,
            expiresAt: nil, accountKey: "todoist-id", displayName: "Todoist", scopes: []
        )
        let transport = QueuedOAuthTransport(responses: [
            Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"results":[{"id":"open","content":"Open","description":"","project_id":"p1","completed_at":null,"updated_at":"open-v1"}],"next_cursor":null}"#
            ),
            Self.httpResponse(
                host: "api.todoist.com",
                json: #"{"items":[{"id":"done","content":"Done","description":"","project_id":"p1","completed_at":"2026-07-20T05:00:00Z","updated_at":"done-v1"}],"next_cursor":null}"#
            )
        ])
        let provider = TodoistTasksProvider(
            session: OAuthTaskProviderSession(
                configuration: try Self.oauthConfiguration(.todoist),
                credentials: InMemoryOAuthCredentialStore([.todoist: credential]),
                transport: transport
            ),
            accountKey: credential.accountKey,
            displayName: credential.displayName,
            now: { Date(timeIntervalSince1970: 1_753_000_000) }
        )
        let list = RemoteTaskList(
            provider: .todoist, id: "project:p1",
            accountKey: credential.accountKey, title: "Inbox",
            sourceTitle: credential.displayName, isWritable: true
        )

        let tasks = try await provider.listTasks(in: [list])

        XCTAssertEqual(tasks.map(\.id), ["open", "done"])
        XCTAssertEqual(tasks.map(\.isCompleted), [false, true])
    }

    func testOAuthConnectionDerivesGoogleSubjectBeforeSavingCredential() async throws {
        let configuration = OAuthProviderConfiguration(
            provider: .googleTasks,
            clientID: "client-id",
            redirectURI: try XCTUnwrap(URL(string: "http://127.0.0.1:43891/oauth/callback"))
        )
        let credentialStore = InMemoryOAuthCredentialStore()
        let transport = StubOAuthTransport(responses: [
            "oauth2.googleapis.com": Self.httpResponse(
                host: "oauth2.googleapis.com",
                json: """
                {"access_token":"access","refresh_token":"refresh","expires_in":3600,"scope":"openid email profile https://www.googleapis.com/auth/tasks"}
                """
            ),
            "openidconnect.googleapis.com": Self.httpResponse(
                host: "openidconnect.googleapis.com",
                json: """
                {"sub":"google-subject","name":"Google User","email":"person@example.invalid"}
                """
            )
        ])

        let credential = try await OAuthProviderConnection.connect(
            configuration: configuration,
            code: "code",
            pkce: OAuthPKCEChallenge.make(verifier: String(repeating: "a", count: 64)),
            credentials: credentialStore,
            transport: transport,
            now: { self.date(2026, 7, 14, 9) }
        )

        XCTAssertEqual(credential.accountKey, "google-subject")
        XCTAssertEqual(credential.displayName, "Google User")
        XCTAssertEqual(
            try credentialStore.loadCredential(for: .googleTasks),
            credential
        )
    }

    func testGoogleOAuthConnectionRejectsMissingTaskScopeBeforeSaving() async throws {
        let configuration = OAuthProviderConfiguration(
            provider: .googleTasks,
            clientID: "client-id",
            redirectURI: try XCTUnwrap(
                URL(string: "http://127.0.0.1:43891")
            )
        )
        let credentialStore = InMemoryOAuthCredentialStore()
        let transport = StubOAuthTransport(responses: [
            "oauth2.googleapis.com": Self.httpResponse(
                host: "oauth2.googleapis.com",
                json: """
                {"access_token":"access","refresh_token":"refresh","expires_in":3600,"scope":"openid email profile"}
                """
            )
        ])

        do {
            _ = try await OAuthProviderConnection.connect(
                configuration: configuration,
                code: "code",
                pkce: OAuthPKCEChallenge.make(
                    verifier: String(repeating: "a", count: 64)
                ),
                credentials: credentialStore,
                transport: transport
            )
            XCTFail("Expected missing Google Tasks scope to reject connection")
        } catch {
            XCTAssertEqual(
                error as? OAuthGrantedScopeError,
                .missingRequiredScopes([
                    "https://www.googleapis.com/auth/tasks"
                ])
            )
        }
        XCTAssertNil(
            try credentialStore.loadCredential(for: .googleTasks)
        )
    }

    func testGoogleOAuthConnectionRejectsMissingOpenIDScopeBeforeSaving() async throws {
        let configuration = OAuthProviderConfiguration(
            provider: .googleTasks,
            clientID: "client-id",
            redirectURI: try XCTUnwrap(URL(string: "http://127.0.0.1:43891"))
        )
        let credentialStore = InMemoryOAuthCredentialStore()
        let transport = StubOAuthTransport(responses: [
            "oauth2.googleapis.com": Self.httpResponse(
                host: "oauth2.googleapis.com",
                json: """
                {"access_token":"access","refresh_token":"refresh","expires_in":3600,"scope":"https://www.googleapis.com/auth/tasks"}
                """
            )
        ])

        do {
            _ = try await OAuthProviderConnection.connect(
                configuration: configuration,
                code: "code",
                pkce: OAuthPKCEChallenge.make(
                    verifier: String(repeating: "a", count: 64)
                ),
                credentials: credentialStore,
                transport: transport
            )
            XCTFail("Expected missing OpenID scope to reject connection")
        } catch {
            XCTAssertEqual(
                error as? OAuthGrantedScopeError,
                .missingRequiredScopes(["openid"])
            )
        }
        XCTAssertNil(try credentialStore.loadCredential(for: .googleTasks))
    }

    func testOAuthConnectionUsesMicrosoftGraphIdentityForAccountKey() async throws {
        let tenantID = "11111111-2222-3333-4444-555555555555"
        let graphObjectID = "FFFFFFFF-1111-4222-8333-444444444444"
        let configuration = OAuthProviderConfiguration(
            provider: .microsoftToDo,
            clientID: "microsoft-public-client",
            redirectURI: try XCTUnwrap(
                URL(string: "http://localhost:43891/oauth/callback")
            )
        )
        let credentialStore = InMemoryOAuthCredentialStore()
        let payload = Data(
            """
            {"tid":"\(tenantID)","oid":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","name":"Token Name"}
            """.utf8
        ).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let idToken = "header.\(payload).signature"
        let transport = StubOAuthTransport(responses: [
            "login.microsoftonline.com": Self.httpResponse(
                host: "login.microsoftonline.com",
                json: """
                {"access_token":"access","refresh_token":"refresh","expires_in":3600,"scope":"openid profile offline_access User.Read Tasks.ReadWrite","id_token":"\(idToken)"}
                """
            ),
            "graph.microsoft.com": Self.httpResponse(
                host: "graph.microsoft.com",
                json: """
                {"id":"\(graphObjectID)","displayName":"Microsoft User","userPrincipalName":"person@example.invalid"}
                """
            )
        ])

        let credential = try await OAuthProviderConnection.connect(
            configuration: configuration,
            code: "code",
            pkce: OAuthPKCEChallenge.make(
                verifier: String(repeating: "m", count: 64)
            ),
            credentials: credentialStore,
            transport: transport
        )

        XCTAssertEqual(
            credential.accountKey,
            "\(tenantID):\(graphObjectID.lowercased())"
        )
        XCTAssertEqual(credential.displayName, "Microsoft User")
        XCTAssertEqual(
            try credentialStore.loadCredential(for: .microsoftToDo),
            credential
        )
    }

    func testOAuthConnectionRejectsInvalidMicrosoftGraphIdentity() async throws {
        let configuration = OAuthProviderConfiguration(
            provider: .microsoftToDo,
            clientID: "microsoft-public-client",
            redirectURI: try XCTUnwrap(
                URL(string: "http://localhost:43891/oauth/callback")
            )
        )
        let credentialStore = InMemoryOAuthCredentialStore()
        let payload = Data(
            #"{"tid":"11111111-2222-3333-4444-555555555555","name":"Token Name"}"#.utf8
        ).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let idToken = "header.\(payload).signature"
        let transport = StubOAuthTransport(responses: [
            "login.microsoftonline.com": Self.httpResponse(
                host: "login.microsoftonline.com",
                json: """
                {"access_token":"access","refresh_token":"refresh","expires_in":3600,"scope":"openid profile offline_access User.Read Tasks.ReadWrite","id_token":"\(idToken)"}
                """
            ),
            "graph.microsoft.com": Self.httpResponse(
                host: "graph.microsoft.com",
                json: """
                {"id":"not-a-guid","displayName":"Microsoft User","userPrincipalName":"person@example.invalid"}
                """
            )
        ])

        do {
            _ = try await OAuthProviderConnection.connect(
                configuration: configuration,
                code: "code",
                pkce: OAuthPKCEChallenge.make(
                    verifier: String(repeating: "m", count: 64)
                ),
                credentials: credentialStore,
                transport: transport
            )
            XCTFail("Expected an invalid Microsoft Graph identity to reject connection")
        } catch {
            XCTAssertEqual(
                error as? TaskProviderError,
                .providerFailure(
                    "Microsoft did not return a valid Graph account identity required to connect To Do."
                )
            )
        }
        XCTAssertNil(try credentialStore.loadCredential(for: .microsoftToDo))
    }

    func testOAuthSessionRefreshesOnceAfterUnexpected401ThenReplaysRequest() async throws {
        let credential = OAuthCredential(
            provider: .googleTasks,
            accessToken: "old-access",
            refreshToken: "refresh-token",
            expiresAt: Date.distantFuture,
            accountKey: "subject",
            displayName: "Google",
            scopes: []
        )
        let credentialStore = InMemoryOAuthCredentialStore([.googleTasks: credential])
        let transport = QueuedOAuthTransport(responses: [
            Self.httpResponse(host: "service.invalid", json: "{}", statusCode: 401),
            Self.httpResponse(
                host: "oauth2.googleapis.com",
                json: #"{"access_token":"new-access","refresh_token":"rotated","expires_in":3600}"#
            ),
            Self.httpResponse(host: "service.invalid", json: #"{"ok":true}"#)
        ])
        let session = OAuthTaskProviderSession(
            configuration: try Self.oauthConfiguration(.googleTasks),
            credentials: credentialStore,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_752_000_000) }
        )

        let (_, response) = try await session.send { token in
            var request = URLRequest(url: URL(string: "https://service.invalid/task")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(
            try credentialStore.loadCredential(for: .googleTasks)?.accessToken,
            "new-access"
        )
        XCTAssertEqual(transport.requestCount, 3)
    }

    func testOAuthSessionMapsProviderFailuresWithoutAutomaticWriteFallback() async throws {
        let cases: [(Int, TaskProviderError)] = [
            (401, .authorizationRequired),
            (403, .accessDenied),
            (404, .taskNotFound),
            (412, .conflict),
            (429, .providerFailure(
                "The task provider is rate limiting requests."
            ))
        ]

        for (statusCode, expectedError) in cases {
            let credential = OAuthCredential(
                provider: .googleTasks,
                accessToken: "access",
                refreshToken: nil,
                expiresAt: nil,
                accountKey: "subject",
                displayName: "Google",
                scopes: ["openid", "https://www.googleapis.com/auth/tasks"]
            )
            let credentialStore = InMemoryOAuthCredentialStore([
                .googleTasks: credential
            ])
            let transport = QueuedOAuthTransport(responses: [
                Self.httpResponse(
                    host: "tasks.googleapis.com",
                    json: "{}",
                    statusCode: statusCode
                )
            ])
            let session = OAuthTaskProviderSession(
                configuration: try Self.oauthConfiguration(.googleTasks),
                credentials: credentialStore,
                transport: transport
            )

            do {
                _ = try await session.send { token in
                    GoogleTasksAPI.deleteTaskRequest(
                        listID: "list",
                        taskID: "task",
                        expectedETag: "etag",
                        accessToken: token
                    )
                }
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch {
                XCTAssertEqual(error as? TaskProviderError, expectedError)
            }
            XCTAssertEqual(transport.requestCount, 1)
            if statusCode == 401 {
                XCTAssertNil(
                    try credentialStore.loadCredential(for: .googleTasks)
                )
            } else {
                XCTAssertNotNil(
                    try credentialStore.loadCredential(for: .googleTasks)
                )
            }
        }
    }

    func testOAuthSessionTreatsRevokedRefreshTokenAsReconnectRequired() async throws {
        let credential = OAuthCredential(
            provider: .googleTasks,
            accessToken: "revoked-access",
            refreshToken: "revoked-refresh",
            expiresAt: Date.distantFuture,
            accountKey: "subject",
            displayName: "Google",
            scopes: ["openid", "https://www.googleapis.com/auth/tasks"]
        )
        let credentialStore = InMemoryOAuthCredentialStore([
            .googleTasks: credential
        ])
        let transport = QueuedOAuthTransport(responses: [
            Self.httpResponse(
                host: "tasks.googleapis.com",
                json: "{}",
                statusCode: 401
            ),
            Self.httpResponse(
                host: "oauth2.googleapis.com",
                json: #"{"error":"invalid_grant"}"#,
                statusCode: 400
            )
        ])
        let session = OAuthTaskProviderSession(
            configuration: try Self.oauthConfiguration(.googleTasks),
            credentials: credentialStore,
            transport: transport
        )

        do {
            _ = try await session.send { token in
                GoogleTasksAPI.taskListsRequest(accessToken: token)
            }
            XCTFail("Expected revoked refresh token to require reconnection")
        } catch {
            XCTAssertEqual(
                error as? TaskProviderError,
                .authorizationRequired
            )
        }
        XCTAssertNil(try credentialStore.loadCredential(for: .googleTasks))
        XCTAssertEqual(session.authorizationState, .notDetermined)
        XCTAssertEqual(transport.requestCount, 2)
    }

    @MainActor
    func testRevokedGoogleProviderPreservesLocalTaskAndMarksReconnectRequired() async throws {
        let harness = try makeHarness()
        let eventTask = try harness.store.appendEventTask(
            for: makeEvent(id: "google-revoked-grant"),
            section: .before,
            title: "Keep local after revoke"
        )
        let list = RemoteTaskList(
            provider: .googleTasks,
            id: "list",
            accountKey: "google-subject",
            title: "KaosCal Test",
            sourceTitle: "Google",
            isWritable: true
        )
        let remote = RemoteTaskSnapshot(
            id: "remote-task",
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: eventTask.title,
            notes: "",
            dueAt: nil,
            isCompleted: false,
            version: "etag",
            deepLink: nil
        )
        let account = try harness.store.taskProviders.upsertAccount(
            provider: .googleTasks,
            accountKey: list.accountKey,
            displayName: list.sourceTitle,
            authorizationState: .authorized
        )
        _ = try harness.store.taskProviders.insertLinkedTask(
            account: account,
            remote: remote,
            eventTaskID: eventTask.id,
            occurrenceKey: nil,
            syncHash: "sync-hash"
        )
        let google = StubAsyncTaskProvider(
            provider: .googleTasks,
            lists: [list],
            tasks: [remote]
        )
        google.listTaskListsError = .authorizationRequired
        let coordinator = TaskProviderCoordinator(
            contextStore: harness.store,
            provider: StubAppleTaskListingProvider(lists: [], tasks: []),
            oauthCredentials: InMemoryOAuthCredentialStore(),
            asyncProviders: [.googleTasks: google]
        )

        for _ in 0..<100 {
            let state = try harness.store.taskProviders
                .fetchAccount(id: account.id)?.authorizationState
            if state == .notDetermined { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(
            coordinator.authorizationState(for: .googleTasks),
            .notDetermined
        )
        XCTAssertEqual(
            try harness.store.taskProviders.fetchAccount(id: account.id)?
                .authorizationState,
            .notDetermined
        )
        XCTAssertEqual(
            try harness.store.taskProviders.fetchBinding(
                eventTaskID: eventTask.id
            )?.syncState,
            .disconnected
        )
        XCTAssertNotNil(try harness.store.eventTasks.fetch(id: eventTask.id))
    }

    @MainActor
    func testMicrosoftProviderAppliesDeltaTombstonesAndOpaqueCursor() async throws {
        let credential = OAuthCredential(
            provider: .microsoftToDo,
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: nil,
            accountKey: "tenant:object",
            displayName: "Microsoft User",
            scopes: ["Tasks.ReadWrite"]
        )
        let credentialStore = InMemoryOAuthCredentialStore([.microsoftToDo: credential])
        let cursor = "https://graph.microsoft.com/v1.0/me/todo/lists/list/tasks/delta?$deltatoken=opaque%2Fvalue"
        let transport = StubOAuthTransport(responses: [
            "graph.microsoft.com": Self.httpResponse(
                host: "graph.microsoft.com",
                json: """
                {
                  "@odata.deltaLink":"\(cursor)",
                  "value":[
                    {"id":"changed","title":"Updated","status":"completed","isReminderOn":true,"reminderDateTime":{"dateTime":"2026-07-20T08:30:00","timeZone":"UTC"},"@odata.etag":"W/\\\"etag\\\"","body":{"content":""}},
                    {"id":"deleted","@removed":{"reason":"deleted"}}
                  ]
                }
                """
            )
        ])
        let provider = MicrosoftToDoProvider(
            session: OAuthTaskProviderSession(
                configuration: OAuthProviderConfiguration(
                    provider: .microsoftToDo,
                    clientID: "client-id",
                    redirectURI: try XCTUnwrap(URL(string: "http://127.0.0.1:43891/oauth/callback"))
                ),
                credentials: credentialStore,
                transport: transport
            ),
            accountKey: credential.accountKey,
            displayName: credential.displayName
        )

        let delta = try await provider.fetchDelta(listID: "list", cursor: nil)

        XCTAssertEqual(delta.deletedTaskIDs, ["deleted"])
        XCTAssertEqual(delta.tasks.map(\.id), ["changed"])
        XCTAssertTrue(delta.tasks[0].isCompleted)
        XCTAssertEqual(
            delta.tasks[0].reminderAt,
            date(2026, 7, 20, 8, 30)
        )
        XCTAssertEqual(delta.cursor?.absoluteString, cursor)
    }

    func testChangeLogMigrationEnforcesChecksForeignKeysAndUndoUniqueness() throws {
        let database = try AppDatabase.inMemory()
        let timestamp = "2026-07-10 08:00:00.000"

        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "dangling", "missing", "moved", "single",
                        "{}", "{}", "unavailable", timestamp
                    ]
                )
            }
        )

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO event_contexts (
                        id, title_snapshot, lifecycle_status, notes,
                        created_at, updated_at
                    ) VALUES (?, ?, 'scheduled', '', ?, ?)
                    """,
                arguments: ["change-context", "Fixture", timestamp, timestamp]
            )
        }

        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "bad-type", "change-context", "unknown", "single",
                        "{}", "{}", "unavailable", timestamp
                    ]
                )
            }
        )
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "bad-undone", "change-context", "moved", "single",
                        "{}", "{}", "undone", timestamp
                    ]
                )
            }
        )
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "bad-restore", "change-context", "restored", "single",
                        "{}", "{}", "unavailable", timestamp
                    ]
                )
            }
        )

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO event_change_log (
                        id, context_id, change_type, scope,
                        before_payload, after_payload, undo_state,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "original-change", "change-context", "moved", "single",
                    "{}", "{}", "available", timestamp
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO event_change_log (
                        id, context_id, change_type, scope,
                        before_payload, after_payload, undo_state,
                        undo_of_change_id, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "restore", "change-context", "restored", "single",
                    "{}", "{}", "unavailable", "original-change", timestamp
                ]
            )
        }
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_change_log (
                            id, context_id, change_type, scope,
                            before_payload, after_payload, undo_state,
                            undo_of_change_id, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "duplicate-restore", "change-context", "restored",
                        "single", "{}", "{}", "unavailable",
                        "original-change", timestamp
                    ]
                )
            }
        )

        let indexNames = try database.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'index' AND tbl_name = 'event_change_log'
                    """
            )
        }
        XCTAssertTrue(indexNames.contains("event_change_log_context_created"))
        XCTAssertTrue(indexNames.contains("event_change_log_unique_undo"))
    }

    func testMigrationRejectsInvalidIdentityDueAndCompletionRows() throws {
        let database = try AppDatabase.inMemory()

        func insertContext(_ id: String) throws {
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO event_contexts (
                            id, title_snapshot, lifecycle_status, notes,
                            created_at, updated_at
                        ) VALUES (
                            ?, 'Fixture', 'scheduled', '',
                            '2026-07-10 08:00:00.000',
                            '2026-07-10 08:00:00.000'
                        )
                        """,
                    arguments: [id]
                )
            }
        }

        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_tasks (
                        id, context_id, section, title, completed,
                        sort_order, due_kind, created_at, updated_at
                    ) VALUES (
                        'dangling', 'missing', 'before', 'Dangling', 0,
                        0, 'none', '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )

        try insertContext("all-day-mismatch")
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_links (
                        id, context_id, calendar_identifier, source_title,
                        calendar_title_snapshot, title_snapshot,
                        start_snapshot, end_snapshot, is_all_day,
                        is_recurring, time_semantics, time_zone_identifier,
                        occurrence_identity_key, is_detached, fingerprint,
                        link_status, last_seen_at, created_at, updated_at
                    ) VALUES (
                        'bad-all-day-link', 'all-day-mismatch', 'calendar',
                        'Work', 'KAOS-TEST', 'Fixture',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 09:00:00.000', 1, 0, 'zoned', 'UTC',
                        'single:v1', 0, 'fingerprint', 'active',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )

        try insertContext("bad-occurrence")
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_links (
                        id, context_id, calendar_identifier, source_title,
                        calendar_title_snapshot, title_snapshot,
                        start_snapshot, end_snapshot, is_all_day,
                        is_recurring, time_semantics, time_zone_identifier,
                        occurrence_date, occurrence_identity_key,
                        is_detached, fingerprint, link_status,
                        last_seen_at, created_at, updated_at
                    ) VALUES (
                        'bad-occurrence-link', 'bad-occurrence', 'calendar',
                        'Work', 'KAOS-TEST', 'Fixture',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 09:00:00.000', 0, 0, 'zoned', 'UTC',
                        '2026-07-10 08:00:00.000', 'instant:v1:1',
                        0, 'fingerprint-2', 'active',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )

        try insertContext("task-context")
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO event_tasks (
                        id, context_id, section, title, completed,
                        sort_order, due_kind, relative_anchor,
                        offset_minutes, created_at, updated_at
                    ) VALUES (
                        'too-far', 'task-context', 'before', 'Too far', 0,
                        0, 'relative', 'before_start', 2628001,
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000'
                    )
                    """)
            }
        )
        XCTAssertThrowsError(
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO personal_tasks (
                        id, title, notes, completed, sort_order,
                        created_at, updated_at, completed_at
                    ) VALUES (
                        'bad-completion', 'Done?', '', 1, 0,
                        '2026-07-10 08:00:00.000',
                        '2026-07-10 08:00:00.000', NULL
                    )
                    """)
            }
        )

        let indexNames = try database.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'index' AND tbl_name = 'event_links'
                    """
            )
        }
        XCTAssertTrue(
            indexNames.contains("event_links_unique_event_occurrence")
        )
        XCTAssertTrue(
            indexNames.contains("event_links_series_occurrence")
        )
    }

    func testSelectionAndEmptyNotesDoNotCreateContext() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "event")

        XCTAssertEqual(try harness.store.resolve(event: event), .notFound)
        XCTAssertNil(try harness.store.saveNotes(for: event, notes: "  "))
        XCTAssertEqual(try harness.store.eventContexts.count(), 0)
    }

    func testLoadBriefIsLazyAndRequiresConfirmationForWeakMatch() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "brief",
            title: "Téam   Sync",
            location: "Room Ａ"
        )

        XCTAssertEqual(try harness.store.loadBrief(for: event), .empty)
        XCTAssertEqual(try harness.store.eventContexts.count(), 0)

        let context = try XCTUnwrap(
            harness.store.saveNotes(for: event, notes: "Local brief")
        )
        guard case let .loaded(snapshot, basis) = try harness.store.loadBrief(
            for: event
        ) else {
            return XCTFail("Expected a linked brief")
        }
        XCTAssertEqual(basis, .eventIdentifier)
        XCTAssertEqual(snapshot.context.id, context.id)
        XCTAssertEqual(snapshot.context.notes, "Local brief")

        let weakCandidate = makeEvent(
            id: "weak-brief",
            title: " team sync ",
            location: "room a",
            includeIdentifiers: false
        )
        XCTAssertEqual(
            try harness.store.loadBrief(for: weakCandidate),
            .confirmationRequired(
                contextIDs: [context.id],
                basis: .fingerprint
            )
        )
        XCTAssertEqual(try harness.store.eventContexts.count(), 1)
        XCTAssertEqual(
            try harness.store.eventContexts.fetch(id: context.id)?.titleSnapshot,
            event.title
        )
    }

    func testLegacySyntheticSingleBriefNormalizesWithoutDataLoss() throws {
        let harness = try makeHarness()
        let legacyEvent = makeEvent(
            id: "legacy-single",
            externalIdentifier: "legacy-single-external",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: legacyEvent, notes: "Keep this brief")
        )
        let task = try harness.store.appendEventTask(
            for: legacyEvent,
            section: .before,
            title: "Keep this task"
        )
        let correctedSingle = makeEvent(
            id: "legacy-single",
            externalIdentifier: "legacy-single-external"
        )

        guard case let .loaded(snapshot, basis) = try harness.store.loadBrief(
            for: correctedSingle
        ) else {
            return XCTFail("Expected the legacy single brief to normalize")
        }
        XCTAssertEqual(basis, .eventIdentifier)
        XCTAssertEqual(snapshot.context.id, context.id)
        XCTAssertEqual(snapshot.context.notes, "Keep this brief")
        XCTAssertEqual(snapshot.tasks.map(\.id), [task.id])
        XCTAssertFalse(snapshot.link.isRecurring)
        XCTAssertNil(snapshot.link.occurrenceDate)
        XCTAssertNil(snapshot.link.occurrenceLocalComponents)
        XCTAssertEqual(snapshot.link.occurrenceIdentityKey, "single:v1")
        XCTAssertNil(snapshot.link.recurrenceSeriesIdentifier)
        XCTAssertNil(snapshot.link.seriesFingerprint)
    }

    func testLegacySyntheticSingleNavigationStaysReadOnlyUntilLoad() throws {
        let harness = try makeHarness()
        let legacyEvent = makeEvent(
            id: "legacy-navigation",
            externalIdentifier: "legacy-navigation-external",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: legacyEvent, notes: "Navigate")
        )
        let correctedSingle = makeEvent(
            id: "legacy-navigation",
            externalIdentifier: "legacy-navigation-external"
        )

        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: context.id,
                among: [correctedSingle]
            ),
            .linked(event: correctedSingle, basis: .eventIdentifier)
        )
        XCTAssertTrue(try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        ).link.isRecurring)

        guard case .loaded = try harness.store.loadBrief(
            for: correctedSingle
        ) else {
            return XCTFail("Expected load to normalize the legacy link")
        }
        XCTAssertFalse(try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        ).link.isRecurring)
    }

    func testLegacySyntheticSingleSnapshotDriftRequiresConfirmation() throws {
        let harness = try makeHarness()
        let legacyEvent = makeEvent(
            id: "legacy-mismatch",
            externalIdentifier: "legacy-mismatch-external",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: legacyEvent, notes: "Do not move")
        )
        let changedSingle = makeEvent(
            id: "legacy-mismatch",
            title: "Changed outside KaosCal",
            start: date(2026, 7, 10, 11),
            end: date(2026, 7, 10, 12),
            externalIdentifier: "legacy-mismatch-external"
        )

        XCTAssertEqual(
            try harness.store.loadBrief(for: changedSingle),
            .confirmationRequired(
                contextIDs: [context.id],
                basis: .legacySyntheticSingle
            )
        )
        XCTAssertTrue(try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        ).link.isRecurring)
        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: context.id,
                among: [changedSingle]
            ),
            .confirmationRequired(
                eventIDs: [changedSingle.id],
                basis: .legacySyntheticSingle
            )
        )
    }

    func testLegacySyntheticSingleWithoutIdentifiersRequiresConfirmation() throws {
        let harness = try makeHarness()
        let legacyEvent = makeEvent(
            id: "legacy-no-identifiers",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            includeIdentifiers: false
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: legacyEvent, notes: "Confirm me")
        )
        let correctedSingle = makeEvent(
            id: "legacy-no-identifiers",
            includeIdentifiers: false
        )

        XCTAssertEqual(
            try harness.store.loadBrief(for: correctedSingle),
            .confirmationRequired(
                contextIDs: [context.id],
                basis: .exactSnapshot
            )
        )
    }

    func testLegacySyntheticAllDaySingleUsesLocalAnchorNormalization() throws {
        let harness = try makeHarness()
        let start = localComponents(2026, 7, 10)
        let end = localComponents(2026, 7, 11)
        let semantics = EventTimeSemantics.allDay(
            start: start,
            endExclusive: end
        )
        let legacyEvent = makeEvent(
            id: "legacy-all-day",
            start: date(2026, 7, 10),
            end: date(2026, 7, 11),
            externalIdentifier: "legacy-all-day-external",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10),
            occurrenceLocalComponents: start,
            isAllDay: true,
            timeSemantics: semantics
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: legacyEvent, notes: "All day")
        )
        let correctedSingle = makeEvent(
            id: "legacy-all-day",
            start: date(2026, 7, 10),
            end: date(2026, 7, 11),
            externalIdentifier: "legacy-all-day-external",
            isAllDay: true,
            timeSemantics: semantics
        )

        guard case let .loaded(snapshot, _) = try harness.store.loadBrief(
            for: correctedSingle
        ) else {
            return XCTFail("Expected local-anchor legacy normalization")
        }
        XCTAssertEqual(snapshot.context.id, context.id)
        XCTAssertFalse(snapshot.link.isRecurring)
        XCTAssertEqual(snapshot.link.occurrenceIdentityKey, "single:v1")
    }

    func testFirstNotesCreateContextAndLinkTogether() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "event")

        let context = try XCTUnwrap(
            harness.store.saveNotes(for: event, notes: "Bring the brief")
        )
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertEqual(brief.context.notes, "Bring the brief")
        XCTAssertEqual(brief.link.eventIdentifier, "event-id-event")
        XCTAssertEqual(brief.link.calendarTitleSnapshot, "KAOS-TEST")
        XCTAssertTrue(brief.tasks.isEmpty)
        XCTAssertEqual(
            try harness.store.resolve(event: event),
            .linked(contextID: context.id, basis: .eventIdentifier)
        )
    }

    func testFirstEventTaskCreatesContextLinkAndTaskAtomically() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "event",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10)
        )

        let task = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Prepare slides",
            sortOrder: 0,
            due: .relative(anchor: .beforeStart, offsetMinutes: 30)
        )
        let contextID = try linkedContextID(
            harness.store.resolve(event: event)
        )
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: contextID)
        )
        let eventRange = brief.link.effectiveDateRange(calendar: testCalendar)

        XCTAssertEqual(try harness.store.eventContexts.count(), 1)
        XCTAssertEqual(try harness.store.eventTasks.count(), 1)
        XCTAssertEqual(
            task.effectiveDueDate(
                eventStart: eventRange.start,
                eventEnd: eventRange.end
            ),
            date(2026, 7, 10, 8, 30)
        )
    }

    func testFailedLinkInsertRollsBackNewContext() throws {
        let database = try AppDatabase.inMemory()
        let firstIDs = IDSequence(["context-1", "shared-link", "task-1"])
        let firstStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 8) },
            makeID: firstIDs.next
        )
        _ = try firstStore.addEventTask(
            for: makeEvent(id: "first"),
            section: .before,
            title: "First",
            sortOrder: 0
        )

        let secondIDs = IDSequence(["context-2", "shared-link", "task-2"])
        let secondStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 9) },
            makeID: secondIDs.next
        )

        XCTAssertThrowsError(
            try secondStore.addEventTask(
                for: makeEvent(id: "second"),
                section: .before,
                title: "Second",
                sortOrder: 0
            )
        )
        XCTAssertEqual(try secondStore.eventContexts.count(), 1)
        XCTAssertEqual(try secondStore.eventTasks.count(), 1)
        XCTAssertEqual(
            try secondStore.resolve(event: makeEvent(id: "second")),
            .candidate(
                contextIDs: ["context-1"],
                basis: .exactSnapshot
            )
        )
    }

    func testConcurrentFirstNoteAndTaskShareOneContext() throws {
        let database = try AppDatabase.inMemory()
        let noteIDs = IDSequence(["note-context", "note-link"])
        let taskIDs = IDSequence(["task-context", "task-link", "task"])
        let noteStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 8) },
            makeID: noteIDs.next
        )
        let taskStore = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 8) },
            makeID: taskIDs.next
        )
        let event = makeEvent(id: "concurrent")
        let errorLock = NSLock()
        var errors: [Error] = []

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                if index == 0 {
                    _ = try noteStore.saveNotes(
                        for: event,
                        notes: "Concurrent notes"
                    )
                } else {
                    _ = try taskStore.addEventTask(
                        for: event,
                        section: .before,
                        title: "Concurrent task",
                        sortOrder: 0
                    )
                }
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
        }

        XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors)")
        XCTAssertEqual(try noteStore.eventContexts.count(), 1)
        XCTAssertEqual(try noteStore.eventTasks.count(), 1)
        let contextID = try linkedContextID(noteStore.resolve(event: event))
        let brief = try XCTUnwrap(
            noteStore.eventContexts.fetchBrief(contextID: contextID)
        )
        XCTAssertEqual(brief.context.notes, "Concurrent notes")
        XCTAssertEqual(brief.tasks.map(\.title), ["Concurrent task"])
    }

    func testEventTaskOrderingUpdateCompletionAndDueValidation() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "ordered",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10)
        )
        let during = try harness.store.addEventTask(
            for: event,
            section: .during,
            title: "During",
            sortOrder: 0
        )
        let after = try harness.store.addEventTask(
            for: event,
            section: .after,
            title: "After",
            sortOrder: 0,
            due: .relative(anchor: .afterEnd, offsetMinutes: 15)
        )
        let before = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Before",
            sortOrder: 0
        )
        let contextID = try linkedContextID(
            harness.store.resolve(event: event)
        )

        XCTAssertEqual(
            try harness.store.eventTasks.fetch(contextID: contextID).map(\.id),
            [before.id, during.id, after.id]
        )
        let updated = try XCTUnwrap(
            harness.store.eventTasks.update(
                id: during.id,
                section: .before,
                title: "During moved",
                sortOrder: 1,
                due: .fixed(date(2026, 7, 10, 8, 45))
            )
        )
        XCTAssertEqual(updated.due, .fixed(date(2026, 7, 10, 8, 45)))
        let completed = try XCTUnwrap(
            harness.store.eventTasks.setCompleted(
                id: after.id,
                isCompleted: true
            )
        )
        XCTAssertTrue(completed.isCompleted)
        XCTAssertNotNil(completed.completedAt)

        XCTAssertThrowsError(
            try harness.store.eventTasks.create(
                contextID: contextID,
                section: .before,
                title: "Invalid",
                sortOrder: 2,
                due: .relative(anchor: .atStart, offsetMinutes: 5)
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidRelativeDue
            )
        }
        XCTAssertThrowsError(
            try harness.store.eventTasks.create(
                contextID: contextID,
                section: .before,
                title: "Too far away",
                sortOrder: 3,
                due: .relative(
                    anchor: .beforeStart,
                    offsetMinutes:
                        EventTaskDuePolicy.maximumOffsetMinutes + 1
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidRelativeDue
            )
        }
    }

    func testAppendEventTaskAllocatesSectionOrderInsideTransaction() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "append-order")

        let first = try harness.store.appendEventTask(
            for: event,
            section: .before,
            title: "First"
        )
        let second = try harness.store.appendEventTask(
            for: event,
            section: .before,
            title: "Second"
        )
        _ = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Explicit",
            sortOrder: 8
        )
        let afterExplicit = try harness.store.appendEventTask(
            for: event,
            section: .before,
            title: "After explicit"
        )
        let during = try harness.store.appendEventTask(
            for: event,
            section: .during,
            title: "During"
        )

        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(second.sortOrder, 1)
        XCTAssertEqual(afterExplicit.sortOrder, 9)
        XCTAssertEqual(during.sortOrder, 0)
    }

    func testContextScopedEventTaskMutationRejectsWrongContextAndMissingTask() throws {
        let harness = try makeHarness()
        let firstTask = try harness.store.appendEventTask(
            for: makeEvent(id: "scoped-first"),
            section: .before,
            title: "First"
        )
        let secondTask = try harness.store.appendEventTask(
            for: makeEvent(
                id: "scoped-second",
                title: "Other event",
                start: date(2026, 7, 10, 11),
                end: date(2026, 7, 10, 12)
            ),
            section: .after,
            title: "Second"
        )

        XCTAssertThrowsError(
            try harness.store.updateEventTask(
                contextID: secondTask.contextID,
                taskID: firstTask.id,
                section: .after,
                title: "Wrong mutation",
                sortOrder: 3,
                due: .none
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .eventTaskContextMismatch(
                    taskID: firstTask.id,
                    expectedContextID: secondTask.contextID
                )
            )
        }
        XCTAssertThrowsError(
            try harness.store.deleteEventTask(
                contextID: secondTask.contextID,
                taskID: firstTask.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .eventTaskContextMismatch(
                    taskID: firstTask.id,
                    expectedContextID: secondTask.contextID
                )
            )
        }
        XCTAssertThrowsError(
            try harness.store.setEventTaskCompleted(
                contextID: firstTask.contextID,
                taskID: "missing-task",
                isCompleted: true
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .missingEventTask("missing-task")
            )
        }

        let unchanged = try XCTUnwrap(
            harness.store.eventTasks.fetch(id: firstTask.id)
        )
        XCTAssertEqual(unchanged.title, "First")
        XCTAssertEqual(unchanged.section, .before)
        XCTAssertFalse(unchanged.isCompleted)
    }

    func testCompletionIsIdempotentForEventAndPersonalTasks() throws {
        var current = date(2026, 7, 10, 12)
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { current }
        )
        let eventTask = try store.appendEventTask(
            for: makeEvent(id: "idempotent"),
            section: .after,
            title: "Follow up"
        )
        let personalTask = try store.personalTasks.create(title: "Personal")

        current = date(2026, 7, 10, 13)
        let completedEvent = try store.setEventTaskCompleted(
            contextID: eventTask.contextID,
            taskID: eventTask.id,
            isCompleted: true
        )
        let completedPersonal = try store.setPersonalTaskCompleted(
            taskID: personalTask.id,
            isCompleted: true
        )

        current = date(2026, 7, 10, 14)
        let repeatedEvent = try store.setEventTaskCompleted(
            contextID: eventTask.contextID,
            taskID: eventTask.id,
            isCompleted: true
        )
        let repeatedPersonal = try store.setPersonalTaskCompleted(
            taskID: personalTask.id,
            isCompleted: true
        )

        XCTAssertEqual(repeatedEvent.completedAt, completedEvent.completedAt)
        XCTAssertEqual(repeatedEvent.updatedAt, completedEvent.updatedAt)
        XCTAssertEqual(
            repeatedPersonal.completedAt,
            completedPersonal.completedAt
        )
        XCTAssertEqual(
            repeatedPersonal.updatedAt,
            completedPersonal.updatedAt
        )
    }

    func testDeletingContextCascadesLinkAndEventTasks() throws {
        let harness = try makeHarness()
        let event = makeEvent(id: "cascade")
        _ = try harness.store.addEventTask(
            for: event,
            section: .after,
            title: "Follow up",
            sortOrder: 0
        )
        let contextID = try linkedContextID(
            harness.store.resolve(event: event)
        )

        try harness.store.eventContexts.delete(contextID: contextID)

        XCTAssertNil(
            try harness.store.eventContexts.fetchBrief(contextID: contextID)
        )
        XCTAssertEqual(try harness.store.eventTasks.count(), 0)
        XCTAssertEqual(try harness.store.resolve(event: event), .notFound)
    }

    func testPersonalTaskCRUDAndLists() throws {
        let harness = try makeHarness()
        let undated = try harness.store.personalTasks.create(
            title: "Inbox",
            sortOrder: 2
        )
        let today = try harness.store.personalTasks.create(
            title: "Today",
            dueAt: date(2026, 7, 10, 18),
            sortOrder: 1
        )
        let upcoming = try harness.store.personalTasks.create(
            title: "Upcoming",
            dueAt: date(2026, 7, 11),
            sortOrder: 0
        )

        XCTAssertEqual(
            try harness.store.personalTasks.fetch(
                list: .today,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [today.id, undated.id]
        )
        XCTAssertEqual(
            try harness.store.personalTasks.fetch(
                list: .upcoming,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [upcoming.id]
        )

        _ = try harness.store.personalTasks.update(
            id: undated.id,
            title: "Inbox edited",
            notes: "local only",
            dueAt: nil,
            sortOrder: 3
        )
        _ = try harness.store.personalTasks.setCompleted(
            id: today.id,
            isCompleted: true
        )
        XCTAssertEqual(
            try harness.store.personalTasks.fetch(
                list: .completed,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [today.id]
        )

        try harness.store.personalTasks.delete(id: upcoming.id)
        XCTAssertNil(try harness.store.personalTasks.fetch(id: upcoming.id))
    }

    func testTypedTaskCenterIdentityRoutesCollidingRawIDs() throws {
        let IDs = IDSequence([
            "event-context",
            "event-link",
            "shared-task-id",
            "shared-task-id"
        ])
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) },
            makeID: IDs.next
        )
        let eventTask = try store.appendEventTask(
            for: makeEvent(
                id: "typed-routing",
                start: date(2026, 7, 10, 15),
                end: date(2026, 7, 10, 16)
            ),
            section: .before,
            title: "Event task"
        )
        let personalTask = try store.personalTasks.create(
            title: "Personal task",
            dueAt: date(2026, 7, 10, 16)
        )

        XCTAssertEqual(eventTask.id, personalTask.id)
        let items = try store.taskCenter.fetch(
            list: .today,
            now: date(2026, 7, 10, 12),
            calendar: testCalendar
        )
        XCTAssertEqual(
            Set(items.map(\.id)),
            Set([
                .eventTask(
                    taskID: eventTask.id,
                    contextID: eventTask.contextID
                ),
                .personalTask(taskID: personalTask.id)
            ])
        )

        let personalResult = try store.setTaskCenterItemCompleted(
            id: .personalTask(taskID: personalTask.id),
            isCompleted: true
        )
        guard case let .personalTask(completedPersonal) = personalResult else {
            return XCTFail("Expected personal task completion")
        }
        XCTAssertTrue(completedPersonal.isCompleted)
        XCTAssertFalse(
            try XCTUnwrap(store.eventTasks.fetch(id: eventTask.id)).isCompleted
        )

        let eventResult = try store.setTaskCenterItemCompleted(
            id: .eventTask(
                taskID: eventTask.id,
                contextID: eventTask.contextID
            ),
            isCompleted: true
        )
        guard case let .eventTask(completedEvent) = eventResult else {
            return XCTFail("Expected event task completion")
        }
        XCTAssertTrue(completedEvent.isCompleted)
        XCTAssertTrue(
            try XCTUnwrap(
                store.personalTasks.fetch(id: personalTask.id)
            ).isCompleted
        )

        XCTAssertThrowsError(
            try store.setTaskCenterItemCompleted(
                id: .personalTask(taskID: "missing-personal"),
                isCompleted: true
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .missingPersonalTask("missing-personal")
            )
        }
    }

    func testTaskCenterCombinesEventAndPersonalTasksAtDayBoundary() throws {
        let harness = try makeHarness()
        let event = makeEvent(
            id: "center",
            start: date(2026, 7, 10, 15),
            end: date(2026, 7, 10, 16)
        )
        let eventTask = try harness.store.addEventTask(
            for: event,
            section: .before,
            title: "Event preparation",
            sortOrder: 0
        )
        let personalToday = try harness.store.personalTasks.create(
            title: "Personal today",
            dueAt: date(2026, 7, 10, 18),
            sortOrder: 1
        )
        let personalUpcoming = try harness.store.personalTasks.create(
            title: "Personal upcoming",
            dueAt: date(2026, 7, 11),
            sortOrder: 0
        )

        let today = try harness.store.taskCenter.fetch(
            list: .today,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(
            Set(today.map(\.id)),
            Set([
                .eventTask(
                    taskID: eventTask.id,
                    contextID: eventTask.contextID
                ),
                .personalTask(taskID: personalToday.id)
            ])
        )
        let eventSourceItem = try XCTUnwrap(today.first {
            $0.id == .eventTask(
                taskID: eventTask.id,
                contextID: eventTask.contextID
            )
        })
        guard case let .event(
            contextID,
            section,
            eventTitle,
            calendarIdentifier,
            calendarTitle,
            sourceTitle,
            eventStart,
            eventEnd,
            isAllDay
        ) = eventSourceItem.source else {
            return XCTFail("Expected event task source")
        }
        XCTAssertEqual(contextID, eventTask.contextID)
        XCTAssertEqual(section, EventTaskSection.before)
        XCTAssertEqual(eventTitle, event.title)
        XCTAssertEqual(calendarIdentifier, event.calendarIdentifier)
        XCTAssertEqual(calendarTitle, "KAOS-TEST")
        XCTAssertEqual(sourceTitle, "Work")
        XCTAssertEqual(eventStart, event.startDate)
        XCTAssertEqual(eventEnd, event.endDate)
        XCTAssertFalse(isAllDay)

        XCTAssertEqual(
            try harness.store.taskCenter.fetch(
                list: .upcoming,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [.personalTask(taskID: personalUpcoming.id)]
        )
    }

    func testTaskCenterSeparatesDateBucketsAndRanksImportantPriority() throws {
        let harness = try makeHarness()
        let overdue = try harness.store.personalTasks.create(
            title: "Overdue",
            dueAt: date(2026, 7, 9, 18)
        )
        let early = try harness.store.personalTasks.create(
            title: "Early today",
            dueAt: date(2026, 7, 10, 9)
        )
        let important = try harness.store.personalTasks.create(
            title: "Important later",
            dueAt: date(2026, 7, 10, 18)
        )
        let upcoming = try harness.store.personalTasks.create(
            title: "Upcoming",
            dueAt: date(2026, 7, 11, 9)
        )
        let noDate = try harness.store.personalTasks.create(title: "No date")
        _ = try harness.store.taskPlanning.save(
            for: .personalTask(taskID: important.id),
            priority: .high,
            isImportant: true,
            repeatFrequency: .none,
            repeatInterval: 1,
            estimatedMinutes: nil
        )

        XCTAssertEqual(
            try harness.store.taskCenter.fetch(
                list: .today,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [
                .personalTask(taskID: important.id),
                .personalTask(taskID: early.id)
            ]
        )
        XCTAssertEqual(
            try harness.store.taskCenter.fetch(
                list: .overdue,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [.personalTask(taskID: overdue.id)]
        )
        XCTAssertEqual(
            try harness.store.taskCenter.fetch(
                list: .upcoming,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [.personalTask(taskID: upcoming.id)]
        )
        XCTAssertEqual(
            try harness.store.taskCenter.fetch(
                list: .noDate,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [.personalTask(taskID: noDate.id)]
        )
    }

    func testTaskCenterUsesLocalTimeSemanticsForFloatingAndAllDayDueDates() throws {
        let harness = try makeHarness()
        var seoulCalendar = testCalendar
        seoulCalendar.timeZone = TimeZone(identifier: "Asia/Seoul")!

        let floatingStart = LocalDateTimeComponents(
            date: date(2026, 7, 11, 9),
            calendar: testCalendar
        )
        let floatingEnd = LocalDateTimeComponents(
            date: date(2026, 7, 11, 10),
            calendar: testCalendar
        )
        let floatingEvent = makeEvent(
            id: "floating",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            timeSemantics: .floating(
                start: floatingStart,
                end: floatingEnd
            )
        )
        let floatingTask = try harness.store.addEventTask(
            for: floatingEvent,
            section: .before,
            title: "Floating preparation",
            sortOrder: 0,
            due: .relative(anchor: .beforeStart, offsetMinutes: 30)
        )

        let allDayStart = LocalDateTimeComponents(
            date: date(2026, 7, 11),
            calendar: testCalendar
        )
        let allDayEnd = LocalDateTimeComponents(
            date: date(2026, 7, 12),
            calendar: testCalendar
        )
        let allDayEvent = makeEvent(
            id: "all-day",
            start: date(2026, 7, 11),
            end: date(2026, 7, 12).addingTimeInterval(-1),
            isAllDay: true,
            timeSemantics: .allDay(
                start: allDayStart,
                endExclusive: allDayEnd
            )
        )
        let allDayTask = try harness.store.addEventTask(
            for: allDayEvent,
            section: .after,
            title: "All-day follow-up",
            sortOrder: 0,
            due: .relative(anchor: .atEnd, offsetMinutes: 0)
        )

        let upcoming = try harness.store.taskCenter.fetch(
            list: .upcoming,
            now: harness.now,
            calendar: seoulCalendar
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: upcoming.map {
            ($0.id, $0)
        })
        let expectedFloatingDue = seoulCalendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 11,
                hour: 8,
                minute: 30
            )
        )
        let expectedAllDayDue = seoulCalendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 12
            )
        )

        XCTAssertEqual(
            itemsByID[.eventTask(
                taskID: floatingTask.id,
                contextID: floatingTask.contextID
            )]?.dueAt,
            expectedFloatingDue
        )
        XCTAssertEqual(
            itemsByID[.eventTask(
                taskID: allDayTask.id,
                contextID: allDayTask.contextID
            )]?.dueAt,
            expectedAllDayDue
        )
    }

    func testTemporalLifecycleUsesExactAndAllDayExclusiveEndBoundaries() throws {
        let database = try AppDatabase.inMemory()
        let store = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 12) }
        )
        let timedEvent = makeEvent(
            id: "lifecycle-timed",
            start: date(2026, 7, 10, 15),
            end: date(2026, 7, 10, 16)
        )
        let timedContext = try XCTUnwrap(
            try store.saveNotes(for: timedEvent, notes: "Keep")
        )
        XCTAssertEqual(timedContext.lifecycleStatus, .scheduled)

        XCTAssertEqual(
            try store.refreshTemporalLifecycle(
                at: timedEvent.endDate,
                calendar: testCalendar
            ),
            [timedContext.id]
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: timedContext.id)?
                .lifecycleStatus,
            .completed
        )

        let movedFuture = makeEvent(
            id: "lifecycle-timed",
            start: date(2026, 7, 11, 15),
            end: date(2026, 7, 11, 16)
        )
        _ = try store.rebindUserApprovedMutation(
            contextID: timedContext.id,
            to: movedFuture
        )
        _ = try store.refreshTemporalLifecycle(
            at: date(2026, 7, 10, 12),
            calendar: testCalendar
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: timedContext.id)?
                .lifecycleStatus,
            .scheduled
        )

        let allDayStart = localComponents(2026, 7, 11)
        let allDayEnd = localComponents(2026, 7, 12)
        let rawInclusiveEnd = date(2026, 7, 12).addingTimeInterval(-1)
        let allDayEvent = makeEvent(
            id: "lifecycle-all-day",
            start: date(2026, 7, 11),
            end: rawInclusiveEnd,
            isAllDay: true,
            timeSemantics: .allDay(
                start: allDayStart,
                endExclusive: allDayEnd
            )
        )
        let allDayContext = try XCTUnwrap(
            try store.saveNotes(for: allDayEvent, notes: "All-day")
        )
        _ = try store.refreshTemporalLifecycle(
            at: rawInclusiveEnd,
            calendar: testCalendar
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: allDayContext.id)?
                .lifecycleStatus,
            .scheduled
        )

        _ = try store.refreshTemporalLifecycle(
            at: date(2026, 7, 12),
            calendar: testCalendar
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: allDayContext.id)?
                .lifecycleStatus,
            .completed
        )
    }

    func testTemporalLifecycleRebuildsFloatingEndInDisplayTimeZone() throws {
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) }
        )
        let floatingEvent = makeEvent(
            id: "lifecycle-floating",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 13),
            timeSemantics: .floating(
                start: localComponents(2026, 7, 10, 9),
                end: localComponents(2026, 7, 10, 13)
            )
        )
        let context = try XCTUnwrap(
            try store.saveNotes(for: floatingEvent, notes: "Floating")
        )

        _ = try store.refreshTemporalLifecycle(
            at: date(2026, 7, 10, 12),
            calendar: testCalendar
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: context.id)?.lifecycleStatus,
            .scheduled
        )

        var seoulCalendar = testCalendar
        seoulCalendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        _ = try store.refreshTemporalLifecycle(
            at: date(2026, 7, 10, 12),
            calendar: seoulCalendar
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: context.id)?.lifecycleStatus,
            .completed
        )

        _ = try store.refreshTemporalLifecycle(
            at: date(2026, 7, 10, 12),
            calendar: testCalendar
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: context.id)?.lifecycleStatus,
            .scheduled
        )
    }

    func testTemporalLifecycleCompletesRecurringOccurrencesIndependently() throws {
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) }
        )
        let ended = makeEvent(
            id: "recurrence-ended",
            title: "Ended occurrence",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            externalIdentifier: "shared-lifecycle-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let future = makeEvent(
            id: "recurrence-future",
            title: "Future occurrence",
            start: date(2026, 7, 10, 15),
            end: date(2026, 7, 10, 16),
            externalIdentifier: "shared-lifecycle-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 15)
        )
        let endedContext = try XCTUnwrap(
            try store.saveNotes(for: ended, notes: "Ended")
        )
        let futureContext = try XCTUnwrap(
            try store.saveNotes(for: future, notes: "Future")
        )

        _ = try store.refreshTemporalLifecycle(
            at: date(2026, 7, 10, 12),
            calendar: testCalendar
        )

        XCTAssertEqual(
            try store.eventContexts.fetch(id: endedContext.id)?
                .lifecycleStatus,
            .completed
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: futureContext.id)?
                .lifecycleStatus,
            .scheduled
        )
    }

    func testTemporalLifecycleNeverOverwritesCancelledOrOrphaned() throws {
        let database = try AppDatabase.inMemory()
        let store = ContextStore(
            database: database,
            now: { self.date(2026, 7, 10, 12) }
        )
        let cancelled = try XCTUnwrap(try store.saveNotes(
            for: makeEvent(
                id: "cancelled-lifecycle",
                title: "Cancelled fixture",
                start: date(2026, 7, 10, 15),
                end: date(2026, 7, 10, 16)
            ),
            notes: "Cancelled"
        ))
        let orphaned = try XCTUnwrap(try store.saveNotes(
            for: makeEvent(
                id: "orphaned-lifecycle",
                title: "Orphaned fixture",
                start: date(2026, 7, 10, 15),
                end: date(2026, 7, 10, 16)
            ),
            notes: "Orphaned"
        ))
        let missingLink = try XCTUnwrap(try store.saveNotes(
            for: makeEvent(
                id: "missing-link-lifecycle",
                title: "Missing link fixture",
                start: date(2026, 7, 10, 15),
                end: date(2026, 7, 10, 16)
            ),
            notes: "Missing link"
        ))
        let orphanedLink = try XCTUnwrap(try store.saveNotes(
            for: makeEvent(
                id: "orphaned-link-lifecycle",
                title: "Orphaned link fixture",
                start: date(2026, 7, 13, 15),
                end: date(2026, 7, 13, 16)
            ),
            notes: "Orphaned link"
        ))
        try database.write { db in
            try db.execute(
                sql: "UPDATE event_contexts SET lifecycle_status = 'cancelled' WHERE id = ?",
                arguments: [cancelled.id]
            )
            try db.execute(
                sql: "UPDATE event_contexts SET lifecycle_status = 'orphaned' WHERE id = ?",
                arguments: [orphaned.id]
            )
            try db.execute(
                sql: "UPDATE event_links SET link_status = 'missing' WHERE context_id = ?",
                arguments: [missingLink.id]
            )
            try db.execute(
                sql: "UPDATE event_contexts SET lifecycle_status = 'completed' WHERE id = ?",
                arguments: [orphanedLink.id]
            )
            try db.execute(
                sql: "UPDATE event_links SET link_status = 'orphaned' WHERE context_id = ?",
                arguments: [orphanedLink.id]
            )
        }

        let changed = try store.refreshTemporalLifecycle(
            at: date(2026, 7, 12),
            calendar: testCalendar
        )

        XCTAssertTrue(changed.isEmpty)
        XCTAssertEqual(
            try store.eventContexts.fetch(id: cancelled.id)?.lifecycleStatus,
            .cancelled
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: orphaned.id)?.lifecycleStatus,
            .orphaned
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: missingLink.id)?
                .lifecycleStatus,
            .scheduled
        )
        XCTAssertEqual(
            try store.eventContexts.fetch(id: orphanedLink.id)?
                .lifecycleStatus,
            .completed
        )
    }

    func testAfterReviewKeepsOnlyOpenAfterTasksWithoutDeletingHistory() throws {
        let harness = try makeHarness()
        let endedEvent = makeEvent(
            id: "after-review",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10)
        )
        let before = try harness.store.appendEventTask(
            for: endedEvent,
            section: .before,
            title: "Prepare"
        )
        let during = try harness.store.appendEventTask(
            for: endedEvent,
            section: .during,
            title: "Take notes"
        )
        let afterToday = try harness.store.appendEventTask(
            for: endedEvent,
            section: .after,
            title: "Send recap"
        )
        let afterFuture = try harness.store.appendEventTask(
            for: endedEvent,
            section: .after,
            title: "Check response",
            due: .fixed(date(2026, 7, 12, 9))
        )
        _ = try harness.store.setEventTaskCompleted(
            contextID: during.contextID,
            taskID: during.id,
            isCompleted: true
        )
        let personal = try harness.store.personalTasks.create(
            title: "Personal inbox"
        )

        let today = try harness.store.taskCenter.fetch(
            list: .today,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(
            Set(today.map(\.id)),
            Set([
                .eventTask(
                    taskID: afterToday.id,
                    contextID: afterToday.contextID
                )
            ])
        )
        XCTAssertEqual(
            try harness.store.taskCenter.fetch(
                list: .noDate,
                now: harness.now,
                calendar: testCalendar
            ).map(\.id),
            [.personalTask(taskID: personal.id)]
        )
        XCTAssertFalse(today.contains {
            $0.id == .eventTask(
                taskID: before.id,
                contextID: before.contextID
            )
        })

        let upcoming = try harness.store.taskCenter.fetch(
            list: .upcoming,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(upcoming.map(\.id), [
            .eventTask(
                taskID: afterFuture.id,
                contextID: afterFuture.contextID
            )
        ])

        let afterReview = try harness.store.taskCenter.fetch(
            list: .afterReview,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(
            Set(afterReview.map(\.id)),
            Set([
                .eventTask(
                    taskID: afterToday.id,
                    contextID: afterToday.contextID
                ),
                .eventTask(
                    taskID: afterFuture.id,
                    contextID: afterFuture.contextID
                )
            ])
        )

        let completed = try harness.store.taskCenter.fetch(
            list: .completed,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(completed.map(\.id), [
            .eventTask(
                taskID: during.id,
                contextID: during.contextID
            )
        ])
        XCTAssertEqual(
            try harness.store.eventTasks.fetch(
                contextID: before.contextID
            ).count,
            4
        )
    }

    func testObservingLinkedMoveRefreshesSnapshotWithoutLosingLocalData() throws {
        let harness = try makeHarness()
        let original = makeEvent(
            id: "moving",
            externalIdentifier: "stable-external"
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Original notes")
        )
        let task = try harness.store.addEventTask(
            for: original,
            section: .during,
            title: "Keep this task",
            sortOrder: 0
        )
        let moved = makeEvent(
            id: "moving-refreshed",
            title: "Renamed meeting",
            location: "Room B",
            start: date(2026, 7, 10, 14),
            end: date(2026, 7, 10, 15),
            externalIdentifier: "stable-external"
        )

        XCTAssertEqual(
            try harness.store.resolve(event: moved),
            .linked(
                contextID: context.id,
                basis: .externalIdentifierAndOccurrence
            )
        )
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertEqual(brief.context.titleSnapshot, "Renamed meeting")
        XCTAssertEqual(brief.context.startSnapshot, date(2026, 7, 10, 14))
        XCTAssertEqual(brief.context.endSnapshot, date(2026, 7, 10, 15))
        XCTAssertEqual(brief.context.notes, "Original notes")
        XCTAssertEqual(brief.link.titleSnapshot, "Renamed meeting")
        XCTAssertEqual(brief.link.locationSnapshot, "Room B")
        XCTAssertEqual(brief.link.startSnapshot, date(2026, 7, 10, 14))
        XCTAssertEqual(
            brief.link.eventIdentifier,
            "event-id-moving-refreshed"
        )
        XCTAssertEqual(brief.tasks.map(\.id), [task.id])
        let todayItems = try harness.store.taskCenter.fetch(
            list: .today,
            now: harness.now,
            calendar: testCalendar
        )
        XCTAssertEqual(
            todayItems.first {
                $0.id == .eventTask(
                    taskID: task.id,
                    contextID: task.contextID
                )
            }?.dueAt,
            date(2026, 7, 10, 14)
        )
    }

    func testRecurringOccurrencesResolveSeparatelyAndDetachedMoveStaysLinked() throws {
        let harness = try makeHarness()
        let firstOccurrence = makeEvent(
            id: "occurrence-1",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            externalIdentifier: "series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let secondOccurrence = makeEvent(
            id: "occurrence-2",
            start: date(2026, 7, 17, 9),
            end: date(2026, 7, 17, 10),
            externalIdentifier: "series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 17, 9)
        )
        let firstContext = try XCTUnwrap(
            harness.store.saveNotes(for: firstOccurrence, notes: "First")
        )
        let secondContext = try XCTUnwrap(
            harness.store.saveNotes(for: secondOccurrence, notes: "Second")
        )

        XCTAssertNotEqual(firstContext.id, secondContext.id)
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: firstOccurrence)),
            firstContext.id
        )
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: secondOccurrence)),
            secondContext.id
        )

        let detachedMoved = makeEvent(
            id: "occurrence-moved",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14),
            externalIdentifier: "series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            isDetached: true
        )
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: detachedMoved)),
            firstContext.id
        )
    }

    func testNavigationMatchingIsReadOnlyStrongAndOccurrenceScoped() throws {
        let harness = try makeHarness()
        let original = makeEvent(
            id: "navigation-original",
            externalIdentifier: "navigation-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Keep snapshot")
        )
        let before = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )

        let target = try XCTUnwrap(
            harness.store.navigationTarget(contextID: context.id)
        )
        XCTAssertEqual(target.contextID, context.id)
        XCTAssertEqual(target.link, before.link)

        let matchingOccurrence = makeEvent(
            id: "navigation-live",
            title: "Moved live event",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14),
            externalIdentifier: "navigation-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            isDetached: true
        )
        let siblingOccurrence = makeEvent(
            id: "navigation-sibling",
            start: date(2026, 7, 17, 9),
            end: date(2026, 7, 17, 10),
            externalIdentifier: "navigation-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 17, 9)
        )

        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: context.id,
                among: [siblingOccurrence, matchingOccurrence]
            ),
            .linked(
                event: matchingOccurrence,
                basis: .externalIdentifierAndOccurrence
            )
        )

        let weakOccurrence = makeEvent(
            id: "navigation-weak",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            includeIdentifiers: false
        )
        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: context.id,
                among: [weakOccurrence]
            ),
            .confirmationRequired(
                eventIDs: [weakOccurrence.id],
                basis: .exactSnapshot
            )
        )
        XCTAssertEqual(
            try harness.store.matchLinkedEvent(
                contextID: "missing-context",
                among: [matchingOccurrence]
            ),
            .notFound
        )

        let after = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after, before)
    }

    func testUserApprovedMutationRebindsChangedCalendarAndIdentifiers() throws {
        let store = try makeHarness().store
        let original = makeEvent(
            id: "before",
            title: "Before",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            externalIdentifier: "external-before",
            calendarIdentifier: "calendar-before"
        )
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep this local note")
        )
        _ = try store.appendEventTask(
            for: original,
            section: .before,
            title: "Keep this task"
        )
        let updated = makeEvent(
            id: "after",
            title: "After",
            start: date(2026, 7, 11, 13),
            end: date(2026, 7, 11, 14),
            externalIdentifier: "external-after",
            calendarIdentifier: "calendar-after"
        )

        XCTAssertEqual(
            try store.mutationContext(for: original),
            .linked(contextID: context.id)
        )
        let rebound = try store.rebindUserApprovedMutation(
            contextID: context.id,
            to: updated
        )

        XCTAssertEqual(rebound.context.notes, "Keep this local note")
        XCTAssertEqual(rebound.context.titleSnapshot, "After")
        XCTAssertEqual(rebound.link.calendarIdentifier, "calendar-after")
        XCTAssertEqual(rebound.link.eventIdentifier, "event-id-after")
        XCTAssertEqual(rebound.tasks.map(\.title), ["Keep this task"])
        guard case let .linked(linkedID, _) = try store.resolve(event: updated) else {
            return XCTFail("Expected updated event to stay linked")
        }
        XCTAssertEqual(linkedID, context.id)
    }

    func testMutationImpactSummarizesLocalDataAndRecentHistory() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "impact-original")
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: original,
                notes: "  Local note  "
            )
        )
        _ = try harness.store.appendEventTask(
            for: original,
            section: .before,
            title: "Prepare"
        )
        _ = try harness.store.appendEventTask(
            for: original,
            section: .during,
            title: "Join"
        )
        let moved = makeEvent(
            id: "impact-moved",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14),
            calendarIdentifier: "destination-calendar"
        )
        let firstChange = try harness.store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: moved,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let renamed = makeEvent(
            id: "impact-renamed",
            title: "Renamed event",
            start: moved.startDate,
            end: moved.endDate,
            calendarIdentifier: moved.calendarIdentifier
        )
        let secondChange = try harness.store.rebindAndRecordMutation(
            contextID: context.id,
            from: moved,
            to: renamed,
            changeType: .detailsUpdated,
            scope: .single,
            undoState: .unavailable
        )

        let impact = try harness.store.mutationImpact(
            contextID: context.id,
            recentHistoryLimit: 1
        )

        XCTAssertTrue(impact.hasNotes)
        XCTAssertEqual(impact.notesCharacterCount, 10)
        XCTAssertEqual(impact.taskCount, 2)
        XCTAssertEqual(
            impact.taskSections,
            [
                EventMutationTaskSummary(
                    section: .before,
                    count: 1,
                    titles: ["Prepare"]
                ),
                EventMutationTaskSummary(
                    section: .during,
                    count: 1,
                    titles: ["Join"]
                ),
                EventMutationTaskSummary(
                    section: .after,
                    count: 0,
                    titles: []
                )
            ]
        )
        XCTAssertEqual(impact.recentHistory.map(\.id), [secondChange.id])
        XCTAssertEqual(impact.recentHistory.first?.before.startDate, moved.startDate)
        XCTAssertEqual(
            impact.recentHistory.first?.after.calendarIdentifier,
            "destination-calendar"
        )

        let history = try harness.store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.id), [secondChange.id, firstChange.id])
        XCTAssertEqual(history[0].undoState, .unavailable)
        XCTAssertEqual(history[1].undoState, .superseded)
        XCTAssertEqual(history[1].before.calendarIdentifier, "calendar")
        XCTAssertEqual(
            history[1].after.calendarIdentifier,
            "destination-calendar"
        )
    }

    func testLinkedOriginalDeletionPreservesLocalBriefAndRecordsCancellation() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "delete-linked-original")
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: original,
                notes: "Keep deletion notes"
            )
        )
        let beforeTask = try harness.store.appendEventTask(
            for: original,
            section: .before,
            title: "Prepare deletion review"
        )
        let afterTask = try harness.store.appendEventTask(
            for: original,
            section: .after,
            title: "Retain follow-up"
        )
        let currentEvent = makeEvent(
            id: "delete-linked-current",
            title: "Current linked title",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14),
            calendarIdentifier: "current-calendar"
        )
        let priorChange = try harness.store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: currentEvent,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )

        let preparation = try harness.store.prepareLinkedOriginalDeletion(
            contextID: context.id
        )

        XCTAssertEqual(preparation.brief.context.notes, "Keep deletion notes")
        XCTAssertEqual(
            preparation.brief.tasks.map(\.id),
            [beforeTask.id, afterTask.id]
        )
        XCTAssertEqual(preparation.brief.link.linkStatus, .active)
        XCTAssertFalse(preparation.brief.hasRecordedOriginalDeletion)
        XCTAssertTrue(preparation.impact.hasNotes)
        XCTAssertEqual(preparation.impact.notesCharacterCount, 19)
        XCTAssertEqual(preparation.impact.taskCount, 2)
        XCTAssertEqual(
            preparation.impact.taskSections,
            [
                EventMutationTaskSummary(
                    section: .before,
                    count: 1,
                    titles: ["Prepare deletion review"]
                ),
                EventMutationTaskSummary(
                    section: .during,
                    count: 0,
                    titles: []
                ),
                EventMutationTaskSummary(
                    section: .after,
                    count: 1,
                    titles: ["Retain follow-up"]
                )
            ]
        )
        XCTAssertEqual(preparation.impact.recentHistory.map(\.id), [priorChange.id])
        XCTAssertEqual(
            preparation.changeSnapshot,
            try EventChangeSnapshot(link: preparation.brief.link)
        )
        XCTAssertNil(preparation.changeSnapshot.originalNotes)
        XCTAssertEqual(
            try harness.store.validateLinkedOriginalDeletion(
                contextID: context.id,
                expectedLink: preparation.brief.link,
                expectedSnapshot: preparation.changeSnapshot
            ),
            preparation.brief
        )

        let finalized = try harness.store.finalizeLinkedOriginalDeletion(
            contextID: context.id,
            expectedLink: preparation.brief.link,
            expectedSnapshot: preparation.changeSnapshot,
            scope: .single
        )

        XCTAssertEqual(finalized.context.lifecycleStatus, .cancelled)
        XCTAssertEqual(finalized.link.linkStatus, .orphaned)
        XCTAssertTrue(finalized.hasRecordedOriginalDeletion)
        XCTAssertEqual(finalized.context.notes, "Keep deletion notes")
        XCTAssertEqual(finalized.tasks, preparation.brief.tasks)
        XCTAssertEqual(finalized.tasks.map(\.id), [beforeTask.id, afterTask.id])
        XCTAssertEqual(
            finalized.link.eventIdentifier,
            preparation.brief.link.eventIdentifier
        )
        XCTAssertEqual(
            finalized.link.occurrenceIdentityKey,
            preparation.brief.link.occurrenceIdentityKey
        )
        XCTAssertEqual(
            finalized.link.lastSeenAt,
            preparation.brief.link.lastSeenAt
        )

        let history = try harness.store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.count, 2)
        let cancellation = history[0]
        XCTAssertEqual(cancellation.changeType, .cancelled)
        XCTAssertEqual(cancellation.scope, .single)
        XCTAssertEqual(cancellation.before, preparation.changeSnapshot)
        XCTAssertEqual(cancellation.after, preparation.changeSnapshot)
        XCTAssertEqual(cancellation.undoState, .unavailable)
        XCTAssertNil(cancellation.undoneAt)
        XCTAssertNil(cancellation.undoOfChangeID)
        XCTAssertEqual(cancellation.createdAt, harness.now)
        XCTAssertEqual(history[1].id, priorChange.id)
        XCTAssertEqual(history[1].undoState, .superseded)
    }

    func testLinkedRecurringOccurrenceDeletionRequiresThisEventScope() throws {
        let harness = try makeHarness()
        let occurrence = date(2026, 7, 17, 9)
        let recurring = makeEvent(
            id: "delete-recurring-occurrence",
            start: occurrence,
            end: date(2026, 7, 17, 10),
            externalIdentifier: "delete-recurring-series",
            isRecurring: true,
            occurrenceDate: occurrence
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: recurring,
                notes: "Keep recurring notes"
            )
        )
        let task = try harness.store.appendEventTask(
            for: recurring,
            section: .during,
            title: "Keep occurrence task"
        )
        let preparation = try harness.store.prepareLinkedOriginalDeletion(
            contextID: context.id
        )

        XCTAssertTrue(preparation.brief.link.isRecurring)
        XCTAssertThrowsError(try harness.store.finalizeLinkedOriginalDeletion(
            contextID: context.id,
            expectedLink: preparation.brief.link,
            expectedSnapshot: preparation.changeSnapshot,
            scope: .single
        )) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidEventLinkTransition
            )
        }
        XCTAssertEqual(
            try harness.store.eventContexts.fetchBrief(contextID: context.id),
            preparation.brief
        )
        XCTAssertTrue(
            try harness.store.changeHistory(contextID: context.id).isEmpty
        )

        let finalized = try harness.store.finalizeLinkedOriginalDeletion(
            contextID: context.id,
            expectedLink: preparation.brief.link,
            expectedSnapshot: preparation.changeSnapshot,
            scope: .thisEvent
        )

        XCTAssertEqual(finalized.context.lifecycleStatus, .cancelled)
        XCTAssertEqual(finalized.link.linkStatus, .orphaned)
        XCTAssertEqual(finalized.context.notes, "Keep recurring notes")
        XCTAssertEqual(finalized.tasks.map(\.id), [task.id])
        let cancellation = try XCTUnwrap(
            harness.store.changeHistory(contextID: context.id).first
        )
        XCTAssertEqual(cancellation.changeType, .cancelled)
        XCTAssertEqual(cancellation.scope, .thisEvent)
        XCTAssertEqual(cancellation.before, preparation.changeSnapshot)
        XCTAssertEqual(cancellation.after, preparation.changeSnapshot)
        XCTAssertEqual(cancellation.undoState, .unavailable)
    }

    func testLinkedOriginalDeletionRejectsStaleExpectedLinkWithoutMutation() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "delete-stale-original")
        let context = try XCTUnwrap(
            harness.store.saveNotes(
                for: original,
                notes: "Keep stale-session notes"
            )
        )
        let task = try harness.store.appendEventTask(
            for: original,
            section: .before,
            title: "Keep stale-session task"
        )
        let stalePreparation = try harness.store.prepareLinkedOriginalDeletion(
            contextID: context.id
        )
        let refreshedEvent = makeEvent(
            id: "delete-stale-refreshed",
            title: "Refreshed outside deletion review",
            start: date(2026, 7, 11, 15),
            end: date(2026, 7, 11, 16),
            calendarIdentifier: "refreshed-calendar"
        )
        let refreshed = try harness.store.rebindUserApprovedMutation(
            contextID: context.id,
            to: refreshedEvent
        )

        XCTAssertThrowsError(try harness.store.validateLinkedOriginalDeletion(
            contextID: context.id,
            expectedLink: stalePreparation.brief.link,
            expectedSnapshot: stalePreparation.changeSnapshot
        )) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidEventLinkTransition
            )
        }
        XCTAssertThrowsError(try harness.store.finalizeLinkedOriginalDeletion(
            contextID: context.id,
            expectedLink: stalePreparation.brief.link,
            expectedSnapshot: stalePreparation.changeSnapshot,
            scope: .single
        )) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidEventLinkTransition
            )
        }

        let after = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after, refreshed)
        XCTAssertEqual(after.link.linkStatus, .active)
        XCTAssertEqual(after.context.notes, "Keep stale-session notes")
        XCTAssertEqual(after.tasks.map(\.id), [task.id])
        XCTAssertTrue(
            try harness.store.changeHistory(contextID: context.id).isEmpty
        )
    }

    func testLinkedOriginalDeletionLogFailureRollsBackEntireTransaction() throws {
        let database = try AppDatabase.inMemory()
        let timestamp = date(2026, 7, 10, 12)
        let store = ContextStore(
            database: database,
            now: { timestamp },
            makeID: IDSequence((1...20).map { "delete-rollback-\($0)" }).next
        )
        let original = makeEvent(id: "delete-log-rollback-original")
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Rollback deletion notes"
        ))
        let task = try store.appendEventTask(
            for: original,
            section: .after,
            title: "Rollback deletion task"
        )
        let currentEvent = makeEvent(
            id: "delete-log-rollback-current",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14)
        )
        let priorChange = try store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: currentEvent,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let preparation = try store.prepareLinkedOriginalDeletion(
            contextID: context.id
        )
        let beforeFailure = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        try database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_cancelled_log
                BEFORE INSERT ON event_change_log
                WHEN NEW.change_type = 'cancelled'
                BEGIN
                    SELECT RAISE(ABORT, 'cancelled log rejected');
                END
                """)
        }

        XCTAssertThrowsError(try store.finalizeLinkedOriginalDeletion(
            contextID: context.id,
            expectedLink: preparation.brief.link,
            expectedSnapshot: preparation.changeSnapshot,
            scope: .single
        ))

        let afterFailure = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(afterFailure, beforeFailure)
        XCTAssertEqual(afterFailure.link.linkStatus, .active)
        XCTAssertEqual(afterFailure.context.notes, "Rollback deletion notes")
        XCTAssertEqual(afterFailure.tasks.map(\.id), [task.id])
        let history = try store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, priorChange.id)
        XCTAssertEqual(history.first?.undoState, .available)
        XCTAssertFalse(history.contains { $0.changeType == .cancelled })
    }

    func testRebindAndChangeLogAppendRollBackTogether() throws {
        let IDs = IDSequence([
            "rollback-context", "rollback-link",
            "duplicate-log", "duplicate-log"
        ])
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) },
            makeID: IDs.next
        )
        let original = makeEvent(id: "rollback-original")
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep local data")
        )
        let firstMove = makeEvent(
            id: "rollback-first",
            start: date(2026, 7, 10, 11),
            end: date(2026, 7, 10, 12)
        )
        let firstChange = try store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: firstMove,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let beforeFailure = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        let secondMove = makeEvent(
            id: "rollback-second",
            start: date(2026, 7, 10, 15),
            end: date(2026, 7, 10, 16)
        )

        XCTAssertThrowsError(
            try store.rebindAndRecordMutation(
                contextID: context.id,
                from: firstMove,
                to: secondMove,
                changeType: .moved,
                scope: .single,
                undoState: .available
            )
        )

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            beforeFailure
        )
        let history = try store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.id), [firstChange.id])
        XCTAssertEqual(history.first?.undoState, .available)
    }

    func testUndoRebindMarksOriginalAndAppendsRestoredAtomically() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "undo-original")
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Keep note")
        )
        let task = try harness.store.appendEventTask(
            for: original,
            section: .after,
            title: "Keep task"
        )
        let moved = makeEvent(
            id: "undo-moved",
            start: date(2026, 7, 11, 13),
            end: date(2026, 7, 11, 14),
            calendarIdentifier: "destination-calendar"
        )
        let originalChange = try harness.store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: moved,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let restoredReceipt = makeEvent(id: "undo-restored")

        let restoredChange = try harness.store.rebindAfterUndo(
            contextID: context.id,
            originalChangeID: originalChange.id,
            from: moved,
            to: restoredReceipt,
            scope: .single
        )

        XCTAssertEqual(restoredChange.changeType, .restored)
        XCTAssertEqual(restoredChange.undoState, .unavailable)
        XCTAssertEqual(restoredChange.undoOfChangeID, originalChange.id)
        XCTAssertEqual(restoredChange.before.calendarIdentifier, moved.calendarIdentifier)
        XCTAssertEqual(
            restoredChange.after.calendarIdentifier,
            restoredReceipt.calendarIdentifier
        )
        let history = try harness.store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.map(\.id), [restoredChange.id, originalChange.id])
        XCTAssertEqual(history[1].undoState, .undone)
        XCTAssertEqual(history[1].undoneAt, harness.now)
        let brief = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(brief.context.id, context.id)
        XCTAssertEqual(brief.context.notes, "Keep note")
        XCTAssertEqual(brief.link.startSnapshot, restoredReceipt.startDate)
        XCTAssertEqual(brief.tasks.map(\.id), [task.id])

        XCTAssertThrowsError(
            try harness.store.rebindAfterUndo(
                contextID: context.id,
                originalChangeID: originalChange.id,
                from: restoredReceipt,
                to: moved,
                scope: .single
            )
        ) { error in
            XCTAssertEqual(
                error as? EventChangeLogError,
                .undoUnavailable(originalChange.id)
            )
        }
        XCTAssertEqual(
            try harness.store.changeHistory(contextID: context.id).count,
            2
        )
    }

    func testUndoRollbackKeepsLinkAndOriginalChangeAvailable() throws {
        let IDs = IDSequence([
            "undo-rollback-context", "undo-rollback-link",
            "duplicate-undo-log", "duplicate-undo-log"
        ])
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { self.date(2026, 7, 10, 12) },
            makeID: IDs.next
        )
        let original = makeEvent(id: "undo-rollback-original")
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Keep")
        )
        let moved = makeEvent(
            id: "undo-rollback-moved",
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14)
        )
        let change = try store.rebindAndRecordMutation(
            contextID: context.id,
            from: original,
            to: moved,
            changeType: .moved,
            scope: .single,
            undoState: .available
        )
        let beforeFailure = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertThrowsError(
            try store.rebindAfterUndo(
                contextID: context.id,
                originalChangeID: change.id,
                from: moved,
                to: makeEvent(id: "undo-rollback-restored"),
                scope: .single
            )
        )

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            beforeFailure
        )
        let history = try store.changeHistory(contextID: context.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, change.id)
        XCTAssertEqual(history.first?.undoState, .available)
        XCTAssertNil(history.first?.undoneAt)
    }

    func testUserApprovedMutationCollisionRollsBackBothContextsAndTasks() throws {
        let store = try makeHarness().store
        let first = makeEvent(id: "collision-first")
        let second = makeEvent(
            id: "collision-second",
            title: "Other event",
            location: "Room B",
            start: date(2026, 7, 10, 11),
            end: date(2026, 7, 10, 12)
        )
        let firstContext = try XCTUnwrap(
            store.saveNotes(for: first, notes: "First local note")
        )
        let secondContext = try XCTUnwrap(
            store.saveNotes(for: second, notes: "Second local note")
        )
        _ = try store.appendEventTask(
            for: first,
            section: .before,
            title: "First task"
        )
        _ = try store.appendEventTask(
            for: second,
            section: .after,
            title: "Second task"
        )
        let firstBefore = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: firstContext.id)
        )
        let secondBefore = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: secondContext.id)
        )

        XCTAssertThrowsError(
            try store.rebindUserApprovedMutation(
                contextID: firstContext.id,
                to: second
            )
        )

        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: firstContext.id),
            firstBefore
        )
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: secondContext.id),
            secondBefore
        )
    }

    func testUserApprovedMutationMissingContextChangesNothing() throws {
        let store = try makeHarness().store
        let event = makeEvent(id: "missing-rebind")
        let context = try XCTUnwrap(
            store.saveNotes(for: event, notes: "Existing note")
        )
        let before = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )

        XCTAssertThrowsError(
            try store.rebindUserApprovedMutation(
                contextID: "missing-context",
                to: makeEvent(id: "new-receipt")
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .missingContext("missing-context")
            )
        }

        XCTAssertEqual(try store.eventContexts.count(), 1)
        XCTAssertEqual(
            try store.eventContexts.fetchBrief(contextID: context.id),
            before
        )
    }

    func testMutationContextDoesNotAutoChooseWeakCandidate() throws {
        let store = try makeHarness().store
        let original = makeEvent(
            id: "weak-original",
            title: "Weak candidate",
            start: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            calendarIdentifier: "calendar",
            includeIdentifiers: false
        )
        let context = try XCTUnwrap(
            store.saveNotes(for: original, notes: "Candidate note")
        )
        let candidate = makeEvent(
            id: "weak-candidate",
            title: original.title,
            start: original.startDate,
            end: original.endDate,
            calendarIdentifier: "calendar"
        )

        XCTAssertEqual(
            try store.mutationContext(for: candidate),
            .confirmationRequired(contextIDs: [context.id])
        )
    }

    func testFloatingOccurrenceUsesCivilAnchorAcrossTimeZoneAndDetachedMove() throws {
        let harness = try makeHarness()
        let occurrenceStart = localComponents(2026, 7, 10, 9)
        let occurrenceEnd = localComponents(2026, 7, 10, 10)
        let original = makeEvent(
            id: "floating-occurrence",
            start: date(2026, 7, 10),
            end: date(2026, 7, 10, 1),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10),
            occurrenceLocalComponents: occurrenceStart,
            timeSemantics: .floating(
                start: occurrenceStart,
                end: occurrenceEnd
            )
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Civil anchor")
        )
        let sameCivilTimeInAnotherZone = makeEvent(
            id: "floating-occurrence",
            start: date(2026, 7, 10, 16),
            end: date(2026, 7, 10, 17),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 16),
            occurrenceLocalComponents: occurrenceStart,
            timeSemantics: .floating(
                start: occurrenceStart,
                end: occurrenceEnd
            )
        )

        XCTAssertEqual(
            try linkedContextID(
                harness.store.resolve(event: sameCivilTimeInAnotherZone)
            ),
            context.id
        )

        let detachedStart = localComponents(2026, 7, 10, 13)
        let detachedEnd = localComponents(2026, 7, 10, 14)
        let detached = makeEvent(
            id: "floating-detached",
            start: date(2026, 7, 10, 20),
            end: date(2026, 7, 10, 21),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 16),
            occurrenceLocalComponents: occurrenceStart,
            isDetached: true,
            timeSemantics: .floating(
                start: detachedStart,
                end: detachedEnd
            )
        )
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: detached)),
            context.id
        )

        let nextOccurrenceStart = localComponents(2026, 7, 17, 9)
        let nextOccurrenceEnd = localComponents(2026, 7, 17, 10)
        let nextOccurrence = makeEvent(
            id: "floating-occurrence",
            start: date(2026, 7, 17),
            end: date(2026, 7, 17, 1),
            externalIdentifier: "floating-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 17),
            occurrenceLocalComponents: nextOccurrenceStart,
            timeSemantics: .floating(
                start: nextOccurrenceStart,
                end: nextOccurrenceEnd
            )
        )
        XCTAssertEqual(
            try harness.store.resolve(event: nextOccurrence),
            .notFound
        )
    }

    func testAllDayOccurrenceUsesCivilAnchorAcrossRawDateChange() throws {
        let harness = try makeHarness()
        let start = localComponents(2026, 7, 10)
        let end = localComponents(2026, 7, 11)
        let first = makeEvent(
            id: "all-day-occurrence",
            start: date(2026, 7, 9, 15),
            end: date(2026, 7, 10, 15).addingTimeInterval(-1),
            externalIdentifier: "all-day-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 9, 15),
            occurrenceLocalComponents: start,
            isAllDay: true,
            timeSemantics: .allDay(start: start, endExclusive: end)
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: first, notes: "All-day civil")
        )
        let sameCivilDate = makeEvent(
            id: "all-day-occurrence",
            start: date(2026, 7, 10, 7),
            end: date(2026, 7, 11, 7).addingTimeInterval(-1),
            externalIdentifier: "all-day-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 7),
            occurrenceLocalComponents: start,
            isAllDay: true,
            timeSemantics: .allDay(start: start, endExclusive: end)
        )

        XCTAssertNotEqual(first.occurrenceDate, sameCivilDate.occurrenceDate)
        XCTAssertEqual(
            try linkedContextID(harness.store.resolve(event: sameCivilDate)),
            context.id
        )
    }

    func testFingerprintIsNormalizedAndNeverAutoLinks() throws {
        let harness = try makeHarness()
        let original = makeEvent(
            id: "fingerprint",
            title: "Téam   Sync",
            location: "Room Ａ"
        )
        let context = try XCTUnwrap(
            harness.store.saveNotes(for: original, notes: "Keep")
        )
        let changedIdentifiers = makeEvent(
            id: "different",
            title: " team sync ",
            location: "room a",
            includeIdentifiers: false
        )

        let originalFingerprint = EventIdentityFingerprint.make(event: original)
        let changedFingerprint = EventIdentityFingerprint.make(
            event: changedIdentifiers
        )
        XCTAssertEqual(originalFingerprint, changedFingerprint)
        XCTAssertEqual(
            originalFingerprint,
            "v1:f1a3dcf23724448190fa8ce0a40fdad3d877bde91067e5f0b180f902c39d428a"
        )
        XCTAssertTrue(originalFingerprint.hasPrefix("v1:"))
        XCTAssertEqual(originalFingerprint.count, 67)
        XCTAssertEqual(
            try harness.store.resolve(event: changedIdentifiers),
            .candidate(contextIDs: [context.id], basis: .fingerprint)
        )
        XCTAssertThrowsError(
            try harness.store.saveNotes(
                for: changedIdentifiers,
                notes: "Must confirm"
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .identityConfirmationRequired([context.id])
            )
        }
    }

    func testSeriesIdentitySkipsEmptyIdentifiers() throws {
        let fallbackEvent = makeEvent(
            id: "series-fallback",
            externalIdentifier: "",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9)
        )
        let fallbackSnapshot = try EventLinkSnapshot(event: fallbackEvent)

        XCTAssertEqual(
            fallbackSnapshot.recurrenceSeriesIdentifier,
            "item-id-series-fallback"
        )
        XCTAssertNotNil(fallbackSnapshot.seriesFingerprint)

        let noSeriesIdentifier = makeEvent(
            id: "series-missing",
            externalIdentifier: "",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 9),
            includeIdentifiers: false
        )
        let missingSnapshot = try EventLinkSnapshot(
            event: noSeriesIdentifier
        )

        XCTAssertNil(missingSnapshot.recurrenceSeriesIdentifier)
        XCTAssertNil(missingSnapshot.seriesFingerprint)
    }

    func testFileBackedDatabaseReopensWithAllPhaseThreeData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaosCal-ContextStore-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("kaoscal.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let event = makeEvent(id: "persistent")
        let floatingStart = localComponents(2026, 7, 11, 9)
        let floatingEnd = localComponents(2026, 7, 11, 10)
        let floatingEvent = makeEvent(
            id: "persistent-floating",
            title: "Persistent floating event",
            timeSemantics: .floating(
                start: floatingStart,
                end: floatingEnd
            )
        )
        let allDayStart = localComponents(2026, 7, 12)
        let allDayEnd = localComponents(2026, 7, 13)
        let allDayEvent = makeEvent(
            id: "persistent-all-day",
            start: date(2026, 7, 12),
            end: date(2026, 7, 13).addingTimeInterval(-1),
            externalIdentifier: "persistent-series",
            isRecurring: true,
            occurrenceDate: date(2026, 7, 12),
            occurrenceLocalComponents: allDayStart,
            isAllDay: true,
            timeSemantics: .allDay(
                start: allDayStart,
                endExclusive: allDayEnd
            )
        )
        var contextID = ""
        var eventTaskID = ""
        var floatingContextID = ""
        var floatingTaskID = ""
        var allDayContextID = ""
        var personalTaskID = ""

        do {
            let database = try AppDatabase.open(at: databaseURL)
            let IDs = IDSequence([
                "context", "link", "event-task", "personal-task"
            ])
            let store = ContextStore(
                database: database,
                now: { self.date(2026, 7, 10, 12) },
                makeID: IDs.next
            )
            let context = try XCTUnwrap(
                store.saveNotes(for: event, notes: "Persistent notes")
            )
            let eventTask = try store.addEventTask(
                for: event,
                section: .after,
                title: "Persistent event task",
                sortOrder: 0,
                due: .relative(anchor: .afterEnd, offsetMinutes: 45)
            )
            _ = try store.eventTasks.setCompleted(
                id: eventTask.id,
                isCompleted: true
            )
            let floatingContext = try XCTUnwrap(
                store.saveNotes(
                    for: floatingEvent,
                    notes: "Floating notes"
                )
            )
            let floatingTask = try store.addEventTask(
                for: floatingEvent,
                section: .before,
                title: "Persistent fixed task",
                sortOrder: 0,
                due: .fixed(date(2026, 7, 11, 8, 30))
            )
            let allDayContext = try XCTUnwrap(
                store.saveNotes(
                    for: allDayEvent,
                    notes: "All-day recurring notes"
                )
            )
            let personalTask = try store.personalTasks.create(
                title: "Persistent personal task",
                dueAt: date(2026, 7, 10, 18)
            )
            _ = try store.personalTasks.setCompleted(
                id: personalTask.id,
                isCompleted: true
            )
            contextID = context.id
            eventTaskID = eventTask.id
            floatingContextID = floatingContext.id
            floatingTaskID = floatingTask.id
            allDayContextID = allDayContext.id
            personalTaskID = personalTask.id
        }

        do {
            let database = try AppDatabase.open(at: databaseURL)
            let store = ContextStore(database: database)
            let brief = try XCTUnwrap(
                store.eventContexts.fetchBrief(contextID: contextID)
            )
            let floatingBrief = try XCTUnwrap(
                store.eventContexts.fetchBrief(contextID: floatingContextID)
            )
            let allDayBrief = try XCTUnwrap(
                store.eventContexts.fetchBrief(contextID: allDayContextID)
            )

            XCTAssertEqual(
                try database.appliedMigrations(),
                [
                    "v1_context_store",
                    "v2_event_change_log",
                    "v3_calendar_clarity",
                    "v4_task_provider",
                    "v5_oauth_task_providers",
                    "v6_context_references",
                    "v7_microsoft_to_do_provider",
                    "v8_calendar_usage",
                    "v9_saved_calendar_sets",
                    "v10_task_provider_recovery",
                    "v11_local_task_planning"
                ]
            )
            XCTAssertEqual(brief.context.notes, "Persistent notes")
            XCTAssertEqual(brief.tasks.map(\.id), [eventTaskID])
            XCTAssertTrue(try XCTUnwrap(brief.tasks.first).isCompleted)
            XCTAssertEqual(
                try XCTUnwrap(brief.tasks.first).due,
                .relative(anchor: .afterEnd, offsetMinutes: 45)
            )
            XCTAssertEqual(
                floatingBrief.tasks.map(\.id),
                [floatingTaskID]
            )
            XCTAssertEqual(
                try XCTUnwrap(floatingBrief.tasks.first).due,
                .fixed(date(2026, 7, 11, 8, 30))
            )
            XCTAssertEqual(floatingBrief.link.timeSemantics, .floating)
            XCTAssertNotNil(floatingBrief.link.startLocalComponents)
            XCTAssertEqual(allDayBrief.link.timeSemantics, .allDay)
            XCTAssertTrue(allDayBrief.link.isRecurring)
            XCTAssertNotNil(allDayBrief.link.occurrenceLocalComponents)
            XCTAssertTrue(
                allDayBrief.link.occurrenceIdentityKey
                    .hasPrefix("local:v1:")
            )
            XCTAssertEqual(
                try store.personalTasks.fetch(id: personalTaskID)?.title,
                "Persistent personal task"
            )
            XCTAssertTrue(
                try XCTUnwrap(
                    store.personalTasks.fetch(id: personalTaskID)
                ).isCompleted
            )
            XCTAssertEqual(
                try linkedContextID(store.resolve(event: event)),
                contextID
            )
            let storage = try database.read { db in
                try XCTUnwrap(Row.fetchOne(db, sql: """
                    SELECT
                        typeof(created_at) AS created_type,
                        created_at AS created_value
                    FROM event_contexts
                    WHERE id = ?
                    """, arguments: [contextID]))
            }
            XCTAssertEqual(storage["created_type"] as String?, "text")
            XCTAssertEqual(
                storage["created_value"] as String?,
                "2026-07-10 12:00:00.000"
            )
            let matchingCreationDates = try database.read { db in
                try EventContext
                    .filter(Column("created_at") == date(2026, 7, 10, 12))
                    .fetchCount(db)
            }
            XCTAssertEqual(matchingCreationDates, 3)
            let completedItems = try store.taskCenter.fetch(
                list: .completed,
                now: date(2026, 7, 10, 12),
                calendar: testCalendar
            )
            XCTAssertEqual(
                Set(completedItems.map(\.id)),
                Set([
                    .eventTask(
                        taskID: eventTaskID,
                        contextID: contextID
                    ),
                    .personalTask(taskID: personalTaskID)
                ])
            )
        }
    }

    func testMissingOrphanAndExplicitRelinkPreserveLocalBrief() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "recovery-original")
        let context = try XCTUnwrap(harness.store.saveNotes(
            for: original,
            notes: "Keep recovery notes"
        ))
        let task = try harness.store.appendEventTask(
            for: original,
            section: .after,
            title: "Keep recovery task"
        )
        let initial = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )

        let missing = try harness.store.markLinkedEventMissing(
            contextID: context.id
        )

        XCTAssertEqual(missing.link.linkStatus, .missing)
        XCTAssertEqual(missing.context.lifecycleStatus, .scheduled)
        XCTAssertEqual(missing.link.lastSeenAt, initial.link.lastSeenAt)
        XCTAssertEqual(missing.context.notes, "Keep recovery notes")
        XCTAssertEqual(missing.tasks.map(\.id), [task.id])
        XCTAssertEqual(
            try harness.store.fetchRecoveryBriefs().map(\.context.id),
            [context.id]
        )

        let orphan = try harness.store.keepLocalBriefAsOrphan(
            contextID: context.id
        )
        XCTAssertEqual(orphan.link.linkStatus, .orphaned)
        XCTAssertEqual(orphan.context.lifecycleStatus, .orphaned)

        let observed = try harness.store.observe(events: [original])
        guard case let .candidate(contextIDs, _) = observed.first else {
            return XCTFail("An orphan must require explicit relink")
        }
        XCTAssertEqual(contextIDs, [context.id])
        let stillOrphan = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(stillOrphan.link.linkStatus, .orphaned)
        XCTAssertEqual(stillOrphan.context.lifecycleStatus, .orphaned)
        XCTAssertThrowsError(try harness.store.saveNotes(
            for: original,
            notes: "Must not create a duplicate"
        )) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .identityConfirmationRequired([context.id])
            )
        }
        XCTAssertEqual(try harness.store.eventContexts.count(), 1)

        let replacement = makeEvent(
            id: "recovery-replacement",
            title: original.title,
            location: original.location,
            start: original.startDate,
            end: original.endDate,
            calendarIdentifier: "replacement-calendar"
        )
        let relinked = try harness.store.relinkLocalBrief(
            contextID: context.id,
            to: replacement,
            expectedLink: orphan.link,
            at: harness.now,
            calendar: testCalendar
        )

        XCTAssertEqual(relinked.link.linkStatus, .active)
        XCTAssertEqual(relinked.context.lifecycleStatus, .completed)
        XCTAssertEqual(relinked.link.calendarIdentifier, "replacement-calendar")
        XCTAssertEqual(relinked.context.notes, "Keep recovery notes")
        XCTAssertEqual(relinked.tasks.map(\.id), [task.id])
        let relinkChange = try XCTUnwrap(
            harness.store.changeHistory(contextID: context.id).first
        )
        XCTAssertEqual(relinkChange.changeType, .relinked)
        XCTAssertNil(relinkChange.before.originalNotes)
    }

    func testExplicitRelinkCollisionRollsBackMissingBrief() throws {
        let harness = try makeHarness()
        let first = makeEvent(id: "relink-collision-first")
        let second = makeEvent(
            id: "relink-collision-second",
            title: "Second linked event",
            start: date(2026, 7, 10, 11),
            end: date(2026, 7, 10, 12)
        )
        let firstContext = try XCTUnwrap(harness.store.saveNotes(
            for: first,
            notes: "First notes"
        ))
        let secondContext = try XCTUnwrap(harness.store.saveNotes(
            for: second,
            notes: "Second notes"
        ))
        let missing = try harness.store.markLinkedEventMissing(
            contextID: firstContext.id
        )

        XCTAssertThrowsError(try harness.store.relinkLocalBrief(
            contextID: firstContext.id,
            to: second,
            expectedLink: missing.link,
            at: harness.now,
            calendar: testCalendar
        )) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .eventAlreadyLinked(secondContext.id)
            )
        }

        let firstAfter = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: firstContext.id)
        )
        let secondAfter = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: secondContext.id)
        )
        XCTAssertEqual(firstAfter.link.linkStatus, .missing)
        XCTAssertEqual(firstAfter.context.notes, "First notes")
        XCTAssertEqual(secondAfter.link.eventIdentifier, second.eventIdentifier)
        XCTAssertEqual(secondAfter.context.notes, "Second notes")
        XCTAssertTrue(
            try harness.store.changeHistory(contextID: firstContext.id).isEmpty
        )
    }

    func testDeleteLocalBriefRequiresRecoveryStatusAndCascadesHistory() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "local-delete")
        let context = try XCTUnwrap(harness.store.saveNotes(
            for: original,
            notes: "Delete locally"
        ))
        let task = try harness.store.appendEventTask(
            for: original,
            section: .before,
            title: "Cascaded task"
        )

        XCTAssertThrowsError(try harness.store.deleteLocalBrief(
            contextID: context.id
        )) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidEventLinkTransition
            )
        }

        let missing = try harness.store.markLinkedEventMissing(
            contextID: context.id
        )
        let replacement = makeEvent(
            id: "local-delete-relinked",
            title: original.title,
            location: original.location,
            start: original.startDate,
            end: original.endDate
        )
        _ = try harness.store.relinkLocalBrief(
            contextID: context.id,
            to: replacement,
            expectedLink: missing.link,
            at: harness.now,
            calendar: testCalendar
        )
        _ = try harness.store.markLinkedEventMissing(contextID: context.id)
        XCTAssertFalse(
            try harness.store.changeHistory(contextID: context.id).isEmpty
        )

        try harness.store.deleteLocalBrief(contextID: context.id)

        XCTAssertNil(try harness.store.eventContexts.fetch(id: context.id))
        XCTAssertNil(try harness.store.eventTasks.fetch(id: task.id))
        XCTAssertTrue(
            try harness.store.changeHistory(contextID: context.id).isEmpty
        )
    }

    func testExplicitRelinkRejectsStaleLinkVersionWithoutMutation() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "stale-relink-original")
        let context = try XCTUnwrap(harness.store.saveNotes(
            for: original,
            notes: "Do not overwrite recovered link"
        ))
        let missing = try harness.store.markLinkedEventMissing(
            contextID: context.id
        )
        let recovered = makeEvent(
            id: original.id,
            title: "Recovered by normal observation",
            location: original.location,
            start: date(2026, 7, 10, 13),
            end: date(2026, 7, 10, 14)
        )
        let refreshed = try harness.store.refreshStrongLookup(
            contextID: context.id,
            event: recovered,
            at: harness.now,
            calendar: testCalendar
        )
        let staleCandidate = makeEvent(
            id: "stale-manual-candidate",
            title: "Stale manual candidate",
            start: date(2026, 7, 11, 9),
            end: date(2026, 7, 11, 10)
        )

        XCTAssertThrowsError(try harness.store.relinkLocalBrief(
            contextID: context.id,
            to: staleCandidate,
            expectedLink: missing.link,
            at: harness.now,
            calendar: testCalendar
        )) { error in
            XCTAssertEqual(
                error as? ContextStoreError,
                .invalidEventLinkTransition
            )
        }

        let after = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after.link, refreshed.link)
        XCTAssertEqual(after.context.notes, "Do not overwrite recovered link")
        XCTAssertTrue(
            try harness.store.changeHistory(contextID: context.id).isEmpty
        )
    }

    func testExplicitRelinkRejectsIdentifierlessCandidate() throws {
        let harness = try makeHarness()
        let original = makeEvent(id: "identifierless-original")
        let context = try XCTUnwrap(harness.store.saveNotes(
            for: original,
            notes: "Strong identity required"
        ))
        let missing = try harness.store.markLinkedEventMissing(
            contextID: context.id
        )
        let identifierless = makeEvent(
            id: "identifierless-candidate",
            title: "Identifierless",
            includeIdentifiers: false
        )

        XCTAssertThrowsError(try harness.store.relinkLocalBrief(
            contextID: context.id,
            to: identifierless,
            expectedLink: missing.link,
            at: harness.now,
            calendar: testCalendar
        )) { error in
            XCTAssertEqual(
                error as? CalendarEventLookupError,
                .missingStrongIdentifier
            )
        }

        let after = try XCTUnwrap(
            harness.store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after.link, missing.link)
        XCTAssertEqual(after.context.notes, "Strong identity required")
        XCTAssertTrue(
            try harness.store.changeHistory(contextID: context.id).isEmpty
        )
    }

    func testRelinkLogFailureRollsBackLinkAndLifecycle() throws {
        let database = try AppDatabase.inMemory()
        let timestamp = date(2026, 7, 10, 12)
        let store = ContextStore(
            database: database,
            now: { timestamp },
            makeID: IDSequence((1...20).map { "rollback-\($0)" }).next
        )
        let original = makeEvent(id: "relink-log-rollback")
        let context = try XCTUnwrap(store.saveNotes(
            for: original,
            notes: "Rollback notes"
        ))
        let missing = try store.markLinkedEventMissing(contextID: context.id)
        let candidate = makeEvent(
            id: "relink-log-candidate",
            title: "Verified candidate",
            start: date(2026, 7, 11, 9),
            end: date(2026, 7, 11, 10)
        )
        try database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_relink_log
                BEFORE INSERT ON event_change_log
                WHEN NEW.change_type = 'relinked'
                BEGIN
                    SELECT RAISE(ABORT, 'relink log rejected');
                END
                """)
        }

        XCTAssertThrowsError(try store.relinkLocalBrief(
            contextID: context.id,
            to: candidate,
            expectedLink: missing.link,
            at: timestamp,
            calendar: testCalendar
        ))

        let after = try XCTUnwrap(
            store.eventContexts.fetchBrief(contextID: context.id)
        )
        XCTAssertEqual(after.link, missing.link)
        XCTAssertEqual(after.context.lifecycleStatus, missing.context.lifecycleStatus)
        XCTAssertEqual(after.context.notes, "Rollback notes")
        XCTAssertTrue(try store.changeHistory(contextID: context.id).isEmpty)
    }

    func testStoredLookupQueryKeepsRecurringCivilAndInstantAnchors() throws {
        let harness = try makeHarness()
        let instant = date(2026, 7, 10, 9)
        let zoned = makeEvent(
            id: "lookup-zoned",
            start: instant,
            isRecurring: true,
            occurrenceDate: instant
        )
        let zonedContext = try XCTUnwrap(
            harness.store.saveNotes(for: zoned, notes: "Zoned")
        )
        let zonedQuery = try harness.store.linkedEventLookupTarget(
            contextID: zonedContext.id
        ).query
        XCTAssertEqual(zonedQuery.occurrence, .instant(instant))

        let civilStart = localComponents(2026, 7, 10, 9)
        let civilEnd = localComponents(2026, 7, 10, 10)
        let floating = makeEvent(
            id: "lookup-floating",
            start: date(2026, 7, 10, 16),
            end: date(2026, 7, 10, 17),
            isRecurring: true,
            occurrenceDate: date(2026, 7, 10, 16),
            occurrenceLocalComponents: civilStart,
            timeSemantics: .floating(start: civilStart, end: civilEnd)
        )
        let floatingContext = try XCTUnwrap(
            harness.store.saveNotes(for: floating, notes: "Floating")
        )
        let floatingQuery = try harness.store.linkedEventLookupTarget(
            contextID: floatingContext.id
        ).query
        XCTAssertEqual(floatingQuery.occurrence, .floating(civilStart))
    }

    func testSavedCalendarSetCRUDOrderingAndSelectionPersistence() throws {
        let database = try AppDatabase.inMemory()
        var current = date(2026, 7, 15, 9)
        let IDs = IDSequence([
            "focus-set", "focus-member", "home-set"
        ])
        let store = ContextStore(
            database: database,
            now: { current },
            makeID: IDs.next
        )
        let work = makeCalendarSource(id: "calendar-work", title: "Work")

        XCTAssertEqual(try store.calendarSets.fetchSelection(), .all)
        XCTAssertThrowsError(
            try store.calendarSets.create(name: " \n ", calendars: [])
        ) { error in
            XCTAssertEqual(error as? CalendarSetRepositoryError, .emptyName)
        }
        XCTAssertThrowsError(
            try store.calendarSets.create(
                name: String(repeating: "a", count: 81),
                calendars: []
            )
        ) { error in
            XCTAssertEqual(
                error as? CalendarSetRepositoryError,
                .nameTooLong(maximum: 80)
            )
        }
        let focus = try store.calendarSets.create(
            name: "  Focus  ",
            calendars: [work, work]
        )
        XCTAssertEqual(focus.id, "focus-set")
        XCTAssertEqual(focus.name, "Focus")
        XCTAssertEqual(focus.memberships.map(\.id), ["focus-member"])
        XCTAssertEqual(focus.calendarIdentifiers, [work.id])

        current = date(2026, 7, 15, 10)
        let renamed = try store.calendarSets.rename(
            id: focus.id,
            name: "Deep Focus"
        )
        XCTAssertEqual(renamed.name, "Deep Focus")
        XCTAssertEqual(renamed.calendarSet.createdAt, focus.calendarSet.createdAt)
        XCTAssertEqual(renamed.calendarSet.updatedAt, current)

        let home = try store.calendarSets.create(name: "Home", calendars: [])
        XCTAssertThrowsError(
            try store.calendarSets.create(name: " home ", calendars: [])
        ) { error in
            XCTAssertEqual(
                error as? CalendarSetRepositoryError,
                .duplicateName("home")
            )
        }

        try store.calendarSets.reorder(ids: [home.id, focus.id])
        XCTAssertEqual(
            try store.calendarSets.fetchAll().map(\.id),
            [home.id, focus.id]
        )
        XCTAssertThrowsError(
            try store.calendarSets.reorder(ids: [focus.id])
        ) { error in
            XCTAssertEqual(
                error as? CalendarSetRepositoryError,
                .invalidSetOrder
            )
        }
        XCTAssertEqual(
            try store.calendarSets.fetchAll().map(\.id),
            [home.id, focus.id]
        )

        try store.calendarSets.saveSelection(.role(.personal))
        XCTAssertEqual(
            try store.calendarSets.fetchSelection(),
            .role(.personal)
        )
        try store.calendarSets.saveSelection(.saved(home.id))
        XCTAssertEqual(try store.calendarSets.fetchSelection(), .saved(home.id))
        let reopenedStore = ContextStore(database: database)
        XCTAssertEqual(
            try reopenedStore.calendarSets.fetchAll().map(\.id),
            [home.id, focus.id]
        )
        XCTAssertEqual(
            try reopenedStore.calendarSets.fetchSelection(),
            .saved(home.id)
        )

        XCTAssertTrue(try store.calendarSets.delete(id: home.id))
        XCTAssertEqual(try store.calendarSets.fetchSelection(), .all)
        XCTAssertEqual(
            try database.read { db in
                try CalendarSetSelectionRecord.fetchCount(db)
            },
            0
        )
        XCTAssertFalse(try store.calendarSets.delete(id: home.id))

        try store.calendarSets.saveSelection(.saved(focus.id))
        try store.calendarSets.saveSelection(.all)
        XCTAssertEqual(try store.calendarSets.fetchSelection(), .all)
        XCTAssertEqual(
            try database.read { db in
                try CalendarSetSelectionRecord.fetchCount(db)
            },
            0
        )
        XCTAssertTrue(try store.calendarSets.delete(id: focus.id))
        XCTAssertEqual(try store.calendarSets.membershipCount(), 0)
    }

    func testSavedCalendarSetBulkUpdatePreservesMissingAndRequiresExplicitRebind() throws {
        let database = try AppDatabase.inMemory()
        var current = date(2026, 7, 15, 9)
        let IDs = IDSequence([
            "travel-set", "available-member", "missing-member", "new-member"
        ])
        let store = ContextStore(
            database: database,
            now: { current },
            makeID: IDs.next
        )
        let available = makeCalendarSource(
            id: "calendar-available",
            title: "Available"
        )
        let missing = makeCalendarSource(
            id: "calendar-missing",
            title: "Missing",
            sourceIdentifier: "old-source"
        )
        let added = makeCalendarSource(id: "calendar-added", title: "Added")
        let replacement = makeCalendarSource(
            id: "calendar-replacement",
            title: "Replacement",
            sourceIdentifier: "new-source"
        )
        let created = try store.calendarSets.create(
            name: "Travel",
            calendars: [available, missing]
        )
        let missingMembership = try XCTUnwrap(
            created.memberships.first(where: {
                $0.calendarIdentifier == missing.id
            })
        )

        current = date(2026, 7, 15, 10)
        let updated = try store.calendarSets.updateAvailableMemberships(
            setID: created.id,
            availableCalendarIDs: [available.id, added.id],
            selectedSources: [added]
        )
        XCTAssertEqual(
            updated.memberships.map(\.calendarIdentifier),
            [missing.id, added.id]
        )
        XCTAssertEqual(
            updated.memberships.first(where: {
                $0.calendarIdentifier == missing.id
            })?.id,
            missingMembership.id
        )

        let rebound = try store.calendarSets.rebindMembership(
            id: missingMembership.id,
            expectedCalendarIdentifier: missing.id,
            to: replacement
        )
        XCTAssertEqual(rebound.id, missingMembership.id)
        XCTAssertEqual(rebound.calendarIdentifier, replacement.id)
        XCTAssertEqual(rebound.sourceIdentifierSnapshot, "new-source")
        XCTAssertThrowsError(try store.calendarSets.rebindMembership(
            id: missingMembership.id,
            expectedCalendarIdentifier: missing.id,
            to: missing
        )) { error in
            XCTAssertEqual(
                error as? CalendarSetRepositoryError,
                .staleMembership(
                    membershipID: missingMembership.id,
                    expectedCalendarIdentifier: missing.id,
                    actualCalendarIdentifier: replacement.id
                )
            )
        }
        XCTAssertThrowsError(
            try store.calendarSets.add(replacement, to: created.id)
        ) { error in
            XCTAssertEqual(
                error as? CalendarSetRepositoryError,
                .duplicateMembership(
                    calendarSetID: created.id,
                    calendarIdentifier: replacement.id
                )
            )
        }

        let addedMembership = try XCTUnwrap(
            try store.calendarSets.fetch(id: created.id)?.memberships.first(
                where: { $0.calendarIdentifier == added.id }
            )
        )
        XCTAssertTrue(
            try store.calendarSets.removeMembership(id: addedMembership.id)
        )
        XCTAssertFalse(
            try store.calendarSets.removeMembership(id: addedMembership.id)
        )
        XCTAssertEqual(
            try store.calendarSets.fetch(id: created.id)?.calendarIdentifiers,
            [replacement.id]
        )

        XCTAssertThrowsError(
            try store.calendarSets.updateAvailableMemberships(
                setID: created.id,
                availableCalendarIDs: [available.id],
                selectedSources: [added]
            )
        ) { error in
            XCTAssertEqual(
                error as? CalendarSetRepositoryError,
                .selectedCalendarOutsideAvailableScope(added.id)
            )
        }
        XCTAssertEqual(
            try store.calendarSets.fetch(id: created.id)?.calendarIdentifiers,
            [replacement.id]
        )
    }

    private struct Harness {
        let store: ContextStore
        let now: Date
    }

    private func makeHarness() throws -> Harness {
        let now = date(2026, 7, 10, 12)
        let IDs = IDSequence((1...100).map { "id-\($0)" })
        let store = ContextStore(
            database: try AppDatabase.inMemory(),
            now: { now },
            makeID: IDs.next
        )
        return Harness(store: store, now: now)
    }

    private func linkedContextID(
        _ resolution: EventContextResolution
    ) throws -> String {
        guard case let .linked(contextID, _) = resolution else {
            throw TestError.expectedLinkedContext
        }
        return contextID
    }

    private enum TestError: Error {
        case expectedLinkedContext
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        testCalendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func localComponents(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> LocalDateTimeComponents {
        LocalDateTimeComponents(
            date: date(year, month, day, hour, minute),
            calendar: testCalendar
        )
    }

    private func makeCalendarSource(
        id: String,
        title: String,
        sourceIdentifier: String = "source"
    ) -> CalendarSource {
        CalendarSource(
            id: id,
            title: title,
            sourceTitle: "Exchange",
            sourceIdentifier: sourceIdentifier,
            accountType: .exchange,
            isWritable: true,
            color: nil
        )
    }

    private func makeEvent(
        id: String,
        title: String = "Team Sync",
        location: String? = "Room A",
        start: Date? = nil,
        end: Date? = nil,
        externalIdentifier: String? = nil,
        calendarIdentifier: String = "calendar",
        isRecurring: Bool = false,
        occurrenceDate: Date? = nil,
        occurrenceLocalComponents: LocalDateTimeComponents? = nil,
        isDetached: Bool = false,
        includeIdentifiers: Bool = true,
        isAllDay: Bool = false,
        timeSemantics: EventTimeSemantics? = nil
    ) -> DisplayEvent {
        let start = start ?? date(2026, 7, 10, 9)
        let end = end ?? date(2026, 7, 10, 10)
        let timeSemantics = timeSemantics
            ?? .zoned(timeZoneIdentifier: "UTC")
        let timeZoneIdentifier: String?
        switch timeSemantics {
        case let .zoned(identifier):
            timeZoneIdentifier = identifier
        case .allDay, .floating:
            timeZoneIdentifier = nil
        }
        return DisplayEvent(
            id: id,
            eventIdentifier: includeIdentifiers ? "event-id-\(id)" : nil,
            calendarItemIdentifier: includeIdentifiers ? "item-id-\(id)" : nil,
            calendarItemExternalIdentifier: externalIdentifier,
            calendarIdentifier: calendarIdentifier,
            calendarTitle: "KAOS-TEST",
            sourceTitle: "Work",
            accountType: .exchange,
            calendarColor: nil,
            title: title,
            location: location,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            timeSemantics: timeSemantics,
            isRecurring: isRecurring,
            occurrenceDate: occurrenceDate,
            occurrenceLocalComponents: occurrenceLocalComponents,
            isDetached: isDetached,
            isReadOnly: false,
            isInvitation: false,
            hasAttendees: false,
            originalNotes: nil
        )
    }
}

private final class IDSequence {
    private var values: [String]
    private var fallback = 0

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        if !values.isEmpty {
            return values.removeFirst()
        }
        fallback += 1
        return "fallback-\(fallback)"
    }
}

final class InMemoryOAuthCredentialStore: OAuthCredentialStoring {
    private var credentials: [TaskProviderKind: OAuthCredential]

    init(_ credentials: [TaskProviderKind: OAuthCredential] = [:]) {
        self.credentials = credentials
    }

    func loadCredential(for provider: TaskProviderKind) throws -> OAuthCredential? {
        credentials[provider]
    }

    func saveCredential(_ credential: OAuthCredential) throws {
        credentials[credential.provider] = credential
    }

    func deleteCredential(for provider: TaskProviderKind) throws {
        credentials[provider] = nil
    }
}

@MainActor
final class StubAppleTaskListingProvider: TaskProviding, TaskSnapshotListing {
    let provider: TaskProviderKind = .appleReminders
    let capabilities = TaskProviderCapabilities(
        supportsNotes: true,
        supportsTimedDue: true,
        supportsCompletion: true,
        supportsDeletion: true,
        supportsDeepLink: true,
        supportsListMove: true,
        supportsPriority: true
    )
    var authorizationState: TaskProviderAuthorizationState = .authorized
    var storeChangeHandler: (() -> Void)?
    var requestAccessCount = 0
    var refreshAuthorizationStateCount = 0
    var grantsAccessOnRequest = true
    var listTaskListsError: TaskProviderError?
    var createTaskError: TaskProviderError?
    var updateTaskError: TaskProviderError?
    var deleteTaskError: TaskProviderError?
    var moveTaskError: TaskProviderError?
    private(set) var createTaskCount = 0
    private(set) var updateTaskCount = 0
    private(set) var deleteTaskCount = 0
    private(set) var moveTaskCount = 0

    private let lists: [RemoteTaskList]
    private var tasks: [RemoteTaskSnapshot]

    var snapshots: [RemoteTaskSnapshot] { tasks }

    init(
        lists: [RemoteTaskList],
        tasks: [RemoteTaskSnapshot],
        authorizationState: TaskProviderAuthorizationState = .authorized
    ) {
        self.lists = lists
        self.tasks = tasks
        self.authorizationState = authorizationState
    }

    func requestFullAccess() async throws -> Bool {
        requestAccessCount += 1
        if grantsAccessOnRequest {
            authorizationState = .authorized
        }
        return grantsAccessOnRequest
    }

    func refreshAuthorizationState() {
        refreshAuthorizationStateCount += 1
    }

    func listTaskLists() throws -> [RemoteTaskList] {
        if let listTaskListsError { throw listTaskListsError }
        return lists
    }

    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot] {
        let listIDs = Set(lists.map(\.id))
        return tasks.filter { listIDs.contains($0.parentID) }
    }

    func replaceSnapshot(_ snapshot: RemoteTaskSnapshot) {
        if let index = tasks.firstIndex(where: {
            $0.id == snapshot.id && $0.parentID == snapshot.parentID
        }) {
            tasks[index] = snapshot
        } else {
            tasks.append(snapshot)
        }
    }

    func removeSnapshot(id: String, parentID: String) {
        tasks.removeAll { $0.id == id && $0.parentID == parentID }
    }

    func createTask(_ draft: RemoteTaskDraft) throws -> RemoteTaskSnapshot {
        createTaskCount += 1
        if let createTaskError { throw createTaskError }
        let created = RemoteTaskSnapshot(
            id: "created-\(tasks.count + 1)",
            parentID: draft.parentID,
            parentAccountKey: lists.first {
                $0.id == draft.parentID
            }?.accountKey,
            title: draft.title,
            notes: draft.notes,
            dueAt: draft.dueAt,
            isCompleted: false,
            priority: draft.priority,
            version: "created-v1",
            deepLink: draft.deepLink
        )
        tasks.append(created)
        return created
    }

    func updateTask(
        _ task: RemoteTaskSnapshot,
        with patch: RemoteTaskPatch
    ) throws -> RemoteTaskSnapshot {
        updateTaskCount += 1
        if let updateTaskError { throw updateTaskError }
        guard let index = tasks.firstIndex(where: {
            $0.id == task.id && $0.parentID == task.parentID
        }) else {
            throw TaskProviderError.taskNotFound
        }
        let dueAt: Date?
        switch patch.dueAt {
        case .none:
            dueAt = task.dueAt
        case let .some(value):
            dueAt = value
        }
        let updated = RemoteTaskSnapshot(
            id: task.id,
            parentID: task.parentID,
            parentAccountKey: task.parentAccountKey,
            title: patch.title ?? task.title,
            notes: patch.notes ?? task.notes,
            dueAt: dueAt,
            isCompleted: patch.isCompleted ?? task.isCompleted,
            priority: patch.priority ?? task.priority,
            version: "\(task.version ?? "version")-updated",
            deepLink: task.deepLink
        )
        tasks[index] = updated
        return updated
    }

    func deleteTask(
        _ task: RemoteTaskSnapshot,
        expectedVersion: String?
    ) throws {
        deleteTaskCount += 1
        if let deleteTaskError { throw deleteTaskError }
        guard tasks.contains(where: {
            $0.id == task.id && $0.parentID == task.parentID
        }) else {
            throw TaskProviderError.taskNotFound
        }
        removeSnapshot(id: task.id, parentID: task.parentID)
    }

    func moveTask(
        _ task: RemoteTaskSnapshot,
        to list: RemoteTaskList
    ) throws -> RemoteTaskSnapshot {
        moveTaskCount += 1
        if let moveTaskError { throw moveTaskError }
        guard let index = tasks.firstIndex(where: {
            $0.id == task.id && $0.parentID == task.parentID
        }), lists.contains(where: {
            $0.id == list.id
                && $0.accountKey == list.accountKey
                && $0.isWritable
        }) else {
            throw TaskProviderError.listUnavailable
        }
        let moved = RemoteTaskSnapshot(
            id: task.id,
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: task.title,
            notes: task.notes,
            dueAt: task.dueAt,
            isCompleted: task.isCompleted,
            priority: task.priority,
            version: "\(task.version ?? "version")-moved",
            deepLink: task.deepLink
        )
        tasks[index] = moved
        return moved
    }

    func lookupTask(
        id: String,
        parentID: String
    ) throws -> RemoteTaskSnapshot? {
        tasks.first { $0.id == id && $0.parentID == parentID }
    }
}

@MainActor
private final class StubAsyncTaskProvider: AsyncTaskProviding {
    let provider: TaskProviderKind
    let capabilities: TaskProviderCapabilities
    var authorizationState: TaskProviderAuthorizationState = .authorized
    private let lists: [RemoteTaskList]
    private var tasks: [RemoteTaskSnapshot]
    private var nextID = 1
    var listTaskListsError: TaskProviderError?

    var snapshots: [RemoteTaskSnapshot] { tasks }

    init(
        provider: TaskProviderKind,
        lists: [RemoteTaskList],
        tasks: [RemoteTaskSnapshot]
    ) {
        self.provider = provider
        self.lists = lists
        self.tasks = tasks
        capabilities = TaskProviderCapabilities(
            supportsNotes: true,
            supportsTimedDue: provider != .googleTasks,
            supportsCompletion: true,
            supportsDeletion: true,
            supportsDeepLink: provider == .todoist
                || provider == .microsoftToDo,
            supportsListMove: provider == .todoist,
            supportsPriority: provider == .todoist
                || provider == .microsoftToDo,
            supportsReminder: provider == .microsoftToDo
        )
    }

    func listTaskLists() async throws -> [RemoteTaskList] {
        if let listTaskListsError { throw listTaskListsError }
        return lists
    }

    func listTasks(
        in lists: [RemoteTaskList]
    ) async throws -> [RemoteTaskSnapshot] {
        let identities = Set(lists.map {
            "\($0.accountKey)\u{1F}\($0.id)"
        })
        return tasks.filter {
            guard let account = $0.parentAccountKey else { return false }
            return identities.contains("\(account)\u{1F}\($0.parentID)")
        }
    }

    func createTask(
        _ draft: RemoteTaskDraft
    ) async throws -> RemoteTaskSnapshot {
        guard let list = lists.first(where: {
            $0.id == draft.parentID && $0.isWritable
        }) else {
            throw TaskProviderError.listUnavailable
        }
        let task = RemoteTaskSnapshot(
            id: "async-created-\(nextID)",
            parentID: draft.parentID,
            parentAccountKey: list.accountKey,
            title: draft.title,
            notes: draft.notes,
            dueAt: draft.dueAt,
            reminderAt: draft.reminderAt,
            isCompleted: false,
            priority: draft.priority,
            version: "created-v1",
            deepLink: draft.deepLink
        )
        nextID += 1
        tasks.append(task)
        return task
    }

    func updateTask(
        _ task: RemoteTaskSnapshot,
        with patch: RemoteTaskPatch
    ) async throws -> RemoteTaskSnapshot {
        guard let index = tasks.firstIndex(where: {
            $0.id == task.id && $0.parentID == task.parentID
        }), tasks[index].version == task.version else {
            throw TaskProviderError.conflict
        }
        let dueAt: Date?
        switch patch.dueAt {
        case .none:
            dueAt = task.dueAt
        case let .some(value):
            dueAt = value
        }
        let reminderAt: Date?
        switch patch.reminderAt {
        case .none:
            reminderAt = task.reminderAt
        case let .some(value):
            reminderAt = value
        }
        let updated = RemoteTaskSnapshot(
            id: task.id,
            parentID: task.parentID,
            parentAccountKey: task.parentAccountKey,
            title: patch.title ?? task.title,
            notes: patch.notes ?? task.notes,
            dueAt: dueAt,
            reminderAt: reminderAt,
            isCompleted: patch.isCompleted ?? task.isCompleted,
            priority: patch.priority ?? task.priority,
            version: "\(task.version ?? "v")-next",
            deepLink: task.deepLink
        )
        tasks[index] = updated
        return updated
    }

    func deleteTask(
        _ task: RemoteTaskSnapshot,
        expectedVersion: String?
    ) async throws {
        guard let index = tasks.firstIndex(where: {
            $0.id == task.id && $0.parentID == task.parentID
        }) else {
            throw TaskProviderError.taskNotFound
        }
        guard tasks[index].version == expectedVersion else {
            throw TaskProviderError.conflict
        }
        tasks.remove(at: index)
    }

    func moveTask(
        _ task: RemoteTaskSnapshot,
        to list: RemoteTaskList
    ) async throws -> RemoteTaskSnapshot {
        guard capabilities.supportsListMove,
              list.provider == provider,
              let index = tasks.firstIndex(where: {
                  $0.id == task.id && $0.parentID == task.parentID
              }), tasks[index].version == task.version,
              lists.contains(where: {
                  $0.provider == list.provider
                      && $0.accountKey == list.accountKey
                      && $0.id == list.id
                      && $0.isWritable
              }) else {
            throw TaskProviderError.listUnavailable
        }
        let moved = RemoteTaskSnapshot(
            id: task.id,
            parentID: list.id,
            parentAccountKey: list.accountKey,
            title: task.title,
            notes: task.notes,
            dueAt: task.dueAt,
            reminderAt: task.reminderAt,
            isCompleted: task.isCompleted,
            priority: task.priority,
            version: "\(task.version ?? "v")-moved",
            deepLink: task.deepLink
        )
        tasks[index] = moved
        return moved
    }

    func lookupTask(
        id: String,
        parentID: String
    ) async throws -> RemoteTaskSnapshot? {
        tasks.first { $0.id == id && $0.parentID == parentID }
    }
}

private final class StubOAuthTransport: OAuthHTTPTransport {
    private var responses: [String: (Data, HTTPURLResponse)]

    init(responses: [String: (Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let host = request.url?.host, let response = responses[host] else {
            throw TaskProviderError.providerFailure("Unexpected OAuth test request.")
        }
        return response
    }
}

private final class URLStubOAuthTransport: OAuthHTTPTransport {
    private let responses: [String: (Data, HTTPURLResponse)]

    init(responses: [String: (Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let key = request.url?.absoluteString,
              let response = responses[key] else {
            throw TaskProviderError.providerFailure("Unexpected paged OAuth test request.")
        }
        return response
    }
}

private final class QueuedOAuthTransport: OAuthHTTPTransport {
    private var responses: [(Data, HTTPURLResponse)]
    private(set) var requestCount = 0
    private(set) var requestedPaths = [String]()

    init(responses: [(Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        requestedPaths.append(request.url?.path ?? "")
        guard !responses.isEmpty else {
            throw TaskProviderError.providerFailure("Unexpected OAuth retry request.")
        }
        return responses.removeFirst()
    }
}

private extension ContextStoreTests {
    static func oauthConfiguration(
        _ provider: TaskProviderKind
    ) throws -> OAuthProviderConfiguration {
        OAuthProviderConfiguration(
            provider: provider,
            clientID: "test-client",
            redirectURI: try XCTUnwrap(
                URL(string: "http://127.0.0.1:43891/oauth/callback")
            )
        )
    }

    static func httpResponse(
        host: String,
        json: String,
        statusCode: Int = 200
    ) -> (Data, HTTPURLResponse) {
        (
            Data(json.utf8),
            HTTPURLResponse(
                url: URL(string: "https://\(host)/")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
