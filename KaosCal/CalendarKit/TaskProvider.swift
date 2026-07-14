import EventKit
import Foundation
import Combine
import CryptoKit

@MainActor
protocol TaskProviding: AnyObject {
    var provider: TaskProviderKind { get }
    var capabilities: TaskProviderCapabilities { get }
    var authorizationState: TaskProviderAuthorizationState { get }
    var storeChangeHandler: (() -> Void)? { get set }

    func requestFullAccess() async throws -> Bool
    func listTaskLists() throws -> [RemoteTaskList]
    func createTask(_ draft: RemoteTaskDraft) throws -> RemoteTaskSnapshot
    func updateTask(
        _ task: RemoteTaskSnapshot,
        with patch: RemoteTaskPatch
    ) throws -> RemoteTaskSnapshot
    func deleteTask(
        _ task: RemoteTaskSnapshot,
        expectedVersion: String?
    ) throws
    func lookupTask(
        id: String,
        parentID: String
    ) throws -> RemoteTaskSnapshot?
}

@MainActor
final class AppleRemindersProvider: TaskProviding {
    private let eventStore: EKEventStore
    private let notificationCenter: NotificationCenter
    private var storeChangeObserver: NSObjectProtocol?

    let provider: TaskProviderKind = .appleReminders
    let capabilities = TaskProviderCapabilities(
        supportsNotes: true,
        supportsTimedDue: true,
        supportsCompletion: true,
        supportsDeletion: true,
        supportsDeepLink: true
    )
    var storeChangeHandler: (() -> Void)?

