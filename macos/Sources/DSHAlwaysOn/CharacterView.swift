import AppKit
import SwiftUI
import CompanionCore

/// Cached, normalized frames exported from the persistent character playground.
@MainActor final class CharacterArtwork {
    static let size: CGFloat = 208
    static let shared = CharacterArtwork()
    let manifest: CharacterManifest?
    let failure: String?
    private let images: [TaskState: [NSImage]]
    private let hitMask: [UInt8]

    static var resourceDirectory: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("characters", isDirectory: true)
        if let bundled, Bundle.main.bundleURL.pathExtension == "app" { return bundled }
        // Swift Package art export runs without an App bundle, using this checkout only.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/characters", isDirectory: true)
    }

    private init() {
        do {
            let directory = Self.resourceDirectory
            let data = try Data(contentsOf: directory.appendingPathComponent("character.json"))
            let spec = try JSONDecoder().decode(CharacterManifest.self, from: data)
            try spec.validate()
            guard spec.canvasSize == Int(Self.size),
                  let source = NSImage(contentsOf: directory.appendingPathComponent(spec.atlas)),
                  let atlas = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  atlas.width == spec.atlasWidth, atlas.height == spec.atlasHeight else { throw CharacterManifestError.invalid }
            let all = spec.states.flatMap(\.frames)
            let scale = CGFloat(spec.canvasSize - 2 * spec.padding) / CGFloat(max(all.map(\.height).max()!, all.map(\.width).max()!))
            var loaded: [TaskState: [NSImage]] = [:]
            for motion in spec.states {
                loaded[motion.state] = try motion.frames.enumerated().map { index, frame in
                    let crop = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                    guard let sprite = atlas.cropping(to: crop),
                          let context = CGContext(data: nil, width: spec.canvasSize * 2, height: spec.canvasSize * 2,
                                                  bitsPerComponent: 8, bytesPerRow: spec.canvasSize * 8,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CharacterManifestError.invalid }
                    context.scaleBy(x: 2, y: 2)
                    context.interpolationQuality = .high
                    let width = CGFloat(frame.width) * scale, height = CGFloat(frame.height) * scale
                    context.draw(sprite, in: CGRect(x: (Self.size - width) / 2,
                                                    y: CGFloat(spec.padding) + CGFloat(motion.hops[index]),
                                                    width: width, height: height))
                    guard let image = context.makeImage() else { throw CharacterManifestError.invalid }
                    return NSImage(cgImage: image, size: NSSize(width: Self.size, height: Self.size))
                }
            }
            // Union of all poses: moving hands and hair remain draggable without
            // making the surrounding transparent corners block another application.
            var mask = [UInt8](repeating: 0, count: spec.canvasSize * spec.canvasSize * 4)
            try mask.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: spec.canvasSize, height: spec.canvasSize,
                                              bitsPerComponent: 8, bytesPerRow: spec.canvasSize * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CharacterManifestError.invalid }
                for image in loaded.values.flatMap({ $0 }) {
                    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw CharacterManifestError.invalid }
                    context.draw(cg, in: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
                }
            }
            manifest = spec; images = loaded; hitMask = mask; failure = nil
        } catch {
            manifest = nil; images = [:]; hitMask = []; failure = String(describing: error)
        }
    }

    func image(state: TaskState, frame: Int = 0) -> NSImage? {
        guard let frames = images[state], frames.indices.contains(frame) else { return nil }
        return frames[frame]
    }
    func contains(_ point: CGPoint) -> Bool {
        guard point.x >= 0, point.y >= 0, point.x < Self.size, point.y < Self.size else { return false }
        guard !hitMask.isEmpty else { return CGRect(x: 20, y: 10, width: 168, height: 198).contains(point) }
        return hitMask[(Int(point.y) * Int(Self.size) + Int(point.x)) * 4 + 3] > 20 || LifeArtwork.shared.contains(point)
    }

    func export(to directory: URL) throws {
        guard let manifest else { throw CharacterManifestError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for motion in manifest.states {
            for index in motion.frames.indices {
                guard let image = image(state: motion.state, frame: index),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CharacterManifestError.invalid }
                try png.write(to: directory.appendingPathComponent("\(motion.state.rawValue)-\(index).png"), options: .atomic)
                if index == 0 { try png.write(to: directory.appendingPathComponent("\(motion.state.rawValue).png"), options: .atomic) }
            }
        }
        try LifeArtwork.shared.export(to: directory)
    }

    func validate() throws -> [String: Any] {
        guard let manifest else { throw CharacterManifestError.invalid }
        try manifest.validate()
        for motion in manifest.states {
            guard images[motion.state]?.count == motion.frames.count else { throw CharacterManifestError.invalid }
        }
        guard contains(CGPoint(x: 104, y: 90)), !contains(.zero), !contains(CGPoint(x: 207, y: 207)) else { throw CharacterManifestError.invalid }
        try LifeArtwork.shared.validate()
        return ["lifeClips": 2, "lifeFrames": 47, "id": manifest.id, "states": manifest.states.count, "frames": manifest.states.reduce(0) { $0 + $1.frames.count },
                "canvas": manifest.canvasSize, "transparentHitRegion": true]
    }
}

