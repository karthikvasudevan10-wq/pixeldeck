import Foundation

/// Eased playback (a Pro feature): frames are shown for different lengths of time so the motion
/// speeds up or slows down, while the whole loop lasts as long as it would at the chosen fps.
///
/// The easing curve maps time to progress through the animation. Frame `i` is on screen while
/// progress is in [i/n, (i+1)/n), so its duration is the time the curve takes to cross that band.
/// With Ease in, early frames are held longer (a slow start); with Ease out, the late ones.
enum PlaybackTiming {
    /// Shortest frame we produce. GIF delays are in hundredths of a second, and many viewers treat
    /// anything under 0.02 s as 0.1 s, which would break the timing.
    static let minimumDuration = 1.0 / 120

    /// Seconds each frame is shown, for `count` frames at `fps`.
    static func durations(count: Int, fps: Int, easing: Easing) -> [Double] {
        guard count > 0 else { return [] }
        let base = 1 / Double(max(fps, 1))
        guard easing != .linear, count > 1 else { return Array(repeating: base, count: count) }
        let total = base * Double(count)
        // Times at which progress crosses each frame boundary.
        let boundaries = (0...count).map { i in inverse(easing, Double(i) / Double(count)) }
        var out = (0..<count).map { i in max(minimumDuration, (boundaries[i + 1] - boundaries[i]) * total) }
        // Keep the loop the same length after clamping very short frames.
        let sum = out.reduce(0, +)
        if sum > 0 {
            let k = total / sum
            out = out.map { max(minimumDuration, $0 * k) }
        }
        return out
    }

    /// Which frame is showing `elapsed` seconds into a loop with these durations.
    static func frameIndex(at elapsed: TimeInterval, durations: [Double]) -> Int {
        guard !durations.isEmpty else { return 0 }
        let total = durations.reduce(0, +)
        guard total > 0 else { return 0 }
        var t = elapsed.truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }
        for (i, d) in durations.enumerated() {
            if t < d { return i }
            t -= d
        }
        return durations.count - 1
    }

    /// The time (0…1) at which the eased progress reaches `p`. The curves are monotonic, so
    /// bisection is exact enough and works for any of them.
    static func inverse(_ easing: Easing, _ p: Double) -> Double {
        if p <= 0 { return 0 }
        if p >= 1 { return 1 }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if easing.apply(mid) < p { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}
