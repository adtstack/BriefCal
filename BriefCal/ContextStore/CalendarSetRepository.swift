import Foundation
import GRDB

enum CalendarSetRepositoryError: Error, Equatable {
    case emptyName
    case nameTooLong(maximum: Int)
    case duplicateName(String)
    case invalidCalendarIdentifier
    case missingCalendarSet(String)
    case missingMembership(String)
    case duplicateMembership(
        calendarSetID: String,
        calendarIdentifier: String
    )
    case staleMembership(
        membershipID: String,
        expectedCalendarIdentifier: String,
        actualCalendarIdentifier: String
    )
    case selectedCalendarOutsideAvailableScope(String)
    case invalidSetOrder
}

extension CalendarSetRepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Calendar Set name cannot be empty."
        case let .nameTooLong(maximum):
            "Calendar Set name cannot exceed \(maximum) characters."
        case let .duplicateName(name):
            "A Calendar Set named \(name) already exists."
        case .invalidCalendarIdentifier:
            "The calendar identifier is empty or invalid."
        case let .missingCalendarSet(id):
            "The saved Calendar Set is missing: \(id)."
        case let .missingMembership(id):
            "The saved Calendar Set membership is missing: \(id)."
        case let .duplicateMembership(calendarSetID, calendarIdentifier):
            "Calendar \(calendarIdentifier) already belongs to Calendar Set \(calendarSetID)."
        case let .staleMembership(membershipID, _, _):
            "Calendar Set membership \(membershipID) changed before it could be updated."
        case let .selectedCalendarOutsideAvailableScope(calendarIdentifier):
            "Calendar \(calendarIdentifier) is not in the current available-calendar snapshot."
        case .invalidSetOrder:
            "Calendar Set order does not match the saved sets."
        }
    }
}

final class CalendarSetRepository {
    static let maximumNameLength = 80

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

    func fetchAll() throws -> [SavedCalendarSetSnapshot] {
        try database.read { db in
            try fetchAll(in: db)
        }
    }

    func fetch(id: String) throws -> SavedCalendarSetSnapshot? {
        try database.read { db in
            try fetch(id: id, in: db)
        }
    }

