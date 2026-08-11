import Foundation
import GRDB

enum TaskProviderKind: String, Codable, CaseIterable, DatabaseValueConvertible {
    case appleReminders = "apple_reminders"
    case googleTasks = "google_tasks"
    case todoist
    case microsoftToDo = "microsoft_to_do"

    var title: String {
        switch self {
        case .appleReminders:
            return "Apple Reminders"
        case .googleTasks:
            return "Google Tasks"
        case .todoist:
            return "Todoist"
        case .microsoftToDo:
            return "Microsoft To Do"
        }
    }

    var settingsIcon: String {
        switch self {
        case .appleReminders:
            return "checklist"
        case .googleTasks:
            return "checklist.checked"
        case .todoist:
            return "checklist.unchecked"
        case .microsoftToDo:
            return "checklist.checked"
        }
    }
}

enum TaskProviderAuthorizationState: String, Codable, CaseIterable, DatabaseValueConvertible {
    case notConfigured
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown

    var title: String {
        switch self {
        case .notConfigured: "Not configured"
        case .notDetermined: "Not requested"
        case .authorized: "Full access"
        case .denied: "Access denied"
        case .restricted: "Access restricted"
        case .unknown: "Unknown access"
        }
    }
}

enum TaskProviderSyncState: String, Codable, CaseIterable, DatabaseValueConvertible {
    case pendingCreate = "pending_create"
    case linked
    case missing
    case conflict
    case disconnected

    var title: String {
        switch self {
        case .pendingCreate: "Syncing"
        case .linked: "Linked"
        case .missing: "Remote task missing"
        case .conflict: "Sync conflict"
        case .disconnected: "Provider disconnected"
        }
    }

    var recoveryMessage: String? {
        switch self {
        case .pendingCreate, .linked:
            nil
        case .missing:
            "The remote task could not be found. Recheck the provider, recreate it from the local task, or keep this task local-only."
        case .conflict:
            "The local and remote task changed independently. Choose which version to keep or keep the local task without a provider link."
        case .disconnected:
            "The provider account is unavailable. Reconnect it in Settings or keep this task local-only."
        }
    }
}

enum ProviderPendingOperationKind: String, Codable, CaseIterable, DatabaseValueConvertible {
    case create
    case update
    case delete

    var title: String {
        switch self {
        case .create: "Create pending"
        case .update: "Update pending"
        case .delete: "Delete pending"
        }
    }

    var recoveryMessage: String {
        switch self {
        case .create:
            "The remote task was not confirmed. Retry explicitly, link the local task to an existing remote task, or keep it local-only."
        case .update:
            "The remote update was not confirmed. Retry explicitly, review another remote task, or keep this task local-only."
        case .delete:
            "The remote delete was not confirmed. Retry explicitly or keep the local and remote tasks without a provider link."
        }
    }

    var retryTitle: String {
        switch self {
        case .create: "Retry Create"
        case .update: "Retry Update"
        case .delete: "Retry Delete"
        }
    }
}

struct ProviderPendingOperationRecord: Equatable, Identifiable {
    static let maximumAttempts = 3

    let id: String
    let accountID: String
    let eventTaskID: String
    var operation: ProviderPendingOperationKind
    var remoteID: String?
    var remoteParentID: String
    var expectedVersion: String?
    var attemptCount: Int
    var lastError: String?
    let createdAt: Date
    var updatedAt: Date

    var canRetry: Bool { attemptCount < Self.maximumAttempts }
}

extension ProviderPendingOperationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "provider_pending_operations"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy { .deferredToDate }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy { .deferredToDate }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case eventTaskID = "event_task_id"
        case operation
        case remoteID = "remote_id"
        case remoteParentID = "remote_parent_id"
        case expectedVersion = "expected_version"
        case attemptCount = "attempt_count"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum TaskProviderLinkMode: String, Codable, DatabaseValueConvertible {
    case localOnly = "local_only"
}

struct TaskProviderPreferenceRecord: Equatable {
    let eventTaskID: String
    var linkMode: TaskProviderLinkMode
    let createdAt: Date
    var updatedAt: Date
}