/// Original pose registration is retained; all sprites are decoded once.
@MainActor final class LifeArtwork {
    static let shared = LifeArtwork()
    let manifest: LifeManifest?
    let failure: String?
    private let images: [PetAnimation: [NSImage]]
    private let mask: [UInt8]
    private init() {
        do {
            let dir = CharacterArtwork.resourceDirectory
            let spec = try JSONDecoder().decode(LifeManifest.self, from: Data(contentsOf: dir.appendingPathComponent("life.json")))
            try spec.validate()
            var sources: [String: CGImage] = [:]
            var loaded: [PetAnimation: [NSImage]] = [:]
            for clip in spec.clips {
                // Fit floating props as well as the body inside the native square.
                let extent = clip.frames.map { max($0.anchorX, Double($0.width)-$0.anchorX) }.max()!
                let scale = min(196.0 / Double(clip.normalHeight), 98.0 / extent)
                loaded[clip.animation] = try clip.frames.map { f in
                    if sources[f.file] == nil {
                        guard let image = NSImage(contentsOf: dir.appendingPathComponent(f.file)),
                              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw CharacterManifestError.invalid }
                        sources[f.file] = cg
                    }
                    let source = sources[f.file]!
                    guard f.width <= source.width, f.height <= source.height,
                          f.x <= source.width-f.width, f.y <= source.height-f.height,
                          let sprite = source.cropping(to: CGRect(x: f.x,y: f.y,width: f.width,height: f.height)),
                          let context = CGContext(data: nil,width: 416,height: 416,bitsPerComponent: 8,bytesPerRow: 1664,
                              space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CharacterManifestError.invalid }
                    context.scaleBy(x: 2,y: 2); context.interpolationQuality = .high
                    context.draw(sprite,in: CGRect(x: 104-f.anchorX*scale,y: 6-(Double(f.height)-f.footY)*scale,
                                                   width: Double(f.width)*scale,height: Double(f.height)*scale))
                    guard let cg = context.makeImage() else { throw CharacterManifestError.invalid }
                    return NSImage(cgImage: cg,size: NSSize(width: 208,height: 208))
                }
            }
            var bytes = [UInt8](repeating: 0,count: 208*208*4)
            try bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress,width: 208,height: 208,bitsPerComponent: 8,bytesPerRow: 832,
                    space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CharacterManifestError.invalid }
                for image in loaded.values.flatMap({$0}) {
                    guard let cg = image.cgImage(forProposedRect: nil,context: nil,hints: nil) else { throw CharacterManifestError.invalid }
                    context.draw(cg,in: CGRect(x: 0,y: 0,width: 208,height: 208))
                }
            }
            manifest = spec; images = loaded; mask = bytes; failure = nil
        } catch { manifest = nil; images = [:]; mask = []; failure = String(describing: error) }
    }
    func image(animation: PetAnimation,frame: Int) -> NSImage? {
        guard let frames = images[animation],frames.indices.contains(frame) else { return nil }
        return frames[frame]
    }
    func contains(_ point: CGPoint) -> Bool {
        guard !mask.isEmpty,point.x >= 0,point.y >= 0,point.x < 208,point.y < 208 else { return false }
        return mask[(Int(point.y)*208+Int(point.x))*4+3] > 20
    }
    func validate() throws {
        guard let manifest else { throw CharacterManifestError.invalid }
        try manifest.validate()
        for clip in manifest.clips { guard images[clip.animation]?.count == clip.frames.count else { throw CharacterManifestError.invalid } }
    }
    func export(to directory: URL) throws {
        try validate()
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        for clip in manifest!.clips {
            for i in clip.frames.indices {
                guard let image = image(animation: clip.animation,frame: i),let cg = image.cgImage(forProposedRect: nil,context: nil,hints: nil),
                      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png,properties: [:]) else { throw CharacterManifestError.invalid }
                try png.write(to: directory.appendingPathComponent("life-\(clip.animation.rawValue)-\(i+1).png"),options: .atomic)
            }
        }
    }
}

