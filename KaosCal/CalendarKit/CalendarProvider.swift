import Foundation

protocol CalendarProviding: AnyObject {
    @MainActor var authorizationState: CalendarAuthorizationState { get }
    @MainActor var storeChangeHandler: (() -> Void)? { get set }

    @MainActor func requestFullAccess() async throws -> Bool
    @MainActor func listCalendars() async throws -> [CalendarSource]
    @MainActor func fetchEvents(in interval: DateInterval) async throws -> [DisplayEvent]
    @MainActor func lookupEvent(
        _ query: CalendarEventLookupQuery
    ) async throws -> CalendarEventLookupResult
    @MainActor func defaultCalendarIdentifierForNewEvents() -> String?
    @MainActor func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent
    @MainActor func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent
    @MainActor func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt
    @MainActor func deleteEvent(_ original: DisplayEvent) throws
    @MainActor func deleteEvent(
        _ original: DisplayEvent,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt
}

@MainActor
extension CalendarProviding {
    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt {
        guard scope == .thisEvent else {
            throw CalendarEventWriteError.unsupportedRecurrence
        }
        if original.isRecurring {
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
        if original.isRecurring {
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
