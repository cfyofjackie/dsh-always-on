import Foundation

/// A temporary presentation override; never a task event or a persisted preference.
public struct AnimationPreview: Sendable {
    public private(set) var enabled = false
    public private(set) var selectedState: TaskState = .idle
    public private(set) var playing = true
    public init() {}
    public mutating func begin(state: TaskState) { enabled = true; selectedState = state; playing = true }
    public mutating func select(_ state: TaskState) { guard enabled else { return }; selectedState = state }
    public mutating func setPlaying(_ value: Bool) { guard enabled else { return }; playing = value }
    public mutating func end() { enabled = false; playing = true }
    public func displayedState(live: TaskState) -> TaskState { enabled ? selectedState : live }
}

/// Uses monotonic time and excludes paused time from an animation's phase.
public struct CharacterPlaybackClock: Sendable {
    private var state: TaskState?
    private var elapsed: Double = 0
    private var started: Double?
    public init() {}
    public mutating func configure(state: TaskState, playing: Bool, now: Double) {
        elapsed = self.state == state ? elapsedTime(at: now) : 0
        self.state = state
        started = playing ? now : nil
    }
    public func elapsedTime(at now: Double) -> Double {
        elapsed + (started.map { max(0, now - $0) } ?? 0)
    }
}
