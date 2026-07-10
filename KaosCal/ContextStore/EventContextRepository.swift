import Foundation
import GRDB

struct EventBriefSnapshot: Equatable {
    let context: EventContext
    let link: EventLink
    let tasks: [EventTask]
}

enum EventIdentityMatchBasis: Equatable {
    case eventIdentifier
    case calendarItemIdentifier
    case externalIdentifierAndOccurrence
    case recurrenceSeriesAndOccurrence
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
            guard let context = try EventContext.fetchOne(db, key: contextID),
                  let link = try EventLink
                    .filter(EventLink.Columns.contextID == contextID)
                    .fetchOne(db) else {
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

    func delete(contextID: String) throws {
        try database.write { db in
            _ = try EventContext.deleteOne(db, key: contextID)
        }
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
                        eventIsRecurring: event.isRecurring,
                        occurrenceIdentityKey: snapshot.occurrenceIdentityKey
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
                        eventIsRecurring: event.isRecurring,
                        occurrenceIdentityKey: snapshot.occurrenceIdentityKey
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
                        eventIsRecurring: event.isRecurring,
                        occurrenceIdentityKey: snapshot.occurrenceIdentityKey
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
        in db: Database
    ) throws -> EventContext? {
        guard var context = try EventContext.fetchOne(db, key: contextID),
              var link = try EventLink
                .filter(EventLink.Columns.contextID == contextID)
                .fetchOne(db) else {
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

    private static func occurrenceMatches(
        link: EventLink,
        eventIsRecurring: Bool,
        occurrenceIdentityKey: String
    ) -> Bool {
        if eventIsRecurring {
            return link.isRecurring
                && link.occurrenceIdentityKey == occurrenceIdentityKey
        }
        return !link.isRecurring
            && link.occurrenceIdentityKey == "single:v1"
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

    private static func strongResolution(
        _ links: [EventLink],
        basis: EventIdentityMatchBasis
    ) -> EventContextResolution? {
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
