import Foundation
import GRDB

extension CalendarRole: DatabaseValueConvertible {}

struct CalendarRolePreference: Equatable, Identifiable {
    let calendarIdentifier: String
    var sourceTitleSnapshot: String
    var calendarTitleSnapshot: String
    var role: CalendarRole
    let createdAt: Date
    var updatedAt: Date

    var id: String { calendarIdentifier }
}

extension CalendarRolePreference: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_preferences"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case calendarIdentifier = "calendar_identifier"
        case sourceTitleSnapshot = "source_title_snapshot"
        case calendarTitleSnapshot = "calendar_title_snapshot"
        case role
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CalendarUsagePreference: Equatable, Identifiable {
    let calendarIdentifier: String
    var sourceIdentifierSnapshot: String
    var sourceTitleSnapshot: String
    var calendarTitleSnapshot: String
    var visibilityOverride: Bool?
    var blockingOverride: Bool?
    let createdAt: Date
    var updatedAt: Date

    var id: String { calendarIdentifier }
}

extension CalendarUsagePreference: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_usage_preferences"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case calendarIdentifier = "calendar_identifier"
        case sourceIdentifierSnapshot = "source_identifier_snapshot"
        case sourceTitleSnapshot = "source_title_snapshot"
        case calendarTitleSnapshot = "calendar_title_snapshot"
        case visibilityOverride = "visibility_override"
        case blockingOverride = "blocking_override"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SavedCalendarSet: Equatable, Identifiable {
    let id: String
    var name: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
}

extension SavedCalendarSet: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_sets"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CalendarSetMembership: Equatable, Identifiable {
    let id: String
    let calendarSetID: String
    var calendarIdentifier: String
    var sourceIdentifierSnapshot: String
    var sourceTitleSnapshot: String
    var calendarTitleSnapshot: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
}

extension CalendarSetMembership: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_set_memberships"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case calendarSetID = "calendar_set_id"
        case calendarIdentifier = "calendar_identifier"
        case sourceIdentifierSnapshot = "source_identifier_snapshot"
        case sourceTitleSnapshot = "source_title_snapshot"
        case calendarTitleSnapshot = "calendar_title_snapshot"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SavedCalendarSetSnapshot: Equatable, Identifiable {
    let calendarSet: SavedCalendarSet
    let memberships: [CalendarSetMembership]

    var id: String { calendarSet.id }
    var name: String { calendarSet.name }

    var calendarIdentifiers: Set<String> {
        Set(memberships.map(\.calendarIdentifier))
    }
}

enum CalendarSetSelectionKind: String, Codable, DatabaseValueConvertible {
    case role
    case saved
}

struct CalendarSetSelectionRecord: Equatable {
    static let singletonID = 1

    let singletonID: Int
    var selectionKind: CalendarSetSelectionKind
    var role: CalendarRole?
    var calendarSetID: String?
    var updatedAt: Date
}

extension CalendarSetSelectionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_set_selection"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case singletonID = "singleton_id"
        case selectionKind = "selection_kind"
        case role
        case calendarSetID = "calendar_set_id"
        case updatedAt = "updated_at"
    }
}

enum EventLifecycleStatus: String, Codable, CaseIterable, DatabaseValueConvertible {
    case scheduled
    case completed
    case cancelled
    case orphaned
}

enum EventLinkStatus: String, Codable, CaseIterable, DatabaseValueConvertible {
    case active
    case missing
    case orphaned
}

enum StoredEventTimeSemantics: String, Codable, CaseIterable, DatabaseValueConvertible {
    case allDay = "all_day"
    case floating
    case zoned
}

enum EventTaskSection: String, Codable, CaseIterable, DatabaseValueConvertible {
    case before
    case during
    case after

    var sortRank: Int {
        switch self {
        case .before: 0
        case .during: 1
        case .after: 2
        }
    }
}

enum EventTaskDueKind: String, Codable, CaseIterable, DatabaseValueConvertible {
    case none
    case relative
    case fixed
}

enum ContextReferenceProvider: String, Codable, CaseIterable, DatabaseValueConvertible {
    case web
    case notion
}