    init(
        eventStore: EKEventStore = EKEventStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.eventStore = eventStore
        self.notificationCenter = notificationCenter
        storeChangeObserver = notificationCenter.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.storeChangeHandler?()
            }
        }
    }

    deinit {
        if let storeChangeObserver {
            notificationCenter.removeObserver(storeChangeObserver)
        }
    }

    var authorizationState: TaskProviderAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .fullAccess:
            .authorized
        case .writeOnly:
            .denied
        @unknown default:
            .unknown
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    func listTaskLists() throws -> [RemoteTaskList] {
        guard authorizationState == .authorized else {
            throw authorizationError
        }
        return eventStore.calendars(for: .reminder)
            .map { calendar in
                RemoteTaskList(
                    provider: .appleReminders,
                    id: calendar.calendarIdentifier,
                    accountKey: calendar.source.sourceIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title,
                    isWritable: calendar.allowsContentModifications
                )
            }
            .sorted {
                if $0.sourceTitle == $1.sourceTitle {
                    return $0.title.localizedCaseInsensitiveCompare($1.title)
                        == .orderedAscending
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle)
                    == .orderedAscending
            }
    }

    func createTask(_ draft: RemoteTaskDraft) throws -> RemoteTaskSnapshot {
        guard authorizationState == .authorized else {
            throw authorizationError
        }
        guard let calendar = eventStore.calendar(
            withIdentifier: draft.parentID
        ), calendar.allowsContentModifications else {
            throw TaskProviderError.listUnavailable
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = draft.title
        reminder.notes = draft.notes.isEmpty ? nil : draft.notes
        reminder.dueDateComponents = dueDateComponents(draft.dueAt)
        if let deepLink = draft.deepLink {
            reminder.url = deepLink
        }
        try eventStore.save(reminder, commit: true)
        return makeSnapshot(reminder, fallbackParentID: draft.parentID)
    }

    func updateTask(
        _ task: RemoteTaskSnapshot,
        with patch: RemoteTaskPatch
    ) throws -> RemoteTaskSnapshot {
        guard authorizationState == .authorized else {
            throw authorizationError
        }
        guard let reminder = eventStore.calendarItem(
            withIdentifier: task.id
        ) as? EKReminder else {
            throw TaskProviderError.taskNotFound
        }
        guard reminder.calendar?.calendarIdentifier == task.parentID else {
            throw TaskProviderError.taskNotFound
        }
        if let expectedVersion = task.version,
           currentVersion(reminder) != expectedVersion {
            throw TaskProviderError.conflict
        }
        if let title = patch.title {
            reminder.title = title
        }
        if let notes = patch.notes {
            reminder.notes = notes.isEmpty ? nil : notes
        }
        if let dueAt = patch.dueAt {
            reminder.dueDateComponents = dueDateComponents(dueAt)
        }
        if let isCompleted = patch.isCompleted,
           reminder.isCompleted != isCompleted {
            reminder.isCompleted = isCompleted
            reminder.completionDate = isCompleted ? Date() : nil
        }
        try eventStore.save(reminder, commit: true)
        return makeSnapshot(reminder, fallbackParentID: task.parentID)
    }

    func deleteTask(
        _ task: RemoteTaskSnapshot,
        expectedVersion: String?
    ) throws {
        guard authorizationState == .authorized else {
            throw authorizationError
        }
        guard let reminder = eventStore.calendarItem(
            withIdentifier: task.id
        ) as? EKReminder else {
            throw TaskProviderError.taskNotFound
        }
        guard reminder.calendar?.calendarIdentifier == task.parentID else {
            throw TaskProviderError.taskNotFound
        }
        if let expectedVersion,
           currentVersion(reminder) != expectedVersion {
            throw TaskProviderError.conflict
        }
        try eventStore.remove(reminder, commit: true)
    }

    func lookupTask(
        id: String,
        parentID: String
    ) throws -> RemoteTaskSnapshot? {
        guard authorizationState == .authorized else {
            throw authorizationError
        }
        guard let reminder = eventStore.calendarItem(
            withIdentifier: id
        ) as? EKReminder,
        reminder.calendar?.calendarIdentifier == parentID else {
            return nil
        }
        return makeSnapshot(reminder, fallbackParentID: parentID)
    }

    private var authorizationError: TaskProviderError {
        switch authorizationState {
        case .notConfigured:
            .notConfigured
        case .notDetermined:
            .authorizationRequired
        case .denied, .restricted, .unknown:
            .accessDenied
        case .authorized:
            .providerFailure("Unexpected Reminders authorization state.")
        }
    }

    private func makeSnapshot(
        _ reminder: EKReminder,
        fallbackParentID: String
    ) -> RemoteTaskSnapshot {
        let id = reminder.calendarItemIdentifier
        return RemoteTaskSnapshot(
            id: id,
            parentID: reminder.calendar?.calendarIdentifier ?? fallbackParentID,
            title: reminder.title,
            notes: reminder.notes ?? "",
            dueAt: date(from: reminder.dueDateComponents),
            isCompleted: reminder.isCompleted,
            version: currentVersion(reminder),
            deepLink: reminder.url
        )
    }

    private func currentVersion(_ reminder: EKReminder) -> String? {
        reminder.lastModifiedDate.map {
            String(format: "%.6f", $0.timeIntervalSince1970)
        }
    }

    private func dueDateComponents(_ date: Date?) -> DateComponents? {
        guard let date else { return nil }
        return Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }

    private func date(from components: DateComponents?) -> Date? {
        guard let components else { return nil }
        return Calendar.autoupdatingCurrent.date(from: components)
    }
}

/// Coordinates the provider adapter, its durable bindings, and the local task projection.
/// The coordinator deliberately keeps personal tasks local-only in T1; only event-linked
/// tasks are projected to the selected Reminders list for their calendar.
@MainActor
final class TaskProviderCoordinator: ObservableObject {
    let provider: any TaskProviding
    let repository: TaskProviderRepository
    private let contextStore: ContextStore
    private let now: () -> Date
    private let oauthCredentials: OAuthCredentialStoring
    private var asyncProviders = [TaskProviderKind: any AsyncTaskProviding]()

    @Published private(set) var authorizationState: TaskProviderAuthorizationState
    @Published private(set) var providerAuthorizationStates = [TaskProviderKind: TaskProviderAuthorizationState]()
    @Published private(set) var taskLists: [RemoteTaskList] = []
    @Published private(set) var destinations: [CalendarTaskDestinationRecord] = []
    @Published private(set) var lastErrorMessage: String?

    var onLocalProjectionChange: (() -> Void)?

