import Foundation

@MainActor
protocol AsyncTaskProviding: AnyObject {
    var provider: TaskProviderKind { get }
    var capabilities: TaskProviderCapabilities { get }
    var authorizationState: TaskProviderAuthorizationState { get }
    func listTaskLists() async throws -> [RemoteTaskList]
    func createTask(_ draft: RemoteTaskDraft) async throws -> RemoteTaskSnapshot
    func updateTask(_ task: RemoteTaskSnapshot, with patch: RemoteTaskPatch) async throws -> RemoteTaskSnapshot
    func moveTask(_ task: RemoteTaskSnapshot, to list: RemoteTaskList) async throws -> RemoteTaskSnapshot
    func deleteTask(_ task: RemoteTaskSnapshot, expectedVersion: String?) async throws
    func lookupTask(id: String, parentID: String) async throws -> RemoteTaskSnapshot?
    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot]
}

extension AsyncTaskProviding {
    func moveTask(
        _ task: RemoteTaskSnapshot,
        to list: RemoteTaskList
    ) async throws -> RemoteTaskSnapshot {
        throw TaskProviderError.unsupported(
            "This provider does not support moving tasks between lists."
        )
    }

    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot] {
        []
    }
}

@MainActor
final class GoogleTasksProvider: AsyncTaskProviding {
    let provider: TaskProviderKind = .googleTasks
    let capabilities = TaskProviderCapabilities(
        supportsNotes: true, supportsTimedDue: false, supportsCompletion: true,
        supportsDeletion: true, supportsDeepLink: false
    )
    private let session: OAuthTaskProviderSession
    private let accountKey: String
    private let displayName: String

    init(session: OAuthTaskProviderSession, accountKey: String, displayName: String) {
        self.session = session
        self.accountKey = accountKey
        self.displayName = displayName
    }

    var authorizationState: TaskProviderAuthorizationState { session.authorizationState }

    func listTaskLists() async throws -> [RemoteTaskList] {
        var pageToken: String?
        var seenTokens = Set<String>()
        var lists = [List]()
        repeat {
            let (data, _) = try await session.send {
                GoogleTasksAPI.taskListsRequest(
                    accessToken: $0,
                    pageToken: pageToken
                )
            }
            let page = try JSONDecoder().decode(ListResponse.self, from: data)
            lists.append(contentsOf: page.items ?? [])
            pageToken = page.nextPageToken
            if let pageToken, !seenTokens.insert(pageToken).inserted {
                throw TaskProviderError.providerFailure(
                    "Google Tasks returned a repeated task-list page cursor."
                )
            }
        } while pageToken != nil
        return lists.map {
            RemoteTaskList(provider: .googleTasks, id: $0.id, accountKey: accountKey, title: $0.title, sourceTitle: displayName, isWritable: true)
        }
    }

    func createTask(_ draft: RemoteTaskDraft) async throws -> RemoteTaskSnapshot {
        let (data, _) = try await session.send {
            try GoogleTasksAPI.createTaskRequest(listID: draft.parentID, title: draft.title, notes: draft.notes, dueAt: draft.dueAt, accessToken: $0)
        }
        return try snapshot(from: data, parentID: draft.parentID)
    }

    func updateTask(_ task: RemoteTaskSnapshot, with patch: RemoteTaskPatch) async throws -> RemoteTaskSnapshot {
        let (data, _) = try await session.send {
            try GoogleTasksAPI.updateTaskRequest(listID: task.parentID, taskID: task.id, patch: patch, expectedETag: task.version, accessToken: $0)
        }
        return try snapshot(from: data, parentID: task.parentID)
    }

    func deleteTask(_ task: RemoteTaskSnapshot, expectedVersion: String?) async throws {
        _ = try await session.send { GoogleTasksAPI.deleteTaskRequest(listID: task.parentID, taskID: task.id, expectedETag: expectedVersion, accessToken: $0) }
    }