enum ContextReferenceState: String, Codable, CaseIterable, DatabaseValueConvertible {
    case active
    case missing
    case permissionRequired = "permission_required"
    case disconnected
}

struct ContextReference: Equatable, Identifiable {
    let id: String
    let contextID: String
    var provider: ContextReferenceProvider
    var url: URL
    var titleCache: String
    var state: ContextReferenceState
    var lastCheckedAt: Date?
    let createdAt: Date
    var updatedAt: Date
}

extension ContextReference: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "context_references"
    enum CodingKeys: String, CodingKey {
        case id
        case contextID = "context_id"
        case provider
        case url
        case titleCache = "title_cache"
        case state
        case lastCheckedAt = "last_checked_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum RelativeTaskAnchor: String, Codable, CaseIterable, DatabaseValueConvertible {
    case beforeStart = "before_start"
    case atStart = "at_start"
    case atEnd = "at_end"
    case afterEnd = "after_end"
}

enum EventTaskDue: Equatable {
    case none
    case relative(anchor: RelativeTaskAnchor, offsetMinutes: Int)
    case fixed(Date)
}

enum EventTaskDuePolicy {
    static let maximumOffsetMinutes = 2_628_000
}

struct EventContext: Equatable, Identifiable {
    let id: String
    var titleSnapshot: String
    var startSnapshot: Date?
    var endSnapshot: Date?
    var lifecycleStatus: EventLifecycleStatus
    var notes: String
    let createdAt: Date
    var updatedAt: Date
}

extension EventContext: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "event_contexts"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case titleSnapshot = "title_snapshot"
        case startSnapshot = "start_snapshot"
        case endSnapshot = "end_snapshot"
        case lifecycleStatus = "lifecycle_status"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct EventLink: Equatable, Identifiable {
    let id: String
    let contextID: String
    var eventIdentifier: String?
    var calendarItemIdentifier: String?
    var calendarItemExternalIdentifier: String?
    var calendarIdentifier: String
    var sourceTitle: String
    var calendarTitleSnapshot: String
    var titleSnapshot: String
    var startSnapshot: Date
    var endSnapshot: Date
    var locationSnapshot: String?
    var isAllDay: Bool
    var isRecurring: Bool
    var timeSemantics: StoredEventTimeSemantics
    var timeZoneIdentifier: String?
    var startLocalComponents: String?
    var endLocalComponents: String?
    var recurrenceSeriesIdentifier: String?
    var occurrenceDate: Date?
    var occurrenceLocalComponents: String?
    var occurrenceIdentityKey: String
    var isDetached: Bool
    var fingerprint: String
    var seriesFingerprint: String?
    var linkStatus: EventLinkStatus
    var lastSeenAt: Date
    let createdAt: Date
    var updatedAt: Date
}

extension EventLink: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "event_links"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contextID = "context_id"
        case eventIdentifier = "event_identifier"
        case calendarItemIdentifier = "calendar_item_identifier"
        case calendarItemExternalIdentifier = "calendar_item_external_identifier"
        case calendarIdentifier = "calendar_identifier"
        case sourceTitle = "source_title"
        case calendarTitleSnapshot = "calendar_title_snapshot"
        case titleSnapshot = "title_snapshot"
        case startSnapshot = "start_snapshot"
        case endSnapshot = "end_snapshot"
        case locationSnapshot = "location_snapshot"
        case isAllDay = "is_all_day"
        case isRecurring = "is_recurring"
        case timeSemantics = "time_semantics"
        case timeZoneIdentifier = "time_zone_identifier"
        case startLocalComponents = "start_local_components"
        case endLocalComponents = "end_local_components"
        case recurrenceSeriesIdentifier = "recurrence_series_identifier"
        case occurrenceDate = "occurrence_date"
        case occurrenceLocalComponents = "occurrence_local_components"
        case occurrenceIdentityKey = "occurrence_identity_key"
        case isDetached = "is_detached"
        case fingerprint
        case seriesFingerprint = "series_fingerprint"
        case linkStatus = "link_status"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let contextID = Column(CodingKeys.contextID)
    }
}

