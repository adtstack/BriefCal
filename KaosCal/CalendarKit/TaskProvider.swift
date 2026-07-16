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
protocol TaskSnapshotListing: AnyObject {
    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot]
}

@MainActor
final class AppleRemindersProvider: TaskProviding, TaskSnapshotListing {
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

    func listTasks(in lists: [RemoteTaskList]) async throws -> [RemoteTaskSnapshot] {
        guard authorizationState == .authorized else {
            throw authorizationError
        }
        let calendars = lists
            .filter { $0.provider == .appleReminders }
            .compactMap { eventStore.calendar(withIdentifier: $0.id) }
        guard !calendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForReminders(in: calendars)
        let reminders = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
        return reminders
            .compactMap { reminder -> RemoteTaskSnapshot? in
                guard let parentID = reminder.calendar?.calendarIdentifier else {
                    return nil
                }
                return makeSnapshot(reminder, fallbackParentID: parentID)
            }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                switch (lhs.dueAt, rhs.dueAt) {
                case let (left?, right?) where left != right:
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                        == .orderedAscending
                }
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
            parentAccountKey: reminder.calendar?.source.sourceIdentifier,
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

/// Coordinates provider adapters, their durable task cache, and the local
/// Event Brief projection. Personal tasks remain local-only.
@MainActor
final class TaskProviderCoordinator: ObservableObject {
    let provider: any TaskProviding
    let repository: TaskProviderRepository
    private let contextStore: ContextStore
    private let now: () -> Date
    private let oauthCredentials: OAuthCredentialStoring
    private var asyncProviders = [TaskProviderKind: any AsyncTaskProviding]()
    private var appleRemindersRefreshTask: Task<Void, Never>?
    private var activeOAuthListRefreshes = Set<UUID>()

    @Published private(set) var authorizationState: TaskProviderAuthorizationState
    @Published private(set) var providerAuthorizationStates = [TaskProviderKind: TaskProviderAuthorizationState]()
    @Published private(set) var taskLists: [RemoteTaskList] = []
    @Published private(set) var destinations: [CalendarTaskDestinationRecord] = []
    @Published private(set) var appleRemindersTaskState:
        ProviderTaskListState = .unavailable
    @Published private(set) var microsoftToDoTaskState:
        ProviderTaskListState = .unavailable
    @Published private(set) var isRefreshingOAuthTaskLists = false
    @Published private(set) var taskListRefreshFailures = Set<TaskProviderKind>()
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
                taskListRefreshFailures.remove(provider.provider)
                appleRemindersRefreshTask?.cancel()
                appleRemindersTaskState = .unavailable
                replaceTaskLists(for: provider.provider, with: [])
                markProviderBindingsDisconnected(provider.provider)
                scheduleOAuthProviderRefresh()
                return
            }
            let lists = try provider.listTaskLists()
            taskListRefreshFailures.remove(provider.provider)
            replaceTaskLists(for: provider.provider, with: lists)
            scheduleAppleRemindersTaskRefresh(lists)
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
            taskListRefreshFailures.insert(provider.provider)
            appleRemindersTaskState = .failed(Self.message(for: error))
            lastErrorMessage = Self.message(for: error)
        }
        scheduleOAuthProviderRefresh()
    }

    private func scheduleAppleRemindersTaskRefresh(_ lists: [RemoteTaskList]) {
        appleRemindersRefreshTask?.cancel()
        guard let listingProvider = provider as? any TaskSnapshotListing else {
            appleRemindersTaskState = .unavailable
            return
        }

        appleRemindersTaskState = .loading
        appleRemindersRefreshTask = Task { [weak self] in
            do {
                let snapshots = try await listingProvider.listTasks(in: lists)
                guard !Task.isCancelled, let self else { return }
                let listsByID = Dictionary(grouping: lists, by: \.id)
                let items = snapshots.compactMap { snapshot -> ProviderTaskListItem? in
                    let candidates = listsByID[snapshot.parentID] ?? []
                    let list: RemoteTaskList?
                    if let accountKey = snapshot.parentAccountKey {
                        list = candidates.first { $0.accountKey == accountKey }
                    } else {
                        // Never guess when a provider returns an account-scoped
                        // parent ID without its account discriminator.
                        list = candidates.count == 1 ? candidates[0] : nil
                    }
                    guard let list else { return nil }
                    return ProviderTaskListItem(
                        id: Self.sidebarTaskItemID(
                            provider: .appleReminders,
                            accountKey: list.accountKey,
                            listID: list.id,
                            taskID: snapshot.id
                        ),
                        provider: .appleReminders,
                        accountKey: list.accountKey,
                        listID: list.id,
                        title: snapshot.title,
                        details: Self.sidebarDetails(snapshot.notes),
                        dueAt: snapshot.dueAt,
                        isCompleted: snapshot.isCompleted,
                        listTitle: list.title,
                        accountTitle: list.sourceTitle
                    )
                }
                appleRemindersTaskState = .loaded(items)
            } catch {
                guard !Task.isCancelled else { return }
                self?.appleRemindersTaskState = .failed(Self.message(for: error))
            }
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
            lastErrorMessage = nil
            await refreshOAuthProviders()
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
            taskListRefreshFailures.remove(provider)
            providerAuthorizationStates[provider] = isConfigured(provider)
                ? .notDetermined
                : .notConfigured
            replaceTaskLists(for: provider, with: [])
            if provider == .microsoftToDo {
                microsoftToDoTaskState = .unavailable
            }
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

    private func scheduleOAuthProviderRefresh() {
        let token = beginOAuthListRefresh()
        Task { [weak self] in
            await self?.refreshOAuthProviders(token: token)
        }
    }

    private func beginOAuthListRefresh() -> UUID {
        let token = UUID()
        activeOAuthListRefreshes.insert(token)
        isRefreshingOAuthTaskLists = true
        return token
    }

    private func endOAuthListRefresh(_ token: UUID) {
        activeOAuthListRefreshes.remove(token)
        isRefreshingOAuthTaskLists = !activeOAuthListRefreshes.isEmpty
    }

    private func refreshOAuthProviders(token suppliedToken: UUID? = nil) async {
        let token = suppliedToken ?? beginOAuthListRefresh()
        defer { endOAuthListRefresh(token) }
        configureOAuthProviders()
        for kind in [
            TaskProviderKind.googleTasks,
            .todoist,
            .microsoftToDo
        ] {
            guard let asyncProvider = asyncProviders[kind] else {
                taskListRefreshFailures.remove(kind)
                replaceTaskLists(for: kind, with: [])
                markProviderBindingsDisconnected(kind)
                continue
            }
            providerAuthorizationStates[kind] = asyncProvider.authorizationState
            guard asyncProvider.authorizationState == .authorized else {
                taskListRefreshFailures.remove(kind)
                replaceTaskLists(for: kind, with: [])
                markProviderBindingsDisconnected(kind)
                continue
            }
            do {
                let lists = try await asyncProvider.listTaskLists()
                taskListRefreshFailures.remove(kind)
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
                taskListRefreshFailures.insert(kind)
                lastErrorMessage = Self.message(for: error)
                // Keep the last successful metadata during a transient list
                // failure. Authorization loss and explicit disconnect still
                // clear it in the guarded branches above.
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
                    let titleOrder = $0.title.localizedCaseInsensitiveCompare(
                        $1.title
                    )
                    if titleOrder != .orderedSame {
                        return titleOrder == .orderedAscending
                    }
                    if $0.accountKey != $1.accountKey {
                        return $0.accountKey < $1.accountKey
                    }
                    return $0.id < $1.id
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
                    onLocalProjectionChange?()
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
            onLocalProjectionChange?()
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
                    onLocalProjectionChange?()
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
            onLocalProjectionChange?()
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
            _ = try? repository.markBinding(
                bindingID: binding.id,
                state: .conflict
            )
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
            _ = try? repository.markBinding(
                bindingID: binding.id,
                state: .conflict
            )
            throw error
        }
    }

    /// Explicit conflict recovery that accepts the provider's current title
    /// and completion state. It never guesses from task title or account name.
    func acceptRemoteTaskVersion(
        eventTaskID: String,
        in contextStore: ContextStore
    ) async throws {
        guard let binding = try repository.fetchBinding(
            eventTaskID: eventTaskID
        ), let item = try repository.fetchProviderItem(
            id: binding.providerItemID
        ), let account = try repository.fetchAccount(id: item.accountID),
           try contextStore.eventTasks.fetch(id: eventTaskID) != nil else {
            throw TaskProviderError.taskNotFound
        }

        let remote: RemoteTaskSnapshot?
        if account.provider == provider.provider {
            guard authorizationState == .authorized else {
                throw authorizationState == .notDetermined
                    ? TaskProviderError.authorizationRequired
                    : TaskProviderError.accessDenied
            }
            remote = try provider.lookupTask(
                id: item.remoteID,
                parentID: item.remoteParentID
            )
        } else {
            guard account.authorizationState == .authorized,
                  let asyncProvider = asyncProviders[account.provider],
                  asyncProvider.authorizationState == .authorized else {
                throw TaskProviderError.authorizationRequired
            }
            remote = try await asyncProvider.lookupTask(
                id: item.remoteID,
                parentID: item.remoteParentID
            )
        }

        guard let remote else {
            _ = try repository.markBinding(
                bindingID: binding.id,
                state: .missing
            )
            onLocalProjectionChange?()
            throw TaskProviderError.taskNotFound
        }
        _ = applyRemote(
            remote,
            binding: binding,
            item: item,
            eventTaskID: eventTaskID,
            in: contextStore
        )
        lastErrorMessage = nil
        onLocalProjectionChange?()
    }

    /// Explicit recovery that keeps the local task as the chosen version.
    /// The durable binding, rather than the calendar's current default
    /// destination, determines the provider account and list to update.
    func acceptLocalTaskVersion(
        eventTaskID: String,
        in contextStore: ContextStore
    ) async throws {
        guard let binding = try repository.fetchBinding(
            eventTaskID: eventTaskID
        ), let item = try repository.fetchProviderItem(
            id: binding.providerItemID
        ), let account = try repository.fetchAccount(id: item.accountID),
           let task = try contextStore.eventTasks.fetch(id: eventTaskID),
           let brief = try contextStore.eventContexts.fetchBrief(
            contextID: task.contextID
           ) else {
            throw TaskProviderError.taskNotFound
        }

        do {
            if account.provider == provider.provider {
                guard authorizationState == .authorized else {
                    throw authorizationState == .notDetermined
                        ? TaskProviderError.authorizationRequired
                        : TaskProviderError.accessDenied
                }
                try acceptLocalTaskVersion(
                    task: task,
                    brief: brief,
                    binding: binding,
                    item: item,
                    account: account,
                    using: provider
                )
            } else {
                guard account.authorizationState == .authorized,
                      let asyncProvider = asyncProviders[account.provider],
                      asyncProvider.authorizationState == .authorized else {
                    throw TaskProviderError.authorizationRequired
                }
                try await acceptLocalTaskVersion(
                    task: task,
                    brief: brief,
                    binding: binding,
                    item: item,
                    account: account,
                    using: asyncProvider
                )
            }
            lastErrorMessage = nil
            onLocalProjectionChange?()
        } catch {
            recordSyncError(error, bindingID: binding.id)
            throw error
        }
    }

    private func acceptLocalTaskVersion(
        task: EventTask,
        brief: EventBriefSnapshot,
        binding: TaskBindingRecord,
        item: ProviderItemRecord,
        account: ProviderAccountRecord,
        using provider: any TaskProviding
    ) throws {
        let dueAt = remoteDueDate(
            task.effectiveDueDate(
                eventStart: brief.link.startSnapshot,
                eventEnd: brief.link.endSnapshot
            ),
            capabilities: provider.capabilities
        )
        let draft = localRecoveryDraft(
            task: task,
            parentID: item.remoteParentID,
            dueAt: dueAt
        )
        if let remote = try provider.lookupTask(
            id: item.remoteID,
            parentID: item.remoteParentID
        ) {
            let updated = try provider.updateTask(
                remote,
                with: localRecoveryPatch(task: task, dueAt: dueAt)
            )
            try repository.updateLinkedTask(
                bindingID: binding.id,
                itemID: item.id,
                remote: updated,
                syncState: .linked,
                syncHash: localHash(
                    task: task,
                    dueAt: dueAt,
                    remote: updated
                )
            )
        } else {
            let created = try provider.createTask(draft)
            try repository.removeBinding(bindingID: binding.id)
            _ = try repository.insertLinkedTask(
                account: account,
                remote: created,
                eventTaskID: task.id,
                occurrenceKey: brief.link.occurrenceIdentityKey,
                syncHash: localHash(
                    task: task,
                    dueAt: dueAt,
                    remote: created
                )
            )
        }
    }

    private func acceptLocalTaskVersion(
        task: EventTask,
        brief: EventBriefSnapshot,
        binding: TaskBindingRecord,
        item: ProviderItemRecord,
        account: ProviderAccountRecord,
        using provider: any AsyncTaskProviding
    ) async throws {
        let dueAt = remoteDueDate(
            task.effectiveDueDate(
                eventStart: brief.link.startSnapshot,
                eventEnd: brief.link.endSnapshot
            ),
            capabilities: provider.capabilities
        )
        let draft = localRecoveryDraft(
            task: task,
            parentID: item.remoteParentID,
            dueAt: dueAt
        )
        if let remote = try await provider.lookupTask(
            id: item.remoteID,
            parentID: item.remoteParentID
        ) {
            let updated = try await provider.updateTask(
                remote,
                with: localRecoveryPatch(task: task, dueAt: dueAt)
            )
            try repository.updateLinkedTask(
                bindingID: binding.id,
                itemID: item.id,
                remote: updated,
                syncState: .linked,
                syncHash: localHash(
                    task: task,
                    dueAt: dueAt,
                    remote: updated
                )
            )
        } else {
            let created = try await provider.createTask(draft)
            try repository.removeBinding(bindingID: binding.id)
            _ = try repository.insertLinkedTask(
                account: account,
                remote: created,
                eventTaskID: task.id,
                occurrenceKey: brief.link.occurrenceIdentityKey,
                syncHash: localHash(
                    task: task,
                    dueAt: dueAt,
                    remote: created
                )
            )
        }
    }

    private func localRecoveryDraft(
        task: EventTask,
        parentID: String,
        dueAt: Date?
    ) -> RemoteTaskDraft {
        RemoteTaskDraft(
            parentID: parentID,
            title: task.title,
            notes: "",
            dueAt: dueAt,
            deepLink: URL(string: "kaoscal://task/\(task.id)")
        )
    }

    private func localRecoveryPatch(
        task: EventTask,
        dueAt: Date?
    ) -> RemoteTaskPatch {
        var patch = RemoteTaskPatch()
        patch.title = task.title
        patch.dueAt = .some(dueAt)
        patch.isCompleted = task.isCompleted
        return patch
    }

    func refreshLinkedTasks(in contextStore: ContextStore) {
        guard let bindings = try? repository.fetchBindings() else { return }
        var projectionChanged = false
        if authorizationState == .authorized {
            for binding in bindings {
            guard let eventTaskID = binding.eventTaskID,
                  let item = try? repository.fetchProviderItem(id: binding.providerItemID) else {
                projectionChanged = ((try? repository.markBinding(
                    bindingID: binding.id,
                    state: .missing
                )) == true) || projectionChanged
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
                projectionChanged = ((try? repository.markBinding(
                    bindingID: binding.id,
                    state: .disconnected
                )) == true) || projectionChanged
                continue
            } catch {
                lastErrorMessage = Self.message(for: error)
                continue
            }
            guard let remote else {
                projectionChanged = ((try? repository.markBinding(
                    bindingID: binding.id,
                    state: .missing
                )) == true) || projectionChanged
                continue
            }
            if binding.syncState != .linked {
                projectionChanged = true
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
                    projectionChanged = (try repository.markBinding(
                        bindingID: binding.id,
                        state: .missing
                    )) || projectionChanged
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
                projectionChanged = ((try? repository.markBinding(
                    bindingID: binding.id,
                    state: .disconnected
                )) == true) || projectionChanged
            } catch {
                lastErrorMessage = Self.message(for: error)
            }
        }
        if projectionChanged {
            onLocalProjectionChange?()
        }
    }

    private func refreshMicrosoftDeltas(in contextStore: ContextStore) async {
        guard let asyncMicrosoft = asyncProviders[.microsoftToDo],
              asyncMicrosoft.authorizationState == .authorized,
              let microsoft = asyncMicrosoft as? any MicrosoftToDoDeltaProviding,
              let accounts = try? repository.fetchAccounts() else {
            microsoftToDoTaskState = .unavailable
            return
        }
        let authorizedAccounts = accounts.filter {
            $0.provider == .microsoftToDo
                && $0.authorizationState == .authorized
        }
        guard !authorizedAccounts.isEmpty else {
            microsoftToDoTaskState = .unavailable
            return
        }

        let microsoftLists = taskLists.filter {
            $0.provider == .microsoftToDo
        }
        guard !microsoftLists.isEmpty else {
            refreshMicrosoftToDoTaskState()
            return
        }

        microsoftToDoTaskState = .loading
        var projectionChanged = false
        var completedRefresh = false
        var refreshError: String?
        for account in authorizedAccounts {
            let lists = microsoftLists.filter {
                $0.accountKey == account.accountKey
            }
            for list in lists {
                let cursorKey = "microsoft.todo.delta.\(list.id)"
                // Earlier versions stored a cursor solely for Event Brief
                // bindings. The first sidebar refresh must ignore that cursor
                // once, otherwise Graph returns only recent changes and skips
                // long-standing Microsoft-only tasks.
                let sidebarCacheKey = "microsoft.todo.sidebar.cache.v1.\(list.id)"
                let hasCompleteSidebarCache = (try? repository.fetchSyncCursor(
                    accountID: account.id,
                    key: sidebarCacheKey
                )) != nil
                let cursorString: String?
                if hasCompleteSidebarCache {
                    do {
                        cursorString = try repository.fetchSyncCursor(
                            accountID: account.id,
                            key: cursorKey
                        )
                    } catch {
                        cursorString = nil
                    }
                } else {
                    cursorString = nil
                }
                let cursor = cursorString.flatMap(URL.init(string:))
                do {
                    let delta = try await microsoft.fetchDelta(
                        listID: list.id,
                        cursor: cursor
                    )
                    for remoteID in delta.deletedTaskIDs {
                        guard let item = try repository.fetchProviderItem(
                            accountID: account.id,
                            remoteID: remoteID
                        ) else { continue }
                        if let binding = try repository.fetchBinding(
                            providerItemID: item.id
                        ) {
                            projectionChanged = (try repository.markBinding(
                                bindingID: binding.id,
                                state: .missing
                            )) || projectionChanged
                        } else {
                            try repository.deleteUnboundProviderItem(
                                accountID: account.id,
                                remoteID: remoteID
                            )
                        }
                    }
                    for remote in delta.tasks {
                        if let item = try repository.fetchProviderItem(
                            accountID: account.id,
                            remoteID: remote.id
                        ), let binding = try repository.fetchBinding(
                            providerItemID: item.id
                        ), let eventTaskID = binding.eventTaskID {
                            projectionChanged = applyRemote(
                                remote,
                                binding: binding,
                                item: item,
                                eventTaskID: eventTaskID,
                                in: contextStore
                            ) || projectionChanged
                        } else {
                            _ = try repository.upsertProviderItem(
                                accountID: account.id,
                                remote: remote
                            )
                        }
                    }
                    if let nextCursor = delta.cursor {
                        try repository.saveSyncCursor(
                            accountID: account.id,
                            key: cursorKey,
                            value: nextCursor.absoluteString
                        )
                    }
                    try repository.saveSyncCursor(
                        accountID: account.id,
                        key: sidebarCacheKey,
                        value: "complete"
                    )
                    completedRefresh = true
                } catch {
                    // A rejected/expired delta URL must not be reused. The
                    // next refresh starts a full delta round; no local task is
                    // marked missing merely because the cursor failed.
                    try? repository.deleteSyncCursor(
                        accountID: account.id,
                        key: cursorKey
                    )
                    let message = Self.message(for: error)
                    refreshError = message
                    lastErrorMessage = message
                }
            }
        }
        if projectionChanged {
            onLocalProjectionChange?()
        }
        if completedRefresh {
            refreshMicrosoftToDoTaskState()
        } else {
            microsoftToDoTaskState = .failed(
                refreshError ?? "Microsoft To Do could not refresh its tasks."
            )
        }
    }

    private func refreshMicrosoftToDoTaskState() {
        do {
            let accounts = Dictionary(
                uniqueKeysWithValues: try repository.fetchAccounts().map {
                    ($0.id, $0)
                }
            )
            let cachedItems = try repository.fetchProviderItems(
                provider: .microsoftToDo
            )
            let items = cachedItems.compactMap { item -> ProviderTaskListItem? in
                guard let account = accounts[item.accountID] else { return nil }
                let listTitle = taskLists.first {
                    $0.provider == .microsoftToDo
                        && $0.accountKey == account.accountKey
                        && $0.id == item.remoteParentID
                }?.title ?? "Microsoft To Do"
                return ProviderTaskListItem(
                    id: Self.sidebarTaskItemID(
                        provider: .microsoftToDo,
                        accountKey: account.accountKey,
                        listID: item.remoteParentID,
                        taskID: item.remoteID
                    ),
                    provider: .microsoftToDo,
                    accountKey: account.accountKey,
                    listID: item.remoteParentID,
                    title: item.cachedTitle,
                    details: nil,
                    dueAt: item.cachedDueAt,
                    isCompleted: item.cachedCompleted,
                    listTitle: listTitle,
                    accountTitle: account.displayName
                )
            }
            microsoftToDoTaskState = .loaded(items)
        } catch {
            microsoftToDoTaskState = .failed(Self.message(for: error))
        }
    }

    private func applyRemote(
        _ remote: RemoteTaskSnapshot,
        binding: TaskBindingRecord,
        item: ProviderItemRecord,
        eventTaskID: String,
        in contextStore: ContextStore
    ) -> Bool {
        var projectionChanged = binding.syncState != .linked
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

    private static func sidebarDetails(_ notes: String) -> String? {
        let details = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty ? nil : details
    }

    static func sidebarTaskItemID(
        provider: TaskProviderKind,
        accountKey: String,
        listID: String,
        taskID: String
    ) -> String {
        Data(
            "\(provider.rawValue)\u{1F}\(accountKey)\u{1F}\(listID)\u{1F}\(taskID)".utf8
        ).base64EncodedString()
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
        var bindingStateChanged = false
        if let bindingID {
            let state: TaskProviderSyncState?
            switch error {
            case TaskProviderError.conflict:
                state = .conflict
            case TaskProviderError.taskNotFound:
                state = .missing
            case TaskProviderError.authorizationRequired,
                 TaskProviderError.accessDenied:
                state = .disconnected
            default:
                state = nil
            }
            if let state {
                bindingStateChanged = ((try? repository.markBinding(
                    bindingID: bindingID,
                    state: state
                )) == true)
            }
        }
        lastErrorMessage = Self.message(for: error)
        if bindingStateChanged {
            onLocalProjectionChange?()
        }
    }

    private func markProviderBindingsDisconnected(
        _ provider: TaskProviderKind
    ) {
        guard let bindings = try? repository.fetchBindings(),
              let accounts = try? repository.fetchAccounts() else {
            return
        }
        let accountsByID = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0) }
        )
        var projectionChanged = false
        for binding in bindings {
            guard let item = try? repository.fetchProviderItem(
                id: binding.providerItemID
            ), let account = accountsByID[item.accountID],
               account.provider == provider else {
                continue
            }
            projectionChanged = ((try? repository.markBinding(
                bindingID: binding.id,
                state: .disconnected
            )) == true) || projectionChanged
        }
        if projectionChanged {
            onLocalProjectionChange?()
        }
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
