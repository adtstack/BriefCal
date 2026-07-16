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

struct TaskProviderCapabilities: Equatable, Codable {
    var supportsNotes: Bool
    var supportsTimedDue: Bool
    var supportsCompletion: Bool
    var supportsDeletion: Bool
    var supportsDeepLink: Bool
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

/// A transient task projected into the sidebar from one of KaosCal's task
/// providers. `details` is display-only and is not persisted by this model.
struct ProviderTaskListItem: Equatable, Identifiable {
    /// A provider-scoped stable ID suitable for SwiftUI diffing.
    let id: String
    let provider: TaskProviderKind
    let accountKey: String
    let listID: String
    let title: String
    let details: String?
    let dueAt: Date?
    let isCompleted: Bool
    let listTitle: String
    let accountTitle: String
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
    let isCompleted: Bool
    let version: String?
    let deepLink: URL?

    init(
        id: String,
        parentID: String,
        parentAccountKey: String? = nil,
        title: String,
        notes: String,
        dueAt: Date?,
        isCompleted: Bool,
        version: String?,
        deepLink: URL?
    ) {
        self.id = id
        self.parentID = parentID
        self.parentAccountKey = parentAccountKey
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.isCompleted = isCompleted
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
    let deepLink: URL?
}

struct RemoteTaskPatch: Equatable {
    var title: String?
    var notes: String?
    var dueAt: Date??
    var isCompleted: Bool?
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
            "The linked remote task changed outside KaosCal. Review it before retrying."
        case let .unsupported(message), let .providerFailure(message):
            message
        }
    }
}
