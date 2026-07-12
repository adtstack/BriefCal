import Combine
import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable, Identifiable {
    case day
    case week
    case agenda
    case tasks

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .agenda: "Agenda"
        case .tasks: "Tasks"
        }
    }

    var symbolName: String {
        switch self {
        case .day: "calendar"
        case .week: "calendar.badge.clock"
        case .agenda: "list.bullet"
        case .tasks: "checklist"
        }
    }

    var accessibilityIdentifier: String { "nav.\(rawValue)" }
}

enum TaskFilter: String, CaseIterable, Hashable, Identifiable {
    case today
    case upcoming
    case afterReview
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .afterReview: "After Review"
        case .completed: "Completed"
        }
    }
}

enum CalendarContentState: Equatable {
    case disconnected
    case loading
    case empty
    case loaded
    case permissionDenied
    case failed(String)
}

enum LocalContextStoreState: Equatable {
    case unavailable
    case ready
    case failed(String)
}

enum LocalDataOperationState: Equatable {
    case idle
    case exporting
    case importing
    case resetting
    case quarantined
}

typealias LocalDataImportOperation = @Sendable (
    _ service: LocalDataBackupService,
    _ archiveURL: URL,
    _ automaticBackupDirectory: URL,
    _ now: Date,
    _ appVersion: String
) throws -> LocalDataImportResult

typealias LocalDataResetOperation = @Sendable (
    _ service: LocalDataBackupService,
    _ automaticBackupDirectory: URL,
    _ now: Date,
    _ appVersion: String
) throws -> LocalDataResetResult

enum EventBriefState: Equatable {
    case noSelection
    case unavailable
    case empty
    case loaded(EventBriefSnapshot)
    case confirmationRequired([String])
    case failed(String)
}

enum LinkedEventRecoveryStage: Equatable {
    case firstMissing
    case orphanConfirmation
    case orphaned
    case deletedOriginal
    case manualRelink
    case candidates([CalendarEventLookupMatch])
    case confirmRelink(DisplayEvent)
}

struct LinkedEventRecoverySession: Equatable, Identifiable {
    let brief: EventBriefSnapshot
    let stage: LinkedEventRecoveryStage

    var id: String { brief.context.id }
}

enum NotesSaveState: Equatable {
    case idle
    case pending
    case saving
    case saved
    case failed(String)
}

enum TaskCenterState: Equatable {
    case unavailable
    case loading
    case loaded([TaskCenterItem])
    case failed(String)
}

enum CalendarEventEditorTarget: Equatable {
    case newEvent
    case existing(DisplayEvent)
}

struct CalendarEventEditorSession: Equatable, Identifiable {
    let target: CalendarEventEditorTarget
    let initialDraft: CalendarEventDraft
    let writableCalendars: [CalendarSource]
    let mutationContext: EventMutationContext
    let mutationImpact: EventMutationImpact?

    init(
        target: CalendarEventEditorTarget,
        initialDraft: CalendarEventDraft,
        writableCalendars: [CalendarSource],
        mutationContext: EventMutationContext,
        mutationImpact: EventMutationImpact? = nil
    ) {
        self.target = target
        self.initialDraft = initialDraft
        self.writableCalendars = writableCalendars
        self.mutationContext = mutationContext
        self.mutationImpact = mutationImpact
    }

    var id: String {
        switch target {
        case .newEvent:
            "new-event"
        case let .existing(event):
            "edit-\(event.id)"
        }
    }
}

enum CalendarEventEditorOperationState: Equatable {
    case idle
    case saving
    case deleting
}

struct CalendarEventMutationPreview: Equatable, Identifiable {
    let original: DisplayEvent
    let draft: CalendarEventDraft
    let scope: CalendarEventMutationScope
    let mutationContext: EventMutationContext
    let impact: EventMutationImpact?
    let changedFields: Set<CalendarEventChangedField>

    var id: String {
        [
            original.id,
            scope.rawValue,
            changedFields.map(\.rawValue).sorted().joined(separator: ",")
        ].joined(separator: "#")
    }
}

struct LinkedOriginalDeletionPreview: Equatable, Identifiable {
    let original: DisplayEvent
    let scope: CalendarEventMutationScope
    let contextID: String
    let brief: EventBriefSnapshot
    let expectedLink: EventLink
    let expectedSnapshot: EventChangeSnapshot
    let impact: EventMutationImpact

    var id: String {
        [original.id, scope.rawValue, contextID, expectedLink.id]
            .joined(separator: "#")
    }
}

private struct CalendarEventUndoCandidate {
    let contextID: String
    let changeID: String
    let beforeDraft: CalendarEventDraft
    let afterEvent: DisplayEvent
}

private enum EventMutationSafetyError: LocalizedError {
    case linkedFutureSeriesDeferred
    case confirmationUnavailable
    case deletionNotCommitted
    case undoUnavailable

    var errorDescription: String? {
        switch self {
        case .linkedFutureSeriesDeferred:
            "This Event Brief is linked to one occurrence. KaosCal will not change or delete this and future occurrences until every affected Brief can be reconciled safely."
        case .confirmationUnavailable:
            "The prepared event change is no longer current. Review the editor and prepare it again."
        case .deletionNotCommitted:
            "The calendar provider did not confirm a deletion. Nothing local was changed; review and try again."
        case .undoUnavailable:
            "The last calendar change is no longer available to undo."
        }
    }
}

private enum LocalDataMaintenanceError: LocalizedError {
    case unavailable
    case operationInProgress
    case recoveryRequired(String)
    case unsavedNotes
    case interactionInProgress
    case automaticBackupLocationUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "KaosCal local data is unavailable, so this operation did not run."
        case .operationInProgress:
            "Another local data operation is already in progress."
        case let .recoveryRequired(message):
            message
        case .unsavedNotes:
            "KaosCal could not save every open notes draft. Retry the failed draft before backing up, importing, or resetting local data."
        case .interactionInProgress:
            "Finish or close the event editor, recovery review, relink check, or Undo operation before replacing local data."
        case .automaticBackupLocationUnavailable:
            "KaosCal could not determine a safe location for the automatic recovery backup. Nothing was changed."
        }
    }
}

private struct FailedNotesDraft {
    let text: String
    let message: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: WorkspaceSection? = .week
    @Published private(set) var selectedTaskFilter: TaskFilter = .today
    @Published var focusedDate: Date
    @Published private(set) var selectedEventID: String?
    @Published var calendarContentState: CalendarContentState = .disconnected
    @Published private(set) var calendarAuthorizationState: CalendarAuthorizationState
    @Published private(set) var calendarSources: [CalendarSource] = []
    @Published private(set) var calendarRoleOverrides: [String: CalendarRole] = [:]
    @Published private(set) var selectedCalendarSet: CalendarSetFilter = .all
    @Published private(set) var events: [DisplayEvent] = []
    @Published private(set) var localContextStoreState: LocalContextStoreState
    @Published private(set) var localDataOperationState: LocalDataOperationState = .idle
    @Published private(set) var localDataOperationMessage: String?
    @Published private(set) var eventBriefState: EventBriefState = .noSelection
    @Published private(set) var selectedEventNotes = ""
    @Published private(set) var notesSaveState: NotesSaveState = .idle
    @Published private(set) var taskCenterState: TaskCenterState = .unavailable
    @Published private(set) var recoveryBriefs: [EventBriefSnapshot] = []
    @Published private(set) var linkedEventRecoverySession: LinkedEventRecoverySession?
    @Published private(set) var pendingRelinkContextID: String?
    @Published private(set) var isCheckingLinkedEvent = false
    @Published private(set) var localOperationError: String?
    @Published private(set) var eventEditorSession: CalendarEventEditorSession?
    @Published private(set) var eventEditorOperationState: CalendarEventEditorOperationState = .idle
    @Published private(set) var eventEditorError: String?
    @Published private(set) var pendingEventMutation: CalendarEventMutationPreview?
    @Published private(set) var pendingLinkedOriginalDeletion: LinkedOriginalDeletionPreview?
    @Published private(set) var lastEventMutationUndoAvailable = false
    @Published private(set) var eventUndoError: String?
    @Published private(set) var isUndoingEventMutation = false