extension TaskProviderPreferenceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "task_provider_preferences"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy { .deferredToDate }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy { .deferredToDate }

    enum CodingKeys: String, CodingKey {
        case eventTaskID = "event_task_id"
        case linkMode = "link_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TaskProviderCapabilities: Equatable, Codable {
    var supportsNotes: Bool
    var supportsTimedDue: Bool
    var supportsCompletion: Bool
    var supportsDeletion: Bool
    var supportsDeepLink: Bool
    var supportsListMove: Bool
    var supportsPriority: Bool
    var supportsReminder: Bool

    init(
        supportsNotes: Bool,
        supportsTimedDue: Bool,
        supportsCompletion: Bool,
        supportsDeletion: Bool,
        supportsDeepLink: Bool,
        supportsListMove: Bool = false,
        supportsPriority: Bool = false,
        supportsReminder: Bool = false
    ) {
        self.supportsNotes = supportsNotes
        self.supportsTimedDue = supportsTimedDue
        self.supportsCompletion = supportsCompletion
        self.supportsDeletion = supportsDeletion
        self.supportsDeepLink = supportsDeepLink
        self.supportsListMove = supportsListMove
        self.supportsPriority = supportsPriority
        self.supportsReminder = supportsReminder
    }

    private enum CodingKeys: String, CodingKey {
        case supportsNotes
        case supportsTimedDue
        case supportsCompletion
        case supportsDeletion
        case supportsDeepLink
        case supportsListMove
        case supportsPriority
        case supportsReminder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsNotes = try container.decode(Bool.self, forKey: .supportsNotes)
        supportsTimedDue = try container.decode(Bool.self, forKey: .supportsTimedDue)
        supportsCompletion = try container.decode(Bool.self, forKey: .supportsCompletion)
        supportsDeletion = try container.decode(Bool.self, forKey: .supportsDeletion)
        supportsDeepLink = try container.decode(Bool.self, forKey: .supportsDeepLink)
        supportsListMove = try container.decodeIfPresent(
            Bool.self,
            forKey: .supportsListMove
        ) ?? false
        supportsPriority = try container.decodeIfPresent(
            Bool.self,
            forKey: .supportsPriority
        ) ?? false
        supportsReminder = try container.decodeIfPresent(
            Bool.self,
            forKey: .supportsReminder
        ) ?? false
    }
}

struct RemoteTaskList: Equatable, Identifiable {
    let provider: TaskProviderKind
    let id: String
    let accountKey: String
    let title: String
    let sourceTitle: String
    let isWritable: Bool

    /// UI-only discriminator. Remote IDs are unique only within an account and
    /// provider, so a raw list ID is not safe as a Settings Picker selection.
    var destinationSelectionKey: String {
        Data("\(provider.rawValue)\u{1F}\(accountKey)\u{1F}\(id)".utf8)
            .base64EncodedString()
    }
}

/// A transient task projected into the sidebar from one of BriefCal's task
/// providers. `details` is display-only and is not persisted by this model.
struct ProviderTaskListItem: Equatable, Identifiable {
    /// A provider-scoped stable ID suitable for SwiftUI diffing.
    let id: String
    /// The provider's task identifier. Never recover this value by parsing
    /// the SwiftUI `id`, which also contains provider/account/list scope.
    let remoteTaskID: String
    /// The version observed while building this transient projection. Direct
    /// mutations compare it with a fresh lookup before writing.
    let remoteVersion: String?
    let provider: TaskProviderKind
    let accountKey: String
    let listID: String
    let title: String
    let details: String?
    let dueAt: Date?
    let reminderAt: Date?
    let isCompleted: Bool
    let priority: TaskPriority
    let listTitle: String
    let accountTitle: String
    /// A provider-owned URL that is known to open the task in its original
    /// service. Apple EventKit reminder URLs are user content, not reliable
    /// Reminders.app task links, so Apple projections intentionally leave this
    /// nil.
    let originalURL: URL?

