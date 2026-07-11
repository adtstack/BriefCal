import Foundation
import GRDB

struct EventBriefSnapshot: Equatable {
    let context: EventContext
    let link: EventLink
    let tasks: [EventTask]
}

enum EventBriefLoadResult: Equatable {
    case empty
    case loaded(
        snapshot: EventBriefSnapshot,
        basis: EventIdentityMatchBasis
    )
    case confirmationRequired(
        contextIDs: [String],
        basis: EventIdentityMatchBasis
    )
}

struct EventNavigationTarget: Equatable {
    let contextID: String
    let link: EventLink
}

enum EventNavigationResolution: Equatable {
    case linked(event: DisplayEvent, basis: EventIdentityMatchBasis)
    case confirmationRequired(
        eventIDs: [String],
        basis: EventIdentityMatchBasis
    )
    case ambiguous(eventIDs: [String], basis: EventIdentityMatchBasis)
    case notFound
}

enum EventIdentityMatchBasis: Equatable {
    case eventIdentifier
    case calendarItemIdentifier
    case externalIdentifierAndOccurrence
    case recurrenceSeriesAndOccurrence
    case legacySyntheticSingle
    case exactSnapshot
    case fingerprint
}

enum EventContextResolution: Equatable {
    case linked(contextID: String, basis: EventIdentityMatchBasis)
    case candidate(contextIDs: [String], basis: EventIdentityMatchBasis)
    case ambiguous(contextIDs: [String], basis: EventIdentityMatchBasis)
    case notFound
}

final class EventContextRepository {
    private let database: AppDatabase
    private let now: () -> Date
    private let makeID: () -> String

    init(
        database: AppDatabase,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.database = database
        self.now = now
        self.makeID = makeID
    }

    func fetch(id: String) throws -> EventContext? {
        try database.read { db in
            try EventContext.fetchOne(db, key: id)
        }
    }

    func fetchBrief(contextID: String) throws -> EventBriefSnapshot? {
        try database.read { db in
            try fetchBrief(contextID: contextID, in: db)
        }
    }

    func fetchBrief(
        contextID: String,
        in db: Database
    ) throws -> EventBriefSnapshot? {
        guard let context = try EventContext.fetchOne(db, key: contextID),
              let link = try fetchLink(contextID: contextID, in: db) else {
            return nil
        }
        let tasks = try EventTask
            .filter(EventTask.Columns.contextID == contextID)
            .fetchAll(db)
            .sorted(by: Self.taskOrder)
        return EventBriefSnapshot(
            context: context,
            link: link,
            tasks: tasks
        )
    }

    func fetchLink(
        contextID: String,
        in db: Database
    ) throws -> EventLink? {
        try EventLink
            .filter(EventLink.Columns.contextID == contextID)
            .fetchOne(db)
    }

    func fetchAll() throws -> [EventContext] {
        try database.read { db in
            try EventContext.fetchAll(db).sorted {
                if $0.startSnapshot != $1.startSnapshot {
                    return ($0.startSnapshot ?? .distantFuture)
                        < ($1.startSnapshot ?? .distantFuture)
                }
                return $0.id < $1.id
            }
        }
    }

    func fetchRecoveryBriefs() throws -> [EventBriefSnapshot] {
        try database.read { db in
            let links = try EventLink.fetchAll(db)
                .filter {
                    $0.linkStatus == .missing
                        || $0.linkStatus == .orphaned
                }
                .sorted {
                    if $0.updatedAt != $1.updatedAt {
                        return $0.updatedAt > $1.updatedAt
                    }
                    return $0.contextID < $1.contextID
                }
            return try links.compactMap {
                try fetchBrief(contextID: $0.contextID, in: db)
            }
        }
    }

