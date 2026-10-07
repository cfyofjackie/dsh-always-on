import Foundation

/// Presentation choices are separate from real task states.
public enum PetAnimation: String, CaseIterable, Codable, Sendable {
    case idle, working, waiting, success, error, rice, toy, pet, whale
    public static let lifeAnimations: [Self] = [.rice, .toy, .pet, .whale]
    public init(state: TaskState) { self = Self(rawValue: state.rawValue)! }
    public var taskState: TaskState { TaskState(rawValue: rawValue) ?? .idle }
    public var isLife: Bool { Self.lifeAnimations.contains(self) }
    public var label: String {
        switch self {
        case .idle: return "待机"
        case .working: return "工作"
        case .waiting: return "等待"
        case .success: return "完成"
        case .error: return "失败"
        case .rice: return "吃大米饭"
        case .toy: return "扔小鲸鱼"
        case .pet: return "摸头开心"
        case .whale: return "摸小鲸鱼"
        }
    }
}
public enum PetIdleDelay: String, CaseIterable, Sendable {
    case fiveSeconds, tenSeconds
    public var seconds: Double { self == .fiveSeconds ? 5 : 10 }
    public var label: String { self == .fiveSeconds ? "待机 5 秒" : "待机 10 秒" }
    public static func saved(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .tenSeconds }
}
public struct LifeFrame: Codable, Sendable {
    public var file: String
    public var sourcePose: Int
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var anchorX: Double
    public var footY: Double
}
public struct LifeMotion: Codable, Sendable {
    public var animation: PetAnimation
    public var normalHeight: Int
    public var durations: [Double]
    public var rest: Double
    public var frames: [LifeFrame]
    public var duration: Double { durations.reduce(0,+) }
    public var cycle: Double { duration + rest }
    public func frameIndex(at elapsed: Double, looping: Bool = true) -> Int {
        let time = elapsed.isFinite ? max(0,elapsed) : 0
        let phase = looping ? time.truncatingRemainder(dividingBy: cycle) : time
        var end = 0.0
        for (i,hold) in durations.enumerated() { end += hold; if phase + 1e-9 < end { return i } }
        return frames.count - 1
    }
    public func secondsUntilNextFrame(at elapsed: Double) -> Double {
        let phase = max(0,elapsed).truncatingRemainder(dividingBy: cycle)
        let end = phase >= duration ? cycle : durations.prefix(frameIndex(at: elapsed)+1).reduce(0,+)
        return max(0.001,end-phase)
    }
}
public struct LifeManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var clips: [LifeMotion]
    public func motion(for animation: PetAnimation) -> LifeMotion? { clips.first { $0.animation == animation } }
    public func validate() throws {
        let counts: [PetAnimation: Int] = [.rice: 24, .toy: 23, .pet: 8, .whale: 24]
        guard schemaVersion == 1, clips.count == counts.count, Set(clips.map(\.animation)) == Set(PetAnimation.lifeAnimations) else { throw CharacterManifestError.invalid }
        for clip in clips {
            guard clip.normalHeight > 0, clip.frames.count == counts[clip.animation],
                  clip.frames.count == clip.durations.count, clip.durations.allSatisfy({$0.isFinite && $0 > 0}),
                  clip.rest.isFinite, clip.rest >= 0, clip.cycle.isFinite,
                  Set(clip.frames.map(\.sourcePose)).count == clip.frames.count else { throw CharacterManifestError.invalid }
            for f in clip.frames {
                guard !f.file.contains("/"), !f.file.contains("\\"), f.file.hasSuffix(".png"),
                      (1...(clip.animation == .pet ? 8 : 24)).contains(f.sourcePose), f.x >= 0, f.y >= 0, f.width > 0, f.height > 0,
                      f.anchorX.isFinite, f.footY.isFinite, f.anchorX >= 0, f.anchorX <= Double(f.width),
                      f.footY >= 0, f.footY <= Double(f.height) else { throw CharacterManifestError.invalid }
            }
        }
    }
}
/// One idle performance, then a new idle wait. No system-wide inactivity tracking.
public struct PetLoafPlayback: Sendable {
    public private(set) var animation: PetAnimation?
    private var idleSince: Double?
    private var started: Double?
    public init() {}
    public mutating func reset() { animation = nil; idleSince = nil; started = nil }
    public mutating func advance(eligible: Bool, delay: Double, now: Double,
                                 choose: () -> PetAnimation, cycle: (PetAnimation) -> Double) {
        guard eligible else { reset(); return }
        if let animation, let started {
            if now - started + 1e-9 >= cycle(animation) { reset(); idleSince = now }
        } else if let idleSince {
            if now - idleSince + 1e-9 >= delay {
                let next = choose()
                guard next.isLife else { return }
                animation = next; started = now
            }
        } else { idleSince = now }
    }
}
