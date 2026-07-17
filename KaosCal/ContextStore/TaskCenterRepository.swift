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
            let providerItems = Dictionary(
                uniqueKeysWithValues: try ProviderItemRecord.fetchAll(db).map {
                    ($0.id, $0)
                }
            )
            let providerAccounts = Dictionary(
                uniqueKeysWithValues: try ProviderAccountRecord.fetchAll(db).map {
                    ($0.id, $0)
                }
            )
            let providerBindings = Dictionary(
                uniqueKeysWithValues: try TaskBindingRecord.fetchAll(db)
                    .compactMap { binding in
                        binding.eventTaskID.map { ($0, binding) }
                    }
            )
            let pendingOperations = Dictionary(
                uniqueKeysWithValues: try ProviderPendingOperationRecord
                    .fetchAll(db)
                    .map { ($0.eventTaskID, $0) }
            )
            let localOnlyTaskIDs = Set(
                try TaskProviderPreferenceRecord.fetchAll(db)
                    .filter { $0.linkMode == .localOnly }
                    .map(\.eventTaskID)
            )
            let originalDeletionContextIDs = Set(try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT deletion.context_id
                    FROM event_change_log AS deletion
                    WHERE deletion.change_type = 'cancelled'
                      AND deletion.undo_state = 'unavailable'
                      AND NOT EXISTS (
                          SELECT 1
                          FROM event_change_log AS relink
                          WHERE relink.context_id = deletion.context_id
                            AND relink.change_type = 'relinked'
                            AND (
                                relink.created_at > deletion.created_at
                                OR (
                                    relink.created_at = deletion.created_at
                                    AND relink.rowid > deletion.rowid
                                )
                            )
                      )
                    """
            ))
            let eventItems: [TaskCenterItem] = try EventTask
                .fetchAll(db)
                .compactMap { task -> TaskCenterItem? in
                    guard let context = contexts[task.contextID],
                          let link = links[task.contextID] else {
                        return nil
                    }
                    let lifecycleStatus = Self.projectedLifecycleStatus(
                        context: context,
                        link: link,
                        at: currentDate,
                        calendar: calendar
                    )
                    switch list {
                    case .today, .upcoming:
                        if lifecycleStatus == .completed,
                           task.section != .after {
                            return nil
                        }
                    case .afterReview:
                        guard lifecycleStatus == .completed,
                              task.section == .after else {
                            return nil
                        }
                    case .completed:
                        break
                    }
                    let eventRange = link.effectiveDateRange(
                        calendar: calendar
                    )
                    let providerLink: TaskCenterProviderLink?
                    if let binding = providerBindings[task.id],
                       let item = providerItems[binding.providerItemID],
                       let account = providerAccounts[item.accountID] {
                        let pending = pendingOperations[task.id]
                        providerLink = TaskCenterProviderLink(
                            bindingID: binding.id,
                            provider: account.provider,
                            accountKey: account.accountKey,
                            accountTitle: account.displayName,
                            remoteParentID: item.remoteParentID,
                            syncState: binding.syncState,
                            authorizationState: account.authorizationState,
                            pendingOperation: pending?.operation,
                            pendingAttemptCount: pending?.attemptCount ?? 0,
                            pendingLastError: pending?.lastError
                        )
                    } else if let pending = pendingOperations[task.id],
                              let account = providerAccounts[pending.accountID] {
                        providerLink = TaskCenterProviderLink(
                            bindingID: pending.id,
                            provider: account.provider,
                            accountKey: account.accountKey,
                            accountTitle: account.displayName,
                            remoteParentID: pending.remoteParentID,
                            syncState: .pendingCreate,
                            authorizationState: account.authorizationState,
                            pendingOperation: pending.operation,
                            pendingAttemptCount: pending.attemptCount,
                            pendingLastError: pending.lastError
                        )
                    } else {
                        providerLink = nil
                    }
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
                            calendarIdentifier: link.calendarIdentifier,
                            calendarTitle: link.calendarTitleSnapshot,
                            sourceTitle: link.sourceTitle,
                            eventStart: eventRange.start,
                            eventEnd: eventRange.end,
                            isAllDay: link.isAllDay
                        ),
                        providerLink: providerLink,
                        isProviderLocalOnly: localOnlyTaskIDs.contains(task.id),
                        eventLinkStatus: link.linkStatus,
                        eventLifecycleStatus: context.lifecycleStatus,
                        wasOriginalDeletedByKaosCal:
                            originalDeletionContextIDs.contains(context.id)
                    )
                }
            let personalItems: [TaskCenterItem]
            if list == .afterReview {
                personalItems = []
            } else {
                personalItems = try PersonalTask
                    .fetchAll(db)
                    .map { task in
                        TaskCenterItem(
                            id: .personalTask(taskID: task.id),
                            title: task.title,
                            isCompleted: task.isCompleted,
                            dueAt: task.dueAt,
                            completedAt: task.completedAt,
                            sortOrder: task.sortOrder,
                            source: .personal,
                            providerLink: nil,
                            isProviderLocalOnly: false,
                            eventLinkStatus: nil,
                            eventLifecycleStatus: nil,
                            wasOriginalDeletedByKaosCal: false
                        )
                    }
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
        case .afterReview:
            return items.filter { !$0.isCompleted }
                .sorted(by: Self.openItemOrder)
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

    private static func projectedLifecycleStatus(
        context: EventContext,
        link: EventLink,
        at date: Date,
        calendar: Calendar
    ) -> EventLifecycleStatus {
        guard context.lifecycleStatus == .scheduled
                || context.lifecycleStatus == .completed,
              link.linkStatus == .active else {
            return context.lifecycleStatus
        }
        return date >= link.effectiveDateRange(calendar: calendar).end
            ? .completed
            : .scheduled
    }
}
