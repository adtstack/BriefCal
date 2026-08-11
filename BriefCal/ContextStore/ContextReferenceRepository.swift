import Foundation
import GRDB

final class ContextReferenceRepository {
    private let database: AppDatabase
    private let now: () -> Date
    private let makeID: () -> String

    init(database: AppDatabase, now: @escaping () -> Date, makeID: @escaping () -> String) {
        self.database = database
        self.now = now
        self.makeID = makeID
    }

    func fetch(contextID: String) throws -> [ContextReference] {
        try database.read { db in
            try ContextReference.filter(Column("context_id") == contextID).order(Column("created_at")).fetchAll(db)
        }
    }

    func add(contextID: String, provider: ContextReferenceProvider, url: URL, title: String) throws -> ContextReference {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            throw TaskProviderError.providerFailure("References must use an HTTP or HTTPS URL.")
        }
        let timestamp = now()
        let reference = ContextReference(id: makeID(), contextID: contextID, provider: provider, url: url, titleCache: title, state: .active, lastCheckedAt: nil, createdAt: timestamp, updatedAt: timestamp)
        try database.write { db in try reference.insert(db) }
        return reference
    }

    func delete(id: String, contextID: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM context_references WHERE id = ? AND context_id = ?", arguments: [id, contextID])
        }
    }
}
