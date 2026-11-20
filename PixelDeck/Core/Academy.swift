import Foundation

/// Pixel Academy: short lessons that end with a real animation. A lesson is a list of frames to
/// draw, each shown as a yellow guide on the canvas (as in the guided tour); when a frame's guide
/// is filled in the next frame is added, and the lesson ends by pressing Play. Titles and tips
/// are in the app layer (LocalizedTitlesV2).
struct Lesson: Identifiable, Sendable {
    let id: String
    /// Rough length, in minutes.
    let minutes: Int
    let isFree: Bool
    let fps: Int
    /// The squares to fill in on each frame, in world pixels (centred on the canvas).
    let frames: [[PixelPoint]]

    /// One step per frame, then "press Play".
    var stepCount: Int { frames.count + 1 }
}

enum Academy {
    /// A frame's guide counts as drawn when this much of it is filled.
    static let doneCoverage = 0.9

    static let lessons: [Lesson] = [
        Lesson(id: "blink", minutes: 3, isFree: true, fps: 6, frames: blinkingEye),
        Lesson(id: "walk", minutes: 8, isFree: true, fps: 8, frames: walkCycle),
        Lesson(id: "squash", minutes: 6, isFree: false, fps: 10, frames: squashAndStretch),
        Lesson(id: "campfire", minutes: 7, isFree: false, fps: 6, frames: campfire),
        Lesson(id: "coin", minutes: 4, isFree: false, fps: 8, frames: spinningCoin),
        Lesson(id: "explosion", minutes: 9, isFree: false, fps: 10, frames: explosion),
    ]

    static func lesson(id: String) -> Lesson? { lessons.first { $0.id == id } }

    /// The guide for a step, or nil for the last step (press Play).
    static func guide(_ lesson: Lesson, step: Int) -> [PixelPoint]? {
        lesson.frames.indices.contains(step) ? lesson.frames[step] : nil
    }

    /// Whether the step is finished. Drawing steps: the guide on that frame is filled. The last
    /// step: the animation has been played since the step began (`playCountAtStart`).
    static func isDone(_ lesson: Lesson, step: Int, model: EditorModel, playCountAtStart: Int) -> Bool {
        if let guide = guide(lesson, step: step) {
            return model.frameCount > step && GuidedTour.coverage(guide, in: model, frame: step) >= doneCoverage
        }
        return model.playCount > playCountAtStart
    }

    // MARK: Lesson art

