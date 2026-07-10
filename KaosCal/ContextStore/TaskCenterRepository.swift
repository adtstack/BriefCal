import Foundation
import GRDB

final class TaskCenterRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetch(
        list: TaskCenterList,
        now currentDate: Date,
        calendar: Calendar
    ) throws -> [TaskCenterItem] {
        let items = try database.read { db -> [TaskCenterItem] in
            let contexts = Dictionary(
                uniqueKeysWithValues: try EventContext.fetchAll(db).map {
                    ($0.id, $0)
                }
            )
            let links = Dictionary(
                uniqueKeysWithValues: try EventLink.fetchAll(db).map {
                    ($0.contextID, $0)
                }
            )
            let eventItems: [TaskCenterItem] = try EventTask
                .fetchAll(db)
                .compactMap { task -> TaskCenterItem? in
                guard let context = contexts[task.contextID],
                      let link = links[task.contextID] else {
                    return nil
                }
                let eventRange = link.effectiveDateRange(calendar: calendar)
                return TaskCenterItem(
                    id: .eventTask(
                        taskID: task.id,
                        contextID: context.id
                    ),
                    title: task.title,
                    isCompleted: task.isCompleted,
                    dueAt: task.effectiveDueDate(
                        eventStart: eventRange.start,
                        eventEnd: eventRange.end
                    ),
                    completedAt: task.completedAt,
                    sortOrder: task.sortOrder,
                    source: .event(
                        contextID: context.id,
                        section: task.section,
                        eventTitle: context.titleSnapshot,
                        calendarTitle: link.calendarTitleSnapshot,
                        sourceTitle: link.sourceTitle,
                        eventStart: eventRange.start,
                        eventEnd: eventRange.end,
                        isAllDay: link.isAllDay
                    )
                )
            }
            let personalItems: [TaskCenterItem] = try PersonalTask
                .fetchAll(db)
                .map { task in
                TaskCenterItem(
                    id: .personalTask(taskID: task.id),
                    title: task.title,
                    isCompleted: task.isCompleted,
                    dueAt: task.dueAt,
                    completedAt: task.completedAt,
                    sortOrder: task.sortOrder,
                    source: .personal
                )
            }
            return eventItems + personalItems
        }

        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: currentDate)
        ) ?? currentDate

        switch list {
        case .today:
            return items.filter {
                !$0.isCompleted && ($0.dueAt.map { $0 < tomorrow } ?? true)
            }.sorted(by: Self.openItemOrder)
        case .upcoming:
            return items.filter {
                !$0.isCompleted && ($0.dueAt.map { $0 >= tomorrow } ?? false)
            }.sorted(by: Self.openItemOrder)
        case .completed:
            return items.filter { $0.isCompleted }
                .sorted(by: Self.completedItemOrder)
        }
    }

    private static func openItemOrder(
        _ lhs: TaskCenterItem,
        _ rhs: TaskCenterItem
    ) -> Bool {
        if lhs.dueAt != rhs.dueAt {
            return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.id < rhs.id
    }

    private static func completedItemOrder(
        _ lhs: TaskCenterItem,
        _ rhs: TaskCenterItem
    ) -> Bool {
        if lhs.completedAt != rhs.completedAt {
            return (lhs.completedAt ?? .distantPast)
                > (rhs.completedAt ?? .distantPast)
        }
        return lhs.id < rhs.id
    }
}
