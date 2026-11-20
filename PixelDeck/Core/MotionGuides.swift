import Foundation

/// Motion guides: stick-figure poses for common movements, shown on the canvas as a guide to
/// draw over, one pose per frame. They sit under your drawing like the tracing picture and are
/// never part of the art or of any export. Names are localised in the app layer.
enum MotionGuide: String, CaseIterable, Identifiable, Sendable {
    case walk, run, jump, idle

    var id: String { rawValue }

    var poseCount: Int {
        switch self {
        case .walk, .run: 8
        case .jump: 6
        case .idle: 4
        }
    }
}

enum MotionGuides {
    /// How tall the figure can be, in pixels.
    static let heights = [16, 24, 32, 48]

    /// Joint angles for one pose, in radians from straight down (positive swings forward, to the
    /// right), plus how far the body leans and how high the feet are off the ground.
    struct Pose {
        var lean = 0.0
        var thighA = 0.0, shinA = 0.0
        var thighB = 0.0, shinB = 0.0
        var armA = 0.0, foreA = 0.0
        var armB = 0.0, foreB = 0.0
        /// Feet above the ground, as a fraction of the figure's height.
        var lift = 0.0
    }

    static func pose(_ guide: MotionGuide, index: Int) -> Pose {
        let n = guide.poseCount
        let k = ((index % n) + n) % n
        let phase = 2 * Double.pi * Double(k) / Double(n)
        switch guide {
        case .walk:
            let a = 0.5 * sin(phase), b = -a
            // A leg bends as it swings forward under the body.
            let bendA = 0.7 * max(0, cos(phase)), bendB = 0.7 * max(0, -cos(phase))
            return Pose(lean: 0.05, thighA: a, shinA: a - bendA, thighB: b, shinB: b - bendB,
                        armA: -0.45 * sin(phase), foreA: -0.45 * sin(phase) + 0.25,
                        armB: 0.45 * sin(phase), foreB: 0.45 * sin(phase) + 0.25)
        case .run:
            let a = 0.95 * sin(phase), b = -a
            let bendA = 1.4 * max(0, cos(phase)) + 0.2, bendB = 1.4 * max(0, -cos(phase)) + 0.2
            return Pose(lean: 0.3, thighA: a, shinA: a - bendA, thighB: b, shinB: b - bendB,
                        armA: -0.9 * sin(phase), foreA: -0.9 * sin(phase) + 1.3,
                        armB: 0.9 * sin(phase), foreB: 0.9 * sin(phase) + 1.3,
                        lift: 0.05 * abs(sin(phase)))
        case .jump:
            // Crouch, push off, rise, tuck at the top, fall, land.
            let table: [Pose] = [
                Pose(lean: 0.25, thighA: 0.9, shinA: -0.6, thighB: 0.9, shinB: -0.6, armA: -0.9, foreA: -0.6, armB: -0.9, foreB: -0.6),
                Pose(lean: 0.1, thighA: 0.2, shinA: 0, thighB: 0.2, shinB: 0, armA: 1.6, foreA: 2.2, armB: 1.6, foreB: 2.2, lift: 0.06),
                Pose(lean: 0, thighA: 0.1, shinA: -0.2, thighB: -0.1, shinB: -0.3, armA: 2.6, foreA: 2.9, armB: 2.6, foreB: 2.9, lift: 0.3),
                Pose(lean: 0.05, thighA: 1.0, shinA: -0.5, thighB: 0.8, shinB: -0.7, armA: 1.8, foreA: 2.2, armB: 1.8, foreB: 2.2, lift: 0.42),
                Pose(lean: 0, thighA: 0.3, shinA: 0.1, thighB: -0.1, shinB: -0.3, armA: 2.2, foreA: 2.6, armB: 2.2, foreB: 2.6, lift: 0.22),
                Pose(lean: 0.3, thighA: 1.0, shinA: -0.6, thighB: 1.0, shinB: -0.6, armA: 0.6, foreA: 0.9, armB: 0.6, foreB: 0.9),
            ]
            return table[k]
        case .idle:
            // Breathing: the knees give a little and the arms hang.
            let squat = [0.0, 0.18, 0.0, -0.0][k]
            return Pose(thighA: squat, shinA: -squat, thighB: squat, shinB: -squat,
                        armA: 0.08, foreA: 0.12 + squat, armB: -0.08, foreB: -0.04 + squat)
        }
    }

    /// The pixels of pose `index`, for a figure `height` pixels tall standing on world y =
    /// `height / 2` (so it is centred on the canvas origin).
    static func points(_ guide: MotionGuide, index: Int, height: Int) -> [PixelPoint] {
        let h = Double(max(height, 12))
        let p = pose(guide, index: index)
        let head = max(1.5, h * 0.11), torso = h * 0.3, thigh = h * 0.23, shin = h * 0.23, upper = h * 0.17, fore = h * 0.15

        func step(_ from: (Double, Double), _ length: Double, _ angle: Double) -> (Double, Double) {
            (from.0 + sin(angle) * length, from.1 + cos(angle) * length)
        }
        // Built from the hip, then dropped so the lowest foot rests on the ground (minus lift).
        let hip = (0.0, 0.0)
        let neck = (hip.0 + sin(p.lean) * torso, hip.1 - cos(p.lean) * torso)
        let headCentre = (neck.0 + sin(p.lean) * head, neck.1 - cos(p.lean) * head)
        let kneeA = step(hip, thigh, p.thighA), footA = step(kneeA, shin, p.shinA)
        let kneeB = step(hip, thigh, p.thighB), footB = step(kneeB, shin, p.shinB)
        let shoulder = (neck.0, neck.1 + h * 0.03)
        let elbowA = step(shoulder, upper, p.armA), handA = step(elbowA, fore, p.foreA)
        let elbowB = step(shoulder, upper, p.armB), handB = step(elbowB, fore, p.foreB)

        let lowest = max(footA.1, footB.1)
        let ground = h / 2
        let dy = ground - lowest - p.lift * h
        func px(_ q: (Double, Double)) -> PixelPoint { PixelPoint(x: Int(q.0.rounded()), y: Int((q.1 + dy).rounded())) }

        var pts: [PixelPoint] = []
        for (a, b) in [(hip, neck), (hip, kneeA), (kneeA, footA), (hip, kneeB), (kneeB, footB),
                       (shoulder, elbowA), (elbowA, handA), (shoulder, elbowB), (elbowB, handB)] {
            pts += PixelGrid.linePoints(from: px(a), to: px(b))
        }
        let c = px(headCentre)
        let r = Int(head.rounded())
        for y in -r...r {
            for x in -r...r where Double(x * x + y * y) <= (head + 0.3) * (head + 0.3) {
                pts.append(PixelPoint(x: c.x + x, y: c.y + y))
            }
        }
        var seen = Set<PixelPoint>()
        return pts.filter { seen.insert($0).inserted }
    }
}