    func lookupTask(id: String, parentID: String) async throws -> RemoteTaskSnapshot? {
        do {
            let (data, _) = try await session.send { GoogleTasksAPI.taskRequest(listID: parentID, taskID: id, accessToken: $0) }
            return try snapshot(from: data, parentID: parentID)
        } catch TaskProviderError.taskNotFound { return nil }
    }

    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot] {
        var snapshots = [RemoteTaskSnapshot]()
        for list in lists where list.provider == .googleTasks
            && list.accountKey == accountKey {
            var pageToken: String?
            var seenTokens = Set<String>()
            repeat {
                let (data, _) = try await session.send {
                    GoogleTasksAPI.tasksRequest(
                        listID: list.id,
                        pageToken: pageToken,
                        accessToken: $0
                    )
                }
                let page = try JSONDecoder().decode(TaskPage.self, from: data)
                snapshots.append(contentsOf: (page.items ?? []).map {
                    snapshot($0, parentID: list.id)
                })
                pageToken = page.nextPageToken
                if let pageToken, !seenTokens.insert(pageToken).inserted {
                    throw TaskProviderError.providerFailure(
                        "Google Tasks returned a repeated task page cursor."
                    )
                }
            } while pageToken != nil
        }
        return snapshots
    }

    private func snapshot(from data: Data, parentID: String) throws -> RemoteTaskSnapshot {
        snapshot(try JSONDecoder().decode(Task.self, from: data), parentID: parentID)
    }

    private func snapshot(_ task: Task, parentID: String) -> RemoteTaskSnapshot {
        return RemoteTaskSnapshot(
            id: task.id,
            parentID: parentID,
            parentAccountKey: accountKey,
            title: task.title ?? "",
            notes: task.notes ?? "",
            dueAt: task.due.flatMap { GoogleTaskDueDateCodec().decode($0) },
            isCompleted: task.status == "completed",
            version: task.etag,
            deepLink: nil
        )
    }

    private struct ListResponse: Decodable {
        let items: [List]?
        let nextPageToken: String?
    }
    private struct TaskPage: Decodable {
        let items: [Task]?
        let nextPageToken: String?
    }
    private struct List: Decodable { let id: String; let title: String }
    private struct Task: Decodable { let id: String; let title: String?; let notes: String?; let due: String?; let status: String?; let etag: String? }
}

@MainActor
final class TodoistTasksProvider: AsyncTaskProviding {
    let provider: TaskProviderKind = .todoist
    let capabilities = TaskProviderCapabilities(
        supportsNotes: true, supportsTimedDue: true, supportsCompletion: true,
        supportsDeletion: true, supportsDeepLink: true,
        supportsListMove: true,
        supportsPriority: true
    )
    private let session: OAuthTaskProviderSession
    private let accountKey: String
    private let displayName: String
    private let now: () -> Date
    private var activeMutationTaskIDs = Set<String>()
    private var mutationWaiters:
        [String: [CheckedContinuation<Void, Never>]] = [:]

    init(
        session: OAuthTaskProviderSession,
        accountKey: String,
        displayName: String,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.accountKey = accountKey
        self.displayName = displayName
        self.now = now
    }

    var authorizationState: TaskProviderAuthorizationState { session.authorizationState }

