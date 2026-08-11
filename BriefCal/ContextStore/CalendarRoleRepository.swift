import Foundation
import GRDB

final class CalendarRoleRepository {
    private let database: AppDatabase
    private let now: () -> Date

    init(
        database: AppDatabase,
        now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.now = now
    }

    func fetchAll() throws -> [CalendarRolePreference] {
        try database.read { db in
            try CalendarRolePreference.fetchAll(db).sorted {
                if $0.sourceTitleSnapshot != $1.sourceTitleSnapshot {
                    return $0.sourceTitleSnapshot.localizedCaseInsensitiveCompare(
                        $1.sourceTitleSnapshot
                    ) == .orderedAscending
                }
                if $0.calendarTitleSnapshot != $1.calendarTitleSnapshot {
                    return $0.calendarTitleSnapshot.localizedCaseInsensitiveCompare(
                        $1.calendarTitleSnapshot
                    ) == .orderedAscending
                }
                return $0.calendarIdentifier < $1.calendarIdentifier
            }
        }
    }

    func fetch(
        calendarIdentifier: String
    ) throws -> CalendarRolePreference? {
        try database.read { db in
            try CalendarRolePreference.fetchOne(
                db,
                key: calendarIdentifier
            )
        }
    }

    @discardableResult
    func upsert(
        source: CalendarSource,
        role: CalendarRole
    ) throws -> CalendarRolePreference {
        try database.write { db in
            let timestamp = now()
            if var preference = try CalendarRolePreference.fetchOne(
                db,
                key: source.id
            ) {
                preference.sourceTitleSnapshot = source.sourceTitle
                preference.calendarTitleSnapshot = source.title
                preference.role = role
                preference.updatedAt = timestamp
                try preference.update(db)
                return preference
            }

            let preference = CalendarRolePreference(
                calendarIdentifier: source.id,
                sourceTitleSnapshot: source.sourceTitle,
                calendarTitleSnapshot: source.title,
                role: role,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try preference.insert(db)
            return preference
        }
    }

    @discardableResult
    func delete(calendarIdentifier: String) throws -> Bool {
        try database.write { db in
            try CalendarRolePreference.deleteOne(
                db,
                key: calendarIdentifier
            )
        }
    }

    @discardableResult
    func reset() throws -> Int {
        try database.write { db in
            try CalendarRolePreference.deleteAll(db)
        }
    }

    func count() throws -> Int {
        try database.read { db in
            try CalendarRolePreference.fetchCount(db)
        }
    }
}

final class CalendarUsagePreferenceRepository {
    private let database: AppDatabase
    private let now: () -> Date

    init(
        database: AppDatabase,
        now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.now = now
    }

    func fetchAll() throws -> [CalendarUsagePreference] {
        try database.read { db in
            try CalendarUsagePreference.fetchAll(db).sorted {
                if $0.sourceTitleSnapshot != $1.sourceTitleSnapshot {
                    return $0.sourceTitleSnapshot.localizedCaseInsensitiveCompare(
                        $1.sourceTitleSnapshot
                    ) == .orderedAscending
                }
                if $0.calendarTitleSnapshot != $1.calendarTitleSnapshot {
                    return $0.calendarTitleSnapshot.localizedCaseInsensitiveCompare(
                        $1.calendarTitleSnapshot
                    ) == .orderedAscending
                }
                return $0.calendarIdentifier < $1.calendarIdentifier
            }
        }
    }

    func fetch(
        calendarIdentifier: String
    ) throws -> CalendarUsagePreference? {
        try database.read { db in
            try CalendarUsagePreference.fetchOne(
                db,
                key: calendarIdentifier
            )
        }
    }

    func setVisibility(
        _ value: Bool?,
        for sources: [CalendarSource]
    ) throws {
        try update(sources: sources) { preference in
            preference.visibilityOverride = value
        }
    }

    func setBlocksAvailability(
        _ value: Bool?,
        for sources: [CalendarSource]
    ) throws {
        try update(sources: sources) { preference in
            preference.blockingOverride = value
        }
    }

    @discardableResult
    func delete(calendarIdentifier: String) throws -> Bool {
        try database.write { db in
            try CalendarUsagePreference.deleteOne(
                db,
                key: calendarIdentifier
            )
        }
    }

    @discardableResult
    func reset() throws -> Int {
        try database.write { db in
            try CalendarUsagePreference.deleteAll(db)
        }
    }

    func count() throws -> Int {
        try database.read { db in
            try CalendarUsagePreference.fetchCount(db)
        }
    }

    private func update(
        sources: [CalendarSource],
        mutation: (inout CalendarUsagePreference) -> Void
    ) throws {
        try database.write { db in
            let timestamp = now()
            for source in sources {
                var preference = try CalendarUsagePreference.fetchOne(
                    db,
                    key: source.id
                ) ?? CalendarUsagePreference(
                    calendarIdentifier: source.id,
                    sourceIdentifierSnapshot: source.sourceIdentifier,
                    sourceTitleSnapshot: source.sourceTitle,
                    calendarTitleSnapshot: source.title,
                    visibilityOverride: nil,
                    blockingOverride: nil,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )

                preference.sourceIdentifierSnapshot = source.sourceIdentifier
                preference.sourceTitleSnapshot = source.sourceTitle
                preference.calendarTitleSnapshot = source.title
                mutation(&preference)

                if preference.visibilityOverride == nil,
                   preference.blockingOverride == nil {
                    _ = try CalendarUsagePreference.deleteOne(
                        db,
                        key: source.id
                    )
                } else if try CalendarUsagePreference.fetchOne(
                    db,
                    key: source.id
                ) == nil {
                    try preference.insert(db)
                } else {
                    preference.updatedAt = timestamp
                    try preference.update(db)
                }
            }
        }
    }
}