/// Both live playback and test playback use the same cache and clock.
struct CharacterView: View {
    let state: TaskState
    var animated = true
    var animation: PetAnimation? = nil
    var revision = 0
    var looping = true
    private var selected: PetAnimation { animation ?? PetAnimation(state: state) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = 0
    @State private var clock = CharacterPlaybackClock()
    private struct Playback: Hashable {
        let animation: PetAnimation
        let animated: Bool
        let reduceMotion: Bool
        let revision: Int
        let looping: Bool
    }
    private var image: NSImage? {
        selected.isLife ? LifeArtwork.shared.image(animation: selected,frame: frame) : CharacterArtwork.shared.image(state: state,frame: frame)
    }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high) }
            else if let image = NSImage(contentsOf: CharacterArtwork.resourceDirectory.appendingPathComponent("\(state.rawValue).png")) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "sparkles").resizable().scaledToFit().padding(60).foregroundStyle(.blue) }
        }
        .frame(width: CharacterArtwork.size,height: CharacterArtwork.size)
        .accessibilityLabel("\(CharacterArtwork.shared.manifest?.name ?? "桌面伙伴")：\(selected.label)")
        .accessibilityValue(animated && !reduceMotion ? "动画播放中" : "动画已暂停")
        .task(id: Playback(animation: selected,animated: animated,reduceMotion: reduceMotion,revision: revision,looping: looping)) {
            clock.configure(animation: selected,playing: animated && !reduceMotion,now: ProcessInfo.processInfo.systemUptime,revision: revision)
            let life = LifeArtwork.shared.manifest?.motion(for: selected)
            let task = CharacterArtwork.shared.manifest?.motion(for: selected.taskState)
            func index(_ elapsed: Double) -> Int { life?.frameIndex(at: elapsed,looping: looping) ?? task?.frameIndex(at: elapsed) ?? 0 }
            frame = reduceMotion ? 0 : index(clock.elapsedTime(at: ProcessInfo.processInfo.systemUptime))
            guard animated,!reduceMotion else { return }
            while !Task.isCancelled {
                let elapsed = clock.elapsedTime(at: ProcessInfo.processInfo.systemUptime)
                frame = index(elapsed)
                if let life, !looping, elapsed >= life.cycle { return }
                let delay = life?.secondsUntilNextFrame(at: elapsed) ?? task?.secondsUntilNextFrame(at: elapsed) ?? 1
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }
}
