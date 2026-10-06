import Foundation

/// A temporary presentation override; never a task event or a persisted preference.
public struct AnimationPreview: Sendable {
    public private(set) var enabled = false
    public private(set) var selectedAnimation: PetAnimation = .idle
    public var selectedState: TaskState { selectedAnimation.taskState }
    public private(set) var revision = 0
    public private(set) var playing = true
    public init() {}
    public mutating func begin(state: TaskState) { enabled = true; selectedAnimation = PetAnimation(state: state); playing = true; revision += 1 }
    public mutating func select(_ state: TaskState) { guard enabled else { return }; selectedAnimation = PetAnimation(state: state); revision += 1 }
    public mutating func select(_ animation: PetAnimation) { guard enabled else { return }; selectedAnimation = animation; revision += 1 }
    public mutating func restart() { guard enabled else { return }; revision += 1; playing = true }
    public mutating func setPlaying(_ value: Bool) { guard enabled else { return }; playing = value }
    public mutating func end() { enabled = false; playing = true }
    public func displayedState(live: TaskState) -> TaskState { enabled ? selectedState : live }
}

/// Uses monotonic time and excludes paused time from an animation's phase.
public struct CharacterPlaybackClock: Sendable {
    private var animation: PetAnimation?
    private var revision = 0
    private var elapsed: Double = 0
    private var started: Double?
    public init() {}
    public mutating func configure(state: TaskState, playing: Bool, now: Double) {
        configure(animation: PetAnimation(state: state), playing: playing, now: now)
    }
    public mutating func configure(animation: PetAnimation, playing: Bool, now: Double, revision: Int = 0) {
        elapsed = self.animation == animation && self.revision == revision ? elapsedTime(at: now) : 0
        self.animation = animation; self.revision = revision
        started = playing ? now : nil
    }
    public func elapsedTime(at now: Double) -> Double {
        elapsed + (started.map { max(0, now - $0) } ?? 0)
    }
}
