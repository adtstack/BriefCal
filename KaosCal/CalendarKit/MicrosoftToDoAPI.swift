import Foundation

/// Microsoft Graph To Do transport boundary. Delta links are opaque and are
/// persisted unchanged by the coordinator; this type never derives or logs
/// tenant/account identifiers from them.
enum MicrosoftToDoAPI {
    static let baseURL = URL(string: "https://graph.microsoft.com/v1.0/me/todo")!

    static func listsRequest(
        accessToken: String,
        nextLink: URL? = nil
    ) -> URLRequest {
        if let nextLink {
            var request = URLRequest(url: nextLink)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
        return request(path: "lists", accessToken: accessToken)
    }

    static func tasksRequest(listID: String, accessToken: String) -> URLRequest {
        request(path: "lists/\(component(listID))/tasks", accessToken: accessToken)
    }

    static func taskRequest(
        listID: String,
        taskID: String,
        accessToken: String
    ) -> URLRequest {
        request(
            path: "lists/\(component(listID))/tasks/\(component(taskID))",
            accessToken: accessToken
        )
    }

    static func deltaRequest(listID: String, deltaLink: URL?, accessToken: String) -> URLRequest {
        if let deltaLink {
            var request = URLRequest(url: deltaLink)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
        return request(path: "lists/\(component(listID))/tasks/delta", accessToken: accessToken)
    }

    static func createTaskRequest(
        listID: String,
        title: String,
        body: String,
        dueAt: Date?,
        deepLink: URL?,
        accessToken: String
    ) throws -> URLRequest {
        var request = tasksRequest(listID: listID, accessToken: accessToken)
        request.httpMethod = "POST"
        var payload = taskBody(
            title: title, body: body, dueAt: dueAt, completed: nil
        )
        if let deepLink {
            payload["linkedResources"] = [[
                "webUrl": deepLink.absoluteString,
                "applicationName": "KaosCal",
                "displayName": "Open in KaosCal",
                "externalId": deepLink.absoluteString
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    static func updateTaskRequest(listID: String, taskID: String, patch: RemoteTaskPatch, expectedVersion: String?, accessToken: String) throws -> URLRequest {
        var request = request(path: "lists/\(component(listID))/tasks/\(component(taskID))", accessToken: accessToken)
        request.httpMethod = "PATCH"
        if let expectedVersion { request.setValue(expectedVersion, forHTTPHeaderField: "If-Match") }
        request.httpBody = try JSONSerialization.data(withJSONObject: taskPatchBody(patch))
        return request
    }

    static func deleteTaskRequest(listID: String, taskID: String, expectedVersion: String?, accessToken: String) -> URLRequest {
        var request = request(path: "lists/\(component(listID))/tasks/\(component(taskID))", accessToken: accessToken)
        request.httpMethod = "DELETE"
        if let expectedVersion { request.setValue(expectedVersion, forHTTPHeaderField: "If-Match") }
        return request
    }

    private static func request(path: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The Graph API returns dateTimeTimeZone values. Asking for UTC keeps
        // the persisted task projection deterministic across device time zones.
        request.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")
        return request
    }

    private static func taskBody(title: String?, body: String?, dueAt: Date?, completed: Bool?) -> [String: Any] {
        var result = [String: Any]()
        if let title { result["title"] = title }
        if let body { result["body"] = ["contentType": "text", "content": body] }
        if let dueAt { result["dueDateTime"] = graphDateTime(dueAt) }
        if let completed { result["status"] = completed ? "completed" : "notStarted" }
        return result
    }

    private static func taskPatchBody(_ patch: RemoteTaskPatch) -> [String: Any] {
        var result = taskBody(
            title: patch.title,
            body: patch.notes,
            dueAt: nil,
            completed: patch.isCompleted
        )
        // A double optional distinguishes no due-date change from a requested
        // clear. Graph requires JSON null for the latter.
        if let dueAt = patch.dueAt {
            result["dueDateTime"] = dueAt.map(graphDateTime) ?? NSNull()
        }
        return result
    }

    private static func graphDateTime(_ date: Date) -> [String: String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return ["dateTime": formatter.string(from: date), "timeZone": "UTC"]
    }

    private static func component(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