struct EventTask: Equatable, Identifiable {
    let id: String
    let contextID: String
    var section: EventTaskSection
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var dueKind: EventTaskDueKind
    var relativeAnchor: RelativeTaskAnchor?
    var offsetMinutes: Int?
    var fixedDueAt: Date?
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    var due: EventTaskDue {
        switch dueKind {
        case .none:
            return .none
        case .relative:
            guard let relativeAnchor, let offsetMinutes else { return .none }
            return .relative(
                anchor: relativeAnchor,
                offsetMinutes: offsetMinutes
            )
        case .fixed:
            guard let fixedDueAt else { return .none }
            return .fixed(fixedDueAt)
        }
    }

    func effectiveDueDate(
        eventStart: Date?,
        eventEnd: Date?
    ) -> Date? {
        switch due {
        case .none:
            switch section {
            case .before, .during:
                return eventStart
            case .after:
                return eventEnd
            }
        case let .fixed(date):
            return date
        case let .relative(anchor, offsetMinutes):
            let interval = TimeInterval(offsetMinutes) * 60
            switch anchor {
            case .beforeStart:
                return eventStart?.addingTimeInterval(-interval)
            case .atStart:
                return eventStart
            case .atEnd:
                return eventEnd
            case .afterEnd:
                return eventEnd?.addingTimeInterval(interval)
            }
        }
    }
}

extension EventTask: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "event_tasks"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contextID = "context_id"
        case section
        case title
        case isCompleted = "completed"
        case sortOrder = "sort_order"
        case dueKind = "due_kind"
        case relativeAnchor = "relative_anchor"
        case offsetMinutes = "offset_minutes"
        case fixedDueAt = "fixed_due_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }

    enum Columns {
        static let contextID = Column(CodingKeys.contextID)
    }
}

struct PersonalTask: Equatable, Identifiable {
    let id: String
    var title: String
    var notes: String
    var dueAt: Date?
    var isCompleted: Bool
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

extension PersonalTask: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "personal_tasks"

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case dueAt = "due_at"
        case isCompleted = "completed"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }
}

enum PersonalTaskList: Equatable {
    case today
    case upcoming
    case completed
}

enum TaskCenterItemID: Hashable, Comparable {
    case eventTask(taskID: String, contextID: String)
    case personalTask(taskID: String)

    static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (
            .eventTask(lhsTaskID, lhsContextID),
            .eventTask(rhsTaskID, rhsContextID)
        ):
            if lhsContextID != rhsContextID {
                return lhsContextID < rhsContextID
            }
            return lhsTaskID < rhsTaskID
        case (.eventTask, .personalTask):
            return true
        case (.personalTask, .eventTask):
            return false
        case let (.personalTask(lhsTaskID), .personalTask(rhsTaskID)):
            return lhsTaskID < rhsTaskID
        }
    }
}

enum TaskCenterItemSource: Equatable {
    case event(
        contextID: String,
        section: EventTaskSection,
        eventTitle: String,
        calendarIdentifier: String,
        calendarTitle: String,
        sourceTitle: String,
        eventStart: Date,
        eventEnd: Date,
        isAllDay: Bool
    )
    case personal
}

struct TaskCenterProviderLink: Equatable {
    let bindingID: String
    let provider: TaskProviderKind
    let accountKey: String
    let accountTitle: String
    let remoteParentID: String
    let syncState: TaskProviderSyncState
    let authorizationState: TaskProviderAuthorizationState

    var needsAttention: Bool {
        switch syncState {
        case .missing, .conflict, .disconnected:
            true
        case .pendingCreate, .linked:
            false
        }
    }
}

struct TaskCenterItem: Equatable, Identifiable {
    let id: TaskCenterItemID
    let title: String
    let isCompleted: Bool
    let dueAt: Date?
    let completedAt: Date?
    let sortOrder: Int
    let source: TaskCenterItemSource
    let providerLink: TaskCenterProviderLink?
    let eventLinkStatus: EventLinkStatus?
    let eventLifecycleStatus: EventLifecycleStatus?
    let wasOriginalDeletedByKaosCal: Bool
}

enum TaskCenterCompletionResult: Equatable {
    case eventTask(EventTask)
    case personalTask(PersonalTask)
}

