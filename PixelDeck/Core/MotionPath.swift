import Foundation

/// Timing curve applied to a tween.
enum Easing: String, CaseIterable, Identifiable, Sendable {
    case linear, easeIn, easeOut, easeInOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .easeInOut: "Ease in & out"
        }
    }

    func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}

/// The route a moved selection took, as offsets (in canvas pixels) from where it started.
/// Always begins at (0, 0).
struct MotionPath: Hashable, Sendable {
    private(set) var points: [Vec2] = [.zero]

    init() {}

    init(points: [Vec2]) {
        self.points = points.isEmpty ? [.zero] : points
    }

    static func straight(to end: Vec2) -> MotionPath {
        MotionPath(points: [.zero, end])
    }

    var end: Vec2 { points[points.count - 1] }

    var length: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
    }

    /// True when the selection hasn't really gone anywhere.
    var isTrivial: Bool { end.rounded == .zero && length < 1 }

    mutating func append(_ p: Vec2) {
        if (p - end).length < 0.05 { return }
        points.append(p)
    }

    mutating func truncate(toCount count: Int) {
        points = Array(points.prefix(max(1, count)))
    }

    /// Removes finger jitter (Ramer–Douglas–Peucker) then smooths the result with a
    /// Catmull–Rom spline, so the tween follows the gesture's intent rather than every wobble.
    /// Start and end points are kept exactly.
    func refined(epsilon: Double = 0.75, samplesPerSegment: Int = 10) -> MotionPath {
        let key = MotionPath.simplify(points, epsilon: epsilon)
        guard key.count > 2 else { return MotionPath(points: key) }
        var out: [Vec2] = []
        out.reserveCapacity(key.count * samplesPerSegment)
        for i in 0..<(key.count - 1) {
            let p0 = key[max(i - 1, 0)], p1 = key[i], p2 = key[i + 1], p3 = key[min(i + 2, key.count - 1)]
            for s in 0..<samplesPerSegment {
                let t = Double(s) / Double(samplesPerSegment)
                let t2 = t * t, t3 = t2 * t
                let a = p1 * 2
                let b = (p2 - p0) * t
                let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
                let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
                out.append((a + b + c + d) * 0.5)
            }
        }
        out.append(key[key.count - 1])
        return MotionPath(points: out)
    }

    /// Position at `fraction` (0…1) of the way along the path, measured by distance travelled.
    func point(atFraction fraction: Double) -> Vec2 {
        let total = length
        guard total > 0 else { return end }
        var remaining = min(max(fraction, 0), 1) * total
        for (a, b) in zip(points, points.dropFirst()) {
            let seg = (b - a).length
            if seg <= 0 { continue }
            if remaining <= seg { return a + (b - a) * (remaining / seg) }
            remaining -= seg
        }
        return end
    }

    /// Roughly one frame for every two pixels travelled.
    var suggestedFrameCount: Int {
        min(max(Int((length / 2).rounded()), 2), 24)
    }

    // MARK: Ramer–Douglas–Peucker

    static func simplify(_ pts: [Vec2], epsilon: Double) -> [Vec2] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (s, e) = stack.popLast() {
            guard e > s + 1 else { continue }
            var maxDistance = 0.0
            var index = -1
            for i in (s + 1)..<e {
                let d = distance(pts[i], toSegment: pts[s], pts[e])
                if d > maxDistance { maxDistance = d; index = i }
            }
            if maxDistance > epsilon, index >= 0 {
                keep[index] = true
                stack.append((s, index))
                stack.append((index, e))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    private static func distance(_ p: Vec2, toSegment a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let len2 = ab.x * ab.x + ab.y * ab.y
        guard len2 > 0 else { return (p - a).length }
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2, 0), 1)
        return (p - (a + ab * t)).length
    }
}

/// How a tween is drawn along a path.
enum TweenPathStyle: String, CaseIterable, Identifiable, Sendable {
    case traced, straight
    var id: String { rawValue }
    var title: String { self == .traced ? "Follow my drag" : "Straight line" }
}

/// Where generated in-between frames go.
enum TweenMode: String, CaseIterable, Identifiable, Sendable {
    /// Insert new frames after the current one.
    case insertFrames
    /// Re-draw the selection into the frames that already follow the current one.
    case spreadAcrossFollowing
    var id: String { rawValue }
    var title: String { self == .insertFrames ? "Insert new frames" : "Use existing next frames" }
}

/// Moves a patch of pixels along a path, one position per frame.
struct TweenPlan: Sendable {
    var sourceRect: PixelRect
    var patch: PixelPatch
    var path: MotionPath
    var easing: Easing

    /// Whole-pixel offsets for `count` frames. The last one is always the path's end.
    func offsets(count: Int) -> [PixelPoint] {
        guard count > 0 else { return [] }
        return (1...count).map { i in
            if i == count { return path.end.rounded }
            return path.point(atFraction: easing.apply(Double(i) / Double(count))).rounded
        }
    }

    /// `background` with the patch painted at `offset` from its original place.
    func render(onto background: PixelGrid, offset: PixelPoint) -> PixelGrid {
        var g = background
        g.stamp(patch, at: sourceRect.origin + offset)
        return g
    }

    /// For an existing frame: removes the patch from where it started, then paints it at `offset`.
    func move(in grid: PixelGrid, offset: PixelPoint) -> PixelGrid {
        var g = grid
        g.erase(patch, at: sourceRect.origin)
        g.stamp(patch, at: sourceRect.origin + offset)
        return g
    }
}
