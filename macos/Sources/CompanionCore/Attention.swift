import Foundation

/// Client facts are time limited; the native foreground app must also match.
public struct ViewStatus: Codable, Equatable, Sendable {
    public var sessionId: String?
    public var visible: Bool
    public var focused: Bool
    public var loaded: Bool
    public var reportedAt: Double
    public init(sessionId: String?, visible: Bool, focused: Bool, loaded: Bool, reportedAt: Double) {
        self.sessionId = sessionId; self.visible = visible; self.focused = focused; self.loaded = loaded; self.reportedAt = reportedAt
    }
    public func eligible(sessionId: String, foreground: Bool, now: Double) -> Bool {
        foreground && visible && focused && loaded && self.sessionId == sessionId &&
        reportedAt <= now + 1000 && now - reportedAt <= 2500
    }
}

public struct ViewReceipt: Codable, Sendable {
    public var requestId: String
    public var status: String
    public var sessionId: String
    public var instanceId: String
    public var sourceEpoch: String
    public var throughSequence: Int
    public func confirms(requestId: String, sessionId: String, instanceId: String, sourceEpoch: String,
                         throughSequence: Int, foregroundUnchanged: Bool) -> Bool {
        foregroundUnchanged && status == "viewed" && self.requestId == requestId && self.sessionId == sessionId &&
        self.instanceId == instanceId && self.sourceEpoch == sourceEpoch && self.throughSequence == throughSequence
    }
}