enum TaskCenterList: Equatable {
    case today
    case upcoming
    case afterReview
    case completed
}

enum EventChangeType: String, Codable, CaseIterable, DatabaseValueConvertible {
    case created
    case detailsUpdated = "details_updated"
    case moved
    case recurrenceChanged = "recurrence_changed"
    case cancelled
    case completed
    case restored
    case relinked
}

enum EventChangeScope: String, Codable, CaseIterable, DatabaseValueConvertible {
    case single
    case thisEvent = "this_event"
    case futureEvents = "future_events"
}

enum EventChangeUndoState: String, Codable, CaseIterable, DatabaseValueConvertible {
    case available
    case superseded
    case undone
    case unavailable
}

struct EventChangeSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let eventIdentifier: String?
    let calendarItemIdentifier: String?
    let calendarItemExternalIdentifier: String?
    let calendarIdentifier: String
    let calendarTitle: String
    let sourceTitle: String
    let title: String
    let location: String?
    let originalNotes: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeSemantics: StoredEventTimeSemantics
    let timeZoneIdentifier: String?
    let startLocalComponents: StoredLocalDateTimeComponents?
    let endLocalComponents: StoredLocalDateTimeComponents?
    let isRecurring: Bool
    let occurrenceDate: Date?
    let occurrenceLocalComponents: StoredLocalDateTimeComponents?
    let occurrenceIdentityKey: String
    let isDetached: Bool

    init(event: DisplayEvent) throws {
        let linkSnapshot = try EventLinkSnapshot(event: event)
        let localComponents: (
            StoredLocalDateTimeComponents?,
            StoredLocalDateTimeComponents?
        )
        switch event.timeSemantics {
        case let .allDay(start, endExclusive):
            localComponents = (
                StoredLocalDateTimeComponents(components: start),
                StoredLocalDateTimeComponents(components: endExclusive)
            )
        case let .floating(start, end):
            localComponents = (
                StoredLocalDateTimeComponents(components: start),
                StoredLocalDateTimeComponents(components: end)
            )
        case .zoned:
            localComponents = (nil, nil)
        }

        schemaVersion = 1
        eventIdentifier = event.eventIdentifier
        calendarItemIdentifier = event.calendarItemIdentifier
        calendarItemExternalIdentifier = event.calendarItemExternalIdentifier
        calendarIdentifier = event.calendarIdentifier
        calendarTitle = event.calendarTitle
        sourceTitle = event.sourceTitle
        title = event.title
        location = event.location
        originalNotes = event.originalNotes
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        timeSemantics = linkSnapshot.timeSemantics
        timeZoneIdentifier = linkSnapshot.timeZoneIdentifier
        startLocalComponents = localComponents.0
        endLocalComponents = localComponents.1
        isRecurring = event.isRecurring
        occurrenceDate = event.occurrenceDate
        occurrenceLocalComponents = event.occurrenceLocalComponents.map(
            StoredLocalDateTimeComponents.init(components:)
        )
        occurrenceIdentityKey = linkSnapshot.occurrenceIdentityKey
        isDetached = event.isDetached
    }

    init(link: EventLink) throws {
        let storedStart = try Self.decodeStoredComponents(
            link.startLocalComponents
        )
        let storedEnd = try Self.decodeStoredComponents(
            link.endLocalComponents
        )
        let storedOccurrence = try Self.decodeStoredComponents(
            link.occurrenceLocalComponents
        )
        if link.timeSemantics != .zoned,
           storedStart == nil || storedEnd == nil {
            throw CalendarEventLookupError.invalidStoredTimeSemantics
        }
        if link.isRecurring,
           link.timeSemantics != .zoned,
           storedOccurrence == nil {
            throw CalendarEventLookupError.invalidStoredOccurrence
        }

        schemaVersion = 1
        eventIdentifier = link.eventIdentifier
        calendarItemIdentifier = link.calendarItemIdentifier
        calendarItemExternalIdentifier = link.calendarItemExternalIdentifier
        calendarIdentifier = link.calendarIdentifier
        calendarTitle = link.calendarTitleSnapshot
        sourceTitle = link.sourceTitle
        title = link.titleSnapshot
        location = link.locationSnapshot
        originalNotes = nil
        startDate = link.startSnapshot
        endDate = link.endSnapshot
        isAllDay = link.isAllDay
        timeSemantics = link.timeSemantics
        timeZoneIdentifier = link.timeZoneIdentifier
        startLocalComponents = storedStart
        endLocalComponents = storedEnd
        isRecurring = link.isRecurring
        occurrenceDate = link.occurrenceDate
        occurrenceLocalComponents = storedOccurrence
        occurrenceIdentityKey = link.occurrenceIdentityKey
        isDetached = link.isDetached
    }

    var supportsSingleEventUndo: Bool {
        !isRecurring && occurrenceDate == nil && !isDetached
    }

    func hasSameUndoableState(as other: Self) -> Bool {
        guard calendarIdentifier == other.calendarIdentifier,
              title == other.title,
              location == other.location,
              originalNotes == other.originalNotes,
              isAllDay == other.isAllDay,
              timeSemantics == other.timeSemantics,
              timeZoneIdentifier == other.timeZoneIdentifier,
              isRecurring == other.isRecurring,
              occurrenceIdentityKey == other.occurrenceIdentityKey,
              isDetached == other.isDetached else {
            return false
        }

        switch timeSemantics {
        case .zoned:
            return startDate == other.startDate && endDate == other.endDate
        case .allDay, .floating:
            return startLocalComponents == other.startLocalComponents
                && endLocalComponents == other.endLocalComponents
        }
    }

    private static func decodeStoredComponents(
        _ encoded: String?
    ) throws -> StoredLocalDateTimeComponents? {
        guard let encoded,
              let data = encoded.data(using: .utf8) else {
            return nil
        }
        return try JSONDecoder().decode(
            StoredLocalDateTimeComponents.self,
            from: data
        )
    }
}