    init(
        contextStore: ContextStore,
        provider: (any TaskProviding)? = nil,
        oauthCredentials: OAuthCredentialStoring = KeychainOAuthCredentialStore(),
        now: @escaping () -> Date = Date.init
    ) {
        let provider = provider ?? AppleRemindersProvider()
        self.provider = provider
        self.contextStore = contextStore
        repository = contextStore.taskProviders
        self.now = now
        self.oauthCredentials = oauthCredentials
        authorizationState = provider.authorizationState
        providerAuthorizationStates[provider.provider] = provider.authorizationState
        provider.storeChangeHandler = { [weak self] in
            self?.refresh()
            if let self {
                self.refreshLinkedTasks(in: self.contextStore)
            }
        }
        configureOAuthProviders()
        refresh()
    }

    func refresh() {
        authorizationState = provider.authorizationState
        providerAuthorizationStates[provider.provider] = authorizationState
        do {
            destinations = try repository.fetchDestinations()
            guard authorizationState == .authorized else {
                replaceTaskLists(for: provider.provider, with: [])
                Task { [weak self] in
                    await self?.refreshOAuthProviders()
                }
                return
            }
            let lists = try provider.listTaskLists()
            replaceTaskLists(for: provider.provider, with: lists)
            for group in Dictionary(grouping: lists, by: \.accountKey) {
                guard let first = group.value.first else { continue }
                _ = try repository.upsertAccount(
                    provider: provider.provider,
                    accountKey: group.key,
                    displayName: first.sourceTitle,
                    authorizationState: authorizationState
                )
            }
            destinations = try repository.fetchDestinations()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
        Task { [weak self] in
            await self?.refreshOAuthProviders()
        }
    }

    func requestAccess() async {
        do {
            _ = try await provider.requestFullAccess()
            refresh()
        } catch {
            lastErrorMessage = Self.message(for: error)
            authorizationState = provider.authorizationState
            providerAuthorizationStates[provider.provider] = authorizationState
        }
    }

    func authorizationState(for provider: TaskProviderKind) -> TaskProviderAuthorizationState {
        providerAuthorizationStates[provider] ?? .notConfigured
    }

    func isConfigured(_ provider: TaskProviderKind) -> Bool {
        provider == self.provider.provider
            || OAuthProviderConfiguration.load(provider: provider) != nil
    }

    func supportsInAppOAuthConnection(_ provider: TaskProviderKind) -> Bool {
        guard let redirect = OAuthProviderConfiguration
            .load(provider: provider)?.redirectURI,
              redirect.scheme?.lowercased() == "http",
              let host = redirect.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1"
    }

    func connectOAuthProvider(_ provider: TaskProviderKind) async {
        guard provider != self.provider.provider,
              let configuration = OAuthProviderConfiguration.load(provider: provider) else {
            lastErrorMessage = "This provider is not configured for this build."
            return
        }
        do {
            let authorization = try await OAuthLoopbackBrowserAuthorization.authorize(
                configuration: configuration
            )
            _ = try await OAuthProviderConnection.connect(
                configuration: configuration,
                code: authorization.code,
                pkce: authorization.pkce,
                credentials: oauthCredentials
            )
            configureOAuthProviders()
            await refreshOAuthProviders()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    func disconnectOAuthProvider(_ provider: TaskProviderKind) {
        guard provider != self.provider.provider else { return }
        do {
            // Provider revocation differs by client type and must not be faked
            // from a desktop public client. This removes KaosCal's Keychain
            // credential and local metadata; the provider consent page remains
            // the authoritative place to revoke server-side grants.
            try oauthCredentials.deleteCredential(for: provider)
            try repository.deleteAccounts(provider: provider)
            asyncProviders[provider] = nil
            providerAuthorizationStates[provider] = isConfigured(provider)
                ? .notDetermined
                : .notConfigured
            replaceTaskLists(for: provider, with: [])
            destinations = try repository.fetchDestinations()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    private func configureOAuthProviders() {
        for kind in [
            TaskProviderKind.googleTasks,
            .todoist,
            .microsoftToDo
        ] {
            asyncProviders[kind] = nil
            guard let configuration = OAuthProviderConfiguration.load(provider: kind) else {
                providerAuthorizationStates[kind] = .notConfigured
                continue
            }
            guard let credential = try? oauthCredentials.loadCredential(for: kind) else {
                providerAuthorizationStates[kind] = .notDetermined
                continue
            }
            let session = OAuthTaskProviderSession(
                configuration: configuration,
                credentials: oauthCredentials
            )
            switch kind {
            case .googleTasks:
                asyncProviders[kind] = GoogleTasksProvider(
                    session: session,
                    accountKey: credential.accountKey,
                    displayName: credential.displayName
                )
            case .todoist:
                asyncProviders[kind] = TodoistTasksProvider(
                    session: session,
                    accountKey: credential.accountKey,
                    displayName: credential.displayName
                )
            case .microsoftToDo:
                asyncProviders[kind] = MicrosoftToDoProvider(
                    session: session,
                    accountKey: credential.accountKey,
                    displayName: credential.displayName
                )
            case .appleReminders:
                break
            }
            providerAuthorizationStates[kind] = session.authorizationState
        }
    }

    private func refreshOAuthProviders() async {
        configureOAuthProviders()
        for kind in [
            TaskProviderKind.googleTasks,
            .todoist,
            .microsoftToDo
        ] {
            guard let asyncProvider = asyncProviders[kind] else {
                replaceTaskLists(for: kind, with: [])
                continue
            }
            providerAuthorizationStates[kind] = asyncProvider.authorizationState
            guard asyncProvider.authorizationState == .authorized else {
                replaceTaskLists(for: kind, with: [])
                continue
            }
            do {
                let lists = try await asyncProvider.listTaskLists()
                replaceTaskLists(for: kind, with: lists)
                for group in Dictionary(grouping: lists, by: \.accountKey) {
                    guard let first = group.value.first else { continue }
                    _ = try repository.upsertAccount(
                        provider: kind,
                        accountKey: group.key,
                        displayName: first.sourceTitle,
                        authorizationState: .authorized
                    )
                }
                destinations = try repository.fetchDestinations()
            } catch {
                lastErrorMessage = Self.message(for: error)
                replaceTaskLists(for: kind, with: [])
            }
        }
        // A provider refresh is also the bounded polling path for OAuth
        // providers. List discovery must finish first so Graph delta has the
        // current account/list routing context.
        await refreshOAuthLinkedTasks(in: contextStore)
    }

    private func replaceTaskLists(
        for provider: TaskProviderKind,
        with lists: [RemoteTaskList]
    ) {
        taskLists.removeAll { $0.provider == provider }
        taskLists.append(contentsOf: lists)
        taskLists.sort {
            if $0.provider == $1.provider {
                if $0.sourceTitle == $1.sourceTitle {
                    return $0.title.localizedCaseInsensitiveCompare($1.title)
                        == .orderedAscending
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle)
                    == .orderedAscending
            }
            return $0.provider.title.localizedCaseInsensitiveCompare($1.provider.title)
                == .orderedAscending
        }
    }

    func destination(for calendarIdentifier: String) -> CalendarTaskDestinationRecord? {
        destinations.first { $0.calendarIdentifier == calendarIdentifier }
    }

    func destinationSelection(for calendarIdentifier: String) -> String {
        guard let destination = destination(for: calendarIdentifier),
              let account = try? repository.fetchAccount(
                id: destination.providerAccountID
              ) else {
            return ""
        }
        return taskLists.first {
            $0.provider == account.provider
                && $0.accountKey == account.accountKey
                && $0.id == destination.remoteParentID
        }?.destinationSelectionKey ?? ""
    }

    func saveDestination(
        calendarIdentifier: String,
        list: RemoteTaskList?,
        enabled: Bool = true,
        fallbackToLocal: Bool = true
    ) {
        do {
            guard let list else {
                try repository.deleteDestination(calendarIdentifier: calendarIdentifier)
                destinations = try repository.fetchDestinations()
                return
            }
            let account = try repository.upsertAccount(
                provider: list.provider,
                accountKey: list.accountKey,
                displayName: list.sourceTitle,
                authorizationState: authorizationState(for: list.provider)
            )
            let timestamp = now()
            let existing = destination(for: calendarIdentifier)
            try repository.saveDestination(
                CalendarTaskDestinationRecord(
                    calendarIdentifier: calendarIdentifier,
                    providerAccountID: account.id,
                    remoteParentID: list.id,
                    isEnabled: enabled,
                    fallbackToLocal: fallbackToLocal,
                    createdAt: existing?.createdAt ?? timestamp,
                    updatedAt: timestamp
                )
            )
            destinations = try repository.fetchDestinations()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    func syncAllEventTasks(
        in contextStore: ContextStore,
        contextID: String
    ) {
        guard let tasks = try? contextStore.eventTasks.fetch(contextID: contextID) else {
            return
        }
        for task in tasks {
            syncEventTask(in: contextStore, contextID: contextID, task: task)
        }
    }

    func syncEventTask(
        in contextStore: ContextStore,
        contextID: String,
        task: EventTask
    ) {
        guard let brief = try? contextStore.eventContexts.fetchBrief(
            contextID: contextID
        ),
        let destination = destination(for: brief.link.calendarIdentifier),
        destination.isEnabled,
        let account = try? repository.fetchAccount(id: destination.providerAccountID),
        account.authorizationState == .authorized else {
            return
        }
        if account.provider != provider.provider {
            guard let asyncProvider = asyncProviders[account.provider] else {
                return
            }
            Task { [weak self] in
                await self?.syncEventTask(
                    using: asyncProvider,
                    in: contextStore,
                    contextID: contextID,
                    task: task,
                    account: account,
                    destination: destination,
                    brief: brief
                )
            }
            return
        }
        guard authorizationState == .authorized else {
            return
        }

        let dueAt = remoteDueDate(
            task.effectiveDueDate(
            eventStart: brief.link.startSnapshot,
            eventEnd: brief.link.endSnapshot
            ),
            capabilities: provider.capabilities
        )
        let draft = RemoteTaskDraft(
            parentID: destination.remoteParentID,
            title: task.title,
            notes: "",
            dueAt: dueAt,
            deepLink: URL(string: "kaoscal://task/\(task.id)")
        )

        do {
            if let binding = try repository.fetchBinding(eventTaskID: task.id),
               let item = try repository.fetchProviderItem(id: binding.providerItemID) {
                let cached = snapshot(from: item)
                guard let remote = try provider.lookupTask(
                    id: cached.id,
                    parentID: cached.parentID
                ) else {
                    try repository.removeBinding(bindingID: binding.id)
                    let remote = try provider.createTask(draft)
                    _ = try repository.insertLinkedTask(
                        account: account,
                        remote: remote,
                        eventTaskID: task.id,
                        occurrenceKey: brief.link.occurrenceIdentityKey,
                        syncHash: localHash(task: task, dueAt: dueAt, remote: remote)
                    )
                    return
                }
                var patch = RemoteTaskPatch()
                patch.title = task.title
                patch.dueAt = .some(dueAt)
                patch.isCompleted = task.isCompleted
                let updated = try provider.updateTask(remote, with: patch)
                try repository.updateLinkedTask(
                    bindingID: binding.id,
                    itemID: item.id,
                    remote: updated,
                    syncState: .linked,
                    syncHash: localHash(task: task, dueAt: dueAt, remote: updated)
                )
            } else {
                let remote = try provider.createTask(draft)
                _ = try repository.insertLinkedTask(
                    account: account,
                    remote: remote,
                    eventTaskID: task.id,
                    occurrenceKey: brief.link.occurrenceIdentityKey,
                    syncHash: localHash(task: task, dueAt: dueAt, remote: remote)
                )
            }
            lastErrorMessage = nil
        } catch {
            let bindingID: String?
            if let fetchedBinding = try? repository.fetchBinding(eventTaskID: task.id) {
                bindingID = fetchedBinding.id
            } else {
                bindingID = nil
            }
            recordSyncError(error, bindingID: bindingID)
        }
    }

    private func syncEventTask(
        using provider: any AsyncTaskProviding,
        in contextStore: ContextStore,
        contextID: String,
        task: EventTask,
        account: ProviderAccountRecord,
        destination: CalendarTaskDestinationRecord,
        brief: EventBriefSnapshot
    ) async {
        let dueAt = remoteDueDate(
            task.effectiveDueDate(
            eventStart: brief.link.startSnapshot,
            eventEnd: brief.link.endSnapshot
            ),
            capabilities: provider.capabilities
        )
        let draft = RemoteTaskDraft(
            parentID: destination.remoteParentID,
            title: task.title,
            notes: "",
            dueAt: dueAt,
            deepLink: URL(string: "kaoscal://task/\(task.id)")
        )

        do {
            if let binding = try repository.fetchBinding(eventTaskID: task.id),
               let item = try repository.fetchProviderItem(id: binding.providerItemID) {
                let cached = snapshot(from: item)
                guard let remote = try await provider.lookupTask(
                    id: cached.id,
                    parentID: cached.parentID
                ) else {
                    try repository.removeBinding(bindingID: binding.id)
                    let remote = try await provider.createTask(draft)
                    _ = try repository.insertLinkedTask(
                        account: account,
                        remote: remote,
                        eventTaskID: task.id,
                        occurrenceKey: brief.link.occurrenceIdentityKey,
                        syncHash: localHash(task: task, dueAt: dueAt, remote: remote)
                    )
                    return
                }
                var patch = RemoteTaskPatch()
                patch.title = task.title
                patch.dueAt = .some(dueAt)
                patch.isCompleted = task.isCompleted
                let updated = try await provider.updateTask(remote, with: patch)
                try repository.updateLinkedTask(
                    bindingID: binding.id,
                    itemID: item.id,
                    remote: updated,
                    syncState: .linked,
                    syncHash: localHash(task: task, dueAt: dueAt, remote: updated)
                )
            } else {
                let remote = try await provider.createTask(draft)
                _ = try repository.insertLinkedTask(
                    account: account,
                    remote: remote,
                    eventTaskID: task.id,
                    occurrenceKey: brief.link.occurrenceIdentityKey,
                    syncHash: localHash(task: task, dueAt: dueAt, remote: remote)
                )
            }
            lastErrorMessage = nil
        } catch {
            let bindingID: String?
            if let binding = try? repository.fetchBinding(eventTaskID: task.id) {
                bindingID = binding.id
            } else {
                bindingID = nil
            }
            recordSyncError(error, bindingID: bindingID)
        }
    }

    /// Delete the remote task before deleting the local row so the durable binding is still available.
    func deleteRemoteTaskIfBound(eventTaskID: String) throws {
        guard let binding = try repository.fetchBinding(eventTaskID: eventTaskID),
              let item = try repository.fetchProviderItem(id: binding.providerItemID) else {
            return
        }
        guard authorizationState == .authorized else {
            throw authorizationState == .notDetermined
                ? TaskProviderError.authorizationRequired
                : TaskProviderError.accessDenied
        }
        let cached = snapshot(from: item)
        do {
            try provider.deleteTask(cached, expectedVersion: binding.remoteVersion)
            try repository.removeBinding(bindingID: binding.id)
        } catch TaskProviderError.taskNotFound {
            try repository.removeBinding(bindingID: binding.id)
        } catch {
            try? repository.markBinding(bindingID: binding.id, state: .conflict)
            throw error
        }
    }

    /// The async equivalent is required for OAuth providers. It preserves the
    /// same ordering as the Reminders path: a failed remote delete leaves the
    /// local task and binding untouched for the user to resolve.
    func deleteRemoteTaskIfBoundAsync(eventTaskID: String) async throws {
        guard let binding = try repository.fetchBinding(eventTaskID: eventTaskID),
              let item = try repository.fetchProviderItem(id: binding.providerItemID),
              let account = try repository.fetchAccount(id: item.accountID) else {
            return
        }
        if account.provider == provider.provider {
            try deleteRemoteTaskIfBound(eventTaskID: eventTaskID)
            return
        }
        guard account.authorizationState == .authorized,
              let asyncProvider = asyncProviders[account.provider],
              asyncProvider.authorizationState == .authorized else {
            throw TaskProviderError.authorizationRequired
        }
        let cached = snapshot(from: item)
        do {
            try await asyncProvider.deleteTask(
                cached,
                expectedVersion: binding.remoteVersion
            )
            try repository.removeBinding(bindingID: binding.id)
        } catch TaskProviderError.taskNotFound {
            try repository.removeBinding(bindingID: binding.id)
        } catch {
            try? repository.markBinding(bindingID: binding.id, state: .conflict)
            throw error
        }
    }

    func refreshLinkedTasks(in contextStore: ContextStore) {
        guard let bindings = try? repository.fetchBindings() else { return }
        var projectionChanged = false
        if authorizationState == .authorized {
            for binding in bindings {
            guard let eventTaskID = binding.eventTaskID,
                  let item = try? repository.fetchProviderItem(id: binding.providerItemID) else {
                try? repository.markBinding(bindingID: binding.id, state: .missing)
                continue
            }
            guard let account = try? repository.fetchAccount(id: item.accountID),
                  account.provider == provider.provider else {
                continue
            }
            let remote: RemoteTaskSnapshot?
            do {
                remote = try provider.lookupTask(
                    id: item.remoteID,
                    parentID: item.remoteParentID
                )
            } catch TaskProviderError.authorizationRequired,
                    TaskProviderError.accessDenied {
                try? repository.markBinding(bindingID: binding.id, state: .disconnected)
                continue
            } catch {
                lastErrorMessage = Self.message(for: error)
                continue
            }
            guard let remote else {
                try? repository.markBinding(bindingID: binding.id, state: .missing)
                continue
            }
            if let task = try? contextStore.eventTasks.fetch(id: eventTaskID) {
                if task.title != remote.title {
                    _ = try? contextStore.updateEventTask(
                        contextID: task.contextID,
                        taskID: task.id,
                        section: task.section,
                        title: remote.title,
                        sortOrder: task.sortOrder,
                        due: task.due
                    )
                    projectionChanged = true
                }
                if task.isCompleted != remote.isCompleted {
                    _ = try? contextStore.setEventTaskCompleted(
                        contextID: task.contextID,
                        taskID: task.id,
                        isCompleted: remote.isCompleted
                    )
                    projectionChanged = true
                }
            }
            try? repository.updateLinkedTask(
                bindingID: binding.id,
                itemID: item.id,
                remote: remote,
                syncState: .linked,
                syncHash: remoteHash(remote)
            )
        }
        }
        if projectionChanged {
            onLocalProjectionChange?()
        }
        Task { [weak self] in
            await self?.refreshOAuthLinkedTasks(in: contextStore)
        }
    }

    private func refreshOAuthLinkedTasks(in contextStore: ContextStore) async {
        await refreshMicrosoftDeltas(in: contextStore)
        guard let bindings = try? repository.fetchBindings() else { return }
        var projectionChanged = false
        for binding in bindings {
            guard let eventTaskID = binding.eventTaskID,
                  let item = try? repository.fetchProviderItem(id: binding.providerItemID),
                  let account = try? repository.fetchAccount(id: item.accountID),
                  account.provider != provider.provider,
                  account.provider != .microsoftToDo,
                  account.authorizationState == .authorized,
                  let asyncProvider = asyncProviders[account.provider],
                  asyncProvider.authorizationState == .authorized else {
                continue
            }
            do {
                guard let remote = try await asyncProvider.lookupTask(
                    id: item.remoteID,
                    parentID: item.remoteParentID
                ) else {
                    try repository.markBinding(bindingID: binding.id, state: .missing)
                    continue
                }
                projectionChanged = applyRemote(
                    remote,
                    binding: binding,
                    item: item,
                    eventTaskID: eventTaskID,
                    in: contextStore
                ) || projectionChanged
            } catch TaskProviderError.authorizationRequired,
                    TaskProviderError.accessDenied {
                try? repository.markBinding(bindingID: binding.id, state: .disconnected)
            } catch {
                lastErrorMessage = Self.message(for: error)
            }
        }
        if projectionChanged {
            onLocalProjectionChange?()
        }
    }

    private func refreshMicrosoftDeltas(in contextStore: ContextStore) async {
        guard let microsoft = asyncProviders[.microsoftToDo] as? any MicrosoftToDoDeltaProviding,
              let accounts = try? repository.fetchAccounts() else {
            return
        }
        var projectionChanged = false
        for account in accounts where account.provider == .microsoftToDo
            && account.authorizationState == .authorized {
            let lists = taskLists.filter {
                $0.provider == .microsoftToDo && $0.accountKey == account.accountKey
            }
            for list in lists {
                let cursorKey = "microsoft.todo.delta.\(list.id)"
                let cursorString: String?
                do {
                    cursorString = try repository.fetchSyncCursor(
                        accountID: account.id,
                        key: cursorKey
                    )
                } catch {
                    cursorString = nil
                }
                let cursor = cursorString.flatMap(URL.init(string:))
                do {
                    let delta = try await microsoft.fetchDelta(
                        listID: list.id,
                        cursor: cursor
                    )
                    if let nextCursor = delta.cursor {
                        try repository.saveSyncCursor(
                            accountID: account.id,
                            key: cursorKey,
                            value: nextCursor.absoluteString
                        )
                    }
                    for remoteID in delta.deletedTaskIDs {
                        guard let item = try repository.fetchProviderItem(
                            accountID: account.id,
                            remoteID: remoteID
                        ), let binding = try repository.fetchBinding(
                            providerItemID: item.id
                        ) else { continue }
                        try repository.markBinding(
                            bindingID: binding.id,
                            state: .missing
                        )
                    }
                    for remote in delta.tasks {
                        guard let item = try repository.fetchProviderItem(
                            accountID: account.id,
                            remoteID: remote.id
                        ), let binding = try repository.fetchBinding(
                            providerItemID: item.id
                        ), let eventTaskID = binding.eventTaskID else { continue }
                        projectionChanged = applyRemote(
                            remote,
                            binding: binding,
                            item: item,
                            eventTaskID: eventTaskID,
                            in: contextStore
                        ) || projectionChanged
                    }
                } catch {
                    // A rejected/expired delta URL must not be reused. The
                    // next refresh starts a full delta round; no local task is
                    // marked missing merely because the cursor failed.
                    try? repository.deleteSyncCursor(
                        accountID: account.id,
                        key: cursorKey
                    )
                    lastErrorMessage = Self.message(for: error)
                }
            }
        }
        if projectionChanged {
            onLocalProjectionChange?()
        }
    }

    private func applyRemote(
        _ remote: RemoteTaskSnapshot,
        binding: TaskBindingRecord,
        item: ProviderItemRecord,
        eventTaskID: String,
        in contextStore: ContextStore
    ) -> Bool {
        var projectionChanged = false
        if let task = try? contextStore.eventTasks.fetch(id: eventTaskID) {
            if task.title != remote.title {
                _ = try? contextStore.updateEventTask(
                    contextID: task.contextID,
                    taskID: task.id,
                    section: task.section,
                    title: remote.title,
                    sortOrder: task.sortOrder,
                    due: task.due
                )
                projectionChanged = true
            }
            if task.isCompleted != remote.isCompleted {
                _ = try? contextStore.setEventTaskCompleted(
                    contextID: task.contextID,
                    taskID: task.id,
                    isCompleted: remote.isCompleted
                )
                projectionChanged = true
            }
        }
        try? repository.updateLinkedTask(
            bindingID: binding.id,
            itemID: item.id,
            remote: remote,
            syncState: .linked,
            syncHash: remoteHash(remote)
        )
        return projectionChanged
    }

    private func snapshot(from item: ProviderItemRecord) -> RemoteTaskSnapshot {
        RemoteTaskSnapshot(
            id: item.remoteID,
            parentID: item.remoteParentID,
            title: item.cachedTitle,
            notes: item.cachedNotes,
            dueAt: item.cachedDueAt,
            isCompleted: item.cachedCompleted,
            version: item.remoteVersion,
            deepLink: nil
        )
    }

    private func remoteDueDate(
        _ dueAt: Date?,
        capabilities: TaskProviderCapabilities
    ) -> Date? {
        // A provider that cannot preserve a time must not silently turn an
        // Event Brief's timed policy into a date-only remote commitment.
        capabilities.supportsTimedDue ? dueAt : nil
    }

    private func localHash(
        task: EventTask,
        dueAt: Date?,
        remote: RemoteTaskSnapshot
    ) -> String {
        hash([
            task.id, task.title, String(task.isCompleted),
            dueAt?.description ?? "",
            remote.id, remote.version ?? ""
        ].joined(separator: "|"))
    }

    private func remoteHash(_ remote: RemoteTaskSnapshot) -> String {
        hash([
            remote.id, remote.parentID, remote.title, remote.notes,
            remote.dueAt?.description ?? "", String(remote.isCompleted),
            remote.version ?? ""
        ].joined(separator: "|"))
    }

    private func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func recordSyncError(_ error: Error, bindingID: String?) {
        if let bindingID {
            let state: TaskProviderSyncState
            switch error {
            case TaskProviderError.conflict:
                state = .conflict
            case TaskProviderError.authorizationRequired,
                 TaskProviderError.accessDenied:
                state = .disconnected
            default:
                state = .missing
            }
            try? repository.markBinding(bindingID: bindingID, state: state)
        }
        lastErrorMessage = Self.message(for: error)
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}
