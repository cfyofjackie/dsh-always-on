import Foundation

public struct CharacterFrame: Codable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
}

public struct CharacterMotion: Codable, Sendable {
    public var state: TaskState
    public var durations: [Double]
    public var hops: [Double]
    public var frames: [CharacterFrame]

    public var duration: Double { durations.reduce(0, +) }
    private func phase(_ elapsed: Double) -> Double {
        guard elapsed.isFinite, duration > 0 else { return 0 }
        return max(0, elapsed).truncatingRemainder(dividingBy: duration)
    }
    public func frameIndex(at elapsed: Double) -> Int {
        let position = phase(elapsed)
        var boundary = 0.0
        for (index, delay) in durations.enumerated() {
            boundary += delay
            if position + 1e-9 < boundary { return index }
        }
        return 0
    }
    public func secondsUntilNextFrame(at elapsed: Double) -> Double {
        let index = frameIndex(at: elapsed)
        return max(0.001, durations.prefix(index + 1).reduce(0, +) - phase(elapsed))
    }
}

public struct CharacterManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var atlas: String
    public var atlasWidth: Int
    public var atlasHeight: Int
    public var canvasSize: Int
    public var padding: Int
    public var states: [CharacterMotion]

    public func motion(for state: TaskState) -> CharacterMotion? { states.first { $0.state == state } }
    public func validate() throws {
        guard schemaVersion == 1, atlasWidth > 0, atlasHeight > 0,
              canvasSize > 0, padding >= 0, padding * 2 < canvasSize,
              !atlas.contains("/"), !atlas.contains("\\"), atlas.hasSuffix(".png"),
              states.count == TaskState.allCases.count,
              Set(states.map(\.state)) == Set(TaskState.allCases) else { throw CharacterManifestError.invalid }
        for motion in states {
            guard !motion.frames.isEmpty, motion.frames.count == motion.durations.count,
                  motion.frames.count == motion.hops.count,
                  motion.durations.allSatisfy({ $0.isFinite && $0 > 0 }),
                  motion.hops.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= Double(padding * 2) }),
                  motion.duration.isFinite else { throw CharacterManifestError.invalid }
            for frame in motion.frames {
                guard frame.x >= 0, frame.y >= 0, frame.width > 0, frame.height > 0,
                      frame.width <= atlasWidth, frame.height <= atlasHeight,
                      frame.x <= atlasWidth - frame.width, frame.y <= atlasHeight - frame.height else { throw CharacterManifestError.invalid }
            }
        }
    }
}

public enum CharacterManifestError: Error { case invalid }