struct EventChangeLog: Equatable, Identifiable {
    let id: String
    let contextID: String
    let changeType: EventChangeType
    let scope: EventChangeScope
    let before: EventChangeSnapshot
    let after: EventChangeSnapshot
    let undoState: EventChangeUndoState
    let undoneAt: Date?
    let undoOfChangeID: String?
    let createdAt: Date
}

struct EventMutationTaskSummary: Equatable {
    let section: EventTaskSection
    let count: Int
    let titles: [String]
}

struct EventMutationImpact: Equatable {
    let contextID: String
    let hasNotes: Bool
    let notesCharacterCount: Int
    let taskCount: Int
    let taskSections: [EventMutationTaskSummary]
    let recentHistory: [EventChangeLog]
}

struct EventChangeLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "event_change_log"

    let id: String
    let contextID: String
    let changeType: EventChangeType
    let scope: EventChangeScope
    let beforePayload: String
    let afterPayload: String
    var undoState: EventChangeUndoState
    var undoneAt: Date?
    let undoOfChangeID: String?
    let createdAt: Date

    static func databaseDateEncodingStrategy(
        for column: String
    ) -> DatabaseDateEncodingStrategy {
        .deferredToDate
    }

    static func databaseDateDecodingStrategy(
        for column: String
    ) -> DatabaseDateDecodingStrategy {
        .deferredToDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contextID = "context_id"
        case changeType = "change_type"
        case scope
        case beforePayload = "before_payload"
        case afterPayload = "after_payload"
        case undoState = "undo_state"
        case undoneAt = "undone_at"
        case undoOfChangeID = "undo_of_change_id"
        case createdAt = "created_at"
    }
}

struct EventLinkSnapshot: Equatable {
    let eventIdentifier: String?
    let calendarItemIdentifier: String?
    let calendarItemExternalIdentifier: String?
    let calendarIdentifier: String
    let sourceTitle: String
    let calendarTitle: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let isAllDay: Bool
    let isRecurring: Bool
    let timeSemantics: StoredEventTimeSemantics
    let timeZoneIdentifier: String?
    let startLocalComponents: String?
    let endLocalComponents: String?
    let recurrenceSeriesIdentifier: String?
    let occurrenceDate: Date?
    let occurrenceLocalComponents: String?
    let occurrenceIdentityKey: String
    let isDetached: Bool
    let fingerprint: String
    let seriesFingerprint: String?

