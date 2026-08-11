import Foundation

/// Google Tasks stores a civil due date in an RFC 3339-shaped field but
/// discards its time. Converting a local midnight directly to UTC can move the
/// date backward or forward, so encode and decode the calendar day explicitly.
struct GoogleTaskDueDateCodec {
    private let calendar: Calendar

    init(timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    func encode(_ date: Date) -> String? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        return String(
            format: "%04d-%02d-%02dT00:00:00.000Z",
            locale: Locale(identifier: "en_US_POSIX"),
            year,
            month,
            day
        )
    }

    func decode(_ value: String) -> Date? {
        let datePart = value.prefix(10)
        let parts = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day else {
            return nil
        }
        return date
    }
}

/// Transport-level Google Tasks adapter. It deliberately has no EventKit or
/// SQLite dependency so request/etag behavior can be tested without an account.
enum GoogleTasksAPI {
    static let baseURL = URL(string: "https://tasks.googleapis.com/tasks/v1")!

    static func taskListsRequest(
        accessToken: String,
        pageToken: String? = nil
    ) -> URLRequest {
        request(
            path: "/users/@me/lists",
            query: pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [],
            accessToken: accessToken
        )
    }

    static func taskRequest(
        listID: String,
        taskID: String,
        accessToken: String
    ) -> URLRequest {
        request(
            path: "/lists/\(pathComponent(listID))/tasks/\(pathComponent(taskID))",
            accessToken: accessToken
        )
    }

    static func tasksRequest(
        listID: String,
        pageToken: String? = nil,
        accessToken: String
    ) -> URLRequest {
        var query = [
            URLQueryItem(name: "showCompleted", value: "true"),
            URLQueryItem(name: "showHidden", value: "true"),
            URLQueryItem(name: "maxResults", value: "100")
        ]
        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return request(
            path: "/lists/\(pathComponent(listID))/tasks",
            query: query,
            accessToken: accessToken
        )
    }

    static func createTaskRequest(
        listID: String,
        title: String,
        notes: String,
        dueAt: Date?,
        accessToken: String,
        dueDateCodec: GoogleTaskDueDateCodec = GoogleTaskDueDateCodec()
    ) throws -> URLRequest {
        var request = request(
            path: "/lists/\(pathComponent(listID))/tasks",
            accessToken: accessToken
        )
        request.httpMethod = "POST"
        var body: [String: Any] = ["title": title, "notes": notes]
        if let dueAt, let due = dueDateCodec.encode(dueAt) {
            body["due"] = due
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func updateTaskRequest(
        listID: String,
        taskID: String,
        patch: RemoteTaskPatch,
        expectedETag: String?,
        accessToken: String,
        dueDateCodec: GoogleTaskDueDateCodec = GoogleTaskDueDateCodec()
    ) throws -> URLRequest {
        var request = request(
            path: "/lists/\(pathComponent(listID))/tasks/\(pathComponent(taskID))",
            accessToken: accessToken
        )
        request.httpMethod = "PATCH"
        if let expectedETag { request.setValue(expectedETag, forHTTPHeaderField: "If-Match") }
        var body = [String: Any]()
        if let title = patch.title { body["title"] = title }
        if let notes = patch.notes { body["notes"] = notes }
        if let duePatch = patch.dueAt {
            if let dueAt = duePatch,
               let due = dueDateCodec.encode(dueAt) {
                body["due"] = due
            } else {
                body["due"] = NSNull()
            }
        }
        if let completed = patch.isCompleted {
            body["status"] = completed ? "completed" : "needsAction"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func deleteTaskRequest(listID: String, taskID: String, expectedETag: String?, accessToken: String) -> URLRequest {
        var request = taskRequest(listID: listID, taskID: taskID, accessToken: accessToken)
        request.httpMethod = "DELETE"
        if let expectedETag { request.setValue(expectedETag, forHTTPHeaderField: "If-Match") }
        return request
    }

    private static func request(
        path: String,
        query: [URLQueryItem] = [],
        accessToken: String
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(
            path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        ), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

}