    func listTaskLists() async throws -> [RemoteTaskList] {
        let projects = try await allPages(
            request: { TodoistAPI.projectsRequest(accessToken: $0, cursor: $1) },
            type: ProjectPage.self
        )
        let sections = try await allPages(
            request: { TodoistAPI.sectionsRequest(accessToken: $0, cursor: $1) },
            type: SectionPage.self
        )
        let projectNames = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0.name) }
        )
        let projectLists = projects.map {
            RemoteTaskList(provider: .todoist, id: "project:\($0.id)", accountKey: accountKey, title: $0.name, sourceTitle: displayName, isWritable: true)
        }
        let sectionLists = sections.map { section in
            let projectName = projectNames[section.projectID] ?? "Project"
            return RemoteTaskList(
                provider: .todoist,
                id: "section:\(section.id)",
                accountKey: accountKey,
                title: "\(projectName) › \(section.name)",
                sourceTitle: displayName,
                isWritable: true
            )
        }
        return projectLists + sectionLists
    }

    func createTask(_ draft: RemoteTaskDraft) async throws -> RemoteTaskSnapshot {
        let (data, _) = try await session.send {
            try TodoistAPI.createTaskRequest(parentID: draft.parentID, title: draft.title, description: draft.notes, dueAt: draft.dueAt, priority: draft.priority, accessToken: $0)
        }
        return try snapshot(from: data, fallbackParentID: draft.parentID)
    }

    func updateTask(_ task: RemoteTaskSnapshot, with patch: RemoteTaskPatch) async throws -> RemoteTaskSnapshot {
        try await withSerializedMutation(taskID: task.id) {
            try await updateTaskWithoutSerialization(task, with: patch)
        }
    }

    private func updateTaskWithoutSerialization(
        _ task: RemoteTaskSnapshot,
        with patch: RemoteTaskPatch
    ) async throws -> RemoteTaskSnapshot {
        let editsFields = patch.title != nil || patch.notes != nil
            || patch.dueAt != nil || patch.priority != nil
        var updated = task
        if editsFields {
            let (data, _) = try await session.send {
                try TodoistAPI.updateTaskRequest(
                    id: task.id,
                    patch: patch,
                    accessToken: $0
                )
            }
            updated = try snapshot(from: data, fallbackParentID: task.parentID)
        }
        guard let completed = patch.isCompleted,
              completed != updated.isCompleted else {
            return updated
        }
        // Apply ordinary fields while the task is active, then close it. A
        // completed task is no longer available from Todoist's active endpoint.
        _ = try await session.send {
            TodoistAPI.completionRequest(
                id: task.id,
                completed: completed,
                accessToken: $0
            )
        }
        // The completion endpoint has no task body. Prefer the provider's new
        // version when it is already visible, but do not report a successful
        // close/reopen as failed solely because archive projection is delayed.
        if let refreshed = try? await lookupTask(
            id: task.id,
            parentID: task.parentID
        ), refreshed.isCompleted == completed {
            return refreshed
        }
        return replacingCompletion(in: updated, with: completed)
    }

    func moveTask(
        _ task: RemoteTaskSnapshot,
        to list: RemoteTaskList
    ) async throws -> RemoteTaskSnapshot {
        try await withSerializedMutation(taskID: task.id) {
            try await moveTaskWithoutSerialization(task, to: list)
        }
    }

    private func moveTaskWithoutSerialization(
        _ task: RemoteTaskSnapshot,
        to list: RemoteTaskList
    ) async throws -> RemoteTaskSnapshot {
        guard list.provider == .todoist,
              list.accountKey == accountKey,
              list.isWritable else {
            throw TaskProviderError.listUnavailable
        }
        let (data, _) = try await session.send {
            try TodoistAPI.moveTaskRequest(
                id: task.id,
                parentID: list.id,
                accessToken: $0
            )
        }
        return try snapshot(from: data, fallbackParentID: list.id)
    }

    func deleteTask(_ task: RemoteTaskSnapshot, expectedVersion: String?) async throws {
        try await withSerializedMutation(taskID: task.id) {
            _ = try await session.send {
                TodoistAPI.deleteTaskRequest(id: task.id, accessToken: $0)
            }
        }
    }

    func lookupTask(id: String, parentID: String) async throws -> RemoteTaskSnapshot? {
        do {
            let (data, _) = try await session.send { TodoistAPI.taskRequest(id: id, accessToken: $0) }
            return try snapshot(from: data, fallbackParentID: parentID)
        } catch TaskProviderError.taskNotFound {
            return try await completedTask(id: id, parentID: parentID)
        }
    }

    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot] {
        var snapshots = [RemoteTaskSnapshot]()
        for list in lists where list.provider == .todoist
            && list.accountKey == accountKey {
            let tasks = try await allPages(
                request: {
                    TodoistAPI.tasksRequest(
                        parentID: list.id,
                        cursor: $1,
                        accessToken: $0
                    )
                },
                type: TaskPage.self
            )
            snapshots.append(contentsOf: tasks.map {
                snapshot($0, fallbackParentID: list.id)
            })
            snapshots.append(contentsOf: try await recentCompletedTasks(
                parentID: list.id
            ))
        }
        var seen = Set<String>()
        return snapshots.filter {
            seen.insert("\($0.parentAccountKey ?? accountKey)\u{1F}\($0.parentID)\u{1F}\($0.id)")
                .inserted
        }
    }

    private func completedTask(
        id: String,
        parentID: String
    ) async throws -> RemoteTaskSnapshot? {
        try await recentCompletedTasks(parentID: parentID).first {
            $0.id == id
        }
    }

    private func recentCompletedTasks(
        parentID: String
    ) async throws -> [RemoteTaskSnapshot] {
        let until = now()
        let since = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -90,
            to: until
        ) ?? until
        var cursor: String?
        var seenCursors = Set<String>()
        var snapshots = [RemoteTaskSnapshot]()
        repeat {
            let (data, _) = try await session.send {
                TodoistAPI.completedTasksRequest(
                    parentID: parentID,
                    since: since,
                    until: until,
                    cursor: cursor,
                    accessToken: $0
                )
            }
            let page = try JSONDecoder().decode(CompletedTaskPage.self, from: data)
            snapshots.append(contentsOf: page.items.map {
                snapshot($0, fallbackParentID: parentID)
            })
            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw TaskProviderError.providerFailure(
                    "Todoist returned a repeated completed-task cursor."
                )
            }
        } while cursor != nil
        return snapshots
    }

    private func allPages<Page: CursorPage>(
        request: (String, String?) -> URLRequest,
        type: Page.Type
    ) async throws -> [Page.Element] {
        var cursor: String?
        var seenCursors = Set<String>()
        var values = [Page.Element]()
        repeat {
            let (data, _) = try await session.send { request($0, cursor) }
            let page = try JSONDecoder().decode(Page.self, from: data)
            values.append(contentsOf: page.results)
            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw TaskProviderError.providerFailure(
                    "Todoist returned a repeated list page cursor."
                )
            }
        } while cursor != nil
        return values
    }

    private func withSerializedMutation<Value>(
        taskID: String,
        operation: () async throws -> Value
    ) async throws -> Value {
        await acquireMutation(taskID: taskID)
        do {
            try _Concurrency.Task<Never, Never>.checkCancellation()
            let value = try await operation()
            releaseMutation(taskID: taskID)
            return value
        } catch {
            releaseMutation(taskID: taskID)
            throw error
        }
    }

    private func acquireMutation(taskID: String) async {
        guard activeMutationTaskIDs.contains(taskID) else {
            activeMutationTaskIDs.insert(taskID)
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters[taskID, default: []].append(continuation)
        }
    }

    private func releaseMutation(taskID: String) {
        guard var waiters = mutationWaiters[taskID],
              !waiters.isEmpty else {
            mutationWaiters[taskID] = nil
            activeMutationTaskIDs.remove(taskID)
            return
        }
        let next = waiters.removeFirst()
        mutationWaiters[taskID] = waiters.isEmpty ? nil : waiters
        next.resume()
    }

    private func snapshot(from data: Data, fallbackParentID: String) throws -> RemoteTaskSnapshot {
        snapshot(
            try JSONDecoder().decode(Task.self, from: data),
            fallbackParentID: fallbackParentID
        )
    }

    private func snapshot(
        _ task: Task,
        fallbackParentID: String
    ) -> RemoteTaskSnapshot {
        let formatter = ISO8601DateFormatter()
        let parentID = task.sectionID.map { "section:\($0)" } ?? task.projectID.map { "project:\($0)" } ?? fallbackParentID
        return RemoteTaskSnapshot(
            id: task.id,
            parentID: parentID,
            parentAccountKey: accountKey,
            title: task.content,
            notes: task.description ?? "",
            dueAt: task.due?.dateTime.flatMap { formatter.date(from: $0) }
                ?? task.due?.date.flatMap {
                    formatter.date(from: $0 + "T00:00:00Z")
                },
            isCompleted: task.completedAt != nil,
            priority: taskPriority(task.priority),
            version: task.updatedAt,
            deepLink: URL(string: "https://app.todoist.com/app/task/\(task.id)")
        )
    }

    private protocol CursorPage: Decodable {
        associatedtype Element
        var results: [Element] { get }
        var nextCursor: String? { get }
    }
    private struct ProjectPage: CursorPage {
        let results: [Project]
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case results; case nextCursor = "next_cursor" }
    }
    private struct Project: Decodable { let id: String; let name: String }
    private struct SectionPage: CursorPage {
        let results: [Section]
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case results; case nextCursor = "next_cursor" }
    }
    private struct TaskPage: CursorPage {
        let results: [Task]
        let nextCursor: String?
        enum CodingKeys: String, CodingKey {
            case results
            case nextCursor = "next_cursor"
        }
    }
    private struct Section: Decodable {
        let id: String
        let projectID: String
        let name: String
        enum CodingKeys: String, CodingKey { case id, name; case projectID = "project_id" }
    }
    private struct CompletedTaskPage: Decodable {
        let items: [Task]
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" }
    }
    private struct Task: Decodable {
        let id: String; let content: String; let description: String?; let projectID: String?; let sectionID: String?; let due: Due?; let completedAt: String?; let updatedAt: String?; let priority: Int?
        enum CodingKeys: String, CodingKey { case id, content, description, due, priority; case projectID = "project_id"; case sectionID = "section_id"; case completedAt = "completed_at"; case updatedAt = "updated_at" }
        struct Due: Decodable { let date: String?; let dateTime: String?; enum CodingKeys: String, CodingKey { case date; case dateTime = "datetime" } }
    }

    private func taskPriority(_ value: Int?) -> TaskPriority {
        switch value {
        case 4: .high
        case 3: .medium
        case 2: .low
        default: .none
        }
    }

    private func replacingCompletion(
        in task: RemoteTaskSnapshot,
        with isCompleted: Bool
    ) -> RemoteTaskSnapshot {
        RemoteTaskSnapshot(
            id: task.id,
            parentID: task.parentID,
            parentAccountKey: task.parentAccountKey,
            title: task.title,
            notes: task.notes,
            dueAt: task.dueAt,
            reminderAt: task.reminderAt,
            isCompleted: isCompleted,
            priority: task.priority,
            version: task.version,
            deepLink: task.deepLink
        )
    }
}

