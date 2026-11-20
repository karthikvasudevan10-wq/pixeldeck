import Foundation

/// What happens when the animation reaches its last frame.
enum LoopMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Start again from the first frame.
    case loop
    /// Play backwards to the start, then forwards again.
    case pingPong
    /// Stop on the last frame.
    case once

    var id: String { rawValue }
}

/// The order frames are shown in, and for how long: what the canvas, previews, GIF and video play.
struct PlaybackSequence: Equatable, Sendable {
    /// Indices into the sprite's frames.
    var frames: [Int]
    /// Seconds each one is shown.
    var durations: [Double]
    /// False for "Once": players stop on the last frame instead of starting again.
    var repeats = true

    var total: Double { durations.reduce(0, +) }

    /// Which step is showing `elapsed` seconds after the start.
    func step(at elapsed: TimeInterval) -> Int {
        guard !frames.isEmpty else { return 0 }
        if !repeats, elapsed >= total { return frames.count - 1 }
        return PlaybackTiming.frameIndex(at: elapsed, durations: durations)
    }

    /// The frame showing `elapsed` seconds after the start.
    func frame(at elapsed: TimeInterval) -> Int {
        frames.isEmpty ? 0 : frames[step(at: elapsed)]
    }
}

extension Frame {
    /// A frame can stay on screen for up to this many beats.
    static let maxHold = 8
}

extension SpriteProject {
    /// Seconds each frame is shown: the sprite's fps and easing, times each frame's hold.
    var frameDurations: [Double] {
        let base = PlaybackTiming.durations(count: frames.count, fps: fps, easing: playbackEasing)
        return zip(base, frames).map { $0 * Double(min(max($1.hold, 1), Frame.maxHold)) }
    }

    /// One pass of the animation as it plays: every frame in order, and for ping-pong the way
    /// back too (without repeating the two end frames).
    var playbackSequence: PlaybackSequence {
        let d = frameDurations
        var order = Array(frames.indices)
        if loopMode == .pingPong, frames.count > 2 { order += (1..<(frames.count - 1)).reversed() }
        return PlaybackSequence(frames: order, durations: order.map { d[$0] }, repeats: loopMode != .once)
    }
}
