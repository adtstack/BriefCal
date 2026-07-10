import Foundation

@MainActor
protocol CalendarProviding: AnyObject {
    var authorizationState: CalendarAuthorizationState { get }
    var storeChangeHandler: (() -> Void)? { get set }

    func requestFullAccess() async throws -> Bool
    func listCalendars() throws -> [CalendarSource]
    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent]
    func defaultCalendarIdentifierForNewEvents() -> String?
    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent
    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent
    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt
    func deleteEvent(_ original: DisplayEvent) throws
    func deleteEvent(
        _ original: DisplayEvent,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt
}

extension CalendarProviding {
    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt {
        guard scope == .thisEvent else {
            throw CalendarEventWriteError.unsupportedRecurrence
        }
        if original.isRecurring
            || original.occurrenceDate != nil
            || original.isDetached {
            throw CalendarEventWriteError.recurringScopeRequired
        }
        let updated = try updateEvent(original, with: draft)
        let current = CalendarEventDraft(
            event: original,
            calendar: .autoupdatingCurrent
        )
        let changedFields = draft.changedFields(comparedTo: current)
        return CalendarEventMutationReceipt(
            event: updated,
            didWrite: !changedFields.isEmpty,
            scope: scope,
            changedFields: changedFields
        )
    }

    func deleteEvent(
        _ original: DisplayEvent,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt {
        guard scope == .thisEvent else {
            throw CalendarEventWriteError.unsupportedRecurrence
        }
        if original.isRecurring
            || original.occurrenceDate != nil
            || original.isDetached {
            throw CalendarEventWriteError.recurringScopeRequired
        }
        try deleteEvent(original)
        return CalendarEventMutationReceipt(
            event: original,
            didWrite: true,
            scope: scope,
            changedFields: [.deletion]
        )
    }
}
