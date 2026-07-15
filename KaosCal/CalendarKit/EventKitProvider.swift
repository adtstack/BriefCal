import AppKit
import EventKit
import Foundation

struct EventKitRecurrenceClassification: Equatable {
    let isRecurring: Bool
    let occurrenceDate: Date?
}

private struct EventKitLookupCandidate {
    let rawEvent: EKEvent
    let event: DisplayEvent
    let basis: CalendarEventLookupBasis
}

@MainActor
final class EventKitProvider: CalendarProviding {
    private let eventStore: EKEventStore
    private let notificationCenter: NotificationCenter
    private var storeChangeObserver: NSObjectProtocol?

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

    var authorizationState: CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unknown
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func listCalendars() throws -> [CalendarSource] {
        eventStore.calendars(for: .event)
            .map { calendar in
                CalendarSource(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title,
                    sourceIdentifier: calendar.source.sourceIdentifier,
                    accountType: accountType(for: calendar.source.sourceType),
                    isWritable: calendar.allowsContentModifications,
                    color: colorSnapshot(for: calendar)
                )
            }
            .sorted {
                if $0.sourceTitle == $1.sourceTitle {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    func fetchEvents(in interval: DateInterval) throws -> [DisplayEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
            .map(makeDisplayEvent)
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
    }

    func lookupEvent(
        _ query: CalendarEventLookupQuery
    ) throws -> CalendarEventLookupResult {
        guard authorizationState.canReadEvents else {
            throw CalendarEventLookupError.fullAccessRequired
        }
        guard query.hasStrongIdentifier else {
            throw CalendarEventLookupError.missingStrongIdentifier
        }

        eventStore.refreshSourcesIfNecessary()
        let savedCalendarIsAvailable = eventStore.calendar(
            withIdentifier: query.calendarIdentifier
        ) != nil
        var rawCandidates: [EKEvent] = []

        if let identifier = nonEmpty(query.eventIdentifier),
           let event = eventStore.event(withIdentifier: identifier) {
            rawCandidates.append(event)
        }
        if let identifier = nonEmpty(query.calendarItemIdentifier),
           let event = eventStore.calendarItem(
            withIdentifier: identifier
           ) as? EKEvent {
            rawCandidates.append(event)
        }
        if let identifier = nonEmpty(
            query.calendarItemExternalIdentifier
        ) {
            rawCandidates.append(contentsOf: eventStore.calendarItems(
                withExternalIdentifier: identifier
            ).compactMap { $0 as? EKEvent })
        }
        for interval in lookupSearchIntervals(for: query) {
            let predicate = eventStore.predicateForEvents(
                withStart: interval.start,
                end: interval.end,
                calendars: nil
            )
            rawCandidates.append(contentsOf: eventStore.events(matching: predicate))
        }

        var strongMatches: [String: EventKitLookupCandidate] = [:]
        var weakCandidates: [String: EventKitLookupCandidate] = [:]
        var strongIdentifierMismatchIssue: CalendarEventLookupIssue?
        for rawEvent in rawCandidates {
            let event = makeDisplayEvent(rawEvent)
            let key = lookupCandidateKey(event)
            let strongBasis = strongLookupBasis(event, query: query)
            let occurrenceMatches = lookupOccurrenceMatches(
                event,
                query: query
            )
            if let issue = lookupStrongIdentifierMismatchIssue(
                event,
                query: query
            ) {
                if strongIdentifierMismatchIssue == nil
                    || issue == .strongIdentifierOccurrenceMismatch {
                    strongIdentifierMismatchIssue = issue
                }
            }

            if occurrenceMatches, let basis = strongBasis {
                let match = EventKitLookupCandidate(
                    rawEvent: rawEvent,
                    event: event,
                    basis: basis
                )
                if event.calendarIdentifier == query.calendarIdentifier {
                    strongMatches[key] = match
                } else {
                    weakCandidates[key] = match
                }
            } else if exactLookupSnapshotMatches(event, query: query) {
                weakCandidates[key] = EventKitLookupCandidate(
                    rawEvent: rawEvent,
                    event: event,
                    basis: .exactSnapshot
                )
            }
        }

        let exactMatches = sortedLookupCandidates(strongMatches.values)
        if exactMatches.count == 1, let match = exactMatches.first {
            let result = CalendarEventLookupMatch(
                event: match.event,
                basis: match.basis,
                isCancelled: match.rawEvent.status == .canceled
            )
            return match.rawEvent.status == .canceled
                ? .cancelled(result)
                : .found(result)
        }
        if exactMatches.count > 1 {
            return .ambiguous(exactMatches.map {
                CalendarEventLookupMatch(
                    event: $0.event,
                    basis: $0.basis,
                    isCancelled: $0.rawEvent.status == .canceled
                )
            })
        }

        let candidates = sortedLookupCandidates(weakCandidates.values).map {
            CalendarEventLookupMatch(
                event: $0.event,
                basis: $0.basis,
                isCancelled: $0.rawEvent.status == .canceled
            )
        }
        if candidates.count == 1 {
            return .candidates(candidates)
        }
        if candidates.count > 1 {
            return .ambiguous(candidates)
        }
        return lookupTerminalResult(
            strongIdentifierMismatchIssue: strongIdentifierMismatchIssue,
            savedCalendarIsAvailable: savedCalendarIsAvailable
        )
    }

    func defaultCalendarIdentifierForNewEvents() -> String? {
        guard let calendar = eventStore.defaultCalendarForNewEvents,
              calendar.allowsContentModifications else {
            return nil
        }
        return calendar.calendarIdentifier
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> DisplayEvent {
        try requireFullAccess()
        let normalized = try draft.validated(calendar: validationCalendar())
        let calendar = try writableCalendar(
            identifier: normalized.calendarIdentifier
        )
        let event = EKEvent(eventStore: eventStore)
        try applyAll(normalized, calendar: calendar, to: event)
        try eventStore.save(event, span: .thisEvent, commit: true)
        return makeDisplayEvent(event)
    }

    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft
    ) throws -> DisplayEvent {
        if original.isRecurring {
            throw CalendarEventWriteError.recurringScopeRequired
        }
        return try updateEvent(
            original,
            with: draft,
            scope: .thisEvent
        ).event
    }

    func updateEvent(
        _ original: DisplayEvent,
        with draft: CalendarEventDraft,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt {
        try requireFullAccess()
        try validateWritePolicy(original, scope: scope)
        let event = try resolveEvent(for: original)
        try validateCurrentWritePolicy(event, scope: scope)
        let current = makeDisplayEvent(event)
        guard editableFieldsMatch(
            current,
            original
        ) else {
            throw CalendarEventWriteError.eventChangedExternally
        }
        let recurrenceWasEdited = draft.recurrence != current.recurrence
        let normalized = try draft.validated(
            calendar: validationCalendar(),
            enforceRecurrenceEndBoundary:
                recurrenceWasEdited,
            rebaseRecurrenceEndDate: recurrenceWasEdited
        )
        try validateRecurrenceMutation(
            from: current.recurrence,
            to: normalized.recurrence,
            originalIsRecurring: current.isRecurring,
            scope: scope
        )
        let calendar = try writableCalendar(
            identifier: normalized.calendarIdentifier
        )
        let comparisonCalendar = normalized.wallTimeCalendar(
            fallback: validationCalendar()
        )
        let currentDraft = try CalendarEventDraft(
            event: current,
            calendar: comparisonCalendar
        ).validated(
            calendar: comparisonCalendar,
            enforceRecurrenceEndBoundary: false,
            rebaseRecurrenceEndDate: false
        )
        let changedFields = normalized.changedFields(comparedTo: currentDraft)
        guard !changedFields.isEmpty else {
            return CalendarEventMutationReceipt(
                event: current,
                didWrite: false,
                scope: scope,
                changedFields: []
            )
        }
        try applyChanges(
            from: currentDraft,
            to: normalized,
            calendar: calendar,
            event: event,
            scope: scope
        )
        try eventStore.save(
            event,
            span: eventKitSpan(for: scope),
            commit: true
        )
        let provisional = makeDisplayEvent(event)
        let refreshed: EKEvent
        do {
            refreshed = try resolveEvent(for: provisional)
        } catch {
            throw CalendarEventMutationPartialSuccess(
                provisionalEvent: provisional,
                underlyingDescription: error.localizedDescription
            )
        }
        return CalendarEventMutationReceipt(
            event: makeDisplayEvent(refreshed),
            didWrite: true,
            scope: scope,
            changedFields: changedFields
        )
    }

    func deleteEvent(_ original: DisplayEvent) throws {
        if original.isRecurring {
            throw CalendarEventWriteError.recurringScopeRequired
        }
        _ = try deleteEvent(original, scope: .thisEvent)
    }

    func deleteEvent(
        _ original: DisplayEvent,
        scope: CalendarEventMutationScope
    ) throws -> CalendarEventMutationReceipt {
        try requireFullAccess()
        try validateWritePolicy(original, scope: scope)
        let event = try resolveEvent(for: original)
        try validateCurrentWritePolicy(event, scope: scope)
        let current = makeDisplayEvent(event)
        guard editableFieldsMatch(
            current,
            original
        ) else {
            throw CalendarEventWriteError.eventChangedExternally
        }
        try eventStore.remove(
            event,
            span: eventKitSpan(for: scope),
            commit: true
        )
        return CalendarEventMutationReceipt(
            event: current,
            didWrite: true,
            scope: scope,
            changedFields: [.deletion]
        )
    }

    private func makeDisplayEvent(_ event: EKEvent) -> DisplayEvent {
        let title = event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled event"
        let classification = recurrenceClassification(for: event)
        let isRecurring = classification.isRecurring
        let occurrenceDate = classification.occurrenceDate
        let recurrence = makeRecurrenceRepresentation(
            event,
            isRecurring: isRecurring
        )
        let timeSemantics = makeTimeSemantics(event)
        let occurrenceLocalComponents = makeOccurrenceLocalComponents(
            event,
            isRecurring: isRecurring,
            timeSemantics: timeSemantics
        )
        let stableID = DisplayEventIdentity.make(
            calendarIdentifier: event.calendar.calendarIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            eventIdentifier: event.eventIdentifier,
            isRecurring: isRecurring,
            occurrenceDate: occurrenceDate,
            occurrenceLocalComponents: occurrenceLocalComponents,
            startDate: event.startDate,
            endDate: event.endDate,
            title: title
        )

        return DisplayEvent(
            id: stableID,
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            sourceTitle: event.calendar.source.title,
            accountType: accountType(for: event.calendar.source.sourceType),
            calendarColor: colorSnapshot(for: event.calendar),
            title: title,
            location: event.location,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZone?.identifier,
            timeSemantics: timeSemantics,
            isRecurring: isRecurring,
            occurrenceDate: occurrenceDate,
            occurrenceLocalComponents: occurrenceLocalComponents,
            isDetached: event.isDetached,
            isReadOnly: !event.calendar.allowsContentModifications,
            isInvitation: event.organizer.map { !$0.isCurrentUser } ?? false,
            hasAttendees: event.hasAttendees,
            originalNotes: event.notes,
            recurrence: recurrence,
            availability: availability(for: event),
            isCancelled: event.status == .canceled,
            isDeclinedByCurrentUser: event.attendees?.contains(where: {
                $0.isCurrentUser && $0.participantStatus == .declined
            }) ?? false
        )
    }

    func lookupOccurrenceMatches(
        _ candidate: DisplayEvent,
        query: CalendarEventLookupQuery
    ) -> Bool {
        switch query.occurrence {
        case .single:
            return !candidate.isRecurring
        case let .instant(anchor):
            guard candidate.isRecurring,
                  case .zoned = candidate.timeSemantics else {
                return false
            }
            let candidateAnchor = candidate.occurrenceDate
                ?? candidate.startDate
            return abs(candidateAnchor.timeIntervalSince(anchor)) < 0.001
        case let .allDay(anchor):
            guard candidate.isRecurring,
                  case .allDay = candidate.timeSemantics else {
                return false
            }
            return localOccurrenceAnchor(candidate) == anchor
        case let .floating(anchor):
            guard candidate.isRecurring,
                  case .floating = candidate.timeSemantics else {
                return false
            }
            return localOccurrenceAnchor(candidate) == anchor
        }
    }

    private func strongLookupBasis(
        _ event: DisplayEvent,
        query: CalendarEventLookupQuery
    ) -> CalendarEventLookupBasis? {
        if let identifier = nonEmpty(query.eventIdentifier),
           event.eventIdentifier == identifier {
            return .eventIdentifierAndOccurrence
        }
        if let identifier = nonEmpty(query.calendarItemIdentifier),
           event.calendarItemIdentifier == identifier {
            return .calendarItemIdentifierAndOccurrence
        }
        if let identifier = nonEmpty(
            query.calendarItemExternalIdentifier
        ), event.calendarItemExternalIdentifier == identifier {
            return .externalIdentifierAndOccurrence
        }
        return nil
    }

    private func exactLookupSnapshotMatches(
        _ event: DisplayEvent,
        query: CalendarEventLookupQuery
    ) -> Bool {
        let snapshot = query.lastKnown
        guard event.title == snapshot.title,
              event.location == snapshot.location,
              event.isAllDay == snapshot.isAllDay else {
            return false
        }

        switch (event.timeSemantics, snapshot.timeSemantics) {
        case let (
            .zoned(identifier),
            .zoned(snapshotIdentifier)
        ):
            return identifier == snapshotIdentifier
                && abs(event.startDate.timeIntervalSince(snapshot.startDate)) < 0.001
                && abs(event.endDate.timeIntervalSince(snapshot.endDate)) < 0.001
        case let (
            .allDay(start, endExclusive),
            .allDay(snapshotStart, snapshotEndExclusive)
        ):
            return start == snapshotStart
                && endExclusive == snapshotEndExclusive
        case let (
            .floating(start, end),
            .floating(snapshotStart, snapshotEnd)
        ):
            return start == snapshotStart && end == snapshotEnd
        default:
            return false
        }
    }

    private func lookupSearchIntervals(
        for query: CalendarEventLookupQuery
    ) -> [DateInterval] {
        let padding: TimeInterval = 172_800
        let duration = max(
            query.lastKnown.endDate.timeIntervalSince(
                query.lastKnown.startDate
            ),
            3_600
        )
        var anchors = query.searchAnchors
        switch query.occurrence {
        case let .allDay(components), let .floating(components):
            if let date = components.date(in: validationCalendar()) {
                anchors.append(date)
            }
        case .single, .instant:
            break
        }
        var seen = Set<Int64>()
        return anchors
            .filter { anchor in
                seen.insert(Int64(
                    (anchor.timeIntervalSinceReferenceDate * 1_000).rounded()
                )).inserted
            }
            .map { anchor in
                DateInterval(
                    start: anchor.addingTimeInterval(-padding),
                    end: anchor.addingTimeInterval(duration + padding)
                )
            }
    }

    private func lookupCandidateKey(_ event: DisplayEvent) -> String {
        event.id
    }

    private func isRecurringLookup(
        _ query: CalendarEventLookupQuery
    ) -> Bool {
        if case .single = query.occurrence { return false }
        return true
    }

    func lookupTerminalResult(
        strongIdentifierMismatchIssue: CalendarEventLookupIssue?,
        savedCalendarIsAvailable: Bool
    ) -> CalendarEventLookupResult {
        if let strongIdentifierMismatchIssue {
            return .inconclusive(strongIdentifierMismatchIssue)
        }
        if !savedCalendarIsAvailable {
            return .inconclusive(.calendarUnavailable)
        }
        return .notFound
    }

    func lookupStrongIdentifierMismatchIssue(
        _ candidate: DisplayEvent,
        query: CalendarEventLookupQuery
    ) -> CalendarEventLookupIssue? {
        guard strongLookupBasis(candidate, query: query) != nil,
              !lookupOccurrenceMatches(candidate, query: query) else {
            return nil
        }
        return isRecurringLookup(query) && candidate.isRecurring
            ? .recurringOccurrenceUnavailable
            : .strongIdentifierOccurrenceMismatch
    }

    private func sortedLookupCandidates(
        _ candidates: Dictionary<String, EventKitLookupCandidate>.Values
    ) -> [EventKitLookupCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.event.startDate != rhs.event.startDate {
                return lhs.event.startDate < rhs.event.startDate
            }
            if lhs.event.title != rhs.event.title {
                return lhs.event.title.localizedCaseInsensitiveCompare(
                    rhs.event.title
                ) == .orderedAscending
            }
            return lhs.event.id < rhs.event.id
        }
    }

    private func requireFullAccess() throws {
        guard authorizationState.canReadEvents else {
            throw CalendarEventWriteError.fullAccessRequired
        }
    }

    private func validateWritePolicy(
        _ event: DisplayEvent,
        scope: CalendarEventMutationScope
    ) throws {
        if event.isInvitation || event.hasAttendees {
            throw CalendarEventWriteError.meetingIsCalendarAppOnly
        }
        if event.isReadOnly {
            throw CalendarEventWriteError.readOnlyCalendar
        }
        if scope == .futureEvents {
            guard event.isRecurring else {
                throw CalendarEventWriteError.futureScopeRequiresRecurringEvent
            }
            if event.isDetached {
                throw CalendarEventWriteError.detachedFutureScopeUnsupported
            }
            guard event.recurrence.isRepresentable else {
                throw CalendarEventWriteError.unsupportedRecurrence
            }
        }
    }

    private func validateCurrentWritePolicy(
        _ event: EKEvent,
        scope: CalendarEventMutationScope
    ) throws {
        guard event.calendar.allowsContentModifications else {
            throw CalendarEventWriteError.readOnlyCalendar
        }
        if requiresCalendarAppMeetingManagement(event) {
            throw CalendarEventWriteError.meetingIsCalendarAppOnly
        }
        if scope == .futureEvents {
            let current = makeDisplayEvent(event)
            guard current.isRecurring else {
                throw CalendarEventWriteError.futureScopeRequiresRecurringEvent
            }
            if current.isDetached {
                throw CalendarEventWriteError.detachedFutureScopeUnsupported
            }
            guard current.recurrence.isRepresentable else {
                throw CalendarEventWriteError.unsupportedRecurrence
            }
        }
    }

    private func validateRecurrenceMutation(
        from current: CalendarEventRecurrence,
        to requested: CalendarEventRecurrence,
        originalIsRecurring: Bool,
        scope: CalendarEventMutationScope
    ) throws {
        if scope == .thisEvent, originalIsRecurring,
           current != requested {
            throw CalendarEventWriteError.recurrenceChangeRequiresFutureScope
        }
        if scope == .futureEvents {
            guard originalIsRecurring else {
                throw CalendarEventWriteError.futureScopeRequiresRecurringEvent
            }
            guard current.isRepresentable, requested.isRepresentable else {
                throw CalendarEventWriteError.unsupportedRecurrence
            }
        } else if !originalIsRecurring,
                  !requested.isRepresentable {
            throw CalendarEventWriteError.unsupportedRecurrence
        }
    }

    private func writableCalendar(identifier: String) throws -> EKCalendar {
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            throw CalendarEventWriteError.calendarUnavailable
        }
        guard calendar.allowsContentModifications else {
            throw CalendarEventWriteError.readOnlyCalendar
        }
        return calendar
    }

    private func resolveEvent(for original: DisplayEvent) throws -> EKEvent {
        if original.isRecurring {
            return try resolveRecurringEvent(for: original)
        }

        if let identifier = original.eventIdentifier,
           !identifier.isEmpty,
           let event = eventStore.event(withIdentifier: identifier),
           singleEventCandidate(event, matchesCalendarOf: original) {
            return event
        }

        if let identifier = original.calendarItemIdentifier,
           !identifier.isEmpty,
           let event = eventStore.calendarItem(
               withIdentifier: identifier
           ) as? EKEvent,
           singleEventCandidate(event, matchesCalendarOf: original) {
            return event
        }

        if let identifier = original.calendarItemExternalIdentifier,
           !identifier.isEmpty {
            let matches = eventStore.calendarItems(
                withExternalIdentifier: identifier
            )
                .compactMap { $0 as? EKEvent }
                .filter { singleEventCandidate($0, matchesCalendarOf: original) }
            if matches.count == 1, let event = matches.first {
                return event
            }
            if matches.count > 1 {
                throw CalendarEventWriteError.ambiguousEvent
            }
        }

        throw CalendarEventWriteError.eventUnavailable
    }

    private func resolveRecurringEvent(
        for original: DisplayEvent
    ) throws -> EKEvent {
        guard hasStrongIdentifier(original),
              let calendar = eventStore.calendar(
                withIdentifier: original.calendarIdentifier
              ) else {
            throw CalendarEventWriteError.eventUnavailable
        }

        var candidates: [EKEvent] = []
        if let identifier = nonEmpty(original.eventIdentifier),
           let event = eventStore.event(withIdentifier: identifier) {
            candidates.append(event)
        }
        if let identifier = nonEmpty(original.calendarItemIdentifier),
           let event = eventStore.calendarItem(
            withIdentifier: identifier
           ) as? EKEvent {
            candidates.append(event)
        }
        if let identifier = nonEmpty(
            original.calendarItemExternalIdentifier
        ) {
            candidates.append(contentsOf: eventStore.calendarItems(
                withExternalIdentifier: identifier
            ).compactMap { $0 as? EKEvent })
        }
        for interval in recurrenceSearchIntervals(for: original) {
            let predicate = eventStore.predicateForEvents(
                withStart: interval.start,
                end: interval.end,
                calendars: [calendar]
            )
            candidates.append(contentsOf: eventStore.events(matching: predicate))
        }

        var uniqueMatches: [String: EKEvent] = [:]
        for event in candidates where recurringEventCandidate(
            event,
            matches: original
        ) {
            let displayEvent = makeDisplayEvent(event)
            uniqueMatches[recurringCandidateKey(displayEvent)] = event
        }
        if uniqueMatches.count == 1,
           let event = uniqueMatches.values.first {
            return event
        }
        if uniqueMatches.count > 1 {
            throw CalendarEventWriteError.ambiguousEvent
        }
        throw CalendarEventWriteError.eventUnavailable
    }

    private func recurringCandidateKey(_ event: DisplayEvent) -> String {
        let identity = [
            nonEmpty(event.eventIdentifier) ?? "",
            nonEmpty(event.calendarItemIdentifier) ?? "",
            nonEmpty(event.calendarItemExternalIdentifier) ?? ""
        ].joined(separator: "|")
        let occurrence: String
        switch event.timeSemantics {
        case .zoned:
            let anchor = event.occurrenceDate ?? event.startDate
            let milliseconds = Int64(
                (anchor.timeIntervalSince1970 * 1_000).rounded()
            )
            occurrence = "instant:\(milliseconds)"
        case .allDay, .floating:
            if let anchor = localOccurrenceAnchor(event) {
                occurrence = [
                    "local",
                    String(describing: anchor.calendarIdentifier),
                    String(anchor.year),
                    String(anchor.month),
                    String(anchor.day),
                    String(anchor.hour),
                    String(anchor.minute),
                    String(anchor.second)
                ].joined(separator: ":")
            } else {
                occurrence = "local:missing"
            }
        }
        return "\(event.calendarIdentifier)|\(identity)|\(occurrence)"
    }

    private func singleEventCandidate(
        _ event: EKEvent,
        matchesCalendarOf original: DisplayEvent
    ) -> Bool {
        event.calendar.calendarIdentifier == original.calendarIdentifier
            && !recurrenceClassification(for: event).isRecurring
    }

    private func recurringEventCandidate(
        _ event: EKEvent,
        matches original: DisplayEvent
    ) -> Bool {
        guard event.calendar.calendarIdentifier == original.calendarIdentifier,
              strongIdentifierMatches(event, original: original) else {
            return false
        }
        let candidate = makeDisplayEvent(event)
        guard candidate.isRecurring else {
            return false
        }
        return semanticOccurrenceMatches(candidate, original)
    }

    func semanticOccurrenceMatches(
        _ candidate: DisplayEvent,
        _ original: DisplayEvent
    ) -> Bool {
        switch original.timeSemantics {
        case .zoned:
            guard case .zoned = candidate.timeSemantics else { return false }
            let candidateAnchor = candidate.occurrenceDate
                ?? candidate.startDate
            let originalAnchor = original.occurrenceDate
                ?? original.startDate
            return abs(candidateAnchor.timeIntervalSince(originalAnchor)) < 0.001
        case .allDay:
            guard case .allDay = candidate.timeSemantics else { return false }
            return localOccurrenceAnchor(candidate)
                == localOccurrenceAnchor(original)
        case .floating:
            guard case .floating = candidate.timeSemantics else { return false }
            return localOccurrenceAnchor(candidate)
                == localOccurrenceAnchor(original)
        }
    }

    private func localOccurrenceAnchor(
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

    private func recurrenceSearchIntervals(
        for event: DisplayEvent
    ) -> [DateInterval] {
        let padding: TimeInterval = 172_800
        let duration = max(
            event.endDate.timeIntervalSince(event.startDate),
            3_600
        )
        var seen = Set<Int64>()
        return [event.occurrenceDate, event.startDate]
            .compactMap { $0 }
            .filter {
                seen.insert(Int64(
                    ($0.timeIntervalSinceReferenceDate * 1_000).rounded()
                )).inserted
            }
            .map { anchor in
                DateInterval(
                    start: anchor.addingTimeInterval(-padding),
                    end: anchor.addingTimeInterval(duration + padding)
                )
            }
    }

    private func hasStrongIdentifier(_ event: DisplayEvent) -> Bool {
        nonEmpty(event.eventIdentifier) != nil
            || nonEmpty(event.calendarItemIdentifier) != nil
            || nonEmpty(event.calendarItemExternalIdentifier) != nil
    }

    private func strongIdentifierMatches(
        _ event: EKEvent,
        original: DisplayEvent
    ) -> Bool {
        if let identifier = nonEmpty(original.eventIdentifier),
           event.eventIdentifier == identifier {
            return true
        }
        if let identifier = nonEmpty(original.calendarItemIdentifier),
           event.calendarItemIdentifier == identifier {
            return true
        }
        if let identifier = nonEmpty(
            original.calendarItemExternalIdentifier
        ), event.calendarItemExternalIdentifier == identifier {
            return true
        }
        return false
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func editableFieldsMatch(
        _ current: DisplayEvent,
        _ original: DisplayEvent
    ) -> Bool {
        current.calendarIdentifier == original.calendarIdentifier
            && current.title == original.title
            && current.location == original.location
            && current.hasSameEditableTime(as: original)
            && current.originalNotes == original.originalNotes
            && current.recurrence == original.recurrence
    }

    private func applyAll(
        _ draft: CalendarEventDraft,
        calendar: EKCalendar,
        to event: EKEvent
    ) throws {
        event.calendar = calendar
        event.title = draft.title
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.originalNotes.isEmpty
            ? nil
            : draft.originalNotes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.timeZone = draft.isAllDay
            ? nil
            : draft.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        event.recurrenceRules = try makeEventKitRecurrenceRules(
            for: draft.recurrence
        )
    }

    private func applyChanges(
        from current: CalendarEventDraft,
        to draft: CalendarEventDraft,
        calendar: EKCalendar,
        event: EKEvent,
        scope: CalendarEventMutationScope
    ) throws {
        if draft.calendarIdentifier != current.calendarIdentifier {
            event.calendar = calendar
        }
        if draft.title != current.title {
            event.title = draft.title
        }
        if draft.location != current.location {
            event.location = draft.location.isEmpty ? nil : draft.location
        }
        if draft.originalNotes != current.originalNotes {
            event.notes = draft.originalNotes.isEmpty
                ? nil
                : draft.originalNotes
        }
        if draft.startDate != current.startDate
            || draft.endDate != current.endDate
            || draft.isAllDay != current.isAllDay
            || draft.timeZoneIdentifier != current.timeZoneIdentifier {
            event.startDate = draft.startDate
            event.endDate = draft.endDate
            event.isAllDay = draft.isAllDay
            event.timeZone = draft.isAllDay
                ? nil
                : draft.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        }
        if draft.recurrence != current.recurrence {
            if current.recurrence.isRecurring,
               scope == .thisEvent {
                throw CalendarEventWriteError
                    .recurrenceChangeRequiresFutureScope
            }
            event.recurrenceRules = try makeEventKitRecurrenceRules(
                for: draft.recurrence
            )
        }
    }

    private func eventKitSpan(
        for scope: CalendarEventMutationScope
    ) -> EKSpan {
        switch scope {
        case .thisEvent:
            .thisEvent
        case .futureEvents:
            .futureEvents
        }
    }

    func makeEventKitRecurrenceRules(
        for recurrence: CalendarEventRecurrence
    ) throws -> [EKRecurrenceRule]? {
        switch recurrence {
        case .none:
            return nil
        case .unsupported:
            throw CalendarEventWriteError.unsupportedRecurrence
        case let .basic(rule):
            let recurrenceEnd: EKRecurrenceEnd? = switch rule.end {
            case .never:
                nil
            case let .onDate(date):
                EKRecurrenceEnd(end: date)
            case let .afterOccurrences(count):
                EKRecurrenceEnd(occurrenceCount: count)
            }
            let frequency: EKRecurrenceFrequency = switch rule.frequency {
            case .daily: .daily
            case .weekly: .weekly
            case .monthly: .monthly
            case .yearly: .yearly
            }
            if rule.frequency == .weekly {
                let days = rule.weekdays
                    .sorted { $0.rawValue < $1.rawValue }
                    .map {
                        EKRecurrenceDayOfWeek(
                            eventKitWeekday($0),
                            weekNumber: 0
                        )
                    }
                return [EKRecurrenceRule(
                    recurrenceWith: frequency,
                    interval: rule.interval,
                    daysOfTheWeek: days,
                    daysOfTheMonth: nil,
                    monthsOfTheYear: nil,
                    weeksOfTheYear: nil,
                    daysOfTheYear: nil,
                    setPositions: nil,
                    end: recurrenceEnd
                )]
            }
            return [EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: rule.interval,
                end: recurrenceEnd
            )]
        }
    }

    private func eventKitWeekday(
        _ weekday: CalendarRecurrenceWeekday
    ) -> EKWeekday {
        switch weekday {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }

    private func requiresCalendarAppMeetingManagement(
        _ event: EKEvent
    ) -> Bool {
        event.hasAttendees
            || (event.organizer.map { !$0.isCurrentUser } ?? false)
    }

    private func validationCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    func recurrenceRepresentation(
        for event: EKEvent
    ) -> CalendarEventRecurrence {
        makeRecurrenceRepresentation(
            event,
            isRecurring: recurrenceClassification(for: event).isRecurring
        )
    }

    func recurrenceClassification(
        for event: EKEvent
    ) -> EventKitRecurrenceClassification {
        Self.classifyRecurrence(
            hasRecurrenceRules: event.hasRecurrenceRules,
            isDetached: event.isDetached,
            rawOccurrenceDate: event.occurrenceDate
        )
    }

    static func classifyRecurrence(
        hasRecurrenceRules: Bool,
        isDetached: Bool,
        rawOccurrenceDate: Date?
    ) -> EventKitRecurrenceClassification {
        let isRecurring = hasRecurrenceRules || isDetached
        return EventKitRecurrenceClassification(
            isRecurring: isRecurring,
            occurrenceDate: isRecurring ? rawOccurrenceDate : nil
        )
    }

    private func makeRecurrenceRepresentation(
        _ event: EKEvent,
        isRecurring: Bool
    ) -> CalendarEventRecurrence {
        let rules = event.recurrenceRules ?? []
        guard !rules.isEmpty else {
            guard isRecurring else { return .none }
            return .unsupported(UnsupportedRecurrenceSnapshot(
                summary: "Recurring rule unavailable for this occurrence",
                signature: "missing:v1:\(event.hasRecurrenceRules):\(event.isDetached)"
            ))
        }

        let signature = recurrenceSignature(rules)
        guard rules.count == 1, let rule = rules.first else {
            return .unsupported(UnsupportedRecurrenceSnapshot(
                summary: "Multiple recurrence rules",
                signature: signature
            ))
        }
        guard rule.interval > 0,
              let frequency = calendarRecurrenceFrequency(rule.frequency),
              basicSelectorsAreSupported(
                rule,
                frequency: frequency,
                event: event
              ) else {
            return .unsupported(UnsupportedRecurrenceSnapshot(
                summary: "Advanced recurrence rule",
                signature: signature
            ))
        }

        let end: CalendarRecurrenceEnd
        if let endDate = rule.recurrenceEnd?.endDate {
            end = .onDate(endDate)
        } else if let count = rule.recurrenceEnd?.occurrenceCount,
                  count > 0 {
            end = .afterOccurrences(count)
        } else {
            end = .never
        }

        let weekdays: Set<CalendarRecurrenceWeekday>
        if frequency == .weekly {
            if let days = rule.daysOfTheWeek, !days.isEmpty {
                let mapped = days.compactMap {
                    CalendarRecurrenceWeekday(
                        rawValue: $0.dayOfTheWeek.rawValue
                    )
                }
                guard mapped.count == days.count else {
                    return .unsupported(UnsupportedRecurrenceSnapshot(
                        summary: "Advanced weekly recurrence rule",
                        signature: signature
                    ))
                }
                weekdays = Set(mapped)
            } else {
                let semanticCalendar = semanticCalendar(for: event)
                let rawWeekday = semanticCalendar.component(
                    .weekday,
                    from: event.startDate
                )
                guard let weekday = CalendarRecurrenceWeekday(
                    rawValue: rawWeekday
                ) else {
                    return .unsupported(UnsupportedRecurrenceSnapshot(
                        summary: "Weekly recurrence weekday unavailable",
                        signature: signature
                    ))
                }
                weekdays = [weekday]
            }
        } else {
            weekdays = []
        }

        return .basic(BasicRecurrenceRule(
            frequency: frequency,
            interval: rule.interval,
            weekdays: weekdays,
            end: end
        ))
    }

    private func basicSelectorsAreSupported(
        _ rule: EKRecurrenceRule,
        frequency: CalendarRecurrenceFrequency,
        event: EKEvent
    ) -> Bool {
        let noWeekNumbers = (rule.daysOfTheWeek ?? []).allSatisfy {
            $0.weekNumber == 0
        }
        let noSetPositions = rule.setPositions?.isEmpty ?? true
        let noWeeksOfYear = rule.weeksOfTheYear?.isEmpty ?? true
        let noDaysOfYear = rule.daysOfTheYear?.isEmpty ?? true
        let noDaysOfMonth = rule.daysOfTheMonth?.isEmpty ?? true
        let noMonthsOfYear = rule.monthsOfTheYear?.isEmpty ?? true
        let noDaysOfWeek = rule.daysOfTheWeek?.isEmpty ?? true
        let firstWeekdayIsStandard = rule.firstDayOfTheWeek == 0
            || rule.firstDayOfTheWeek == CalendarRecurrenceWeekday.monday.rawValue
        guard noWeekNumbers, noSetPositions else { return false }

        switch frequency {
        case .daily:
            return noDaysOfWeek
                && noDaysOfMonth
                && noMonthsOfYear
                && noWeeksOfYear
                && noDaysOfYear
                && firstWeekdayIsStandard
        case .weekly:
            return noDaysOfMonth
                && noMonthsOfYear
                && noWeeksOfYear
                && noDaysOfYear
                && firstWeekdayIsStandard
        case .monthly:
            let startDay = semanticCalendar(for: event).component(
                .day,
                from: event.startDate
            )
            let monthDays = (rule.daysOfTheMonth ?? [])
                .map(\.intValue)
            let anchoredMonthDay = monthDays.isEmpty
                || monthDays == [startDay]
            return noDaysOfWeek
                && anchoredMonthDay
                && noMonthsOfYear
                && noWeeksOfYear
                && noDaysOfYear
                && firstWeekdayIsStandard
        case .yearly:
            let startMonth = semanticCalendar(for: event).component(
                .month,
                from: event.startDate
            )
            let months = (rule.monthsOfTheYear ?? [])
                .map(\.intValue)
            let anchoredMonth = months.isEmpty || months == [startMonth]
            return noDaysOfWeek
                && noDaysOfMonth
                && anchoredMonth
                && noWeeksOfYear
                && noDaysOfYear
                && firstWeekdayIsStandard
        }
    }

    private func calendarRecurrenceFrequency(
        _ frequency: EKRecurrenceFrequency
    ) -> CalendarRecurrenceFrequency? {
        switch frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        @unknown default: nil
        }
    }

    private func recurrenceSignature(
        _ rules: [EKRecurrenceRule]
    ) -> String {
        rules.map { rule in
            let end: String
            if let date = rule.recurrenceEnd?.endDate {
                end = "date:\(Int64((date.timeIntervalSince1970 * 1_000).rounded()))"
            } else if let count = rule.recurrenceEnd?.occurrenceCount,
                      count > 0 {
                end = "count:\(count)"
            } else {
                end = "never"
            }
            let weekdays = (rule.daysOfTheWeek ?? [])
                .map { "\($0.dayOfTheWeek.rawValue):\($0.weekNumber)" }
                .sorted()
                .joined(separator: ",")
            return [
                "frequency:\(rule.frequency.rawValue)",
                "interval:\(rule.interval)",
                "firstWeekday:\(rule.firstDayOfTheWeek)",
                "end:\(end)",
                "weekdays:\(weekdays)",
                "monthDays:\(numberSignature(rule.daysOfTheMonth))",
                "months:\(numberSignature(rule.monthsOfTheYear))",
                "weeks:\(numberSignature(rule.weeksOfTheYear))",
                "yearDays:\(numberSignature(rule.daysOfTheYear))",
                "positions:\(numberSignature(rule.setPositions))"
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: "||")
    }

    private func numberSignature(_ values: [NSNumber]?) -> String {
        (values ?? [])
            .map(\.intValue)
            .sorted()
            .map(String.init)
            .joined(separator: ",")
    }

    private func makeTimeSemantics(_ event: EKEvent) -> EventTimeSemantics {
        let semanticCalendar = semanticCalendar(for: event)

        if event.isAllDay {
            let range = CalendarEventDateFormatting.normalizedAllDayDateRange(
                startDate: event.startDate,
                endDate: event.endDate,
                calendar: semanticCalendar
            )
            return .allDay(
                start: LocalDateTimeComponents(
                    date: range.start,
                    calendar: semanticCalendar
                ),
                endExclusive: LocalDateTimeComponents(
                    date: range.endExclusive,
                    calendar: semanticCalendar
                )
            )
        }

        let start = LocalDateTimeComponents(
            date: event.startDate,
            calendar: semanticCalendar
        )
        let end = LocalDateTimeComponents(
            date: event.endDate,
            calendar: semanticCalendar
        )

        if let identifier = event.timeZone?.identifier {
            return .zoned(timeZoneIdentifier: identifier)
        }
        return .floating(start: start, end: end)
    }

    private func makeOccurrenceLocalComponents(
        _ event: EKEvent,
        isRecurring: Bool,
        timeSemantics: EventTimeSemantics
    ) -> LocalDateTimeComponents? {
        guard isRecurring else { return nil }
        switch timeSemantics {
        case .zoned:
            return nil
        case let .allDay(start, _), let .floating(start, _):
            guard let occurrenceDate = event.occurrenceDate else {
                return start
            }
            return LocalDateTimeComponents(
                date: occurrenceDate,
                calendar: semanticCalendar(for: event)
            )
        }
    }

    private func semanticCalendar(for event: EKEvent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = event.timeZone ?? .autoupdatingCurrent
        return calendar
    }

    private func colorSnapshot(for calendar: EKCalendar) -> CalendarColor? {
        guard let cgColor = calendar.cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return CalendarColor(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
    }

    private func availability(
        for event: EKEvent
    ) -> CalendarEventAvailability {
        switch event.availability {
        case .notSupported:
            .notSupported
        case .busy:
            .busy
        case .free:
            .free
        case .tentative:
            .tentative
        case .unavailable:
            .unavailable
        @unknown default:
            .notSupported
        }
    }

    private func accountType(for sourceType: EKSourceType) -> CalendarAccountType {
        switch sourceType {
        case .exchange:
            return .exchange
        case .calDAV:
            return .calDAV
        case .mobileMe:
            return .iCloud
        case .local:
            return .local
        case .subscribed:
            return .subscribed
        case .birthdays:
            return .birthdays
        @unknown default:
            return .unknown
        }
    }
}