    init(event: DisplayEvent) throws {
        let localComponents: (String?, String?)
        let semanticStartComponents: LocalDateTimeComponents?
        let storedTimeSemantics: StoredEventTimeSemantics
        let storedTimeZoneIdentifier: String?

        switch event.timeSemantics {
        case let .allDay(start, endExclusive):
            storedTimeSemantics = .allDay
            storedTimeZoneIdentifier = nil
            localComponents = (
                try Self.encode(start),
                try Self.encode(endExclusive)
            )
            semanticStartComponents = start
        case let .floating(start, end):
            storedTimeSemantics = .floating
            storedTimeZoneIdentifier = nil
            localComponents = (
                try Self.encode(start),
                try Self.encode(end)
            )
            semanticStartComponents = start
        case let .zoned(timeZoneIdentifier):
            storedTimeSemantics = .zoned
            storedTimeZoneIdentifier = timeZoneIdentifier
            localComponents = (nil, nil)
            semanticStartComponents = nil
        }

        eventIdentifier = event.eventIdentifier
        calendarItemIdentifier = event.calendarItemIdentifier
        calendarItemExternalIdentifier = event.calendarItemExternalIdentifier
        calendarIdentifier = event.calendarIdentifier
        sourceTitle = event.sourceTitle
        calendarTitle = event.calendarTitle
        title = event.title
        startDate = event.startDate
        endDate = event.endDate
        location = event.location
        isAllDay = event.isAllDay
        isRecurring = event.isRecurring
        timeSemantics = storedTimeSemantics
        timeZoneIdentifier = storedTimeZoneIdentifier
        startLocalComponents = localComponents.0
        endLocalComponents = localComponents.1
        recurrenceSeriesIdentifier = event.isRecurring
            ? EventIdentityFingerprint.firstNonEmpty(
                event.calendarItemExternalIdentifier,
                event.calendarItemIdentifier
            )
            : nil
        let recurringOccurrenceDate = event.isRecurring
            ? (event.occurrenceDate ?? event.startDate)
            : nil
        occurrenceDate = recurringOccurrenceDate
        if event.isRecurring {
            switch storedTimeSemantics {
            case .zoned:
                occurrenceLocalComponents = nil
                occurrenceIdentityKey = Self.instantOccurrenceKey(
                    recurringOccurrenceDate ?? event.startDate
                )
            case .allDay, .floating:
                guard let components = event.occurrenceLocalComponents
                        ?? semanticStartComponents else {
                    throw EventLinkSnapshotError.missingLocalOccurrence
                }
                let encodedComponents = try Self.encode(components)
                occurrenceLocalComponents = encodedComponents
                occurrenceIdentityKey = "local:v1:\(encodedComponents)"
            }
        } else {
            occurrenceLocalComponents = nil
            occurrenceIdentityKey = "single:v1"
        }
        isDetached = event.isDetached
        fingerprint = EventIdentityFingerprint.make(event: event)
        seriesFingerprint = EventIdentityFingerprint.makeSeries(event: event)
    }

    private static func encode(
        _ components: LocalDateTimeComponents
    ) throws -> String {
        let snapshot = StoredLocalDateTimeComponents(components: components)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        return String(decoding: data, as: UTF8.self)
    }

    private static func instantOccurrenceKey(_ date: Date) -> String {
        let milliseconds = Int64(
            (date.timeIntervalSince1970 * 1_000).rounded()
        )
        return "instant:v1:\(milliseconds)"
    }
}

private enum EventLinkSnapshotError: Error {
    case missingLocalOccurrence
}

struct StoredLocalDateTimeComponents: Codable, Equatable {
    let calendarIdentifier: String
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int

    init(components: LocalDateTimeComponents) {
        calendarIdentifier = String(describing: components.calendarIdentifier)
        year = components.year
        month = components.month
        day = components.day
        hour = components.hour
        minute = components.minute
        second = components.second
    }

    var localComponents: LocalDateTimeComponents {
        LocalDateTimeComponents(
            calendarIdentifier: Self.identifier(named: calendarIdentifier),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    }

    func date(in displayCalendar: Calendar) -> Date? {
        var calendar = Calendar(identifier: Self.identifier(
            named: calendarIdentifier
        ))
        calendar.locale = displayCalendar.locale
        calendar.timeZone = displayCalendar.timeZone
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )
    }

