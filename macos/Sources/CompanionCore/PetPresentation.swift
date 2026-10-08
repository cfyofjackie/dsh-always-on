import Foundation

public enum FullScreenPolicy: String, CaseIterable, Sendable {
    case always, remindersOnly, hidden
    public var label: String {
        switch self { case .always: return "始终显示"; case .remindersOnly: return "仅有任务提醒时出现"; case .hidden: return "全屏完全隐藏" }
    }
    public static func saved(_ raw: String?, legacy: Bool?, mode: NotificationMode) -> Self {
        if let value = raw.flatMap(Self.init(rawValue:)) { return value }
        if let legacy { return legacy ? .always : .hidden }
        return mode == .companion ? .always : .remindersOnly
    }
    public func visible(fullScreen: Bool, hasFeedback: Bool) -> Bool {
        !fullScreen || self == .always || (self == .remindersOnly && hasFeedback)
    }
}

public enum ForegroundReminderStyle: String, CaseIterable, Sendable {
    case actionOnly, bubble, silent
    public var label: String {
        switch self { case .actionOnly: return "仅动作"; case .bubble: return "动作和气泡"; case .silent: return "静默" }
    }
    /// Failure / interaction reminders still require an actionable bubble by default.
    public func showsBubble(state: TaskState) -> Bool { self == .bubble || (self == .actionOnly && state != .success) }
}

/// Cosmetic rotation only. It never reads or changes task records.
public struct CompanionPlayback: Sendable {
    public private(set) var animation: PetAnimation = .idle
    public private(set) var revision = 0
    private var nextAt: Double?
    public init() {}
    public mutating func reset() { animation = .idle; nextAt = nil; revision += 1 }
    public mutating func advance(now: Double, fixed: PetAnimation?, choose: ([PetAnimation]) -> PetAnimation,
                                 cycle: (PetAnimation) -> Double) {
        if let fixed {
            if animation != fixed || nextAt != nil { animation = fixed; revision += 1 }
            nextAt = nil; return
        }
        if nextAt == nil || now >= nextAt! {
            let candidates = PetAnimation.allCases.filter { $0 != animation }
            let selected = choose(candidates)
            guard candidates.contains(selected) else { return }
            animation = selected; revision += 1
            nextAt = now + max(5, cycle(selected))
        }
    }
}

public enum PreviewBubble {
    public static func kind(for animation: PetAnimation, waiting: BubblePreviewKind) -> BubblePreviewKind? {
        switch animation {
        case .success: return .success
        case .error: return .error
        case .waiting: return [.question, .approval, .planReview].contains(waiting) ? waiting : .question
        default: return nil
        }
    }
}