    init(
        id: String,
        remoteTaskID: String? = nil,
        remoteVersion: String? = nil,
        provider: TaskProviderKind,
        accountKey: String,
        listID: String,
        title: String,
        details: String?,
        dueAt: Date?,
        reminderAt: Date? = nil,
        isCompleted: Bool,
        priority: TaskPriority = .none,
        listTitle: String,
        accountTitle: String,
        originalURL: URL? = nil
    ) {
        self.id = id
        // The fallback keeps existing fixture construction source-compatible;
        // production projections always pass the remote identifier explicitly.
        self.remoteTaskID = remoteTaskID ?? id
        self.remoteVersion = remoteVersion
        self.provider = provider
        self.accountKey = accountKey
        self.listID = listID
        self.title = title
        self.details = details
        self.dueAt = dueAt
        self.reminderAt = reminderAt
        self.isCompleted = isCompleted
        self.priority = priority
        self.listTitle = listTitle
        self.accountTitle = accountTitle
        self.originalURL = originalURL
    }
}

/// A transient projection of a provider task's durable Event Brief binding.
/// The relationship is derived from the existing provider item, task binding,
/// Event Task, and Event Link records; it is never duplicated in SQLite.
struct ProviderTaskCalendarLink: Equatable {
    let provider: TaskProviderKind
    let accountKey: String
    let listID: String
    let remoteTaskID: String
    let eventTaskID: String
    let contextID: String
    let calendarIdentifier: String
    let calendarTitle: String
    let eventTitle: String
    let eventStart: Date
    let eventEnd: Date
    let linkStatus: EventLinkStatus
}

/// A fresh, non-persisted remote task that the user can explicitly choose as
/// the replacement for an Event Brief task's durable provider binding.
struct TaskProviderLinkCandidate: Equatable, Identifiable {
    let provider: TaskProviderKind
    let accountKey: String
    let accountTitle: String
    let listID: String
    let listTitle: String
    let remoteTaskID: String
    let title: String
    let details: String?
    let dueAt: Date?
    let isCompleted: Bool

    var id: String {
        Data(
            "\(provider.rawValue)\u{1F}\(accountKey)\u{1F}\(listID)\u{1F}\(remoteTaskID)".utf8
        ).base64EncodedString()
    }
}

enum ProviderTaskListState: Equatable {
    case unavailable
    case loading
    case loaded([ProviderTaskListItem])
    case failed(String)

    var items: [ProviderTaskListItem] {
        guard case let .loaded(items) = self else { return [] }
        return items
    }
}

struct ProviderAccountRecord: Equatable, Identifiable {
    let id: String
    var provider: TaskProviderKind
    var accountKey: String
    var displayName: String
    var authorizationState: TaskProviderAuthorizationState
    let createdAt: Date
    var updatedAt: Date
}

extension ProviderAccountRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "provider_accounts"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy { .deferredToDate }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy { .deferredToDate }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case accountKey = "account_key"
        case displayName = "display_name"
        case authorizationState = "authorization_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ProviderItemRecord: Equatable, Identifiable {
    let id: String
    let accountID: String
    var entityType: String
    var remoteID: String
    var remoteParentID: String
    var remoteVersion: String?
    var cachedTitle: String
    var cachedNotes: String
    var cachedDueAt: Date?
    var cachedCompleted: Bool
    var lastSeenAt: Date
    let createdAt: Date
    var updatedAt: Date
}

extension ProviderItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "provider_items"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy { .deferredToDate }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy { .deferredToDate }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case entityType = "entity_type"
        case remoteID = "remote_id"
        case remoteParentID = "remote_parent_id"
        case remoteVersion = "remote_version"
        case cachedTitle = "cached_title"
        case cachedNotes = "cached_notes"
        case cachedDueAt = "cached_due_at"
        case cachedCompleted = "cached_completed"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TaskBindingRecord: Equatable, Identifiable {
    let id: String
    let providerItemID: String
    let eventTaskID: String?
    let personalTaskID: String?
    let occurrenceKey: String?
    var syncState: TaskProviderSyncState
    var lastSyncedHash: String?
    var remoteVersion: String?
    let createdAt: Date
    var updatedAt: Date
}

