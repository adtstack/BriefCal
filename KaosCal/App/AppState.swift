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
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
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

enum EventBriefState: Equatable {
    case noSelection
    case unavailable
    case empty
    case loaded(EventBriefSnapshot)
    case confirmationRequired([String])
    case failed(String)
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

private struct CalendarEventUndoCandidate {
    let contextID: String
    let changeID: String
    let beforeDraft: CalendarEventDraft
    let afterEvent: DisplayEvent
}

private enum EventMutationSafetyError: LocalizedError {
    case linkedFutureSeriesDeferred
    case confirmationUnavailable
    case undoUnavailable

    var errorDescription: String? {
        switch self {
        case .linkedFutureSeriesDeferred:
            "This Event Brief is linked to one occurrence. KaosCal will not change this and future occurrences until every affected Brief can be reconciled safely."
        case .confirmationUnavailable:
            "The prepared event change is no longer current. Review the editor and prepare it again."
        case .undoUnavailable:
            "The last calendar change is no longer available to undo."
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
    @Published private(set) var events: [DisplayEvent] = []
    @Published private(set) var localContextStoreState: LocalContextStoreState
    @Published private(set) var eventBriefState: EventBriefState = .noSelection
    @Published private(set) var selectedEventNotes = ""
    @Published private(set) var notesSaveState: NotesSaveState = .idle
    @Published private(set) var taskCenterState: TaskCenterState = .unavailable
    @Published private(set) var localOperationError: String?
    @Published private(set) var eventEditorSession: CalendarEventEditorSession?
    @Published private(set) var eventEditorOperationState: CalendarEventEditorOperationState = .idle
    @Published private(set) var eventEditorError: String?
    @Published private(set) var pendingEventMutation: CalendarEventMutationPreview?
    @Published private(set) var lastEventMutationUndoAvailable = false
    @Published private(set) var eventUndoError: String?
    @Published private(set) var isUndoingEventMutation = false

    let calendar: Calendar
    let contextStore: ContextStore?
    private let now: () -> Date
    private let calendarProvider: CalendarProviding
    private var storeRefreshTask: Task<Void, Never>?
    private var rangeLoadTask: Task<Void, Never>?
    private var notesSaveTask: Task<Void, Never>?
    private var loadedEventInterval: DateInterval?
    private var activeBriefEvent: DisplayEvent?
    private var persistedEventNotes = ""
    private var failedNotesDrafts: [String: FailedNotesDraft] = [:]
    private var lastEventMutationUndoCandidate: CalendarEventUndoCandidate?

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        calendarProvider: CalendarProviding? = nil,
        contextStore: ContextStore? = nil,
        localContextStoreState: LocalContextStoreState = .unavailable
    ) {
        let calendarProvider = calendarProvider ?? EventKitProvider()
        self.calendar = calendar
        self.now = now
        self.calendarProvider = calendarProvider
        self.contextStore = contextStore
        self.localContextStoreState = localContextStoreState
        calendarAuthorizationState = calendarProvider.authorizationState
        focusedDate = calendar.startOfDay(for: now())

        calendarProvider.storeChangeHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleStoreRefresh()
            }
        }
    }

    var selectedEvent: DisplayEvent? {
        guard let selectedEventID else { return nil }
        return events.first { $0.id == selectedEventID }
    }

    var taskReferenceDate: Date { now() }

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
            return range.start < interval.end && range.end > interval.start
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

    func selectEvent(_ id: String?) {
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

    func reloadSelectedEventBrief() {
        flushPendingEventNotes()
        loadSelectedEventBrief()
    }

    func updateSelectedEventNotes(_ notes: String) {
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
        guard calendarAuthorizationState.canReadEvents else {
            localOperationError = "Full calendar access is required to open the original event. The local task was kept."
            return
        }
        guard let contextStore else {
            localOperationError = "Local task storage is unavailable."
            return
        }

        do {
            guard let target = try contextStore.navigationTarget(
                contextID: contextID
            ) else {
                throw ContextStoreError.missingContext(contextID)
            }
            let effectiveRange = target.link.effectiveDateRange(
                calendar: calendar
            )
            let targetDay = calendar.startOfDay(for: effectiveRange.start)
            let targetEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: targetDay
            ) ?? effectiveRange.end
            let targetInterval = expandedFetchInterval(
                around: DateInterval(start: targetDay, end: targetEnd)
            )

            rangeLoadTask?.cancel()
            rangeLoadTask = nil
            await refreshCalendarData(in: targetInterval)
            guard calendarContentState == .loaded
                    || calendarContentState == .empty else {
                localOperationError = "The original calendar event could not be loaded. The local task was kept."
                return
            }

            switch try contextStore.matchLinkedEvent(
                contextID: contextID,
                among: events
            ) {
            case let .linked(event, _):
                focusedDate = calendar.startOfDay(
                    for: CalendarEventDateFormatting.effectiveDateRange(
                        for: event,
                        calendar: calendar
                    ).start
                )
                selectedSection = .day
                selectEvent(event.id)
            case .confirmationRequired, .ambiguous:
                localOperationError = "KaosCal found similar events but will not choose one automatically. The local task was kept."
            case .notFound:
                localOperationError = "Calendar event unavailable in the stored date range. The local task was kept."
            }
        } catch {
            localOperationError = Self.message(for: error)
        }
    }

