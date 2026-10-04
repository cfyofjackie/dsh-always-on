import Foundation

public enum TaskState: String, Codable, CaseIterable, Sendable {
    case idle, working, waiting, success, error
    public var label: String {
        switch self { case .idle: return "空闲"; case .working: return "工作中"; case .waiting: return "等你处理"; case .success: return "已完成"; case .error: return "执行失败" }
    }
}
public enum NotificationMode: String, Codable, CaseIterable, Sendable {
    case native, pet
    public var label: String { self == .native ? "原生通知" : "桌面伙伴" }
}
public struct WaitItem: Codable, Equatable, Sendable {
    public var actionId: String
    public var reason: String
    public init(actionId: String, reason: String) { self.actionId = actionId; self.reason = reason }
}
public struct SessionRecord: Codable, Identifiable, Sendable {
    public var sessionId: String
    public var title: String
    public var runId: String
    public var state: TaskState
    public var activeWaits: [WaitItem]
    public var updatedAt: Double
    public var lastOutcome: String?
    /// App-local flag for a reminder whose session is absent from the live loaded set.
    public var available: Bool?
    public var id: String { sessionId }
    public init(sessionId: String, title: String, runId: String, state: TaskState, activeWaits: [WaitItem] = [], updatedAt: Double = Date().timeIntervalSince1970 * 1000) {
        self.sessionId = sessionId; self.title = title; self.runId = runId; self.state = state; self.activeWaits = activeWaits; self.updatedAt = updatedAt
    }
}
public struct BridgeEvent: Codable, Sendable {
    public var protocolVersion: String
    public var eventId: String
    public var source: String
    public var instanceId: String
    public var sourceEpoch: String
    public var sequence: Int
    public var sessionId: String
    public var title: String
    public var runId: String
    public var state: TaskState
    public var activeWaits: [WaitItem]
    public var updatedAt: Double
    public var type: String
    public var occurredAt: String
    public var summary: String
    public var notify: Bool
}
public struct BridgeFeed: Codable, Sendable {
    public var protocolVersion: String
    public var sourceEpoch: String
    public var instanceId: String
    public var throughSequence: Int
    public var sessions: [SessionRecord]
    public var events: [BridgeEvent]
    public var reset: Bool
    public var clientConnected: Bool
    public var viewStatus: ViewStatus?
}
public struct Notice: Codable, Identifiable, Sendable {
    public var id: String
    public var sessionId: String
    public var instanceId: String
    public var runId: String
    public var title: String
    public var summary: String
    public var state: TaskState
    public var actionIds: [String]
    public var createdAt: Double
    public var read: Bool
    public var resolved: Bool
}

/// Mutations are owned by the main actor in the app; this value is also tested without UI.
public struct SessionStore: Codable, Sendable {
    public private(set) var sessions: [String: SessionRecord] = [:]
    public private(set) var notices: [Notice] = []
    public private(set) var seen: [String] = []
    public private(set) var sourceEpoch = ""
    public private(set) var instanceId = ""
    public private(set) var sequence = -1
    public init() {}
    public var unreadCount: Int { Set(notices.filter { !$0.read }.map { $0.instanceId + ":" + $0.sessionId }).count }
    public var orderedSessions: [SessionRecord] { sessions.values.sorted { $0.updatedAt > $1.updatedAt } }
    public func unreadIDs(sessionId: String) -> Set<String> { Set(notices.filter { $0.sessionId == sessionId && !$0.read }.map(\.id)) }
    public func latestNotice(sessionId: String) -> Notice? { notices.last { $0.sessionId == sessionId } }

