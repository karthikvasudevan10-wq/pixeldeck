import Foundation

/// The guided tour: a new user draws a heart and makes it bounce in three frames, and on the way
/// meets every gesture and hidden menu, finishing with the swipe right to start their own canvas.
/// Each step finishes by itself when the user has done it (`isDone`), except the two that only
/// explain things, which have a Next button. The words are in the app layer (LocalizedTitles).
enum TourStep: Int, CaseIterable, Sendable {
    case pickColor, drawHeart, undoRedo, zoom, addFrame, drawSecondHeart, onion, duplicate, reorder, play, moreTools, newCanvas

    /// Steps that only explain something, finished with a Next button.
    var hasNextButton: Bool { self == .zoom || self == .moreTools }

    /// What to point at while this step is showing.
    var target: TourTarget {
        switch self {
        case .pickColor: .swatch(GuidedTour.pinkIndex)
        case .drawHeart, .drawSecondHeart: .canvas
        case .undoRedo: .undo
        case .zoom, .moreTools: .none
        case .addFrame: .rightEdge
        case .onion: .onion
        case .duplicate: .frame(0)
        case .reorder: .frame(1)
        case .play: .play
        case .newCanvas: .leftEdge
        }
    }

    var next: TourStep? { TourStep(rawValue: rawValue + 1) }
}

/// A control the tour highlights.
enum TourTarget: Hashable, Sendable {
    case none, canvas, swatch(Int), undo, redo, onion, frame(Int), play, rightEdge, leftEdge
}

/// What the model looked like when a step started, for steps that wait for something to change.
struct TourBaseline: Equatable, Sendable {
    var undoCount = 0
    var redoCount = 0
    var onionOpacity = 0.0
    var playCount = 0

    init() {}

    init(_ model: EditorModel) {
        undoCount = model.undoCount
        redoCount = model.redoCount
        onionOpacity = model.onionOpacity
        playCount = model.playCount
    }
}

enum GuidedTour {
    /// The default palette's pink.
    static let pinkIndex = 6
    static var pink: RGBA { SpriteProject.defaultPalette[pinkIndex] }

    /// A 7 × 6 heart around world (0, 0): the first frame's guide.
    static let heart: [PixelPoint] = {
        let rows = [".##.##.",
                    "#######",
                    "#######",
                    ".#####.",
                    "..###..",
                    "...#..."]
        var out: [PixelPoint] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { out.append(PixelPoint(x: x - 3, y: y - 3)) }
        }
        return out
    }()

    /// The second frame's heart: the same, two pixels higher, so it bounces.
    static let raisedHeart: [PixelPoint] = heart.map { PixelPoint(x: $0.x, y: $0.y - 2) }

    /// Dotted squares to fill in, for the drawing steps.
    static func guide(for step: TourStep) -> [PixelPoint]? {
        switch step {
        case .drawHeart: heart
        case .drawSecondHeart: raisedHeart
        default: nil
        }
    }

    /// Share of `points` painted (any colour) on a frame.
    static func coverage(_ points: [PixelPoint], in model: EditorModel, frame: Int) -> Double {
        guard !points.isEmpty, model.project.frames.indices.contains(frame) else { return 0 }
        let painted = points.filter { !model.pixel($0, frame: frame).isClear }.count
        return Double(painted) / Double(points.count)
    }

    /// A drawing step counts as done when nearly all of the guide is filled.
    static let doneCoverage = 0.85

    /// Whether the user has done what `step` asks. `tourProjectID` is the tour's sprite (the last
    /// step finishes when the user has swiped to a new one).
    static func isDone(_ step: TourStep, model: EditorModel, baseline: TourBaseline, tourProjectID: UUID) -> Bool {
        let frames = model.project.frames
        switch step {
        case .pickColor:
            return model.color == pink
        case .drawHeart:
            return coverage(heart, in: model, frame: 0) >= doneCoverage
        case .undoRedo:
            return model.redoCount > baseline.redoCount
        case .zoom, .moreTools:
            return false                                  // Next button
        case .addFrame:
            return frames.count >= 2 && model.currentIndex >= 1
        case .drawSecondHeart:
            return frames.count >= 2 && coverage(raisedHeart, in: model, frame: 1) >= doneCoverage
        case .onion:
            return model.onionOpacity != baseline.onionOpacity
        case .duplicate:
            return frames.count >= 3
        case .reorder:
            // Down, up, down: the last frame matches the first, the middle one differs.
            return frames.count >= 3 && frames[frames.count - 1].grid == frames[0].grid && frames[1].grid != frames[0].grid
        case .play:
            return model.playCount > baseline.playCount
        case .newCanvas:
            return model.project.id != tourProjectID
        }
    }
}
