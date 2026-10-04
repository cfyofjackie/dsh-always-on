import Foundation

public enum BubbleStyle: String, Codable, CaseIterable, Sendable {
    case chibi, glass
    public var label: String { self == .chibi ? "Q 版蓝白" : "简洁半透明" }
    public static func saved(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .chibi }
}

public enum BubblePreviewKind: String, CaseIterable, Sendable {
    case success, error, question, approval, planReview
    public var label: String {
        switch self { case .success: return "完成"; case .error: return "失败"; case .question: return "提问"; case .approval: return "批准"; case .planReview: return "计划审阅" }
    }
    public var state: TaskState { self == .success ? .success : self == .error ? .error : .waiting }
    public var summary: String {
        switch self {
        case .success: return "任务完成啦，回来看看成果吧。"
        case .error: return "任务遇到了问题，等你回来一起看看。"
        case .question: return "有个问题想问你，方便时来回答一下吧。"
        case .approval: return "有项操作需要你确认，我在这里等你。"
        case .planReview: return "计划已经准备好了，等你来审阅。"
        }
    }
    public var notice: Notice {
        Notice(id: "bubble-test-\(rawValue)", sessionId: "bubble-test", instanceId: "preview", runId: "preview",
               title: "气泡预览 · \(label)", summary: summary, state: state, actionIds: [], createdAt: 0, read: true, resolved: false)
    }
}