    public mutating func apply(_ feed: BridgeFeed) throws -> [Notice] {
        guard feed.protocolVersion.split(separator: ".").first == "1", feed.throughSequence >= 0,
              !feed.sourceEpoch.isEmpty, !feed.instanceId.isEmpty else { throw StoreError.incompatible }
        func validWaits(_ items: [WaitItem]) -> Bool {
            Set(items.map(\.actionId)).count == items.count && items.allSatisfy { !$0.actionId.isEmpty && ["question", "approval", "plan_review"].contains($0.reason) }
        }
        let eventStates: [String: TaskState] = ["session.started": .working, "session.resumed": .working, "session.waiting": .waiting, "session.stopped": .idle, "task.succeeded": .success, "task.failed": .error]
        guard Set(feed.sessions.map(\.sessionId)).count == feed.sessions.count,
              feed.sessions.allSatisfy({ !$0.sessionId.isEmpty && !$0.runId.isEmpty && validWaits($0.activeWaits) && ($0.state == .waiting) == !$0.activeWaits.isEmpty }) else { throw StoreError.invalidEvent }
        // Validate the whole batch before mutating; a rejected packet cannot advance its cursor.
        if !feed.reset {
            guard feed.sourceEpoch == sourceEpoch, feed.instanceId == instanceId else { throw StoreError.missingBaseline }
            var cursor = sequence
            for event in feed.events {
                guard event.sourceEpoch == feed.sourceEpoch, event.instanceId == feed.instanceId,
                      event.protocolVersion.split(separator: ".").first == "1",
                      event.source == "deepseek-harness", !event.eventId.isEmpty,
                      !event.sessionId.isEmpty, !event.runId.isEmpty, validWaits(event.activeWaits),
                      eventStates[event.type] == event.state,
                      !event.notify || [.waiting, .success, .error].contains(event.state),
                      event.sequence <= feed.throughSequence,
                      (event.state == .waiting) == !event.activeWaits.isEmpty else { throw StoreError.invalidEvent }
                if event.sequence <= cursor { continue }
                guard event.sequence == cursor + 1 else { throw StoreError.sequenceGap }
                cursor = event.sequence
            }
            guard cursor == feed.throughSequence else { throw StoreError.sequenceGap }
        }
        if !instanceId.isEmpty && instanceId != feed.instanceId {
            // First version connects one installation; unrelated IDs must not share unread state.
            notices.removeAll(); seen.removeAll()
        }
        var created: [Notice] = []
        if !feed.reset {
            for event in feed.events where event.sequence > sequence && !seen.contains(event.eventId) {
                seen.append(event.eventId)
                if !event.notify { continue }
                let duplicateTerminal = event.type.hasPrefix("task.") && notices.contains { $0.sessionId == event.sessionId && $0.instanceId == event.instanceId && $0.runId == event.runId && $0.state == event.state }
                if duplicateTerminal { continue }
                let freshActions = event.activeWaits.map(\.actionId).filter { id in !notices.contains { $0.sessionId == event.sessionId && $0.instanceId == event.instanceId && $0.actionIds.contains(id) } }
                if event.state == .waiting && freshActions.isEmpty { continue }
                let notice = Notice(id: event.eventId, sessionId: event.sessionId, instanceId: event.instanceId, runId: event.runId,
                                    title: event.title, summary: event.summary, state: event.state, actionIds: freshActions,
                                    createdAt: event.updatedAt, read: false, resolved: false)
                notices.append(notice); created.append(notice)
            }
        }
        sourceEpoch = feed.sourceEpoch; instanceId = feed.instanceId; sequence = feed.throughSequence
        sessions = Dictionary(uniqueKeysWithValues: feed.sessions.map { ($0.sessionId, $0) })
        // Keep an actionable row for unread reminders even if DSH has unloaded the session.
        for notice in notices where !notice.read && sessions[notice.sessionId] == nil {
            var cached = SessionRecord(sessionId: notice.sessionId, title: notice.title, runId: notice.runId, state: .idle, updatedAt: notice.createdAt)
            cached.available = false; sessions[notice.sessionId] = cached
        }
        for index in notices.indices where notices[index].state == .waiting {
            if let session = sessions[notices[index].sessionId], session.available != false {
                let active = Set(session.activeWaits.map(\.actionId))
                notices[index].resolved = !notices[index].actionIds.contains(where: { active.contains($0) })
            }
        }
        if seen.count > 2000 { seen.removeFirst(seen.count - 2000) }
        let cutoff = Date().timeIntervalSince1970 * 1000 - 7 * 86400 * 1000
        notices.removeAll { $0.read && ($0.state != .waiting || $0.resolved) && $0.createdAt < cutoff }
        let removable = notices.filter { $0.read && ($0.state != .waiting || $0.resolved) }
        if removable.count > 500 {
            let ids = Set(removable.prefix(removable.count - 500).map(\.id)); notices.removeAll { ids.contains($0.id) }
        }
        return created.filter { n in !notices.contains { $0.id == n.id && $0.resolved } }
    }
    public mutating func markRead(sessionId: String, ids: Set<String>) {
        for index in notices.indices where notices[index].sessionId == sessionId && ids.contains(notices[index].id) { notices[index].read = true }
    }
    public func portrait(connected: Bool, now: Double = Date().timeIntervalSince1970 * 1000,
                         retention: ReminderRetention = .tenSeconds, dismissedFeedbackIDs: Set<String> = []) -> SessionRecord? {
        guard connected else { return nil }
        func showsFeedback(_ r: SessionRecord) -> Bool {
            let notice = notices.last { $0.sessionId == r.id && $0.runId == r.runId && $0.state == r.state }
            if let notice, notice.read || dismissedFeedbackIDs.contains(notice.id) { return false }
            if let seconds = retention.seconds { return now - r.updatedAt < seconds * 1000 }
            // Never resurrect a historical success baseline without an unread reminder.
            return notice != nil
        }
        func rank(_ r: SessionRecord) -> Int {
            switch r.state { case .waiting: return 5; case .error: return showsFeedback(r) ? 4 : 0; case .success: return showsFeedback(r) ? 3 : 0; case .working: return 2; case .idle: return 0 }
        }
        return sessions.values.filter { $0.available != false && rank($0) > 0 }.max { a, b in rank(a) == rank(b) ? a.updatedAt < b.updatedAt : rank(a) < rank(b) }
    }
}
public enum StoreError: Error { case incompatible, invalidEvent, sequenceGap, missingBaseline }
