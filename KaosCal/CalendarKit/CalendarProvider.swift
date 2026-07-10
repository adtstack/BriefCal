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
    func deleteEvent(_ original: DisplayEvent) throws
}