    func beginCreatingEvent() {
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
        let writableCalendars = calendarSources.filter(\.isWritable)
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
        do {
            try validateOriginalWritePolicy(event)
            return nil
        } catch {
            return Self.message(for: error)
        }
    }

    func beginEditingSelectedEvent() {
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
            let writableCalendars = calendarSources.filter(\.isWritable)
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
        eventEditorSession = nil
        eventEditorError = nil
    }

    func cancelPendingEventMutation() {
        guard eventEditorOperationState == .idle else { return }
        pendingEventMutation = nil
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
        guard let session = eventEditorSession,
              eventEditorOperationState == .idle else { return false }
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
    func deleteEventEditorTarget() async -> Bool {
        await deleteEventEditorTarget(scope: nil)
    }

    @discardableResult
    func deleteEventEditorTarget(
        scope requestedScope: CalendarEventMutationScope?
    ) async -> Bool {
        guard let session = eventEditorSession,
              case let .existing(original) = session.target else {
            return false
        }
        guard eventEditorOperationState == .idle else { return false }
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
            case .linked:
                throw CalendarEventWriteError.linkedDeleteDeferred
            case .confirmationRequired:
                throw CalendarEventWriteError.localIdentityConfirmationRequired
            case .none:
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
                invalidateEventUndoCandidate()
                await refreshCalendarData()
                eventEditorError = "The calendar event was saved, but its local Event Brief could not be refreshed. Your local data was kept. \(Self.message(for: error))"
                return false
            }
        }

        pendingEventMutation = nil
        eventEditorSession = nil
        eventEditorOperationState = .idle
        await focusWrittenEvent(receipt.event)
        return true
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
        if pendingEventMutation != nil {
            pendingEventMutation = nil
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

    func refreshTaskCenter() {
        guard let contextStore else {
            taskCenterState = .unavailable
            return
        }
        taskCenterState = .loading
        do {
            let list: TaskCenterList = switch selectedTaskFilter {
            case .today: .today
            case .upcoming: .upcoming
            case .completed: .completed
            }
            let items = try contextStore.taskCenter.fetch(
                list: list,
                now: now(),
                calendar: calendar
            )
            taskCenterState = .loaded(items)
        } catch {
            taskCenterState = .failed(Self.message(for: error))
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
        if event.isInvitation || event.hasAttendees {
            throw CalendarEventWriteError.meetingIsCalendarAppOnly
        }
        if event.isReadOnly {
            throw CalendarEventWriteError.readOnlyCalendar
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
        let writtenEvent = events.first { candidate in
            if candidate.id == event.id { return true }
            if let identifier = event.eventIdentifier,
               !identifier.isEmpty,
               candidate.eventIdentifier == identifier {
                return true
            }
            if let identifier = event.calendarItemIdentifier,
               !identifier.isEmpty,
               candidate.calendarItemIdentifier == identifier {
                return true
            }
            if let identifier = event.calendarItemExternalIdentifier,
               !identifier.isEmpty {
                return candidate.calendarIdentifier == event.calendarIdentifier
                    && candidate.calendarItemExternalIdentifier == identifier
                    && candidate.startDate == event.startDate
            }
            return false
        }
        selectEvent(writtenEvent?.id)
    }

    private func clearCalendarData() {
        rangeLoadTask?.cancel()
        pendingEventMutation = nil
        eventEditorSession = nil
        eventEditorOperationState = .idle
        eventEditorError = nil
        invalidateEventUndoCandidate()
        eventUndoError = nil
        isUndoingEventMutation = false
        selectEvent(nil)
        calendarSources = []
        events = []
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
}
