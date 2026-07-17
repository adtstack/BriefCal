import Foundation

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
        accessToken: String
    ) throws -> URLRequest {
        var request = request(
            path: "/lists/\(pathComponent(listID))/tasks",
            accessToken: accessToken
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body(
            title: title, notes: notes, dueAt: dueAt, completed: nil
        ))
        return request
    }

    static func updateTaskRequest(
        listID: String,
        taskID: String,
        patch: RemoteTaskPatch,
        expectedETag: String?,
        accessToken: String
    ) throws -> URLRequest {
        var request = request(
            path: "/lists/\(pathComponent(listID))/tasks/\(pathComponent(taskID))",
            accessToken: accessToken
        )
        request.httpMethod = "PATCH"
        if let expectedETag { request.setValue(expectedETag, forHTTPHeaderField: "If-Match") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(
            title: patch.title,
            notes: patch.notes,
            dueAt: patch.dueAt ?? nil,
            completed: patch.isCompleted
        ))
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

    private static func body(title: String?, notes: String?, dueAt: Date?, completed: Bool?) -> [String: Any] {
        var result = [String: Any]()
        if let title { result["title"] = title }
        if let notes { result["notes"] = notes }
        // Google Tasks keeps the due date and discards the time. T2 must not
        // auto-link a timed due value to this provider without an explicit UI choice.
        if let dueAt { result["due"] = ISO8601DateFormatter().string(from: dueAt) }
        if let completed { result["status"] = completed ? "completed" : "needsAction" }
        return result
    }
}
