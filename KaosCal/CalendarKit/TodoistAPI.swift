import Foundation

/// Todoist API v1 transport boundary. Webhooks are intentionally excluded:
/// this desktop app has no authenticated public callback server, so refresh is
/// the only supported remote-change notification mechanism in T2.
enum TodoistAPI {
    static let baseURL = URL(string: "https://api.todoist.com/api/v1")!

    static func projectsRequest(accessToken: String, cursor: String? = nil) -> URLRequest {
        request(path: "projects", query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [], accessToken: accessToken)
    }

    static func sectionsRequest(accessToken: String, cursor: String? = nil) -> URLRequest {
        request(path: "sections", query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [], accessToken: accessToken)
    }

    static func taskRequest(id: String, accessToken: String) -> URLRequest {
        request(path: "tasks/\(component(id))", accessToken: accessToken)
    }

    static func createTaskRequest(parentID: String, title: String, description: String, dueAt: Date?, accessToken: String) throws -> URLRequest {
        var request = request(path: "tasks", accessToken: accessToken)
        request.httpMethod = "POST"
        var body: [String: Any] = ["content": title, "description": description]
        apply(parentID: parentID, to: &body)
        if let dueAt { body["due_datetime"] = ISO8601DateFormatter().string(from: dueAt) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func updateTaskRequest(id: String, patch: RemoteTaskPatch, accessToken: String) throws -> URLRequest {
        var request = taskRequest(id: id, accessToken: accessToken)
        request.httpMethod = "POST"
        var body = [String: Any]()
        if let title = patch.title { body["content"] = title }
        if let notes = patch.notes { body["description"] = notes }
        if let dueAt = patch.dueAt {
            body["due_datetime"] = dueAt.map {
                ISO8601DateFormatter().string(from: $0)
            } ?? NSNull()
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func completionRequest(id: String, completed: Bool, accessToken: String) -> URLRequest {
        var request = request(path: "tasks/\(component(id))/\(completed ? "close" : "reopen")", accessToken: accessToken)
        request.httpMethod = "POST"
        return request
    }

    static func deleteTaskRequest(id: String, accessToken: String) -> URLRequest {
        var request = taskRequest(id: id, accessToken: accessToken)
        request.httpMethod = "DELETE"
        return request
    }

    static func completedTasksRequest(
        parentID: String,
        since: Date,
        until: Date,
        cursor: String? = nil,
        accessToken: String
    ) -> URLRequest {
        let formatter = ISO8601DateFormatter()
        var query = [
            URLQueryItem(name: "since", value: formatter.string(from: since)),
            URLQueryItem(name: "until", value: formatter.string(from: until))
        ]
        if parentID.hasPrefix("section:") {
            query.append(URLQueryItem(
                name: "section_id",
                value: String(parentID.dropFirst("section:".count))
            ))
        } else {
            query.append(URLQueryItem(
                name: "project_id",
                value: parentID.hasPrefix("project:")
                    ? String(parentID.dropFirst("project:".count))
                    : parentID
            ))
        }
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return request(
            path: "tasks/completed/by_completion_date",
            query: query,
            accessToken: accessToken
        )
    }

    private static func request(path: String, query: [URLQueryItem] = [], accessToken: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func apply(parentID: String, to body: inout [String: Any]) {
        if parentID.hasPrefix("section:") {
            body["section_id"] = String(parentID.dropFirst("section:".count))
        } else {
            body["project_id"] = parentID.hasPrefix("project:")
                ? String(parentID.dropFirst("project:".count))
                : parentID
        }
    }

    private static func component(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