    let calendar: Calendar
    let contextStore: ContextStore?
    private let now: () -> Date
    private let calendarProvider: CalendarProviding
    private let localDataImportOperation: LocalDataImportOperation
    private let localDataResetOperation: LocalDataResetOperation
    private var storeRefreshTask: Task<Void, Never>?
    private var rangeLoadTask: Task<Void, Never>?
    private var notesSaveTask: Task<Void, Never>?
    private var loadedEventInterval: DateInterval?
    private var activeBriefEvent: DisplayEvent?
    private var persistedEventNotes = ""
    private var failedNotesDrafts: [String: FailedNotesDraft] = [:]
    private var lastEventMutationUndoCandidate: CalendarEventUndoCandidate?
    private var calendarRefreshDeferredByLocalDataOperation = false
    private var localDataQuarantineMessage: String?
    private var duplicateCandidateIndex:
        [String: [CalendarDuplicateCandidate]] = [:]

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        calendarProvider: CalendarProviding? = nil,
        contextStore: ContextStore? = nil,
        localContextStoreState: LocalContextStoreState = .unavailable,
        localDataImportOperation: @escaping LocalDataImportOperation = {
            service, archiveURL, automaticBackupDirectory, now, appVersion in
            try service.importBackup(
                from: archiveURL,
                automaticBackupDirectory: automaticBackupDirectory,
                now: now,
                appVersion: appVersion
            )
        },
        localDataResetOperation: @escaping LocalDataResetOperation = {
            service, automaticBackupDirectory, now, appVersion in
            try service.resetLocalData(
                automaticBackupDirectory: automaticBackupDirectory,
                now: now,
                appVersion: appVersion
            )
        }
    ) {
        let calendarProvider = calendarProvider ?? EventKitProvider()
        self.calendar = calendar
        self.now = now
        self.calendarProvider = calendarProvider
        self.contextStore = contextStore
        self.localContextStoreState = localContextStoreState
        self.localDataImportOperation = localDataImportOperation
        self.localDataResetOperation = localDataResetOperation
        calendarAuthorizationState = calendarProvider.authorizationState
        focusedDate = calendar.startOfDay(for: now())

        calendarProvider.storeChangeHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleStoreRefresh()
            }
        }
        loadCalendarRolePreferences()
    }

    var selectedEvent: DisplayEvent? {
        guard let selectedEventID else { return nil }
        return events.first { $0.id == selectedEventID }
    }

    var taskReferenceDate: Date { now() }

    var localDataDatabaseURL: URL? {
        contextStore?.localDataBackups.databaseURL
    }

    private var localDataMaintenanceBlockError: LocalDataMaintenanceError {
        guard localDataOperationState == .quarantined else {
            return .operationInProgress
        }
        return .recoveryRequired(
            localDataQuarantineMessage
                ?? "KaosCal local data is locked for this session after a failed rollback. Quit KaosCal before attempting recovery."
        )
    }

    var visibleDates: [Date] {
        let section = selectedSection ?? .week
        let focusedDay = calendar.startOfDay(for: focusedDate)
        let start: Date
        let dayCount: Int

        switch section {
        case .day, .tasks:
            start = focusedDay
            dayCount = 1
        case .week, .agenda:
            start = calendar.dateInterval(
                of: .weekOfYear,
                for: focusedDay
            )?.start ?? focusedDay
            dayCount = 7
        }

        return (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    var visibleInterval: DateInterval {
        let start = visibleDates.first ?? calendar.startOfDay(for: focusedDate)
        let finalDate = visibleDates.last ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: finalDate)
            ?? finalDate.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    var visibleEvents: [DisplayEvent] {
        let interval = visibleInterval
        return events.filter {
            let range = CalendarEventDateFormatting.effectiveDateRange(
                for: $0,
                calendar: calendar
            )
            return range.start < interval.end
                && range.end > interval.start
                && selectedCalendarSet.includes(role: calendarRole(for: $0))
        }.sorted { lhs, rhs in
            let lhsRange = CalendarEventDateFormatting.effectiveDateRange(
                for: lhs,
                calendar: calendar
            )
            let rhsRange = CalendarEventDateFormatting.effectiveDateRange(
                for: rhs,
                calendar: calendar
            )
            if lhsRange.start != rhsRange.start {
                return lhsRange.start < rhsRange.start
            }
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay
            }
            return lhs.id < rhs.id
        }
    }

    var focusedPeriodTitle: String {
        switch selectedSection ?? .week {
        case .day, .tasks:
            return CalendarEventDateFormatting.longDate(
                focusedDate,
                calendar: calendar
            )
        case .week, .agenda:
            guard let start = visibleDates.first,
                  let end = visibleDates.last else {
                return CalendarEventDateFormatting.longDate(
                    focusedDate,
                    calendar: calendar
                )
            }
            return "\(CalendarEventDateFormatting.abbreviatedDate(start, calendar: calendar)) – \(CalendarEventDateFormatting.abbreviatedDate(end, calendar: calendar))"
        }
    }

    func select(_ section: WorkspaceSection) {
        selectedSection = section
        if section == .tasks {
            refreshTaskCenter()
        }
        visiblePeriodDidChange()
    }

    func selectTaskFilter(_ filter: TaskFilter) {
        selectedTaskFilter = filter
        refreshTaskCenter()
    }

    func selectCalendarSet(_ filter: CalendarSetFilter) {
        guard localDataOperationState == .idle else { return }
        guard selectedCalendarSet != filter else { return }
        flushPendingEventNotes()
        selectedCalendarSet = filter
        clearSelectionOutsideVisiblePeriod()
    }

    func calendarDescriptor(for source: CalendarSource) -> CalendarDescriptor {
        CalendarDescriptor(
            source: source,
            explicitRole: calendarRoleOverrides[source.id]
        )
    }

    func calendarRole(for source: CalendarSource) -> CalendarRole {
        calendarDescriptor(for: source).role
    }

    func calendarRole(for event: DisplayEvent) -> CalendarRole {
        if let source = calendarSources.first(where: {
            $0.id == event.calendarIdentifier
        }) {
            return calendarRole(for: source)
        }
        return calendarRoleOverrides[event.calendarIdentifier] ?? .other
    }

    func calendarRole(calendarIdentifier: String) -> CalendarRole {
        if let source = calendarSources.first(where: {
            $0.id == calendarIdentifier
        }) {
            return calendarRole(for: source)
        }
        return calendarRoleOverrides[calendarIdentifier] ?? .other
    }

    @discardableResult
    func setCalendarRole(
        _ role: CalendarRole,
        for source: CalendarSource
    ) -> Bool {
        localOperationError = nil
        guard localDataOperationState == .idle else {
            localOperationError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let contextStore else {
            localOperationError = "Local calendar role storage is unavailable. No calendar data was changed."
            return false
        }
        do {
            let preference = try contextStore.calendarRoles.upsert(
                source: source,
                role: role
            )
            calendarRoleOverrides[source.id] = preference.role
            clearSelectionOutsideVisiblePeriod()
            return true
        } catch {
            localOperationError = Self.message(for: error)
            return false
        }
    }

    func calendarWriteRestriction(
        for event: DisplayEvent
    ) -> CalendarWriteRestriction? {
        CalendarWriteRestriction.restriction(for: event)
    }

    func duplicateCandidates(
        for event: DisplayEvent
    ) -> [CalendarDuplicateCandidate] {
        duplicateCandidateIndex[event.id] ?? []
    }

    func hasDuplicateCandidates(for event: DisplayEvent) -> Bool {
        duplicateCandidateIndex[event.id]?.isEmpty == false
    }

    func selectDuplicateCandidate(_ candidate: CalendarDuplicateCandidate) {
        guard localDataOperationState == .idle else { return }
        selectedCalendarSet = .all
        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: candidate.event,
            calendar: calendar
        )
        focusedDate = calendar.startOfDay(for: range.start)
        selectedSection = .day
        visiblePeriodDidChange()
        selectEvent(candidate.event.id)
    }

    func selectEvent(_ id: String?) {
        guard localDataOperationState == .idle else { return }
        let event = id.flatMap { requestedID in
            events.first { $0.id == requestedID }
        }
        let isChangingEvent = activeBriefEvent?.id != event?.id

        guard isChangingEvent else {
            selectedEventID = event?.id
            activeBriefEvent = event
            return
        }
        flushPendingEventNotes()
        notesSaveTask?.cancel()
        notesSaveTask = nil
        selectedEventID = event?.id
        activeBriefEvent = event
        loadSelectedEventBrief()
    }

    func userSelectEvent(_ id: String?) {
        guard localDataOperationState == .idle else { return }
        selectEvent(id)
        guard let contextID = pendingRelinkContextID,
              let event = id.flatMap({ requestedID in
                  events.first { $0.id == requestedID }
              }),
              let contextStore else {
            return
        }
        do {
            guard let brief = try contextStore.eventContexts.fetchBrief(
                contextID: contextID
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            pendingRelinkContextID = nil
            linkedEventRecoverySession = LinkedEventRecoverySession(
                brief: brief,
                stage: .confirmRelink(event)
            )
        } catch {
            pendingRelinkContextID = nil
            localOperationError = Self.message(for: error)
        }
    }

    func reloadSelectedEventBrief() {
        guard localDataOperationState == .idle else { return }
        flushPendingEventNotes()
        loadSelectedEventBrief()
    }

    func reviewSelectedEventRelinkCandidate(contextID: String) {
        guard localDataOperationState == .idle else { return }
        guard let event = activeBriefEvent,
              let contextStore else {
            return
        }
        localOperationError = nil
        do {
            guard let brief = try contextStore.eventContexts.fetchBrief(
                contextID: contextID
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            linkedEventRecoverySession = LinkedEventRecoverySession(
                brief: brief,
                stage: .confirmRelink(event)
            )
        } catch {
            localOperationError = Self.message(for: error)
        }
    }

    func updateSelectedEventNotes(_ notes: String) {
        guard localDataOperationState == .idle else { return }
        guard let event = activeBriefEvent else { return }
        selectedEventNotes = notes
        notesSaveTask?.cancel()
        notesSaveTask = nil

        guard notes != persistedEventNotes else {
            failedNotesDrafts.removeValue(forKey: event.id)
            notesSaveState = .idle
            return
        }

        notesSaveState = .pending
        notesSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 700_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.activeBriefEvent?.id == event.id else {
                return
            }
            self.saveSelectedEventNotesNow()
        }
    }

    func flushPendingEventNotes() {
        notesSaveTask?.cancel()
        notesSaveTask = nil
        guard selectedEventNotes != persistedEventNotes,
              activeBriefEvent != nil else {
            return
        }
        saveSelectedEventNotesNow()
    }

    func retrySelectedEventNotes() {
        saveSelectedEventNotesNow()
    }

    func clearLocalOperationError() {
        localOperationError = nil
    }

    func clearLocalDataOperationMessage() {
        guard localDataOperationState != .quarantined else { return }
        localDataOperationMessage = nil
    }

    @discardableResult
    func exportLocalDataBackup(
        to destinationURL: URL
    ) async -> LocalDataExportResult? {
        let service: LocalDataBackupService
        do {
            service = try beginLocalDataOperation(
                .exporting,
                replacesLocalData: false
            )
        } catch {
            localDataOperationMessage = "Backup did not run. \(Self.message(for: error))"
            return nil
        }

        let accessStarted = destinationURL
            .startAccessingSecurityScopedResource()
        defer {
            if accessStarted {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let operationDate = now()
            let appVersion = Self.currentAppVersion
            let result = try await Task.detached(priority: .userInitiated) {
                try service.exportBackup(
                    to: destinationURL,
                    now: operationDate,
                    appVersion: appVersion
                )
            }.value
            endLocalDataOperation(reloadLocalProjections: false)
            localDataOperationMessage = "Backup exported to \(result.archiveURL.path(percentEncoded: false)). The ZIP is not encrypted."
            return result
        } catch {
            endLocalDataOperation(reloadLocalProjections: false)
            localDataOperationMessage = "Backup failed. No new partial backup was committed; an existing destination, if any, was left unchanged. \(Self.message(for: error))"
            return nil
        }
    }

    @discardableResult
    func importLocalDataBackup(
        from archiveURL: URL
    ) async -> LocalDataImportResult? {
        let service: LocalDataBackupService
        let automaticDirectory: URL
        var operationBegan = false
        do {
            service = try beginLocalDataOperation(
                .importing,
                replacesLocalData: true
            )
            operationBegan = true
            guard let directory = automaticBackupDirectory(for: service) else {
                throw LocalDataMaintenanceError
                    .automaticBackupLocationUnavailable
            }
            automaticDirectory = directory
        } catch {
            if operationBegan {
                endLocalDataOperation(reloadLocalProjections: false)
            }
            localDataOperationMessage = "Import did not run. \(Self.message(for: error))"
            return nil
        }

        let accessStarted = archiveURL.startAccessingSecurityScopedResource()
        defer {
            if accessStarted {
                archiveURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let operationDate = now()
            let appVersion = Self.currentAppVersion
            let importOperation = localDataImportOperation
            let result = try await Task.detached(priority: .userInitiated) {
                try importOperation(
                    service,
                    archiveURL,
                    automaticDirectory,
                    operationDate,
                    appVersion
                )
            }.value
            endLocalDataOperation(reloadLocalProjections: true)
            localDataOperationMessage = "Backup imported. The previous local database was saved to \(result.automaticBackupURL.path(percentEncoded: false)). Calendar and Exchange events were not changed."
            return result
        } catch {
            if Self.rollbackFailed(error) {
                quarantineLocalData(
                    after: "Import",
                    automaticBackupDirectory: automaticDirectory,
                    error: error
                )
                return nil
            }
            endLocalDataOperation(reloadLocalProjections: false)
            localDataOperationMessage = "Import failed validation or restore. The active local database was kept or rolled back. \(Self.message(for: error))"
            return nil
        }
    }

    @discardableResult
    func resetLocalData() async -> LocalDataResetResult? {
        let service: LocalDataBackupService
        let automaticDirectory: URL
        var operationBegan = false
        do {
            service = try beginLocalDataOperation(
                .resetting,
                replacesLocalData: true
            )
            operationBegan = true
            guard let directory = automaticBackupDirectory(for: service) else {
                throw LocalDataMaintenanceError
                    .automaticBackupLocationUnavailable
            }
            automaticDirectory = directory
        } catch {
            if operationBegan {
                endLocalDataOperation(reloadLocalProjections: false)
            }
            localDataOperationMessage = "Reset did not run. \(Self.message(for: error))"
            return nil
        }

        do {
            let operationDate = now()
            let appVersion = Self.currentAppVersion
            let resetOperation = localDataResetOperation
            let result = try await Task.detached(priority: .userInitiated) {
                try resetOperation(
                    service,
                    automaticDirectory,
                    operationDate,
                    appVersion
                )
            }.value
            endLocalDataOperation(reloadLocalProjections: true)
            localDataOperationMessage = "Active KaosCal local data was reset. A recovery backup remains at \(result.automaticBackupURL.path(percentEncoded: false)). Calendar and Exchange events were not changed."
            return result
        } catch {
            if Self.rollbackFailed(error) {
                quarantineLocalData(
                    after: "Reset",
                    automaticBackupDirectory: automaticDirectory,
                    error: error
                )
                return nil
            }
            endLocalDataOperation(reloadLocalProjections: false)
            localDataOperationMessage = "Reset failed. The active local database was kept or rolled back. \(Self.message(for: error))"
            return nil
        }
    }

    func addSelectedEventTask(
        section: EventTaskSection,
        title: String
    ) {
        performLocalMutation {
            guard let event = activeBriefEvent,
                  let contextStore else {
                throw ContextStoreError.missingContext("selected-event")
            }
            flushPendingEventNotes()
            _ = try contextStore.appendEventTask(
                for: event,
                section: section,
                title: title
            )
        }
    }

    func setSelectedEventTaskCompleted(
        id taskID: String,
        isCompleted: Bool
    ) {
        performSelectedEventTaskMutation(taskID: taskID) {
            contextStore, contextID, task in
            _ = try contextStore.setEventTaskCompleted(
                contextID: contextID,
                taskID: task.id,
                isCompleted: isCompleted
            )
        }
    }

    @discardableResult
    func renameSelectedEventTask(id taskID: String, title: String) -> Bool {
        performSelectedEventTaskMutation(taskID: taskID) {
            contextStore, contextID, task in
            _ = try contextStore.updateEventTask(
                contextID: contextID,
                taskID: task.id,
                section: task.section,
                title: title,
                sortOrder: task.sortOrder,
                due: Self.duePolicy(for: task)
            )
        }
    }

    func moveSelectedEventTask(
        id taskID: String,
        to section: EventTaskSection
    ) {
        performSelectedEventTaskMutation(taskID: taskID) {
            contextStore, contextID, task in
            _ = try contextStore.updateEventTask(
                contextID: contextID,
                taskID: task.id,
                section: section,
                title: task.title,
                sortOrder: task.sortOrder,
                due: Self.duePolicy(for: task)
            )
        }
    }

    @discardableResult
    func deleteSelectedEventTask(id taskID: String) -> Bool {
        performSelectedEventTaskMutation(taskID: taskID) {
            contextStore, contextID, task in
            try contextStore.deleteEventTask(
                contextID: contextID,
                taskID: task.id
            )
        }
    }

    @discardableResult
    func createPersonalTask(title: String, dueAt: Date?) -> Bool {
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now())
        ) ?? now()
        if selectedTaskFilter == .upcoming,
           dueAt.map({ $0 < tomorrow }) ?? true {
            localOperationError = "Upcoming tasks need a due date of tomorrow or later."
            return false
        }

        let didCreate = performLocalMutation {
            guard let contextStore else {
                throw ContextStoreError.missingPersonalTask("local-store")
            }
            _ = try contextStore.personalTasks.create(
                title: title,
                dueAt: dueAt
            )
        }
        if didCreate, let dueAt, dueAt >= tomorrow,
           selectedTaskFilter == .today {
            selectTaskFilter(.upcoming)
        }
        return didCreate
    }

    func setTaskCenterItemCompleted(
        _ id: TaskCenterItemID,
        isCompleted: Bool
    ) {
        performLocalMutation {
            guard let contextStore else {
                throw ContextStoreError.missingPersonalTask("local-store")
            }
            _ = try contextStore.setTaskCenterItemCompleted(
                id: id,
                isCompleted: isCompleted
            )
        }
    }

    @discardableResult
    func renameTaskCenterItem(
        _ id: TaskCenterItemID,
        title: String
    ) -> Bool {
        performLocalMutation {
            guard let contextStore else {
                throw ContextStoreError.missingPersonalTask("local-store")
            }
            switch id {
            case let .eventTask(taskID, contextID):
                guard let task = try contextStore.eventTasks.fetch(id: taskID) else {
                    throw ContextStoreError.missingEventTask(taskID)
                }
                _ = try contextStore.updateEventTask(
                    contextID: contextID,
                    taskID: taskID,
                    section: task.section,
                    title: title,
                    sortOrder: task.sortOrder,
                    due: Self.duePolicy(for: task)
                )
            case let .personalTask(taskID):
                guard let task = try contextStore.personalTasks.fetch(id: taskID) else {
                    throw ContextStoreError.missingPersonalTask(taskID)
                }
                guard try contextStore.personalTasks.update(
                    id: taskID,
                    title: title,
                    notes: task.notes,
                    dueAt: task.dueAt,
                    sortOrder: task.sortOrder
                ) != nil else {
                    throw ContextStoreError.missingPersonalTask(taskID)
                }
            }
        }
    }

    @discardableResult
    func updatePersonalTaskDue(
        _ id: TaskCenterItemID,
        dueAt: Date?
    ) -> Bool {
        guard case let .personalTask(taskID) = id else {
            localOperationError = "Only personal tasks have an editable personal due date."
            return false
        }
        let didUpdate = performLocalMutation {
            guard let contextStore,
                  let task = try contextStore.personalTasks.fetch(id: taskID) else {
                throw ContextStoreError.missingPersonalTask(taskID)
            }
            guard try contextStore.personalTasks.update(
                id: taskID,
                title: task.title,
                notes: task.notes,
                dueAt: dueAt,
                sortOrder: task.sortOrder
            ) != nil else {
                throw ContextStoreError.missingPersonalTask(taskID)
            }
        }
        guard didUpdate else { return false }

        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now())
        ) ?? now()
        if dueAt.map({ $0 >= tomorrow }) ?? false {
            selectTaskFilter(.upcoming)
        } else {
            selectTaskFilter(.today)
        }
        return true
    }

    @discardableResult
    func deleteTaskCenterItem(_ id: TaskCenterItemID) -> Bool {
        performLocalMutation {
            guard let contextStore else {
                throw ContextStoreError.missingPersonalTask("local-store")
            }
            switch id {
            case let .eventTask(taskID, contextID):
                try contextStore.deleteEventTask(
                    contextID: contextID,
                    taskID: taskID
                )
            case let .personalTask(taskID):
                guard try contextStore.personalTasks.fetch(id: taskID) != nil else {
                    throw ContextStoreError.missingPersonalTask(taskID)
                }
                try contextStore.personalTasks.delete(id: taskID)
            }
        }
    }

    func openOriginalEvent(contextID: String) async {
        localOperationError = nil
        guard localDataOperationState == .idle else {
            localOperationError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return
        }
        guard let contextStore else {
            localOperationError = "Local task storage is unavailable."
            return
        }

        do {
            guard let brief = try contextStore.eventContexts.fetchBrief(
                contextID: contextID
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            switch brief.link.linkStatus {
            case .missing:
                linkedEventRecoverySession = LinkedEventRecoverySession(
                    brief: brief,
                    stage: .firstMissing
                )
                return
            case .orphaned:
                linkedEventRecoverySession = LinkedEventRecoverySession(
                    brief: brief,
                    stage: brief.hasRecordedOriginalDeletion
                        && brief.context.lifecycleStatus == .cancelled
                        ? .deletedOriginal
                        : .orphaned
                )
                return
            case .active:
                break
            }
            guard calendarAuthorizationState.canReadEvents else {
                localOperationError = "Full calendar access is required to check the original event. The local Event Brief was kept."
                return
            }
            let target = try contextStore.linkedEventLookupTarget(
                contextID: contextID
            )
            await performLinkedEventLookup(
                target: target,
                explicitRecheck: false
            )
        } catch {
            localOperationError = Self.message(for: error)
            if error is CalendarEventLookupError,
               let brief = try? contextStore.eventContexts.fetchBrief(
                contextID: contextID
               ) {
                linkedEventRecoverySession = LinkedEventRecoverySession(
                    brief: brief,
                    stage: .manualRelink
                )
            }
        }
    }

    func recheckMissingLinkedEvent() async {
        localOperationError = nil
        guard localDataOperationState == .idle else {
            localOperationError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return
        }
        guard let session = linkedEventRecoverySession,
              session.brief.link.linkStatus == .missing,
              let contextStore else {
            return
        }
        guard calendarAuthorizationState.canReadEvents else {
            localOperationError = "Full calendar access is required to check again. This did not change the missing link or local Event Brief."
            return
        }
        do {
            let target = try contextStore.linkedEventLookupTarget(
                contextID: session.brief.context.id
            )
            guard target.brief.link.linkStatus == .missing else {
                switch target.brief.link.linkStatus {
                case .active:
                    linkedEventRecoverySession = nil
                    await performLinkedEventLookup(
                        target: target,
                        explicitRecheck: false
                    )
                case .orphaned:
                    linkedEventRecoverySession = LinkedEventRecoverySession(
                        brief: target.brief,
                        stage: target.brief.hasRecordedOriginalDeletion
                            && target.brief.context.lifecycleStatus == .cancelled
                            ? .deletedOriginal
                            : .orphaned
                    )
                case .missing:
                    break
                }
                return
            }
            await performLinkedEventLookup(
                target: target,
                explicitRecheck: true
            )
        } catch {
            localOperationError = Self.message(for: error)
        }
    }

    func dismissLinkedEventRecovery() {
        linkedEventRecoverySession = nil
    }

    func beginSelectingRelinkCandidate() {
        guard localDataOperationState == .idle else { return }
        guard let session = linkedEventRecoverySession else { return }
        pendingRelinkContextID = session.brief.context.id
        selectedCalendarSet = .all
        focusedDate = calendar.startOfDay(
            for: session.brief.link.effectiveDateRange(
                calendar: calendar
            ).start
        )
        linkedEventRecoverySession = nil
        select(.agenda)
    }

    func cancelRelinkSelection() {
        pendingRelinkContextID = nil
    }

    func chooseLinkedEventCandidate(_ event: DisplayEvent) {
        guard localDataOperationState == .idle else { return }
        guard let session = linkedEventRecoverySession else { return }
        linkedEventRecoverySession = LinkedEventRecoverySession(
            brief: session.brief,
            stage: .confirmRelink(event)
        )
    }

    @discardableResult
    func confirmLinkedEventRelink() async -> Bool {
        guard localDataOperationState == .idle else {
            localOperationError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let session = linkedEventRecoverySession,
              case let .confirmRelink(event) = session.stage,
              let contextStore else {
            return false
        }
        localOperationError = nil
        guard calendarAuthorizationState.canReadEvents else {
            localOperationError = "Full calendar access is required to verify the replacement event. No local or calendar data was changed."
            return false
        }
        isCheckingLinkedEvent = true
        defer { isCheckingLinkedEvent = false }
        do {
            let result = try calendarProvider.lookupEvent(
                CalendarEventLookupQuery(event: event)
            )
            let match: CalendarEventLookupMatch
            let isCancelled: Bool
            switch result {
            case let .found(found):
                match = found
                isCancelled = false
            case let .cancelled(cancelled):
                match = cancelled
                isCancelled = true
            case .candidates, .ambiguous:
                localOperationError = "The replacement event is no longer an exact strong match. Review and choose it again; nothing was relinked."
                return false
            case .notFound:
                localOperationError = "The replacement event could not be found during final verification. Nothing was relinked."
                return false
            case .inconclusive:
                localOperationError = "The replacement event could not be verified conclusively. Nothing was relinked."
                return false
            }
            _ = try contextStore.relinkLocalBrief(
                contextID: session.brief.context.id,
                to: match.event,
                expectedLink: session.brief.link,
                calendarStatusIsCancelled: isCancelled,
                at: now(),
                calendar: calendar
            )
            linkedEventRecoverySession = nil
            pendingRelinkContextID = nil
            refreshTaskCenter()
            await focusLinkedEvent(
                match.event,
                contextID: session.brief.context.id
            )
            if let refreshedEvent = events.first(where: {
                $0.id == match.event.id
            }) {
                selectedEventID = refreshedEvent.id
                activeBriefEvent = refreshedEvent
                loadSelectedEventBrief()
            }
            return true
        } catch {
            localOperationError = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    func keepLinkedEventAsOrphan() -> Bool {
        guard localDataOperationState == .idle else {
            localOperationError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let session = linkedEventRecoverySession,
              let contextStore else {
            return false
        }
        localOperationError = nil
        do {
            _ = try contextStore.keepLocalBriefAsOrphan(
                contextID: session.brief.context.id
            )
            linkedEventRecoverySession = nil
            refreshTaskCenter()
            return true
        } catch {
            localOperationError = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    func deleteRecoverableLocalBrief() -> Bool {
        guard localDataOperationState == .idle else {
            localOperationError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let session = linkedEventRecoverySession,
              let contextStore else {
            return false
        }
        localOperationError = nil
        do {
            try contextStore.deleteLocalBrief(
                contextID: session.brief.context.id
            )
            linkedEventRecoverySession = nil
            pendingRelinkContextID = nil
            refreshTaskCenter()
            return true
        } catch {
            localOperationError = Self.message(for: error)
            return false
        }
    }

    private func performLinkedEventLookup(
        target: LinkedEventLookupTarget,
        explicitRecheck: Bool
    ) async {
        guard localDataOperationState == .idle else { return }
        guard let contextStore else { return }
        isCheckingLinkedEvent = true
        defer { isCheckingLinkedEvent = false }

        do {
            switch try calendarProvider.lookupEvent(target.query) {
            case let .found(match):
                _ = try contextStore.refreshStrongLookup(
                    contextID: target.brief.context.id,
                    event: match.event,
                    at: now(),
                    calendar: calendar
                )
                linkedEventRecoverySession = nil
                refreshTaskCenter()
                await focusLinkedEvent(match.event, contextID: target.brief.context.id)
            case let .cancelled(match):
                _ = try contextStore.markCalendarEventCancelled(
                    contextID: target.brief.context.id,
                    event: match.event,
                    at: now()
                )
                linkedEventRecoverySession = nil
                refreshTaskCenter()
                await focusLinkedEvent(match.event, contextID: target.brief.context.id)
                localOperationError = "Calendar reports that this event is cancelled. The local Event Brief was kept and no calendar data was changed."
            case let .candidates(matches), let .ambiguous(matches):
                linkedEventRecoverySession = LinkedEventRecoverySession(
                    brief: target.brief,
                    stage: .candidates(matches)
                )
            case .notFound:
                if explicitRecheck {
                    linkedEventRecoverySession = LinkedEventRecoverySession(
                        brief: target.brief,
                        stage: .orphanConfirmation
                    )
                } else {
                    let missing = try contextStore.markLinkedEventMissing(
                        contextID: target.brief.context.id
                    )
                    linkedEventRecoverySession = LinkedEventRecoverySession(
                        brief: missing,
                        stage: .firstMissing
                    )
                    refreshTaskCenter()
                }
            case let .inconclusive(issue):
                switch issue {
                case .calendarUnavailable:
                    localOperationError = "The saved calendar is currently unavailable, so KaosCal did not count this as a missing event. The local Event Brief was kept."
                case .invalidStoredLink:
                    localOperationError = "The saved link could not be checked safely. Choose a calendar event to relink the local Brief manually."
                case .recurringOccurrenceUnavailable:
                    localOperationError = "The recurring series is visible, but the exact occurrence could not be proven inside the safe search bounds. KaosCal did not mark it missing. Choose the occurrence manually if it moved."
                case .strongIdentifierOccurrenceMismatch:
                    localOperationError = "A strongly identified calendar item still exists, but its recurrence or occurrence no longer matches the saved link. KaosCal did not mark it missing. Choose the exact occurrence manually."
                }
                linkedEventRecoverySession = LinkedEventRecoverySession(
                    brief: target.brief,
                    stage: .manualRelink
                )
            }
        } catch {
            localOperationError = Self.message(for: error)
        }
    }

    private func focusLinkedEvent(
        _ event: DisplayEvent,
        contextID: String
    ) async {
        selectedCalendarSet = .all
        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: calendar
        )
        let targetDay = calendar.startOfDay(for: range.start)
        let targetEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: targetDay
        ) ?? range.end
        rangeLoadTask?.cancel()
        rangeLoadTask = nil
        await refreshCalendarData(in: expandedFetchInterval(
            around: DateInterval(start: targetDay, end: targetEnd)
        ))

        var resolvedEvent = events.first(where: { $0.id == event.id })
        if resolvedEvent == nil,
           let contextStore,
           let resolution = try? contextStore.matchLinkedEvent(
            contextID: contextID,
            among: events
           ),
           case let .linked(candidate, _) = resolution {
            resolvedEvent = candidate
        }

        guard let resolvedEvent else {
            localOperationError = "The dedicated lookup found the event, but the calendar view has not received it yet. The link remains active; try opening it again after sync finishes."
            return
        }
        focusedDate = calendar.startOfDay(
            for: CalendarEventDateFormatting.effectiveDateRange(
                for: resolvedEvent,
                calendar: calendar
            ).start
        )
        selectedSection = .day
        selectEvent(resolvedEvent.id)
    }

    func beginCreatingEvent() {
        guard localDataOperationState == .idle else {
            eventEditorError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return
        }
        guard eventEditorSession == nil,
              eventEditorOperationState == .idle else {
            eventEditorError = Self.message(
                for: CalendarEventWriteError.editorAlreadyOpen
            )
            return
        }
        eventEditorError = nil
        guard calendarAuthorizationState.canReadEvents else {
            eventEditorError = Self.message(
                for: CalendarEventWriteError.fullAccessRequired
            )
            return
        }
        let writableCalendars = calendarSources.filter {
            CalendarWriteRestriction.restriction(for: $0) == nil
        }
        guard !writableCalendars.isEmpty else {
            eventEditorError = Self.message(
                for: CalendarEventWriteError.noWritableCalendar
            )
            return
        }

        let providerDefault = calendarProvider
            .defaultCalendarIdentifierForNewEvents()
        let selectedCalendar = selectedEvent?.calendarIdentifier
        let calendarIdentifier = [providerDefault, selectedCalendar]
            .compactMap { $0 }
            .first { identifier in
                writableCalendars.contains { $0.id == identifier }
            }
            ?? writableCalendars.first(where: {
                $0.accountType == .exchange
            })?.id
            ?? writableCalendars[0].id
        let start = defaultNewEventStart()
        let end = calendar.date(
            byAdding: .hour,
            value: 1,
            to: start
        ) ?? start.addingTimeInterval(3_600)
        eventEditorSession = CalendarEventEditorSession(
            target: .newEvent,
            initialDraft: CalendarEventDraft(
                title: "",
                calendarIdentifier: calendarIdentifier,
                startDate: start,
                endDate: end,
                isAllDay: false,
                timeZoneIdentifier: calendar.timeZone.identifier,
                referenceTimeZoneIdentifier: calendar.timeZone.identifier
            ),
            writableCalendars: writableCalendars,
            mutationContext: .none
        )
        eventEditorOperationState = .idle
    }

    func originalEventWriteRestriction(
        for event: DisplayEvent
    ) -> String? {
        guard calendarAuthorizationState.canReadEvents else {
            return Self.message(
                for: CalendarEventWriteError.fullAccessRequired
            )
        }
        return calendarWriteRestriction(for: event)?.message
    }

    func beginEditingSelectedEvent() {
        guard localDataOperationState == .idle else {
            eventEditorError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return
        }
        guard eventEditorSession == nil,
              eventEditorOperationState == .idle else {
            eventEditorError = Self.message(
                for: CalendarEventWriteError.editorAlreadyOpen
            )
            return
        }
        eventEditorError = nil
        guard calendarAuthorizationState.canReadEvents else {
            eventEditorError = Self.message(
                for: CalendarEventWriteError.fullAccessRequired
            )
            return
        }
        guard let event = selectedEvent else {
            eventEditorError = Self.message(
                for: CalendarEventWriteError.eventUnavailable
            )
            return
        }

        do {
            try validateOriginalWritePolicy(event)
            flushPendingEventNotes()
            if case .failed = notesSaveState {
                throw CalendarEventWriteError.localDraftSaveRequired
            }
            let mutationContext = try contextStore?.mutationContext(
                for: event
            ) ?? .none
            if case .confirmationRequired = mutationContext {
                throw CalendarEventWriteError.localIdentityConfirmationRequired
            }
            let mutationImpact: EventMutationImpact?
            if case let .linked(contextID) = mutationContext,
               let contextStore {
                mutationImpact = try contextStore.mutationImpact(
                    contextID: contextID,
                    recentHistoryLimit: 5
                )
            } else {
                mutationImpact = nil
            }
            let writableCalendars = calendarSources.filter {
                CalendarWriteRestriction.restriction(for: $0) == nil
            }
            guard writableCalendars.contains(where: {
                $0.id == event.calendarIdentifier
            }) else {
                throw CalendarEventWriteError.readOnlyCalendar
            }
            eventEditorSession = CalendarEventEditorSession(
                target: .existing(event),
                initialDraft: CalendarEventDraft(
                    event: event,
                    calendar: calendar
                ),
                writableCalendars: writableCalendars,
                mutationContext: mutationContext,
                mutationImpact: mutationImpact
            )
            eventEditorOperationState = .idle
        } catch {
            eventEditorError = Self.message(for: error)
        }
    }

    func cancelEventEditor() {
        guard eventEditorOperationState == .idle else { return }
        pendingEventMutation = nil
        pendingLinkedOriginalDeletion = nil
        eventEditorSession = nil
        eventEditorError = nil
    }

    func cancelPendingEventMutation() {
        guard eventEditorOperationState == .idle else { return }
        pendingEventMutation = nil
        eventEditorError = nil
    }

    func cancelPendingLinkedOriginalDeletion() {
        guard eventEditorOperationState == .idle else { return }
        pendingLinkedOriginalDeletion = nil
        eventEditorError = nil
    }

    func clearEventEditorError() {
        eventEditorError = nil
    }

    @discardableResult
    func saveEventEditor(_ draft: CalendarEventDraft) async -> Bool {
        await saveEventEditor(draft, scope: nil)
    }

    @discardableResult
    func saveEventEditor(
        _ draft: CalendarEventDraft,
        scope requestedScope: CalendarEventMutationScope?
    ) async -> Bool {
        guard localDataOperationState == .idle else {
            eventEditorError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let session = eventEditorSession,
              eventEditorOperationState == .idle else { return false }
        guard pendingLinkedOriginalDeletion == nil else {
            eventEditorError = Self.message(
                for: EventMutationSafetyError.confirmationUnavailable
            )
            return false
        }
        eventEditorError = nil

        do {
            let enforceRecurrenceEndBoundary: Bool = switch session.target {
            case .newEvent:
                true
            case .existing:
                draft.recurrence != session.initialDraft.recurrence
            }
            let normalized = try draft.validated(
                calendar: calendar,
                enforceRecurrenceEndBoundary:
                    enforceRecurrenceEndBoundary,
                rebaseRecurrenceEndDate:
                    enforceRecurrenceEndBoundary
            )
            switch session.target {
            case .newEvent:
                eventEditorOperationState = .saving
                defer {
                    if eventEditorOperationState == .saving {
                        eventEditorOperationState = .idle
                    }
                }
                let created = try calendarProvider.createEvent(normalized)
                invalidateEventUndoCandidate()
                pendingEventMutation = nil
                pendingLinkedOriginalDeletion = nil
                eventEditorSession = nil
                eventEditorOperationState = .idle
                await focusWrittenEvent(created)
                return true
            case let .existing(original):
                try validateOriginalWritePolicy(original)
                let scope = try mutationScope(
                    for: original,
                    requested: requestedScope
                )
                let baseline = try session.initialDraft.validated(
                    calendar: calendar,
                    enforceRecurrenceEndBoundary: false,
                    rebaseRecurrenceEndDate: false
                )
                let changedFields = normalized.changedFields(
                    comparedTo: baseline
                )
                if changedFields.contains(.recurrence),
                   original.isRecurring,
                   scope != .futureEvents {
                    throw CalendarEventWriteError
                        .recurrenceChangeRequiresFutureScope
                }
                if scope == .futureEvents,
                   case .linked = session.mutationContext {
                    throw EventMutationSafetyError
                        .linkedFutureSeriesDeferred
                }

                let preview = CalendarEventMutationPreview(
                    original: original,
                    draft: normalized,
                    scope: scope,
                    mutationContext: session.mutationContext,
                    impact: session.mutationImpact,
                    changedFields: changedFields
                )
                if requiresImpactConfirmation(preview) {
                    pendingLinkedOriginalDeletion = nil
                    pendingEventMutation = preview
                    return false
                }
                return await performEventMutation(preview)
            }
        } catch {
            eventEditorError = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    func confirmPendingEventMutation() async -> Bool {
        guard localDataOperationState == .idle else {
            eventEditorError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard pendingLinkedOriginalDeletion == nil else {
            eventEditorError = Self.message(
                for: EventMutationSafetyError.confirmationUnavailable
            )
            return false
        }
        guard let preview = pendingEventMutation,
              let session = eventEditorSession,
              case let .existing(original) = session.target,
              original.id == preview.original.id else {
            eventEditorError = Self.message(
                for: EventMutationSafetyError.confirmationUnavailable
            )
            return false
        }
        return await performEventMutation(preview)
    }

    @discardableResult
    func prepareLinkedOriginalDeletion(
        scope requestedScope: CalendarEventMutationScope?
    ) -> Bool {
        guard localDataOperationState == .idle else {
            eventEditorError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let session = eventEditorSession,
              case let .existing(original) = session.target,
              eventEditorOperationState == .idle else {
            return false
        }
        eventEditorError = nil

        do {
            try validateOriginalWritePolicy(original)
            flushPendingEventNotes()
            if case .failed = notesSaveState {
                throw CalendarEventWriteError.localDraftSaveRequired
            }
            let scope = try mutationScope(
                for: original,
                requested: requestedScope
            )
            if scope == .futureEvents {
                throw EventMutationSafetyError.linkedFutureSeriesDeferred
            }
            guard case let .linked(contextID) = session.mutationContext,
                  let contextStore else {
                throw EventMutationSafetyError.confirmationUnavailable
            }
            guard try contextStore.mutationContext(for: original)
                    == .linked(contextID: contextID) else {
                throw EventMutationSafetyError.confirmationUnavailable
            }
            let preparation = try contextStore.prepareLinkedOriginalDeletion(
                contextID: contextID,
                recentHistoryLimit: 5
            )
            guard preparation.brief.link.isRecurring
                    == original.isRecurring else {
                throw EventMutationSafetyError.confirmationUnavailable
            }
            pendingEventMutation = nil
            pendingLinkedOriginalDeletion = LinkedOriginalDeletionPreview(
                original: original,
                scope: scope,
                contextID: contextID,
                brief: preparation.brief,
                expectedLink: preparation.brief.link,
                expectedSnapshot: preparation.changeSnapshot,
                impact: preparation.impact
            )
            return true
        } catch {
            pendingLinkedOriginalDeletion = nil
            eventEditorError = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    func confirmPendingLinkedOriginalDeletion() async -> Bool {
        guard localDataOperationState == .idle else {
            eventEditorError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let preview = pendingLinkedOriginalDeletion,
              let session = eventEditorSession,
              case let .existing(original) = session.target,
              original.id == preview.original.id,
              eventEditorOperationState == .idle,
              let contextStore else {
            eventEditorError = Self.message(
                for: EventMutationSafetyError.confirmationUnavailable
            )
            return false
        }
        eventEditorError = nil

        do {
            try validateOriginalWritePolicy(original)
            let scope = try mutationScope(
                for: original,
                requested: preview.scope
            )
            guard scope == preview.scope,
                  scope != .futureEvents,
                  session.mutationContext
                    == .linked(contextID: preview.contextID),
                  try contextStore.mutationContext(for: original)
                    == .linked(contextID: preview.contextID) else {
                throw EventMutationSafetyError.confirmationUnavailable
            }
            _ = try contextStore.validateLinkedOriginalDeletion(
                contextID: preview.contextID,
                expectedLink: preview.expectedLink,
                expectedSnapshot: preview.expectedSnapshot
            )
        } catch {
            pendingLinkedOriginalDeletion = nil
            eventEditorError = Self.message(for: error)
            return false
        }

        eventEditorOperationState = .deleting
        defer {
            if eventEditorOperationState == .deleting {
                eventEditorOperationState = .idle
            }
        }

        let receipt: CalendarEventMutationReceipt
        do {
            receipt = try calendarProvider.deleteEvent(
                preview.original,
                scope: preview.scope
            )
        } catch let partial as CalendarEventMutationPartialSuccess {
            invalidateEventUndoCandidate()
            await finishIrreversibleLinkedDeletionFailure(
                "The original calendar event may already be deleted, but KaosCal could not verify the deletion receipt. Do not retry Delete. Your local Event Brief, notes, and tasks were kept. \(partial.localizedDescription)"
            )
            return false
        } catch {
            eventEditorError = Self.message(for: error)
            return false
        }

        guard receipt.didWrite else {
            eventEditorError = Self.message(
                for: EventMutationSafetyError.deletionNotCommitted
            )
            return false
        }
        invalidateEventUndoCandidate()

        guard receipt.scope == preview.scope,
              receipt.changedFields == [.deletion],
              Self.eventsShareStrongIdentity(
                receipt.event,
                preview.original
              ) else {
            await finishIrreversibleLinkedDeletionFailure(
                "The original calendar event reported a deletion, but the provider returned an invalid receipt. Do not retry Delete. Your local Event Brief, notes, and tasks were kept for recovery in Task Center."
            )
            return false
        }

        do {
            _ = try contextStore.finalizeLinkedOriginalDeletion(
                contextID: preview.contextID,
                expectedLink: preview.expectedLink,
                expectedSnapshot: preview.expectedSnapshot,
                scope: Self.changeScope(
                    for: preview.original,
                    mutationScope: preview.scope
                )
            )
        } catch {
            await finishIrreversibleLinkedDeletionFailure(
                "The original calendar event was deleted, but its local Event Brief could not be finalized. Do not retry Delete. Your local notes and tasks were kept for recovery in Task Center. \(Self.message(for: error))"
            )
            return false
        }

        pendingLinkedOriginalDeletion = nil
        pendingEventMutation = nil
        eventEditorSession = nil
        eventEditorOperationState = .idle
        selectEvent(nil)
        selectedSection = .tasks
        await refreshCalendarData()
        return true
    }

    @discardableResult
    func deleteEventEditorTarget() async -> Bool {
        await deleteEventEditorTarget(scope: nil)
    }

    @discardableResult
    func deleteEventEditorTarget(
        scope requestedScope: CalendarEventMutationScope?
    ) async -> Bool {
        guard localDataOperationState == .idle else {
            eventEditorError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard let session = eventEditorSession,
              case let .existing(original) = session.target else {
            return false
        }
        guard eventEditorOperationState == .idle else { return false }
        if case .linked = session.mutationContext {
            _ = prepareLinkedOriginalDeletion(scope: requestedScope)
            return false
        }
        eventEditorError = nil
        eventEditorOperationState = .deleting
        defer {
            if eventEditorOperationState == .deleting {
                eventEditorOperationState = .idle
            }
        }

        do {
            try validateOriginalWritePolicy(original)
            let scope = try mutationScope(
                for: original,
                requested: requestedScope
            )
            switch session.mutationContext {
            case .confirmationRequired:
                throw CalendarEventWriteError.localIdentityConfirmationRequired
            case .none, .linked:
                break
            }
            let receipt = try calendarProvider.deleteEvent(
                original,
                scope: scope
            )
            if receipt.didWrite {
                invalidateEventUndoCandidate()
            }
            pendingEventMutation = nil
            pendingLinkedOriginalDeletion = nil
            eventEditorSession = nil
            eventEditorOperationState = .idle
            selectEvent(nil)
            await refreshCalendarData()
            return true
        } catch {
            eventEditorError = Self.message(for: error)
            return false
        }
    }

    func canUndoLastEventMutation(for event: DisplayEvent) -> Bool {
        guard lastEventMutationUndoAvailable,
              let candidate = lastEventMutationUndoCandidate else {
            return false
        }
        return Self.eventsShareStrongIdentity(
            event,
            candidate.afterEvent
        )
    }

    func clearEventUndoError() {
        eventUndoError = nil
    }

    @discardableResult
    func undoLastEventMutation() async -> Bool {
        guard localDataOperationState == .idle else {
            eventUndoError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        guard !isUndoingEventMutation,
              let candidate = lastEventMutationUndoCandidate,
              let contextStore else {
            eventUndoError = Self.message(
                for: EventMutationSafetyError.undoUnavailable
            )
            return false
        }

        eventUndoError = nil
        isUndoingEventMutation = true
        defer { isUndoingEventMutation = false }

        let receipt: CalendarEventMutationReceipt
        do {
            receipt = try calendarProvider.updateEvent(
                candidate.afterEvent,
                with: candidate.beforeDraft,
                scope: .thisEvent
            )
        } catch let partial as CalendarEventMutationPartialSuccess {
            invalidateEventUndoCandidate()
            await refreshCalendarData()
            eventUndoError = partial.localizedDescription
            return false
        } catch {
            eventUndoError = Self.message(for: error)
            return false
        }

        do {
            _ = try contextStore.rebindAfterUndo(
                contextID: candidate.contextID,
                originalChangeID: candidate.changeID,
                from: candidate.afterEvent,
                to: receipt.event,
                scope: .single
            )
        } catch {
            invalidateEventUndoCandidate()
            await refreshCalendarData()
            eventUndoError = "The calendar change was undone, but the local Event Brief could not be rebound. Your local notes and tasks were kept. \(Self.message(for: error))"
            return false
        }

        invalidateEventUndoCandidate()
        await focusWrittenEvent(receipt.event)
        return true
    }

    private func mutationScope(
        for original: DisplayEvent,
        requested: CalendarEventMutationScope?
    ) throws -> CalendarEventMutationScope {
        if original.isRecurring {
            guard let requested else {
                throw CalendarEventWriteError.recurringScopeRequired
            }
            if original.isDetached, requested == .futureEvents {
                throw CalendarEventWriteError.detachedFutureScopeUnsupported
            }
            if requested == .futureEvents,
               case .unsupported = original.recurrence {
                throw CalendarEventWriteError.unsupportedRecurrence
            }
            return requested
        }
        if requested == .futureEvents {
            throw CalendarEventWriteError.futureScopeRequiresRecurringEvent
        }
        return .thisEvent
    }

    private func requiresImpactConfirmation(
        _ preview: CalendarEventMutationPreview
    ) -> Bool {
        preview.original.isRecurring
            || preview.changedFields.contains(.calendar)
            || preview.changedFields.contains(.time)
            || preview.changedFields.contains(.recurrence)
    }

    @discardableResult
    private func performEventMutation(
        _ preview: CalendarEventMutationPreview
    ) async -> Bool {
        guard eventEditorOperationState == .idle else { return false }
        eventEditorOperationState = .saving
        eventEditorError = nil
        defer {
            if eventEditorOperationState == .saving {
                eventEditorOperationState = .idle
            }
        }

        let receipt: CalendarEventMutationReceipt
        do {
            receipt = try calendarProvider.updateEvent(
                preview.original,
                with: preview.draft,
                scope: preview.scope
            )
        } catch let partial as CalendarEventMutationPartialSuccess {
            pendingEventMutation = nil
            pendingLinkedOriginalDeletion = nil
            invalidateEventUndoCandidate()
            eventEditorSession = nil
            eventEditorOperationState = .idle
            await refreshCalendarData()
            eventEditorError = partial.localizedDescription
            return false
        } catch {
            eventEditorError = Self.message(for: error)
            return false
        }

        if receipt.didWrite {
            invalidateEventUndoCandidate()
        }

        if receipt.didWrite,
           case let .linked(contextID) = preview.mutationContext,
           let contextStore {
            let undoState: EventChangeUndoState =
                !preview.original.isRecurring
                    && !preview.draft.recurrence.isRecurring
                    && preview.scope == .thisEvent
                    && !preview.changedFields.contains(.recurrence)
                    && !preview.changedFields
                        .isDisjoint(with: [.calendar, .time])
                ? .available
                : .unavailable
            do {
                let log = try contextStore.rebindAndRecordMutation(
                    contextID: contextID,
                    from: preview.original,
                    to: receipt.event,
                    changeType: Self.changeType(
                        for: preview.changedFields
                    ),
                    scope: Self.changeScope(
                        for: preview.original,
                        mutationScope: preview.scope
                    ),
                    undoState: undoState
                )
                if undoState == .available {
                    let beforeDraft = try CalendarEventDraft(
                        event: preview.original,
                        calendar: calendar
                    ).validated(
                        calendar: calendar,
                        enforceRecurrenceEndBoundary: false,
                        rebaseRecurrenceEndDate: false
                    )
                    lastEventMutationUndoCandidate =
                        CalendarEventUndoCandidate(
                            contextID: contextID,
                            changeID: log.id,
                            beforeDraft: beforeDraft,
                            afterEvent: receipt.event
                        )
                    lastEventMutationUndoAvailable = true
                }
            } catch {
                pendingEventMutation = nil
                pendingLinkedOriginalDeletion = nil
                invalidateEventUndoCandidate()
                await refreshCalendarData()
                eventEditorError = "The calendar event was saved, but its local Event Brief could not be refreshed. Your local data was kept. \(Self.message(for: error))"
                return false
            }
        }

        pendingEventMutation = nil
        pendingLinkedOriginalDeletion = nil
        eventEditorSession = nil
        eventEditorOperationState = .idle
        await focusWrittenEvent(receipt.event)
        return true
    }

    private func finishIrreversibleLinkedDeletionFailure(
        _ message: String
    ) async {
        pendingLinkedOriginalDeletion = nil
        pendingEventMutation = nil
        eventEditorSession = nil
        eventEditorOperationState = .idle
        selectEvent(nil)
        selectedSection = .tasks
        await refreshCalendarData()
        eventEditorError = message
    }

    private func invalidateEventUndoCandidate() {
        lastEventMutationUndoCandidate = nil
        lastEventMutationUndoAvailable = false
    }

    private static func changeType(
        for fields: Set<CalendarEventChangedField>
    ) -> EventChangeType {
        if fields.contains(.calendar) { return .moved }
        if fields.contains(.recurrence) { return .recurrenceChanged }
        return .detailsUpdated
    }

    private static func changeScope(
        for event: DisplayEvent,
        mutationScope: CalendarEventMutationScope
    ) -> EventChangeScope {
        guard event.isRecurring else { return .single }
        switch mutationScope {
        case .thisEvent: return .thisEvent
        case .futureEvents: return .futureEvents
        }
    }

    func goToToday() {
        focusedDate = calendar.startOfDay(for: now())
        visiblePeriodDidChange()
    }

    func selectMiniMonthDate(_ date: Date) {
        focusedDate = calendar.startOfDay(for: date)
        if selectedSection == .tasks || selectedSection == nil {
            selectedSection = .day
        }
        visiblePeriodDidChange()
    }

    func moveFocusedPeriod(direction: Int) {
        let dayCount: Int
        switch selectedSection ?? .week {
        case .day, .tasks:
            dayCount = 1
        case .week, .agenda:
            dayCount = 7
        }

        focusedDate = calendar.date(
            byAdding: .day,
            value: dayCount * direction,
            to: focusedDate
        ) ?? focusedDate
        visiblePeriodDidChange()
    }

    func loadCalendarStatus() async {
        guard localDataOperationState == .idle else { return }
        calendarAuthorizationState = calendarProvider.authorizationState
        switch calendarAuthorizationState {
        case .notDetermined:
            clearCalendarData()
            calendarContentState = .disconnected
        case .fullAccess:
            await refreshCalendarData()
        case .denied, .restricted, .writeOnly:
            clearCalendarData()
            calendarContentState = .permissionDenied
        case .unknown:
            clearCalendarData()
            calendarContentState = .failed("Unknown calendar permission state")
        }
    }

    func requestCalendarAccess() async {
        guard localDataOperationState == .idle else { return }
        calendarContentState = .loading
        do {
            let granted = try await calendarProvider.requestFullAccess()
            calendarAuthorizationState = calendarProvider.authorizationState
            guard granted, calendarAuthorizationState.canReadEvents else {
                clearCalendarData()
                calendarContentState = .permissionDenied
                return
            }
            await refreshCalendarData()
        } catch {
            calendarAuthorizationState = calendarProvider.authorizationState
            if !calendarAuthorizationState.canReadEvents {
                clearCalendarData()
            }
            switch calendarAuthorizationState {
            case .denied, .restricted, .writeOnly:
                calendarContentState = .permissionDenied
            default:
                calendarContentState = .failed(Self.message(for: error))
            }
        }
    }

    func refreshCalendarData(in requestedInterval: DateInterval? = nil) async {
        guard localDataOperationState == .idle else { return }
        if pendingEventMutation != nil
            || pendingLinkedOriginalDeletion != nil {
            pendingEventMutation = nil
            pendingLinkedOriginalDeletion = nil
            eventEditorError = "Calendar data was refreshed. Review the current event and prepare the change again."
        }
        calendarAuthorizationState = calendarProvider.authorizationState
        guard calendarAuthorizationState.canReadEvents else {
            clearCalendarData()
            switch calendarAuthorizationState {
            case .notDetermined:
                calendarContentState = .disconnected
            case .denied, .restricted, .writeOnly:
                calendarContentState = .permissionDenied
            case .unknown:
                calendarContentState = .failed("Unknown calendar permission state")
            case .fullAccess:
                break
            }
            return
        }

        calendarContentState = .loading
        do {
            let interval = requestedInterval
                ?? loadedEventInterval
                ?? initialFetchInterval()
            let sources = try calendarProvider.listCalendars()
            let fetchedEvents = try calendarProvider.fetchEvents(in: interval)
            observeLocalContexts(fetchedEvents)
            calendarSources = sources
            events = fetchedEvents
            duplicateCandidateIndex = CalendarDuplicateCandidateDetector
                .candidateIndex(
                    among: fetchedEvents,
                    calendar: calendar
                )
            loadCalendarRolePreferences()
            loadedEventInterval = interval

            if let selectedEventID, !fetchedEvents.contains(where: { $0.id == selectedEventID }) {
                selectEvent(nil)
            } else if let selectedEventID {
                selectEvent(selectedEventID)
                refreshSelectedBriefPreservingDraft()
            }
            clearSelectionOutsideVisiblePeriod()
            calendarContentState = fetchedEvents.isEmpty ? .empty : .loaded
            refreshTaskCenter()
        } catch {
            calendarContentState = .failed(Self.message(for: error))
        }
    }

    private func scheduleStoreRefresh() {
        guard localDataOperationState != .quarantined else {
            calendarRefreshDeferredByLocalDataOperation = false
            return
        }
        guard localDataOperationState == .idle else {
            calendarRefreshDeferredByLocalDataOperation = true
            return
        }
        storeRefreshTask?.cancel()
        storeRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard let self else { return }
            await self.refreshCalendarData(in: self.loadedEventInterval)
        }
    }

    private func observeLocalContexts(_ events: [DisplayEvent]) {
        guard let contextStore else { return }
        do {
            _ = try contextStore.observe(events: events)
            localContextStoreState = .ready
        } catch {
            localContextStoreState = .failed(Self.message(for: error))
        }
    }

    private func loadCalendarRolePreferences() {
        guard let contextStore else {
            calendarRoleOverrides = [:]
            return
        }
        do {
            calendarRoleOverrides = Dictionary(
                uniqueKeysWithValues: try contextStore.calendarRoles
                    .fetchAll()
                    .map { ($0.calendarIdentifier, $0.role) }
            )
        } catch {
            calendarRoleOverrides = [:]
            localOperationError = Self.message(for: error)
        }
    }

    func refreshTaskCenter() {
        guard localDataOperationState == .idle else { return }
        guard let contextStore else {
            taskCenterState = .unavailable
            recoveryBriefs = []
            return
        }
        taskCenterState = .loading
        do {
            let referenceDate = now()
            let changedContextIDs = try contextStore.refreshTemporalLifecycle(
                at: referenceDate,
                calendar: calendar
            )
            let list: TaskCenterList = switch selectedTaskFilter {
            case .today: .today
            case .upcoming: .upcoming
            case .afterReview: .afterReview
            case .completed: .completed
            }
            let items = try contextStore.taskCenter.fetch(
                list: list,
                now: referenceDate,
                calendar: calendar
            )
            taskCenterState = .loaded(items)
            recoveryBriefs = try contextStore.fetchRecoveryBriefs()
            reconcileLinkedEventRecoverySession(with: recoveryBriefs)
            if case let .loaded(snapshot) = eventBriefState,
               changedContextIDs.contains(snapshot.context.id) {
                refreshSelectedBriefPreservingDraft()
            }
        } catch {
            taskCenterState = .failed(Self.message(for: error))
            recoveryBriefs = []
        }
    }

    private func reconcileLinkedEventRecoverySession(
        with briefs: [EventBriefSnapshot]
    ) {
        guard let session = linkedEventRecoverySession else { return }
        let contextID = session.brief.context.id
        guard let refreshed = briefs.first(where: {
            $0.context.id == contextID
        }) else {
            linkedEventRecoverySession = nil
            if pendingRelinkContextID == contextID {
                pendingRelinkContextID = nil
            }
            return
        }

        if refreshed.link == session.brief.link {
            linkedEventRecoverySession = LinkedEventRecoverySession(
                brief: refreshed,
                stage: session.stage
            )
            return
        }

        switch refreshed.link.linkStatus {
        case .active:
            linkedEventRecoverySession = nil
        case .missing:
            linkedEventRecoverySession = LinkedEventRecoverySession(
                brief: refreshed,
                stage: .firstMissing
            )
        case .orphaned:
            linkedEventRecoverySession = LinkedEventRecoverySession(
                brief: refreshed,
                stage: refreshed.hasRecordedOriginalDeletion
                    && refreshed.context.lifecycleStatus == .cancelled
                    ? .deletedOriginal
                    : .orphaned
            )
        }
    }

    private func loadSelectedEventBrief() {
        guard let event = activeBriefEvent else {
            eventBriefState = .noSelection
            selectedEventNotes = ""
            persistedEventNotes = ""
            notesSaveState = .idle
            return
        }
        guard let contextStore else {
            eventBriefState = .unavailable
            selectedEventNotes = ""
            persistedEventNotes = ""
            notesSaveState = .idle
            return
        }

        do {
            _ = try contextStore.refreshTemporalLifecycle(
                at: now(),
                calendar: calendar
            )
            let result = try contextStore.loadBrief(for: event)
            applyBriefLoadResult(result, eventID: event.id)
        } catch {
            eventBriefState = .failed(Self.message(for: error))
        }
    }

    private func refreshSelectedBriefPreservingDraft() {
        let draft = selectedEventNotes
        let saveState = notesSaveState
        let shouldPreserveDraft = draft != persistedEventNotes
        loadSelectedEventBrief()
        guard shouldPreserveDraft else { return }
        selectedEventNotes = draft
        notesSaveState = saveState
    }

    private func applyBriefLoadResult(
        _ result: EventBriefLoadResult,
        eventID: String
    ) {
        switch result {
        case .empty:
            eventBriefState = .empty
            persistedEventNotes = ""
        case let .loaded(snapshot, _):
            eventBriefState = .loaded(snapshot)
            persistedEventNotes = snapshot.context.notes
        case let .confirmationRequired(contextIDs, _):
            eventBriefState = .confirmationRequired(contextIDs)
            persistedEventNotes = ""
        }

        if let failedDraft = failedNotesDrafts[eventID] {
            selectedEventNotes = failedDraft.text
            notesSaveState = .failed(failedDraft.message)
        } else {
            selectedEventNotes = persistedEventNotes
            notesSaveState = .idle
        }
    }

    private func saveSelectedEventNotesNow() {
        guard localDataOperationState == .idle else { return }
        guard let event = activeBriefEvent,
              let contextStore else {
            return
        }
        let draft = selectedEventNotes
        guard draft != persistedEventNotes else {
            notesSaveState = .idle
            return
        }

        notesSaveState = .saving
        do {
            _ = try contextStore.saveNotes(for: event, notes: draft)
            _ = try contextStore.refreshTemporalLifecycle(
                at: now(),
                calendar: calendar
            )
            failedNotesDrafts.removeValue(forKey: event.id)
            let result = try contextStore.loadBrief(for: event)
            applyBriefLoadResult(result, eventID: event.id)
            notesSaveState = .saved
        } catch {
            let message = Self.message(for: error)
            selectedEventNotes = draft
            failedNotesDrafts[event.id] = FailedNotesDraft(
                text: draft,
                message: message
            )
            notesSaveState = .failed(message)
        }
    }

    @discardableResult
    private func performSelectedEventTaskMutation(
        taskID: String,
        operation: (
            _ contextStore: ContextStore,
            _ contextID: String,
            _ task: EventTask
        ) throws -> Void
    ) -> Bool {
        performLocalMutation {
            guard let contextStore else {
                throw ContextStoreError.missingContext("selected-event")
            }
            guard case let .loaded(snapshot) = eventBriefState else {
                throw ContextStoreError.missingEventTask(taskID)
            }
            guard let task = snapshot.tasks.first(where: { $0.id == taskID }) else {
                throw ContextStoreError.missingEventTask(taskID)
            }
            try operation(contextStore, snapshot.context.id, task)
        }
    }

    @discardableResult
    private func performLocalMutation(
        _ operation: () throws -> Void
    ) -> Bool {
        localOperationError = nil
        guard localDataOperationState == .idle else {
            localOperationError = Self.message(
                for: localDataMaintenanceBlockError
            )
            return false
        }
        flushPendingEventNotes()
        do {
            try operation()
            loadSelectedEventBrief()
            refreshTaskCenter()
            return true
        } catch {
            localOperationError = Self.message(for: error)
            return false
        }
    }

    private func beginLocalDataOperation(
        _ operation: LocalDataOperationState,
        replacesLocalData: Bool
    ) throws -> LocalDataBackupService {
        guard localDataOperationState == .idle else {
            throw localDataMaintenanceBlockError
        }
        guard case .ready = localContextStoreState,
              let contextStore,
              contextStore.localDataBackups.databaseURL != nil else {
            throw LocalDataMaintenanceError.unavailable
        }

        localDataOperationMessage = nil
        flushPendingEventNotes()
        guard failedNotesDrafts.isEmpty else {
            throw LocalDataMaintenanceError.unsavedNotes
        }
        if case .failed = notesSaveState {
            throw LocalDataMaintenanceError.unsavedNotes
        }

        guard eventEditorOperationState == .idle,
              !isUndoingEventMutation,
              !isCheckingLinkedEvent else {
            throw LocalDataMaintenanceError.interactionInProgress
        }

        if replacesLocalData {
            guard eventEditorSession == nil,
                  pendingEventMutation == nil,
                  pendingLinkedOriginalDeletion == nil,
                  linkedEventRecoverySession == nil,
                  pendingRelinkContextID == nil else {
                throw LocalDataMaintenanceError.interactionInProgress
            }
        }

        localDataOperationState = operation
        notesSaveTask?.cancel()
        notesSaveTask = nil
        rangeLoadTask?.cancel()
        rangeLoadTask = nil
        storeRefreshTask?.cancel()
        storeRefreshTask = nil
        return contextStore.localDataBackups
    }

    private static func rollbackFailed(_ error: Error) -> Bool {
        guard let backupError = error as? LocalDataBackupError else {
            return false
        }
        switch backupError {
        case .importFailed(_, false), .resetFailed(_, false):
            return true
        default:
            return false
        }
    }

    private func quarantineLocalData(
        after operation: String,
        automaticBackupDirectory: URL,
        error: Error
    ) {
        notesSaveTask?.cancel()
        notesSaveTask = nil
        rangeLoadTask?.cancel()
        rangeLoadTask = nil
        storeRefreshTask?.cancel()
        storeRefreshTask = nil
        calendarRefreshDeferredByLocalDataOperation = false
        invalidateEventUndoCandidate()

        let operationName = operation.lowercased()
        let message = "\(operation) failed, and KaosCal could not restore the previous local database. Local data changes, calendar changes, and refresh are locked for this session. Quit KaosCal before recovery. The automatic pre-\(operationName) recovery ZIP is in \(automaticBackupDirectory.path(percentEncoded: false)). \(Self.message(for: error))"
        localDataQuarantineMessage = message
        localDataOperationMessage = message
        localOperationError = message
        eventEditorError = message
        eventUndoError = message
        localContextStoreState = .failed(message)
        localDataOperationState = .quarantined
    }

    private func automaticBackupDirectory(
        for service: LocalDataBackupService
    ) -> URL? {
        service.databaseURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private func endLocalDataOperation(
        reloadLocalProjections: Bool
    ) {
        guard localDataOperationState != .quarantined else { return }
        localDataOperationState = .idle
        if reloadLocalProjections {
            reloadLocalDataProjections()
        }
        scheduleVisiblePeriodLoadIfNeeded()

        guard calendarRefreshDeferredByLocalDataOperation else { return }
        calendarRefreshDeferredByLocalDataOperation = false
        let interval = loadedEventInterval
        Task { @MainActor [weak self] in
            await self?.refreshCalendarData(in: interval)
        }
    }

    private func reloadLocalDataProjections() {
        notesSaveTask?.cancel()
        notesSaveTask = nil
        failedNotesDrafts.removeAll()
        selectedEventNotes = ""
        persistedEventNotes = ""
        notesSaveState = .idle

        eventEditorSession = nil
        pendingEventMutation = nil
        pendingLinkedOriginalDeletion = nil
        eventEditorOperationState = .idle
        eventEditorError = nil
        invalidateEventUndoCandidate()
        eventUndoError = nil
        isUndoingEventMutation = false

        linkedEventRecoverySession = nil
        pendingRelinkContextID = nil
        isCheckingLinkedEvent = false
        recoveryBriefs = []
        localOperationError = nil
        localDataQuarantineMessage = nil
        selectedCalendarSet = .all
        localContextStoreState = .ready

        loadCalendarRolePreferences()
        observeLocalContexts(events)
        activeBriefEvent = selectedEvent
        if activeBriefEvent == nil {
            eventBriefState = .noSelection
        } else {
            loadSelectedEventBrief()
        }
        refreshTaskCenter()
        clearSelectionOutsideVisiblePeriod()
    }

    private static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String
            ?? info?["CFBundleVersion"] as? String
            ?? "unknown"
    }

    private static func duePolicy(for task: EventTask) -> EventTaskDue {
        switch task.dueKind {
        case .none:
            return .none
        case .relative:
            guard let anchor = task.relativeAnchor,
                  let offsetMinutes = task.offsetMinutes else {
                return .none
            }
            return .relative(
                anchor: anchor,
                offsetMinutes: offsetMinutes
            )
        case .fixed:
            guard let fixedDueAt = task.fixedDueAt else {
                return .none
            }
            return .fixed(fixedDueAt)
        }
    }

    private func visiblePeriodDidChange() {
        clearSelectionOutsideVisiblePeriod()
        scheduleVisiblePeriodLoadIfNeeded()
    }

    private func clearSelectionOutsideVisiblePeriod() {
        guard let selectedEventID else { return }
        if !visibleEvents.contains(where: { $0.id == selectedEventID }) {
            selectEvent(nil)
        }
    }

    private func scheduleVisiblePeriodLoadIfNeeded() {
        rangeLoadTask?.cancel()
        rangeLoadTask = nil
        guard localDataOperationState == .idle else { return }
        guard calendarAuthorizationState.canReadEvents else { return }
        let visible = visibleInterval
        if let loadedEventInterval,
           loadedEventInterval.start <= visible.start,
           loadedEventInterval.end >= visible.end {
            return
        }

        let interval = expandedFetchInterval(around: visible)
        rangeLoadTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await self?.refreshCalendarData(in: interval)
        }
    }

    private func defaultNewEventStart() -> Date {
        let focusedDay = calendar.startOfDay(for: focusedDate)
        guard calendar.isDate(focusedDay, inSameDayAs: now()) else {
            return calendar.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: focusedDay
            ) ?? focusedDay
        }
        let current = now().timeIntervalSinceReferenceDate
        let halfHour: TimeInterval = 30 * 60
        return Date(
            timeIntervalSinceReferenceDate:
                (floor(current / halfHour) + 1) * halfHour
        )
    }

    private func validateOriginalWritePolicy(
        _ event: DisplayEvent
    ) throws {
        guard calendarAuthorizationState.canReadEvents else {
            throw CalendarEventWriteError.fullAccessRequired
        }
        if let restriction = calendarWriteRestriction(for: event) {
            throw restriction
        }
    }

    private func focusWrittenEvent(_ event: DisplayEvent) async {
        let range = CalendarEventDateFormatting.effectiveDateRange(
            for: event,
            calendar: calendar
        )
        let startDay = calendar.startOfDay(for: range.start)
        let endDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: startDay
        ) ?? range.end
        rangeLoadTask?.cancel()
        rangeLoadTask = nil
        await refreshCalendarData(
            in: expandedFetchInterval(
                around: DateInterval(start: startDay, end: endDay)
            )
        )
        focusedDate = startDay
        selectedSection = .day
        let exactWrittenEvent = events.first { $0.id == event.id }
        let writtenEvent = exactWrittenEvent ?? events.first { candidate in
            Self.isPostWriteFallback(candidate, matching: event)
        }
        selectEvent(writtenEvent?.id)
    }

    private func clearCalendarData() {
        rangeLoadTask?.cancel()
        pendingEventMutation = nil
        pendingLinkedOriginalDeletion = nil
        eventEditorSession = nil
        eventEditorOperationState = .idle
        eventEditorError = nil
        invalidateEventUndoCandidate()
        eventUndoError = nil
        isUndoingEventMutation = false
        selectEvent(nil)
        calendarSources = []
        events = []
        duplicateCandidateIndex = [:]
        loadedEventInterval = nil
    }

    private func initialFetchInterval() -> DateInterval {
        let today = calendar.startOfDay(for: now())
        let start = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 90, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    private func expandedFetchInterval(around visible: DateInterval) -> DateInterval {
        let start = calendar.date(
            byAdding: .day,
            value: -30,
            to: visible.start
        ) ?? visible.start
        let end = calendar.date(
            byAdding: .day,
            value: 90,
            to: visible.end
        ) ?? visible.end
        return DateInterval(start: start, end: end)
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private static func eventsShareStrongIdentity(
        _ lhs: DisplayEvent,
        _ rhs: DisplayEvent
    ) -> Bool {
        if lhs.id == rhs.id { return true }
        if let identifier = rhs.eventIdentifier,
           !identifier.isEmpty,
           lhs.eventIdentifier == identifier {
            return true
        }
        if let identifier = rhs.calendarItemIdentifier,
           !identifier.isEmpty,
           lhs.calendarItemIdentifier == identifier {
            return true
        }
        if let identifier = rhs.calendarItemExternalIdentifier,
           !identifier.isEmpty,
           lhs.calendarIdentifier == rhs.calendarIdentifier,
           lhs.calendarItemExternalIdentifier == identifier {
            return true
        }
        return false
    }

    private static func isPostWriteFallback(
        _ candidate: DisplayEvent,
        matching writtenEvent: DisplayEvent
    ) -> Bool {
        guard candidate.isRecurring == writtenEvent.isRecurring,
              eventsShareStrongIdentity(candidate, writtenEvent) else {
            return false
        }
        guard writtenEvent.isRecurring else {
            return true
        }
        guard candidate.calendarIdentifier
                == writtenEvent.calendarIdentifier else {
            return false
        }
        return recurringOccurrenceMatches(candidate, writtenEvent)
    }

    private static func recurringOccurrenceMatches(
        _ candidate: DisplayEvent,
        _ writtenEvent: DisplayEvent
    ) -> Bool {
        switch writtenEvent.timeSemantics {
        case .zoned:
            guard case .zoned = candidate.timeSemantics else {
                return false
            }
            let candidateAnchor = candidate.occurrenceDate
                ?? candidate.startDate
            let writtenAnchor = writtenEvent.occurrenceDate
                ?? writtenEvent.startDate
            return abs(
                candidateAnchor.timeIntervalSince(writtenAnchor)
            ) < 0.001
        case .allDay:
            guard case .allDay = candidate.timeSemantics else {
                return false
            }
            return localOccurrenceAnchor(candidate)
                == localOccurrenceAnchor(writtenEvent)
        case .floating:
            guard case .floating = candidate.timeSemantics else {
                return false
            }
            return localOccurrenceAnchor(candidate)
                == localOccurrenceAnchor(writtenEvent)
        }
    }

    private static func localOccurrenceAnchor(
        _ event: DisplayEvent
    ) -> LocalDateTimeComponents? {
        if let occurrenceLocalComponents = event.occurrenceLocalComponents {
            return occurrenceLocalComponents
        }
        switch event.timeSemantics {
        case let .allDay(start, _), let .floating(start, _):
            return start
        case .zoned:
            return nil
        }
    }
}