    /// Points for rows of text where '#' is a filled square, centred on world (0, 0).
    static func points(_ rows: [String]) -> [PixelPoint] {
        let h = rows.count, w = rows.map(\.count).max() ?? 0
        var out: [PixelPoint] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { out.append(PixelPoint(x: x - w / 2, y: y - h / 2)) }
        }
        return out
    }

    private static func unique(_ pts: [PixelPoint]) -> [PixelPoint] {
        var seen = Set<PixelPoint>()
        return pts.filter { seen.insert($0).inserted }
    }

    /// A filled ellipse `w × h` whose bottom-centre sits at (cx, baseY).
    private static func blob(cx: Int, baseY: Int, w: Int, h: Int) -> [PixelPoint] {
        let r = PixelRect(x: cx - w / 2, y: baseY - h + 1, width: max(1, w), height: max(1, h))
        return ShapeRaster.points(.ellipse, from: r.origin, to: PixelPoint(x: r.maxX - 1, y: r.maxY - 1), filled: true)
    }

    /// Open, half shut, shut, half shut.
    static let blinkingEye: [[PixelPoint]] = {
        let open = ["...#####...",
                    ".##.....##.",
                    "#...###...#",
                    "#...###...#",
                    "#...###...#",
                    ".##.....##.",
                    "...#####..."]
        let half = ["...........",
                    "...#####...",
                    ".##.###.##.",
                    "#...###...#",
                    ".##.###.##.",
                    "...#####...",
                    "..........."]
        let shut = ["...........",
                    "...........",
                    "...........",
                    "###########",
                    ".#.#.#.#.#.",
                    "...........",
                    "..........."]
        return [points(open), points(half), points(shut), points(half)]
    }()

    /// Eight poses of a little walker: the legs and arms swing, and the body bobs.
    static let walkCycle: [[PixelPoint]] = (0..<8).map { k in
        let phase = 2 * Double.pi * Double(k) / 8
        let swing = sin(phase)
        // Lowest when the legs are apart, highest as they pass.
        let bob = Int((abs(swing) * 1.4).rounded())
        var pts: [PixelPoint] = []
        // Head (4 × 4) and body (2 wide, 5 tall).
        for y in -8..<(-4) { for x in -2..<2 { pts.append(PixelPoint(x: x, y: y + bob)) } }
        for y in -4..<1 { for x in -1..<1 { pts.append(PixelPoint(x: x, y: y + bob)) } }
        let hip = PixelPoint(x: 0, y: bob), shoulder = PixelPoint(x: 0, y: -3 + bob)
        func limb(from a: PixelPoint, length: Double, angle: Double) -> [PixelPoint] {
            let end = PixelPoint(x: a.x + Int((sin(angle) * length).rounded()), y: a.y + Int((cos(angle) * length).rounded()))
            let line = PixelGrid.linePoints(from: a, to: end)
            return line + line.map { PixelPoint(x: $0.x - 1, y: $0.y) }
        }
        // Legs reach the ground (y = 6); arms swing the opposite way.
        let ground = 6
        pts += limb(from: hip, length: Double(ground - bob), angle: swing * 0.6)
        pts += limb(from: hip, length: Double(ground - bob), angle: -swing * 0.6)
        pts += limb(from: shoulder, length: 4, angle: -swing * 0.8)
        pts += limb(from: shoulder, length: 4, angle: swing * 0.8)
        return unique(pts)
    }

    /// A ball falls, squashes on the ground and springs back up, stretched.
    static let squashAndStretch: [[PixelPoint]] = {
        // (width, height, height of the ball's base above the ground)
        let poses: [(Int, Int, Int)] = [(8, 8, 9), (7, 9, 5), (6, 10, 1), (11, 5, 0), (6, 10, 2), (7, 9, 6)]
        return poses.map { w, h, up in blob(cx: 0, baseY: 6 - up, w: w, h: h) }
    }()

    /// Two logs and a flame that leans left, stands, leans right, stands.
    static let campfire: [[PixelPoint]] = {
        let logs = ["#.......#",
                    ".##...##.",
                    "...###...",
                    ".##...##.",
                    "#.......#"]
        let flames = [
            ["...#.....",
             "..##.....",
             "..###....",
             ".####.#..",
             ".######..",
             ".#######.",
             "..#####.."],
            ["....#....",
             "....#....",
             "...###...",
             "..####...",
             ".######..",
             ".#######.",
             "..#####.."],
            [".....#...",
             ".....##..",
             "....###..",
             "..#.####.",
             "..######.",
             ".#######.",
             "..#####.."],
            ["....#....",
             "...##....",
             "...###...",
             "...####..",
             "..######.",
             ".#######.",
             "..#####.."],
        ]
        return flames.map { points($0 + logs) }
    }()

    /// A coin turning: full face, narrower, edge on, narrower.
    static let spinningCoin: [[PixelPoint]] = [8, 5, 2, 5].map { w in blob(cx: 0, baseY: 4, w: w, h: 9) }

    /// A flash that swells, opens into a ring and breaks into sparks.
    static let explosion: [[PixelPoint]] = {
        func ring(_ outer: Int, _ inner: Int) -> [PixelPoint] {
            var pts: [PixelPoint] = []
            for y in -outer...outer {
                for x in -outer...outer {
                    let d = (Double(x * x + y * y)).squareRoot()
                    if d <= Double(outer) + 0.3 && d >= Double(inner) - 0.3 { pts.append(PixelPoint(x: x, y: y)) }
                }
            }
            return pts
        }
        func sparks(_ radius: Int) -> [PixelPoint] {
            (0..<8).flatMap { i -> [PixelPoint] in
                let a = Double(i) * .pi / 4
                let x = Int((cos(a) * Double(radius)).rounded()), y = Int((sin(a) * Double(radius)).rounded())
                return [PixelPoint(x: x, y: y), PixelPoint(x: x + (x >= 0 ? -1 : 1) * (x == 0 ? 0 : 1), y: y)]
            }
        }
        return [ring(1, 0), ring(3, 0), ring(5, 0), ring(6, 4), unique(ring(7, 6) + sparks(4)), unique(sparks(8))]
    }()
}

/// Idea of the day: one drawing prompt a day, the same for everyone, with no streaks and nothing
/// lost by skipping a day. The prompts themselves are in the app layer (localised).
enum DailyIdea {
    /// Which of `count` ideas belongs to `date`: the days since a fixed date, in the user's calendar.
    static func index(for date: Date, count: Int, calendar: Calendar = .current) -> Int {
        guard count > 0 else { return 0 }
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        return ((days % count) + count) % count
    }
}