extension TaskBindingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "task_bindings"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy { .deferredToDate }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy { .deferredToDate }

    enum CodingKeys: String, CodingKey {
        case id
        case providerItemID = "provider_item_id"
        case eventTaskID = "event_task_id"
        case personalTaskID = "personal_task_id"
        case occurrenceKey = "occurrence_key"
        case syncState = "sync_state"
        case lastSyncedHash = "last_synced_hash"
        case remoteVersion = "remote_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CalendarTaskDestinationRecord: Equatable, Identifiable {
    let calendarIdentifier: String
    let providerAccountID: String
    var remoteParentID: String
    var isEnabled: Bool
    var fallbackToLocal: Bool
    let createdAt: Date
    var updatedAt: Date

    var id: String { calendarIdentifier }
}

/// Read-only display metadata for the destination used by newly created
/// Event Brief tasks. Remote identifiers stay out of the UI.
struct CalendarTaskDestinationSummary: Equatable {
    let provider: TaskProviderKind
    let accountTitle: String
    let listTitle: String?
    let authorizationState: TaskProviderAuthorizationState
}

extension CalendarTaskDestinationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_task_destinations"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy { .deferredToDate }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy { .deferredToDate }

    enum CodingKeys: String, CodingKey {
        case calendarIdentifier = "calendar_identifier"
        case providerAccountID = "provider_account_id"
        case remoteParentID = "remote_parent_id"
        case isEnabled = "enabled"
        case fallbackToLocal = "fallback_to_local"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RemoteTaskSnapshot: Equatable, Identifiable {
    let id: String
    let parentID: String
    /// Optional account discriminator for provider UIs where a parent ID is
    /// only unique inside an account. Durable bindings continue to use their
    /// provider account record as the source of truth.
    let parentAccountKey: String?
    let title: String
    let notes: String
    let dueAt: Date?
    let reminderAt: Date?
    let isCompleted: Bool
    let priority: TaskPriority
    let version: String?
    let deepLink: URL?

    init(
        id: String,
        parentID: String,
        parentAccountKey: String? = nil,
        title: String,
        notes: String,
        dueAt: Date?,
        reminderAt: Date? = nil,
        isCompleted: Bool,
        priority: TaskPriority = .none,
        version: String?,
        deepLink: URL?
    ) {
        self.id = id
        self.parentID = parentID
        self.parentAccountKey = parentAccountKey
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.reminderAt = reminderAt
        self.isCompleted = isCompleted
        self.priority = priority
        self.version = version
        self.deepLink = deepLink
    }

    var remoteID: String { id }
}

struct RemoteTaskDraft: Equatable {
    let parentID: String
    let title: String
    let notes: String
    let dueAt: Date?
    let reminderAt: Date?
    let priority: TaskPriority
    let deepLink: URL?

    init(
        parentID: String,
        title: String,
        notes: String,
        dueAt: Date?,
        reminderAt: Date? = nil,
        priority: TaskPriority = .none,
        deepLink: URL?
    ) {
        self.parentID = parentID
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.reminderAt = reminderAt
        self.priority = priority
        self.deepLink = deepLink
    }
}

struct RemoteTaskPatch: Equatable {
    var title: String?
    var notes: String?
    var dueAt: Date??
    var reminderAt: Date??
    var isCompleted: Bool?
    var priority: TaskPriority?
}

enum TaskProviderError: LocalizedError, Equatable {
    case notConfigured
    case authorizationRequired
    case accessDenied
    case listUnavailable
    case taskNotFound
    case conflict
    case unsupported(String)
    case providerFailure(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "This task provider has not been configured for this build."
        case .authorizationRequired:
            "Task provider access has not been granted."
        case .accessDenied:
            "Task provider access was denied or restricted."
        case .listUnavailable:
            "The selected task list is no longer available."
        case .taskNotFound:
            "The linked remote task is no longer available."
        case .conflict:
            "The linked remote task changed outside BriefCal. Review it before retrying."
        case let .unsupported(message), let .providerFailure(message):
            message
        }
    }
}