    static func identifier(
        named name: String
    ) -> Calendar.Identifier {
        switch name {
        case "buddhist": .buddhist
        case "iso8601": .iso8601
        case "japanese": .japanese
        default: .gregorian
        }
    }
}

extension EventLink {
    func calendarEventLookupQuery() throws -> CalendarEventLookupQuery {
        guard EventIdentityFingerprint.firstNonEmpty(
            eventIdentifier,
            calendarItemIdentifier,
            calendarItemExternalIdentifier
        ) != nil else {
            throw CalendarEventLookupError.missingStrongIdentifier
        }

        let semantics: EventTimeSemantics
        switch timeSemantics {
        case .zoned:
            guard let timeZoneIdentifier else {
                throw CalendarEventLookupError.invalidStoredTimeSemantics
            }
            semantics = .zoned(timeZoneIdentifier: timeZoneIdentifier)
        case .allDay, .floating:
            guard let start = try decodedLocalComponents(startLocalComponents),
                  let end = try decodedLocalComponents(endLocalComponents) else {
                throw CalendarEventLookupError.invalidStoredTimeSemantics
            }
            semantics = timeSemantics == .allDay
                ? .allDay(start: start, endExclusive: end)
                : .floating(start: start, end: end)
        }

        let occurrence: CalendarEventLookupOccurrence
        if !isRecurring {
            occurrence = .single
        } else {
            switch timeSemantics {
            case .zoned:
                guard let occurrenceDate else {
                    throw CalendarEventLookupError.invalidStoredOccurrence
                }
                occurrence = .instant(occurrenceDate)
            case .allDay, .floating:
                guard let components = try decodedLocalComponents(
                    occurrenceLocalComponents
                ) else {
                    throw CalendarEventLookupError.invalidStoredOccurrence
                }
                occurrence = timeSemantics == .allDay
                    ? .allDay(components)
                    : .floating(components)
            }
        }

        var seenAnchors = Set<Int64>()
        let searchAnchors = [occurrenceDate, startSnapshot]
            .compactMap { $0 }
            .filter { date in
                seenAnchors.insert(Int64(
                    (date.timeIntervalSinceReferenceDate * 1_000).rounded()
                )).inserted
            }

        return CalendarEventLookupQuery(
            eventIdentifier: eventIdentifier,
            calendarItemIdentifier: calendarItemIdentifier,
            calendarItemExternalIdentifier: calendarItemExternalIdentifier,
            calendarIdentifier: calendarIdentifier,
            occurrence: occurrence,
            searchAnchors: searchAnchors,
            lastKnown: CalendarEventLookupSnapshot(
                calendarTitle: calendarTitleSnapshot,
                sourceTitle: sourceTitle,
                title: titleSnapshot,
                location: locationSnapshot,
                startDate: startSnapshot,
                endDate: endSnapshot,
                isAllDay: isAllDay,
                timeSemantics: semantics
            )
        )
    }

    func effectiveDateRange(
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        guard timeSemantics != .zoned,
              let startLocalComponents,
              let endLocalComponents,
              let startData = startLocalComponents.data(using: .utf8),
              let endData = endLocalComponents.data(using: .utf8),
              let startSnapshot = try? JSONDecoder().decode(
                StoredLocalDateTimeComponents.self,
                from: startData
              ),
              let endSnapshot = try? JSONDecoder().decode(
                StoredLocalDateTimeComponents.self,
                from: endData
              ),
              let start = startSnapshot.date(in: calendar),
              let end = endSnapshot.date(in: calendar) else {
            return (self.startSnapshot, self.endSnapshot)
        }
        return (start, end)
    }

    private func decodedLocalComponents(
        _ encoded: String?
    ) throws -> LocalDateTimeComponents? {
        guard let encoded,
              let data = encoded.data(using: .utf8) else {
            return nil
        }
        return try JSONDecoder().decode(
            StoredLocalDateTimeComponents.self,
            from: data
        ).localComponents
    }
}