    func create(
        name: String,
        calendars: [CalendarSource]
    ) throws -> SavedCalendarSetSnapshot {
        let normalizedName = try validatedName(name)
        let sources = try uniqueValidatedSources(calendars)

        return try database.write { db in
            try requireUniqueName(normalizedName, excludingID: nil, in: db)
            let timestamp = now()
            let calendarSet = SavedCalendarSet(
                id: makeID(),
                name: normalizedName,
                sortOrder: try nextSetSortOrder(in: db),
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try calendarSet.insert(db)

            var memberships: [CalendarSetMembership] = []
            memberships.reserveCapacity(sources.count)
            for (sortOrder, source) in sources.enumerated() {
                let membership = makeMembership(
                    calendarSetID: calendarSet.id,
                    source: source,
                    sortOrder: sortOrder,
                    timestamp: timestamp
                )
                try membership.insert(db)
                memberships.append(membership)
            }
            return SavedCalendarSetSnapshot(
                calendarSet: calendarSet,
                memberships: memberships
            )
        }
    }

    func rename(
        id: String,
        name: String
    ) throws -> SavedCalendarSetSnapshot {
        let normalizedName = try validatedName(name)
        return try database.write { db in
            guard var calendarSet = try SavedCalendarSet.fetchOne(db, key: id) else {
                throw CalendarSetRepositoryError.missingCalendarSet(id)
            }
            try requireUniqueName(normalizedName, excludingID: id, in: db)
            if calendarSet.name != normalizedName {
                calendarSet.name = normalizedName
                calendarSet.updatedAt = now()
                try calendarSet.update(db)
            }
            return try snapshot(for: calendarSet, in: db)
        }
    }

    @discardableResult
    func delete(id: String) throws -> Bool {
        try database.write { db in
            try SavedCalendarSet.deleteOne(db, key: id)
        }
    }

    func reorder(ids: [String]) throws {
        try database.write { db in
            let savedSets = try SavedCalendarSet.fetchAll(db)
            let currentIDs = Set(savedSets.map(\.id))
            guard ids.count == currentIDs.count,
                  Set(ids).count == ids.count,
                  Set(ids) == currentIDs else {
                throw CalendarSetRepositoryError.invalidSetOrder
            }

            let byID = Dictionary(uniqueKeysWithValues: savedSets.map { ($0.id, $0) })
            let timestamp = now()
            for (sortOrder, id) in ids.enumerated() {
                guard var calendarSet = byID[id] else {
                    throw CalendarSetRepositoryError.invalidSetOrder
                }
                guard calendarSet.sortOrder != sortOrder else { continue }
                calendarSet.sortOrder = sortOrder
                calendarSet.updatedAt = timestamp
                try calendarSet.update(db)
            }
        }
    }

    @discardableResult
    func add(
        _ source: CalendarSource,
        to setID: String
    ) throws -> CalendarSetMembership {
        try validateCalendarIdentifier(source.id)
        return try database.write { db in
            guard var calendarSet = try SavedCalendarSet.fetchOne(db, key: setID) else {
                throw CalendarSetRepositoryError.missingCalendarSet(setID)
            }
            if try membership(
                calendarSetID: setID,
                calendarIdentifier: source.id,
                in: db
            ) != nil {
                throw CalendarSetRepositoryError.duplicateMembership(
                    calendarSetID: setID,
                    calendarIdentifier: source.id
                )
            }

            let timestamp = now()
            let result = makeMembership(
                calendarSetID: setID,
                source: source,
                sortOrder: try nextMembershipSortOrder(calendarSetID: setID, in: db),
                timestamp: timestamp
            )
            try result.insert(db)
            try touch(&calendarSet, at: timestamp, in: db)
            return result
        }
    }

    @discardableResult
    func removeMembership(id: String) throws -> Bool {
        try database.write { db in
            guard let membership = try CalendarSetMembership.fetchOne(db, key: id) else {
                return false
            }
            let didDelete = try CalendarSetMembership.deleteOne(db, key: id)
            if didDelete,
               var calendarSet = try SavedCalendarSet.fetchOne(
                   db,
                   key: membership.calendarSetID
               ) {
                try touch(&calendarSet, at: now(), in: db)
            }
            return didDelete
        }
    }

    func rebindMembership(
        id: String,
        expectedCalendarIdentifier: String,
        to source: CalendarSource
    ) throws -> CalendarSetMembership {
        try validateCalendarIdentifier(source.id)
        return try database.write { db in
            guard var membership = try CalendarSetMembership.fetchOne(db, key: id) else {
                throw CalendarSetRepositoryError.missingMembership(id)
            }
            guard membership.calendarIdentifier == expectedCalendarIdentifier else {
                throw CalendarSetRepositoryError.staleMembership(
                    membershipID: id,
                    expectedCalendarIdentifier: expectedCalendarIdentifier,
                    actualCalendarIdentifier: membership.calendarIdentifier
                )
            }
            if let duplicate = try self.membership(
                calendarSetID: membership.calendarSetID,
                calendarIdentifier: source.id,
                in: db
            ), duplicate.id != id {
                throw CalendarSetRepositoryError.duplicateMembership(
                    calendarSetID: membership.calendarSetID,
                    calendarIdentifier: source.id
                )
            }

            let didChange = apply(source: source, to: &membership)
            guard didChange else { return membership }
            let timestamp = now()
            membership.updatedAt = timestamp
            try membership.update(db)
            if var calendarSet = try SavedCalendarSet.fetchOne(
                db,
                key: membership.calendarSetID
            ) {
                try touch(&calendarSet, at: timestamp, in: db)
            }
            return membership
        }
    }

    func updateAvailableMemberships(
        setID: String,
        availableCalendarIDs: Set<String>,
        selectedSources: [CalendarSource]
    ) throws -> SavedCalendarSetSnapshot {
        for calendarIdentifier in availableCalendarIDs {
            try validateCalendarIdentifier(calendarIdentifier)
        }
        let selected = try uniqueValidatedSources(selectedSources)
        for source in selected where !availableCalendarIDs.contains(source.id) {
            throw CalendarSetRepositoryError.selectedCalendarOutsideAvailableScope(
                source.id
            )
        }
        let selectedByID = Dictionary(
            uniqueKeysWithValues: selected.map { ($0.id, $0) }
        )

        return try database.write { db in
            guard var calendarSet = try SavedCalendarSet.fetchOne(db, key: setID) else {
                throw CalendarSetRepositoryError.missingCalendarSet(setID)
            }
            let existing = try memberships(calendarSetID: setID, in: db)
            let existingByCalendarID = Dictionary(
                uniqueKeysWithValues: existing.map { ($0.calendarIdentifier, $0) }
            )
            var didMutate = false
            let timestamp = now()

            for membership in existing
            where availableCalendarIDs.contains(membership.calendarIdentifier)
                && selectedByID[membership.calendarIdentifier] == nil {
                _ = try CalendarSetMembership.deleteOne(db, key: membership.id)
                didMutate = true
            }

            var nextSortOrder = try nextMembershipSortOrder(
                calendarSetID: setID,
                in: db
            )
            for source in selected {
                if var membership = existingByCalendarID[source.id] {
                    if apply(source: source, to: &membership) {
                        membership.updatedAt = timestamp
                        try membership.update(db)
                        didMutate = true
                    }
                } else {
                    let membership = makeMembership(
                        calendarSetID: setID,
                        source: source,
                        sortOrder: nextSortOrder,
                        timestamp: timestamp
                    )
                    nextSortOrder += 1
                    try membership.insert(db)
                    didMutate = true
                }
            }

            if didMutate {
                try touch(&calendarSet, at: timestamp, in: db)
            }
            return try snapshot(for: calendarSet, in: db)
        }
    }

    func fetchSelection() throws -> CalendarSetFilter {
        try database.read { db in
            guard let record = try CalendarSetSelectionRecord.fetchOne(
                db,
                key: CalendarSetSelectionRecord.singletonID
            ) else {
                return .all
            }
            switch record.selectionKind {
            case .role:
                guard let role = record.role else { return .all }
                return .role(role)
            case .saved:
                guard let setID = record.calendarSetID,
                      try SavedCalendarSet.fetchOne(db, key: setID) != nil else {
                    return .all
                }
                return .saved(setID)
            }
        }
    }

    func saveSelection(_ selection: CalendarSetFilter) throws {
        try database.write { db in
            switch selection {
            case .all:
                _ = try CalendarSetSelectionRecord.deleteOne(
                    db,
                    key: CalendarSetSelectionRecord.singletonID
                )
            case let .role(role):
                let record = CalendarSetSelectionRecord(
                    singletonID: CalendarSetSelectionRecord.singletonID,
                    selectionKind: .role,
                    role: role,
                    calendarSetID: nil,
                    updatedAt: now()
                )
                try record.save(db)
            case let .saved(rawSetID):
                guard let setID = CalendarSetFilter(
                    savedSetIdentifier: rawSetID
                )?.savedSetIdentifier,
                      try SavedCalendarSet.fetchOne(db, key: setID) != nil else {
                    throw CalendarSetRepositoryError.missingCalendarSet(rawSetID)
                }
                let record = CalendarSetSelectionRecord(
                    singletonID: CalendarSetSelectionRecord.singletonID,
                    selectionKind: .saved,
                    role: nil,
                    calendarSetID: setID,
                    updatedAt: now()
                )
                try record.save(db)
            }
        }
    }

    func count() throws -> Int {
        try database.read { db in
            try SavedCalendarSet.fetchCount(db)
        }
    }

    func membershipCount() throws -> Int {
        try database.read { db in
            try CalendarSetMembership.fetchCount(db)
        }
    }

    private func fetchAll(in db: Database) throws -> [SavedCalendarSetSnapshot] {
        let savedSets = try SavedCalendarSet.fetchAll(db).sorted(by: setOrder)
        let groupedMemberships = Dictionary(
            grouping: try CalendarSetMembership.fetchAll(db),
            by: \.calendarSetID
        )
        return savedSets.map { calendarSet in
            SavedCalendarSetSnapshot(
                calendarSet: calendarSet,
                memberships: (groupedMemberships[calendarSet.id] ?? [])
                    .sorted(by: membershipOrder)
            )
        }
    }

    private func fetch(
        id: String,
        in db: Database
    ) throws -> SavedCalendarSetSnapshot? {
        guard let calendarSet = try SavedCalendarSet.fetchOne(db, key: id) else {
            return nil
        }
        return try snapshot(for: calendarSet, in: db)
    }

    private func snapshot(
        for calendarSet: SavedCalendarSet,
        in db: Database
    ) throws -> SavedCalendarSetSnapshot {
        SavedCalendarSetSnapshot(
            calendarSet: calendarSet,
            memberships: try memberships(
                calendarSetID: calendarSet.id,
                in: db
            )
        )
    }

    private func memberships(
        calendarSetID: String,
        in db: Database
    ) throws -> [CalendarSetMembership] {
        try CalendarSetMembership
            .filter(Column("calendar_set_id") == calendarSetID)
            .fetchAll(db)
            .sorted(by: membershipOrder)
    }

    private func membership(
        calendarSetID: String,
        calendarIdentifier: String,
        in db: Database
    ) throws -> CalendarSetMembership? {
        try CalendarSetMembership
            .filter(Column("calendar_set_id") == calendarSetID)
            .filter(Column("calendar_identifier") == calendarIdentifier)
            .fetchOne(db)
    }

    private func validatedName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CalendarSetRepositoryError.emptyName
        }
        guard normalized.unicodeScalars.count <= Self.maximumNameLength else {
            throw CalendarSetRepositoryError.nameTooLong(
                maximum: Self.maximumNameLength
            )
        }
        return normalized
    }

    private func requireUniqueName(
        _ name: String,
        excludingID: String?,
        in db: Database
    ) throws {
        let duplicateCount: Int
        if let excludingID {
            duplicateCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM calendar_sets
                    WHERE name = ? COLLATE NOCASE AND id <> ?
                    """,
                arguments: [name, excludingID]
            ) ?? 0
        } else {
            duplicateCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM calendar_sets
                    WHERE name = ? COLLATE NOCASE
                    """,
                arguments: [name]
            ) ?? 0
        }
        guard duplicateCount == 0 else {
            throw CalendarSetRepositoryError.duplicateName(name)
        }
    }

    private func uniqueValidatedSources(
        _ sources: [CalendarSource]
    ) throws -> [CalendarSource] {
        var seen: Set<String> = []
        var result: [CalendarSource] = []
        result.reserveCapacity(sources.count)
        for source in sources {
            try validateCalendarIdentifier(source.id)
            if seen.insert(source.id).inserted {
                result.append(source)
            }
        }
        return result
    }

    private func validateCalendarIdentifier(_ identifier: String) throws {
        guard !identifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw CalendarSetRepositoryError.invalidCalendarIdentifier
        }
    }

    private func makeMembership(
        calendarSetID: String,
        source: CalendarSource,
        sortOrder: Int,
        timestamp: Date
    ) -> CalendarSetMembership {
        CalendarSetMembership(
            id: makeID(),
            calendarSetID: calendarSetID,
            calendarIdentifier: source.id,
            sourceIdentifierSnapshot: source.sourceIdentifier,
            sourceTitleSnapshot: source.sourceTitle,
            calendarTitleSnapshot: source.title,
            sortOrder: sortOrder,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func apply(
        source: CalendarSource,
        to membership: inout CalendarSetMembership
    ) -> Bool {
        let didChange = membership.calendarIdentifier != source.id
            || membership.sourceIdentifierSnapshot != source.sourceIdentifier
            || membership.sourceTitleSnapshot != source.sourceTitle
            || membership.calendarTitleSnapshot != source.title
        membership.calendarIdentifier = source.id
        membership.sourceIdentifierSnapshot = source.sourceIdentifier
        membership.sourceTitleSnapshot = source.sourceTitle
        membership.calendarTitleSnapshot = source.title
        return didChange
    }

    private func touch(
        _ calendarSet: inout SavedCalendarSet,
        at timestamp: Date,
        in db: Database
    ) throws {
        calendarSet.updatedAt = timestamp
        try calendarSet.update(db)
    }

    private func nextSetSortOrder(in db: Database) throws -> Int {
        let maximum = try Int.fetchOne(
            db,
            sql: "SELECT MAX(sort_order) FROM calendar_sets"
        )
        return (maximum ?? -1) + 1
    }

    private func nextMembershipSortOrder(
        calendarSetID: String,
        in db: Database
    ) throws -> Int {
        let maximum = try Int.fetchOne(
            db,
            sql: """
                SELECT MAX(sort_order)
                FROM calendar_set_memberships
                WHERE calendar_set_id = ?
                """,
            arguments: [calendarSetID]
        )
        return (maximum ?? -1) + 1
    }

    private func setOrder(
        _ lhs: SavedCalendarSet,
        _ rhs: SavedCalendarSet
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }

    private func membershipOrder(
        _ lhs: CalendarSetMembership,
        _ rhs: CalendarSetMembership
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}
