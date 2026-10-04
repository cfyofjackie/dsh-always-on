import Foundation

public enum ReminderRetention: String, CaseIterable, Codable, Sendable {
    case tenSeconds, fiveSeconds, untilOpened
    public static func saved(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .tenSeconds
    }
    public var label: String {
        switch self {
        case .tenSeconds: return "保留 10 秒"
        case .fiveSeconds: return "保留 5 秒"
        case .untilOpened: return "一直保留，直到点击打开"
        }
    }
    public var seconds: Double? {
        switch self { case .tenSeconds: return 10; case .fiveSeconds: return 5; case .untilOpened: return nil }
    }
}

/// Display state only. Removing a bubble never acknowledges or resolves its reminder.
public struct PetReminderQueue: Sendable {
    public private(set) var current: Notice?
    public private(set) var queued: [Notice] = []
    private var shownAt: Double = 0
    public init() {}

    public mutating func enqueue(_ notice: Notice, retention: ReminderRetention, now: Double) {
        queued.removeAll { $0.sessionId == notice.sessionId }
        if let visible = current, retention == .untilOpened {
            // New reminders remain visible even when an older bubble has no deadline.
            // The displaced reminder is still accessible in the session list.
            if visible.sessionId == notice.sessionId || notice.state == .waiting || visible.state != .waiting {
                current = notice; shownAt = now; return
            }
        }
        queued.append(notice)
        queued.sort { ($0.state == .waiting ? 1 : 0) > ($1.state == .waiting ? 1 : 0) }
        if queued.count > 20 { queued.removeLast(queued.count - 20) }
        advance(now: now)
    }
    public mutating func advance(now: Double) {
        if current == nil, !queued.isEmpty { current = queued.removeFirst(); shownAt = now }
    }
    public func remaining(retention: ReminderRetention, now: Double) -> Double? {
        guard current != nil, let seconds = retention.seconds else { return nil }
        return max(0, seconds - (now - shownAt) / 1000)
    }
    public mutating func restartTimer(now: Double) { shownAt = now }
    public mutating func remove(ids: Set<String>, now: Double) {
        queued.removeAll { ids.contains($0.id) }
        if let current, ids.contains(current.id) { self.current = nil }
        advance(now: now)
    }
    public mutating func expire(id: String, retention: ReminderRetention, now: Double) {
        guard current?.id == id, let remaining = remaining(retention: retention, now: now), remaining <= 0 else { return }
        remove(ids: [id], now: now)
    }
    public mutating func clear() { current = nil; queued.removeAll() }
}