struct MicrosoftToDoDelta: Equatable {
    let tasks: [RemoteTaskSnapshot]
    let deletedTaskIDs: [String]
    /// The Graph-supplied opaque URL to use for the next delta round.
    let cursor: URL?
}

@MainActor
protocol MicrosoftToDoDeltaProviding: AnyObject {
    func fetchDelta(
        listID: String,
        cursor: URL?
    ) async throws -> MicrosoftToDoDelta
}

@MainActor
final class MicrosoftToDoProvider: AsyncTaskProviding, MicrosoftToDoDeltaProviding {
    private static let maximumPageCount = 500
    let provider: TaskProviderKind = .microsoftToDo
    let capabilities = TaskProviderCapabilities(
        supportsNotes: true, supportsTimedDue: true, supportsCompletion: true,
        supportsDeletion: true, supportsDeepLink: true,
        supportsPriority: true, supportsReminder: true
    )
    private let session: OAuthTaskProviderSession
    private let accountKey: String
    private let displayName: String

    init(session: OAuthTaskProviderSession, accountKey: String, displayName: String) {
        self.session = session
        self.accountKey = accountKey
        self.displayName = displayName
    }

    var authorizationState: TaskProviderAuthorizationState {
        session.authorizationState
    }

    func listTaskLists() async throws -> [RemoteTaskList] {
        var nextLink: URL?
        var seenLinks = Set<String>()
        var values = [ListPage.List]()
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= Self.maximumPageCount else {
                throw TaskProviderError.providerFailure(
                    "Microsoft To Do exceeded the task-list page limit."
                )
            }
            let (data, _) = try await session.send {
                try MicrosoftToDoAPI.listsRequest(
                    accessToken: $0,
                    nextLink: nextLink
                )
            }
            let page = try JSONDecoder().decode(ListPage.self, from: data)
            values.append(contentsOf: page.value)
            nextLink = try MicrosoftToDoAPI.validatedContinuationURL(page.nextLink)
            if let nextLink, !seenLinks.insert(nextLink.absoluteString).inserted {
                throw TaskProviderError.providerFailure(
                    "Microsoft To Do returned a repeated task-list page link."
                )
            }
        } while nextLink != nil
        return values.map {
            RemoteTaskList(
                provider: .microsoftToDo,
                id: $0.id,
                accountKey: accountKey,
                title: $0.displayName,
                sourceTitle: displayName,
                isWritable: $0.isOwner ?? true
            )
        }
    }

    func createTask(_ draft: RemoteTaskDraft) async throws -> RemoteTaskSnapshot {
        let (data, _) = try await session.send {
            try MicrosoftToDoAPI.createTaskRequest(
                listID: draft.parentID,
                title: draft.title,
                body: draft.notes,
                dueAt: draft.dueAt,
                reminderAt: draft.reminderAt,
                priority: draft.priority,
                deepLink: draft.deepLink,
                accessToken: $0
            )
        }
        return try snapshot(from: data, parentID: draft.parentID, fallbackDeepLink: draft.deepLink)
    }

    func updateTask(
        _ task: RemoteTaskSnapshot,
        with patch: RemoteTaskPatch
    ) async throws -> RemoteTaskSnapshot {
        let (data, _) = try await session.send {
            try MicrosoftToDoAPI.updateTaskRequest(
                listID: task.parentID,
                taskID: task.id,
                patch: patch,
                expectedVersion: task.version,
                accessToken: $0
            )
        }
        return try snapshot(
            from: data,
            parentID: task.parentID,
            fallbackDeepLink: task.deepLink
        )
    }

    func deleteTask(
        _ task: RemoteTaskSnapshot,
        expectedVersion: String?
    ) async throws {
        _ = try await session.send {
            MicrosoftToDoAPI.deleteTaskRequest(
                listID: task.parentID,
                taskID: task.id,
                expectedVersion: expectedVersion,
                accessToken: $0
            )
        }
    }

    func lookupTask(
        id: String,
        parentID: String
    ) async throws -> RemoteTaskSnapshot? {
        do {
            let (data, _) = try await session.send {
                MicrosoftToDoAPI.taskRequest(
                    listID: parentID,
                    taskID: id,
                    accessToken: $0
                )
            }
            let task = try JSONDecoder().decode(Task.self, from: data)
            return snapshot(task, parentID: parentID, fallbackDeepLink: nil)
        } catch TaskProviderError.taskNotFound {
            return nil
        }
    }

    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot] {
        var snapshots = [RemoteTaskSnapshot]()
        for list in lists where list.provider == .microsoftToDo
            && list.accountKey == accountKey {
            var nextLink: URL?
            var seenLinks = Set<String>()
            var pageCount = 0
            repeat {
                pageCount += 1
                guard pageCount <= Self.maximumPageCount else {
                    throw TaskProviderError.providerFailure(
                        "Microsoft To Do exceeded the task page limit."
                    )
                }
                let (data, _) = try await session.send {
                    try MicrosoftToDoAPI.tasksRequest(
                        listID: list.id,
                        accessToken: $0,
                        nextLink: nextLink
                    )
                }
                let page = try JSONDecoder().decode(TaskPage.self, from: data)
                snapshots.append(contentsOf: page.value.map {
                    snapshot($0, parentID: list.id, fallbackDeepLink: nil)
                })
                nextLink = try MicrosoftToDoAPI.validatedContinuationURL(page.nextLink)
                if let nextLink,
                   !seenLinks.insert(nextLink.absoluteString).inserted {
                    throw TaskProviderError.providerFailure(
                        "Microsoft To Do returned a repeated task page link."
                    )
                }
            } while nextLink != nil
        }
        return snapshots
    }

    func fetchDelta(listID: String, cursor: URL?) async throws -> MicrosoftToDoDelta {
        var nextURL = cursor
        var tasks = [RemoteTaskSnapshot]()
        var deletedTaskIDs = [String]()
        var finalCursor: URL?
        var seenLinks = Set<String>()
        if let cursor {
            seenLinks.insert(cursor.absoluteString)
        }
        var pageCount = 0

        repeat {
            pageCount += 1
            guard pageCount <= Self.maximumPageCount else {
                throw TaskProviderError.providerFailure(
                    "Microsoft To Do exceeded the delta page limit."
                )
            }
            let (data, _) = try await session.send {
                try MicrosoftToDoAPI.deltaRequest(
                    listID: listID,
                    deltaLink: nextURL,
                    accessToken: $0
                )
            }
            let page = try JSONDecoder().decode(DeltaPage.self, from: data)
            for task in page.value {
                if task.removed != nil {
                    deletedTaskIDs.append(task.id)
                } else {
                    tasks.append(snapshot(task, parentID: listID, fallbackDeepLink: nil))
                }
            }
            nextURL = try MicrosoftToDoAPI.validatedContinuationURL(page.nextLink)
            finalCursor = try MicrosoftToDoAPI.validatedContinuationURL(page.deltaLink)
                ?? finalCursor
            if let nextURL,
               !seenLinks.insert(nextURL.absoluteString).inserted {
                throw TaskProviderError.providerFailure(
                    "Microsoft To Do returned a repeated delta page link."
                )
            }
        } while nextURL != nil

        return MicrosoftToDoDelta(
            tasks: tasks,
            deletedTaskIDs: deletedTaskIDs,
            cursor: finalCursor
        )
    }

    private func snapshot(
        from data: Data,
        parentID: String,
        fallbackDeepLink: URL?
    ) throws -> RemoteTaskSnapshot {
        try snapshot(
            JSONDecoder().decode(Task.self, from: data),
            parentID: parentID,
            fallbackDeepLink: fallbackDeepLink
        )
    }

    private func snapshot(
        _ task: Task,
        parentID: String,
        fallbackDeepLink: URL?
    ) -> RemoteTaskSnapshot {
        RemoteTaskSnapshot(
            id: task.id,
            parentID: parentID,
            parentAccountKey: accountKey,
            title: task.title ?? "",
            notes: task.body?.content ?? "",
            dueAt: task.dueDateTime.flatMap(date(from:)),
            reminderAt: task.isReminderOn == true
                ? task.reminderDateTime.flatMap(date(from:))
                : nil,
            isCompleted: task.status == "completed",
            priority: taskPriority(task.importance),
            version: task.etag ?? task.lastModifiedDateTime,
            deepLink: (
                task.linkedResources?
                    .compactMap { $0.webURL.flatMap(URL.init(string:)) }
                    .first(where: Self.isTrustedMicrosoftToDoURL)
            ) ?? fallbackDeepLink.flatMap {
                Self.isTrustedMicrosoftToDoURL($0) ? $0 : nil
            }
        )
    }

    private static func isTrustedMicrosoftToDoURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "to-do.office.com"
            && (url.port == nil || url.port == 443)
            && url.user == nil
            && url.password == nil
    }

    private func date(from value: DateTimeTimeZone) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value.dateTime) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: value.dateTime) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: value.dateTime)
    }

    private struct ListPage: Decodable {
        let value: [List]
        let nextLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
        struct List: Decodable { let id: String; let displayName: String; let isOwner: Bool? }
    }

    private struct DeltaPage: Decodable {
        let value: [Task]
        let nextLink: String?
        let deltaLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
            case deltaLink = "@odata.deltaLink"
        }
    }

    private struct TaskPage: Decodable {
        let value: [Task]
        let nextLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    private struct Task: Decodable {
        let id: String
        let title: String?
        let body: Body?
        let dueDateTime: DateTimeTimeZone?
        let reminderDateTime: DateTimeTimeZone?
        let isReminderOn: Bool?
        let status: String?
        let importance: String?
        let etag: String?
        let lastModifiedDateTime: String?
        let removed: Removed?
        let linkedResources: [LinkedResource]?
        enum CodingKeys: String, CodingKey {
            case id, title, body, status, importance, isReminderOn
            case etag = "@odata.etag"
            case dueDateTime = "dueDateTime"
            case reminderDateTime = "reminderDateTime"
            case linkedResources = "linkedResources"
            case lastModifiedDateTime = "lastModifiedDateTime"
            case removed = "@removed"
        }
    }

    private struct Body: Decodable { let content: String? }
    private struct DateTimeTimeZone: Decodable { let dateTime: String; let timeZone: String? }
    private struct Removed: Decodable { let reason: String? }
    private struct LinkedResource: Decodable {
        let webURL: String?
        enum CodingKeys: String, CodingKey { case webURL = "webUrl" }
    }

    private func taskPriority(_ value: String?) -> TaskPriority {
        switch value {
        case "high": .high
        case "low": .low
        default: .none
        }
    }
}