    func fetchAllBriefs() throws -> [EventBriefSnapshot] {
        try database.read { db in
            let links = try EventLink.fetchAll(db).sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.contextID < $1.contextID
            }
            return try links.compactMap {
                try fetchBrief(contextID: $0.contextID, in: db)
            }
        }
    }

    @discardableResult
    func reconcileTemporalLifecycle(
        at date: Date,
        calendar: Calendar,
        in db: Database
    ) throws -> [String] {
        let linksByContextID = Dictionary(
            uniqueKeysWithValues: try EventLink.fetchAll(db).map {
                ($0.contextID, $0)
            }
        )
        var changedContextIDs: [String] = []

        for var context in try EventContext.fetchAll(db) {
            guard context.lifecycleStatus == .scheduled
                    || context.lifecycleStatus == .completed,
                  let link = linksByContextID[context.id],
                  link.linkStatus == .active else {
                continue
            }
            let desiredStatus = Self.temporalLifecycleStatus(
                eventEnd: link.effectiveDateRange(calendar: calendar).end,
                at: date
            )
            guard context.lifecycleStatus != desiredStatus else { continue }
            context.lifecycleStatus = desiredStatus
            context.updatedAt = date
            try context.update(db)
            changedContextIDs.append(context.id)
        }

        return changedContextIDs.sorted()
    }

    func delete(contextID: String) throws {
        try database.write { db in
            try delete(contextID: contextID, in: db)
        }
    }

    func delete(contextID: String, in db: Database) throws {
        _ = try EventContext.deleteOne(db, key: contextID)
    }

    @discardableResult
    func markMissing(
        contextID: String,
        in db: Database
    ) throws -> EventBriefSnapshot {
        guard let context = try EventContext.fetchOne(db, key: contextID),
              var link = try fetchLink(contextID: contextID, in: db) else {
            throw ContextStoreError.missingContext(contextID)
        }
        guard link.linkStatus == .active || link.linkStatus == .missing else {
            throw ContextStoreError.invalidEventLinkTransition
        }
        if link.linkStatus == .active {
            link.linkStatus = .missing
            link.updatedAt = now()
            try link.update(db)
        }
        let tasks = try EventTask
            .filter(EventTask.Columns.contextID == contextID)
            .fetchAll(db)
            .sorted(by: Self.taskOrder)
        return EventBriefSnapshot(context: context, link: link, tasks: tasks)
    }

    @discardableResult
    func keepAsOrphan(
        contextID: String,
        in db: Database
    ) throws -> EventBriefSnapshot {
        guard var context = try EventContext.fetchOne(db, key: contextID),
              var link = try fetchLink(contextID: contextID, in: db) else {
            throw ContextStoreError.missingContext(contextID)
        }
        guard link.linkStatus == .missing || link.linkStatus == .orphaned else {
            throw ContextStoreError.invalidEventLinkTransition
        }
        let timestamp = now()
        context.lifecycleStatus = .orphaned
        context.updatedAt = timestamp
        link.linkStatus = .orphaned
        link.updatedAt = timestamp
        try context.update(db)
        try link.update(db)
        let tasks = try EventTask
            .filter(EventTask.Columns.contextID == contextID)
            .fetchAll(db)
            .sorted(by: Self.taskOrder)
        return EventBriefSnapshot(context: context, link: link, tasks: tasks)
    }

    func resolve(
        event: DisplayEvent,
        in db: Database
    ) throws -> EventContextResolution {
        let links = try EventLink.fetchAll(db)
        let snapshot = try EventLinkSnapshot(event: event)

        if let identifier = event.eventIdentifier, !identifier.isEmpty {
            let matches = links.filter {
                $0.eventIdentifier == identifier
                    && Self.occurrenceMatches(
                        link: $0,
                        eventSnapshot: snapshot
                    )
            }
            if let resolution = Self.strongResolution(
                matches,
                basis: .eventIdentifier
            ) { return resolution }
        }

        if let identifier = event.calendarItemIdentifier, !identifier.isEmpty {
            let matches = links.filter {
                $0.calendarItemIdentifier == identifier
                    && Self.occurrenceMatches(
                        link: $0,
                        eventSnapshot: snapshot
                    )
            }
            if let resolution = Self.strongResolution(
                matches,
                basis: .calendarItemIdentifier
            ) { return resolution }
        }

        if let identifier = event.calendarItemExternalIdentifier,
           !identifier.isEmpty {
            let matches = links.filter {
                $0.calendarItemExternalIdentifier == identifier
                    && $0.calendarIdentifier == event.calendarIdentifier
                    && Self.occurrenceMatches(
                        link: $0,
                        eventSnapshot: snapshot
                    )
            }
            if let resolution = Self.strongResolution(
                matches,
                basis: .externalIdentifierAndOccurrence
            ) { return resolution }
        }

        if event.isRecurring,
           let seriesIdentifier = snapshot.recurrenceSeriesIdentifier {
            let matches = links.filter {
                $0.calendarIdentifier == event.calendarIdentifier
                    && $0.recurrenceSeriesIdentifier == seriesIdentifier
                    && $0.occurrenceIdentityKey
                        == snapshot.occurrenceIdentityKey
            }
            if let resolution = Self.strongResolution(
                matches,
                basis: .recurrenceSeriesAndOccurrence
            ) { return resolution }
        }

        if !event.isRecurring {
            let matches = links.filter {
                Self.legacySyntheticSingleCandidateMatches(
                    link: $0,
                    eventSnapshot: snapshot
                )
            }
            if !matches.isEmpty {
                return Self.weakResolution(
                    matches,
                    basis: .legacySyntheticSingle
                )
            }
        }

        let exactSnapshotMatches = links.filter {
            $0.calendarIdentifier == event.calendarIdentifier
                && $0.titleSnapshot == event.title
                && Self.sameInstant($0.startSnapshot, event.startDate)
                && Self.sameInstant($0.endSnapshot, event.endDate)
                && $0.locationSnapshot == event.location
        }
        if !exactSnapshotMatches.isEmpty {
            return Self.weakResolution(
                exactSnapshotMatches,
                basis: .exactSnapshot
            )
        }

        let fingerprintMatches = links.filter {
            $0.fingerprint == snapshot.fingerprint
        }
        if !fingerprintMatches.isEmpty {
            return Self.weakResolution(
                fingerprintMatches,
                basis: .fingerprint
            )
        }

        return .notFound
    }

    func matchLinkedEvent(
        link: EventLink,
        among events: [DisplayEvent]
    ) throws -> EventNavigationResolution {
        let candidates = try events.map { event in
            (event: event, snapshot: try EventLinkSnapshot(event: event))
        }

        if let identifier = link.eventIdentifier, !identifier.isEmpty {
            let matches = candidates.filter {
                $0.snapshot.eventIdentifier == identifier
                    && Self.occurrenceMatches(
                        link: link,
                        eventSnapshot: $0.snapshot
                    )
            }
            if let resolution = Self.strongNavigationResolution(
                matches,
                basis: .eventIdentifier
            ) { return resolution }
        }

        if let identifier = link.calendarItemIdentifier,
           !identifier.isEmpty {
            let matches = candidates.filter {
                $0.snapshot.calendarItemIdentifier == identifier
                    && Self.occurrenceMatches(
                        link: link,
                        eventSnapshot: $0.snapshot
                    )
            }
            if let resolution = Self.strongNavigationResolution(
                matches,
                basis: .calendarItemIdentifier
            ) { return resolution }
        }

        if let identifier = link.calendarItemExternalIdentifier,
           !identifier.isEmpty {
            let matches = candidates.filter {
                $0.snapshot.calendarItemExternalIdentifier == identifier
                    && $0.snapshot.calendarIdentifier
                        == link.calendarIdentifier
                    && Self.occurrenceMatches(
                        link: link,
                        eventSnapshot: $0.snapshot
                    )
            }
            if let resolution = Self.strongNavigationResolution(
                matches,
                basis: .externalIdentifierAndOccurrence
            ) { return resolution }
        }

        if link.isRecurring,
           let seriesIdentifier = link.recurrenceSeriesIdentifier,
           !seriesIdentifier.isEmpty {
            let matches = candidates.filter {
                $0.snapshot.calendarIdentifier == link.calendarIdentifier
                    && $0.snapshot.recurrenceSeriesIdentifier
                        == seriesIdentifier
                    && $0.snapshot.occurrenceIdentityKey
                        == link.occurrenceIdentityKey
            }
            if let resolution = Self.strongNavigationResolution(
                matches,
                basis: .recurrenceSeriesAndOccurrence
            ) { return resolution }
        }

        if link.isRecurring {
            let matches = candidates.filter {
                Self.legacySyntheticSingleCandidateMatches(
                    link: link,
                    eventSnapshot: $0.snapshot
                )
            }
            if !matches.isEmpty {
                return Self.weakNavigationResolution(
                    matches,
                    basis: .legacySyntheticSingle
                )
            }
        }

        let exactSnapshotMatches = candidates.filter {
            $0.snapshot.calendarIdentifier == link.calendarIdentifier
                && $0.snapshot.title == link.titleSnapshot
                && Self.sameInstant(
                    $0.snapshot.startDate,
                    link.startSnapshot
                )
                && Self.sameInstant(
                    $0.snapshot.endDate,
                    link.endSnapshot
                )
                && $0.snapshot.location == link.locationSnapshot
        }
        if !exactSnapshotMatches.isEmpty {
            return Self.weakNavigationResolution(
                exactSnapshotMatches,
                basis: .exactSnapshot
            )
        }

        let fingerprintMatches = candidates.filter {
            $0.snapshot.fingerprint == link.fingerprint
        }
        if !fingerprintMatches.isEmpty {
            return Self.weakNavigationResolution(
                fingerprintMatches,
                basis: .fingerprint
            )
        }

        return .notFound
    }

    func count() throws -> Int {
        try database.read { db in
            try EventContext.fetchCount(db)
        }
    }

    func makeRecords(
        for event: DisplayEvent,
        notes: String
    ) throws -> (context: EventContext, link: EventLink) {
        let timestamp = now()
        let contextID = makeID()
        let snapshot = try EventLinkSnapshot(event: event)
        let context = EventContext(
            id: contextID,
            titleSnapshot: event.title,
            startSnapshot: event.startDate,
            endSnapshot: event.endDate,
            lifecycleStatus: .scheduled,
            notes: notes,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let link = EventLink(
            id: makeID(),
            contextID: contextID,
            eventIdentifier: snapshot.eventIdentifier,
            calendarItemIdentifier: snapshot.calendarItemIdentifier,
            calendarItemExternalIdentifier: snapshot.calendarItemExternalIdentifier,
            calendarIdentifier: snapshot.calendarIdentifier,
            sourceTitle: snapshot.sourceTitle,
            calendarTitleSnapshot: snapshot.calendarTitle,
            titleSnapshot: snapshot.title,
            startSnapshot: snapshot.startDate,
            endSnapshot: snapshot.endDate,
            locationSnapshot: snapshot.location,
            isAllDay: snapshot.isAllDay,
            isRecurring: snapshot.isRecurring,
            timeSemantics: snapshot.timeSemantics,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            startLocalComponents: snapshot.startLocalComponents,
            endLocalComponents: snapshot.endLocalComponents,
            recurrenceSeriesIdentifier: snapshot.recurrenceSeriesIdentifier,
            occurrenceDate: snapshot.occurrenceDate,
            occurrenceLocalComponents: snapshot.occurrenceLocalComponents,
            occurrenceIdentityKey: snapshot.occurrenceIdentityKey,
            isDetached: snapshot.isDetached,
            fingerprint: snapshot.fingerprint,
            seriesFingerprint: snapshot.seriesFingerprint,
            linkStatus: .active,
            lastSeenAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        return (context, link)
    }

    func insert(
        context: EventContext,
        link: EventLink,
        in db: Database
    ) throws {
        try context.insert(db)
        try link.insert(db)
    }

    @discardableResult
    func updateSnapshot(
        contextID: String,
        event: DisplayEvent,
        notes: String?,
        allowOrphanReactivation: Bool = false,
        in db: Database
    ) throws -> EventContext? {
        guard var context = try EventContext.fetchOne(db, key: contextID),
              var link = try EventLink
                .filter(EventLink.Columns.contextID == contextID)
                .fetchOne(db) else {
            return nil
        }
        guard link.linkStatus != .orphaned || allowOrphanReactivation else {
            return nil
        }
        let snapshot = try EventLinkSnapshot(event: event)
        let timestamp = now()

        context.titleSnapshot = snapshot.title
        context.startSnapshot = snapshot.startDate
        context.endSnapshot = snapshot.endDate
        if let notes {
            context.notes = notes
        }
        context.updatedAt = timestamp

        link.eventIdentifier = snapshot.eventIdentifier
        link.calendarItemIdentifier = snapshot.calendarItemIdentifier
        link.calendarItemExternalIdentifier = snapshot.calendarItemExternalIdentifier
        link.calendarIdentifier = snapshot.calendarIdentifier
        link.sourceTitle = snapshot.sourceTitle
        link.calendarTitleSnapshot = snapshot.calendarTitle
        link.titleSnapshot = snapshot.title
        link.startSnapshot = snapshot.startDate
        link.endSnapshot = snapshot.endDate
        link.locationSnapshot = snapshot.location
        link.isAllDay = snapshot.isAllDay
        link.isRecurring = snapshot.isRecurring
        link.timeSemantics = snapshot.timeSemantics
        link.timeZoneIdentifier = snapshot.timeZoneIdentifier
        link.startLocalComponents = snapshot.startLocalComponents
        link.endLocalComponents = snapshot.endLocalComponents
        link.recurrenceSeriesIdentifier = snapshot.recurrenceSeriesIdentifier
        link.occurrenceDate = snapshot.occurrenceDate
        link.occurrenceLocalComponents = snapshot.occurrenceLocalComponents
        link.occurrenceIdentityKey = snapshot.occurrenceIdentityKey
        link.isDetached = snapshot.isDetached
        link.fingerprint = snapshot.fingerprint
        link.seriesFingerprint = snapshot.seriesFingerprint
        link.linkStatus = .active
        link.lastSeenAt = timestamp
        link.updatedAt = timestamp

        try context.update(db)
        try link.update(db)
        return context
    }

    @discardableResult
    func relink(
        contextID: String,
        to event: DisplayEvent,
        at date: Date,
        calendar: Calendar,
        in db: Database
    ) throws -> EventBriefSnapshot {
        guard try updateSnapshot(
            contextID: contextID,
            event: event,
            notes: nil,
            allowOrphanReactivation: true,
            in: db
        ) != nil,
        var context = try EventContext.fetchOne(db, key: contextID),
        let link = try fetchLink(contextID: contextID, in: db) else {
            throw ContextStoreError.missingContext(contextID)
        }
        context.lifecycleStatus = Self.temporalLifecycleStatus(
            eventEnd: link.effectiveDateRange(calendar: calendar).end,
            at: date
        )
        context.updatedAt = date
        try context.update(db)
        let tasks = try EventTask
            .filter(EventTask.Columns.contextID == contextID)
            .fetchAll(db)
            .sorted(by: Self.taskOrder)
        return EventBriefSnapshot(context: context, link: link, tasks: tasks)
    }

    private static func occurrenceMatches(
        link: EventLink,
        eventSnapshot: EventLinkSnapshot
    ) -> Bool {
        if eventSnapshot.isRecurring {
            return link.isRecurring
                && link.occurrenceIdentityKey
                    == eventSnapshot.occurrenceIdentityKey
        }
        if !link.isRecurring {
            return link.occurrenceIdentityKey == "single:v1"
        }
        return legacySyntheticSingleMatches(
            link: link,
            eventSnapshot: eventSnapshot
        )
    }

    private static func legacySyntheticSingleMatches(
        link: EventLink,
        eventSnapshot: EventLinkSnapshot
    ) -> Bool {
        guard legacySyntheticSingleCandidateMatches(
                link: link,
                eventSnapshot: eventSnapshot
              ),
              link.titleSnapshot == eventSnapshot.title,
              link.locationSnapshot == eventSnapshot.location,
              sameInstant(link.startSnapshot, eventSnapshot.startDate),
              sameInstant(link.endSnapshot, eventSnapshot.endDate),
              link.isAllDay == eventSnapshot.isAllDay,
              link.timeSemantics == eventSnapshot.timeSemantics,
              link.timeZoneIdentifier == eventSnapshot.timeZoneIdentifier,
              link.startLocalComponents
                == eventSnapshot.startLocalComponents,
              link.endLocalComponents == eventSnapshot.endLocalComponents,
              link.fingerprint == eventSnapshot.fingerprint,
              let expectedSeriesIdentifier =
                EventIdentityFingerprint.firstNonEmpty(
                    eventSnapshot.calendarItemExternalIdentifier,
                    eventSnapshot.calendarItemIdentifier
                ),
              link.recurrenceSeriesIdentifier == expectedSeriesIdentifier else {
            return false
        }

        return true
    }

    private static func legacySyntheticSingleCandidateMatches(
        link: EventLink,
        eventSnapshot: EventLinkSnapshot
    ) -> Bool {
        guard !eventSnapshot.isRecurring,
              !eventSnapshot.isDetached,
              eventSnapshot.occurrenceIdentityKey == "single:v1",
              link.isRecurring,
              !link.isDetached,
              link.calendarIdentifier == eventSnapshot.calendarIdentifier,
              strongIdentifierMatches(
                link: link,
                eventSnapshot: eventSnapshot
              ),
              let storedSeriesIdentifier =
                EventIdentityFingerprint.firstNonEmpty(
                    link.calendarItemExternalIdentifier,
                    link.calendarItemIdentifier
                ),
              link.recurrenceSeriesIdentifier == storedSeriesIdentifier,
              link.seriesFingerprint != nil,
              sameInstant(link.occurrenceDate, link.startSnapshot) else {
            return false
        }

        switch link.timeSemantics {
        case .zoned:
            let milliseconds = Int64(
                (link.startSnapshot.timeIntervalSince1970 * 1_000).rounded()
            )
            return link.occurrenceIdentityKey
                == "instant:v1:\(milliseconds)"
        case .allDay, .floating:
            guard let startLocalComponents = link.startLocalComponents else {
                return false
            }
            return link.occurrenceLocalComponents == startLocalComponents
                && link.occurrenceIdentityKey
                    == "local:v1:\(startLocalComponents)"
        }
    }

    private static func strongIdentifierMatches(
        link: EventLink,
        eventSnapshot: EventLinkSnapshot
    ) -> Bool {
        if let identifier = eventSnapshot.eventIdentifier,
           !identifier.isEmpty,
           link.eventIdentifier == identifier {
            return true
        }
        if let identifier = eventSnapshot.calendarItemIdentifier,
           !identifier.isEmpty,
           link.calendarItemIdentifier == identifier {
            return true
        }
        if let identifier = eventSnapshot.calendarItemExternalIdentifier,
           !identifier.isEmpty,
           link.calendarItemExternalIdentifier == identifier {
            return true
        }
        return false
    }

    private static func sameInstant(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return abs(lhs.timeIntervalSince(rhs)) < 0.001
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private static func temporalLifecycleStatus(
        eventEnd: Date,
        at date: Date
    ) -> EventLifecycleStatus {
        date >= eventEnd ? .completed : .scheduled
    }

    private static func strongResolution(
        _ links: [EventLink],
        basis: EventIdentityMatchBasis
    ) -> EventContextResolution? {
        if links.contains(where: { $0.linkStatus == .orphaned }) {
            return weakResolution(links, basis: basis)
        }
        let contextIDs = uniqueContextIDs(links)
        if contextIDs.count == 1 {
            return .linked(contextID: contextIDs[0], basis: basis)
        }
        if contextIDs.count > 1 {
            return .ambiguous(contextIDs: contextIDs, basis: basis)
        }
        return nil
    }

    private static func weakResolution(
        _ links: [EventLink],
        basis: EventIdentityMatchBasis
    ) -> EventContextResolution {
        let contextIDs = uniqueContextIDs(links)
        if contextIDs.count == 1 {
            return .candidate(contextIDs: contextIDs, basis: basis)
        }
        return .ambiguous(contextIDs: contextIDs, basis: basis)
    }

    private static func strongNavigationResolution(
        _ candidates: [(event: DisplayEvent, snapshot: EventLinkSnapshot)],
        basis: EventIdentityMatchBasis
    ) -> EventNavigationResolution? {
        let events = uniqueDisplayEvents(candidates)
        if events.count == 1 {
            return .linked(event: events[0], basis: basis)
        }
        if events.count > 1 {
            return .ambiguous(
                eventIDs: events.map(\.id),
                basis: basis
            )
        }
        return nil
    }

    private static func weakNavigationResolution(
        _ candidates: [(event: DisplayEvent, snapshot: EventLinkSnapshot)],
        basis: EventIdentityMatchBasis
    ) -> EventNavigationResolution {
        let events = uniqueDisplayEvents(candidates)
        if events.count == 1 {
            return .confirmationRequired(
                eventIDs: [events[0].id],
                basis: basis
            )
        }
        return .ambiguous(
            eventIDs: events.map(\.id),
            basis: basis
        )
    }

    private static func uniqueDisplayEvents(
        _ candidates: [(event: DisplayEvent, snapshot: EventLinkSnapshot)]
    ) -> [DisplayEvent] {
        var seenIDs = Set<String>()
        return candidates
            .map { $0.event }
            .filter { seenIDs.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
    }

    private static func uniqueContextIDs(_ links: [EventLink]) -> [String] {
        Array(Set(links.map(\.contextID))).sorted()
    }

    private static func taskOrder(_ lhs: EventTask, _ rhs: EventTask) -> Bool {
        if lhs.section.sortRank != rhs.section.sortRank {
            return lhs.section.sortRank < rhs.section.sortRank
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}
