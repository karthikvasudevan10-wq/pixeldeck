import Foundation
import Observation

/// Drawing tools. Mirror is a mode (`EditorModel.mirror`), not a tool. Display names are
/// localised in the app layer (LocalizedTitles.swift).
enum Tool: String, CaseIterable, Identifiable, Sendable {
    /// `shape` draws the kind chosen in `EditorModel.shapeKind`.
    case pencil, eraser, fill, eyedropper, select, shape

    var id: String { rawValue }
}

/// Everything the canvas view needs to draw one state of the editor. Rectangles and points are in
/// world pixel coordinates; `grid` covers `bounds`.
struct CanvasState: Equatable {
    var bounds: PixelRect
    var grid: PixelGrid
    /// Changes whenever `grid` does, so the view can tell without comparing every pixel.
    var gridVersion: Int
    /// The frame just before the current one (nil when onion skin shows nothing behind).
    var onion: PixelGrid?
    /// Identifies the whole set of onion frames, before and after.
    var onionVersion: Int?
    /// Earlier frames, nearest first (drawn pink), and later frames, nearest first (blue).
    var onionBefore: [PixelGrid] = []
    var onionAfter: [PixelGrid] = []
    var onionOpacity: Double
    var showGrid: Bool
    /// Marquee or floating-selection outline.
    var selection: PixelRect?
    /// The exact pixels of a lasso or wand selection (nil for plain rectangles).
    var selectionMask: SelectionMask? = nil
    /// The lasso line being drawn.
    var lasso: [PixelPoint]? = nil
    /// Path the selection's centre has travelled.
    var motionPath: [Vec2]?
    /// Show the mirror axis (world x = 0).
    var mirror: Bool
    /// Show the top-bottom symmetry axis (world y = 0).
    var mirrorVertical: Bool = false
    /// The tracing picture's placement and opacity, if one is shown (never during playback).
    var trace: TraceSettings? = nil
    /// Squares to fill in (the guided tour's dotted guide, a lesson's, or a motion guide's pose),
    /// in world pixels.
    var guide: [PixelPoint]? = nil
    /// The poses either side of a motion guide's, drawn faintly.
    var guideGhost: [PixelPoint]? = nil

    /// Compares versions rather than pixels: cheap enough to run on every touch.
    static func == (l: CanvasState, r: CanvasState) -> Bool {
        l.gridVersion == r.gridVersion && l.onionVersion == r.onionVersion && l.bounds == r.bounds
            && l.onionOpacity == r.onionOpacity && l.showGrid == r.showGrid && l.selection == r.selection
            && l.motionPath == r.motionPath && l.mirror == r.mirror && l.mirrorVertical == r.mirrorVertical
            && l.trace == r.trace && l.guide == r.guide && l.guideGhost == r.guideGhost
            && l.selectionMask == r.selectionMask && l.lasso == r.lasso
    }
}

/// Where the user is looking on the infinite canvas: how many points one art pixel takes on
/// screen (the zoom), and the world point at the centre of the view. Kept across folds,
/// rotations and layout changes.
struct Viewport: Equatable, Sendable {
    var pixelSize: Double
    var centerX: Double
    var centerY: Double

    static let minPixelSize = 1.0
    static let maxPixelSize = 64.0
    /// A new canvas: about 24 art pixels across an iPhone.
    static let initial = Viewport(pixelSize: 16, centerX: 0, centerY: 0)
}

/// The editing session for one sprite. Platform-independent so it can be unit-tested.
///
/// The canvas is unbounded: drawing outside the stored `bounds` grows every frame (up to the
/// plan's art-size cap), and after each edit the bounds shrink back to the art plus a margin.
@Observable
final class EditorModel {
    /// Change it through the editing methods (or `updateProject` for settings), not directly.
    var project: SpriteProject
    private(set) var currentIndex = 0

    var tool: Tool = .pencil {
        didSet {
            if tool != .select { commitSelection() }
            if tool != oldValue { previousTool = oldValue }
        }
    }
    /// For Apple Pencil's "switch to previous tool" and toggling the eraser.
    private(set) var previousTool: Tool = .pencil
    /// Mirror drawing across world x = 0 (pencil, eraser, fill and shapes).
    var mirror = false
    /// Top-bottom symmetry (Pro). With `mirror` too, it's four-way.
    var mirrorVertical = false {
        didSet {
            if mirrorVertical && !access.allowsArtistBrushes { mirrorVertical = false; onProRequired?(.artistBrushes) }
        }
    }
    /// Pencil and eraser size in pixels, 1–4.
    var brushSize = 1 {
        didSet {
            // Only reassign when out of range: in an @Observable class this observer runs again.
            let clamped = min(max(brushSize, 1), EditorModel.maxBrushSize)
            if clamped != brushSize { brushSize = clamped }
        }
    }
    static let maxBrushSize = 4
    /// Round brush tips (sizes 3 and 4); square otherwise.
    var brushRound = false
    /// Dither brush (Pro): paints only every other pixel, in a checkerboard fixed to the canvas.
    var dither = false {
        didSet {
            // Dither is part of every retro canvas; elsewhere it comes with Pro.
            if dither && !access.allowsArtistBrushes && project.retroMode == nil { dither = false; onProRequired?(.artistBrushes) }
        }
    }
    /// Pixel-perfect strokes: L-shaped corners are cleaned as you draw, so 1-pixel lines and
    /// curves stay 1 pixel wide. On for everyone by default.
    var pixelPerfect = true
    /// The shading assistant: when set, the pencil shades or highlights instead of drawing.
    var shadeMode: ShadeMode? = nil
    var lightDirection: LightDirection = .topLeft
    /// The ramp the shading assistant (and the Ramps panel) steps through.
    var rampSteps = 5 {
        didSet {
            let c = min(max(rampSteps, ColorRamp.stepRange.lowerBound), ColorRamp.stepRange.upperBound)
            if c != rampSteps { rampSteps = c }
        }
    }
    var rampHueShift = 18.0
    /// How the Select tool picks pixels.
    var selectionMode: SelectionMode = .box
    /// How many earlier (0–3) and later (0–2) frames the onion skin shows.
    var onionBefore = 1 {
        didSet {
            let c = min(max(onionBefore, 0), EditorModel.maxOnionBefore)
            if c != onionBefore { onionBefore = c }
        }
    }
    var onionAfter = 0 {
        didSet {
            let c = min(max(onionAfter, 0), EditorModel.maxOnionAfter)
            if c != onionAfter { onionAfter = c }
        }
    }
    static let maxOnionBefore = 3
    static let maxOnionAfter = 2
    /// A motion guide (Pro): a stick-figure pose to draw over on each frame. Never part of the art.
    var motionGuide: MotionGuide? = nil {
        didSet {
            if motionGuide != nil && !access.allowsMotionGuides { motionGuide = nil; onProRequired?(.motionGuides) }
        }
    }
    /// How tall the motion guide's figure is, in pixels.
    var motionGuideHeight = 24
    var shapeKind: ShapeKind = .rectangle
    var shapeFilled = false
    /// Outline thickness for shapes, 1–4 pixels.
    var shapeThickness = 1 {
        didSet {
            let c = min(max(shapeThickness, ShapeRaster.thicknessRange.lowerBound), ShapeRaster.thicknessRange.upperBound)
            if c != shapeThickness { shapeThickness = c }
        }
    }
    /// Squares, circles, equal-sided triangles, and lines snapped to 0°/45°/90°.
    var lockProportions = false
    /// The layer being drawn on (index into `project.layers`, bottom first).
    private(set) var activeLayer = 0
    /// Names for new layers, localised by the app.
    @ObservationIgnored var newLayerName: (Int) -> String = { "Layer \($0)" }
    @ObservationIgnored var shapesLayerName = "Shapes"
    private(set) var color: RGBA = SpriteProject.defaultPalette[2]
    var showGrid = true
    var onionSkinEnabled = true
    /// The design draws the previous frame as a flat accent tint at 38%.
    var onionOpacity = 0.38
    /// Playing the animation in place on the canvas. Drawing is paused meanwhile.
    var isPlaying = false {
        didSet {
            if isPlaying { commitSelection() }
            if isPlaying && !oldValue {
                playStartedAt = Date()
                playCount += 1
            }
        }
    }
    /// How many times these were used (the guided tour watches them).
    private(set) var undoCount = 0
    private(set) var redoCount = 0
    private(set) var playCount = 0
    /// When playback last began (for animations that play once and stop).
    @ObservationIgnored private(set) var playStartedAt = Date()

    /// A selected area that hasn't been moved yet (world).
    var marquee: PixelRect?
    /// The exact pixels of a lasso or wand selection (`marquee` is then its bounding box).
    var marqueeMask: SelectionMask?
    /// The lasso line while it's being drawn.
    private(set) var lassoTrail: [PixelPoint]?
    /// A selection that has been lifted and is being moved.
    var floating: FloatingSelection?
    /// Whether the floating selection is an irregular shape (lasso, wand, or turned).
    @ObservationIgnored var floatingIsMasked = false

    /// The stroke so far, for pixel-perfect clean-up, and how many times it painted each pixel.
    @ObservationIgnored private var strokePath: [PixelPoint] = []
    @ObservationIgnored private var strokePainted: [PixelPoint: Int] = [:]

    /// A colour adjustment in progress: the art as it was, and the selected pixels.
    @ObservationIgnored var adjustBase: Snapshot?
    @ObservationIgnored var adjustMask: SelectionMask?

    struct Snapshot {
        var frames: [Frame]
        var bounds: PixelRect
        var currentIndex: Int
        var layers: [LayerInfo]
        var activeLayer: Int
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let undoLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Called after every finished edit with the project to save.
    @ObservationIgnored var onChange: ((SpriteProject) -> Void)?

    /// Last reported canvas viewport. Not observed: it changes on every scroll.
    @ObservationIgnored var viewport: Viewport?
    /// How many screen points one art pixel takes, for the zoom read-out (it changes only when
    /// the zoom does, so it's fine to observe).
    var zoom = Viewport.initial.pixelSize

    /// What the user has unlocked. Set by the app from the purchase state.
    var access: FeatureAccess = .free
    /// Called when an action needs Pro, so the app can offer the upgrade.
    @ObservationIgnored var onProRequired: ((ProFeature) -> Void)?

    private enum Gesture {
        case none
        case stroke(last: PixelPoint, color: RGBA, before: Snapshot)
        case marquee(start: PixelPoint)
        case move(start: Vec2, startOffset: Vec2, pathCount: Int)
        /// Drawing a lasso around pixels.
        case lasso
        /// The shading assistant: recolours the touched shape along `ramp`.
        case shade(last: PixelPoint, ramp: [RGBA], baseIndex: Int, region: PixelRect, before: Snapshot)
        /// Dragging out a shape: the layer as it was, redrawn with the shape on every move.
        case shape(start: PixelPoint, base: PixelGrid, baseBounds: PixelRect, before: Snapshot)
        /// Fill or colour pick: applied when the finger lifts, so a touch that turns into a
        /// pinch or pan changes nothing.
        case tap(PixelPoint)
    }
    @ObservationIgnored private var gesture: Gesture = .none
    /// Only offer Pro once per gesture, not on every finger movement.
    @ObservationIgnored var promptedThisGesture = false
    /// Offered when the finger lifts: presenting the paywall mid-stroke would cancel the touch
    /// and throw the stroke away.
    @ObservationIgnored private var pendingPro: ProFeature?

    /// World rectangle of all drawn pixels, cached because scanning every frame is costly.
    @ObservationIgnored private var cachedContent: PixelRect?
    @ObservationIgnored var contentKnown = false

    /// Extra room added when the canvas grows, so it doesn't reallocate on every pixel.
    private let growMargin = 8
    /// Empty border kept around the art when the canvas shrinks back.
    private let restMargin = 2

    init(project: SpriteProject) {
        self.project = project
    }

    /// Switch to a different sprite, e.g. after "new canvas".
    func load(_ project: SpriteProject) {
        commitSelection()
        self.project = project
        currentIndex = 0
        viewport = nil
        marquee = nil
        marqueeMask = nil
        lassoTrail = nil
        floating = nil
        adjustBase = nil
        adjustMask = nil
        isPlaying = false
        activeLayer = max(0, project.layers.count - 1)
        undoStack = []
        redoStack = []
        gesture = .none
        contentKnown = false
    }

    // MARK: Derived state

    var bounds: PixelRect { project.bounds }
    var frameCount: Int { project.frames.count }
    /// The current frame, all visible layers flattened.
    var currentGrid: PixelGrid { project.frames[currentIndex].grid }
    /// The active layer's cel in the current frame.
    var currentLayerGrid: PixelGrid { project.frames[currentIndex].layers[activeLayer] }
    var layers: [LayerInfo] { project.layers }
    var palette: [RGBA] { project.palette }
    /// Retro canvases keep their mode's colours: swatches can't be changed or swapped.
    var isPaletteLocked: Bool { project.retroMode != nil }

    /// Colour at a world pixel in a frame (the current one by default); clear outside the canvas.
    func pixel(_ p: PixelPoint, frame: Int? = nil) -> RGBA {
        let i = frame ?? currentIndex
        guard project.frames.indices.contains(i) else { return .clear }
        return project.frames[i].grid[p - bounds.origin]
    }

    var onionGrid: PixelGrid? {
        guard onionSkinEnabled, currentIndex > 0 else { return nil }
        return project.frames[currentIndex - 1].grid
    }

    var selectionRect: PixelRect? { floating?.currentRect ?? marquee }

    var canTween: Bool { floating.map { !$0.path.isTrivial } ?? false }

    var followingFrameCount: Int { project.frames.count - currentIndex - 1 }

    var suggestedTweenFrames: Int { floating?.path.refined().suggestedFrameCount ?? 8 }

    /// World rectangle of everything drawn, or nil for a blank sprite.
    var contentBounds: PixelRect? {
        if !contentKnown {
            cachedContent = project.contentBounds
            contentKnown = true
        }
        return cachedContent
    }

    /// `playingFrame` shows that frame without onion skin or selection (for in-place playback).
    func canvasState(playingFrame: Int? = nil) -> CanvasState {
        if let i = playingFrame, project.frames.indices.contains(i) {
            let f = project.frames[i]
            return CanvasState(bounds: bounds, grid: f.grid, gridVersion: f.version, onion: nil, onionVersion: nil,
                               onionOpacity: onionOpacity, showGrid: showGrid, selection: nil, motionPath: nil, mirror: false)
        }
        var path: [Vec2]?
        if let f = floating, !f.path.isTrivial {
            let c = f.sourceRect.center
            path = f.path.refined().points.map { $0 + c }
        }
        let current = project.frames[currentIndex]
        var before: [Frame] = [], after: [Frame] = []
        if onionSkinEnabled {
            before = (0..<onionBefore).map { currentIndex - 1 - $0 }.filter { $0 >= 0 }.map { project.frames[$0] }
            after = (0..<onionAfter).map { currentIndex + 1 + $0 }.filter { $0 < project.frames.count }.map { project.frames[$0] }
        }
        var version: Int?
        if !before.isEmpty || !after.isEmpty {
            var h = Hasher()
            for f in before { h.combine(f.version) }
            h.combine(-1)
            for f in after { h.combine(f.version) }
            version = h.finalize()
        }
        var mask: SelectionMask?
        if let f = floating { mask = floatingIsMasked ? f.currentMask : nil } else { mask = marqueeMask }
        var pose: [PixelPoint]?, neighbours: [PixelPoint]?
        if let g = motionGuide {
            pose = MotionGuides.points(g, index: currentIndex, height: motionGuideHeight)
            neighbours = MotionGuides.points(g, index: currentIndex - 1, height: motionGuideHeight)
                + MotionGuides.points(g, index: currentIndex + 1, height: motionGuideHeight)
        }
        return CanvasState(bounds: bounds, grid: current.grid, gridVersion: current.version,
                           onion: before.first?.grid, onionVersion: version,
                           onionBefore: before.map(\.grid), onionAfter: after.map(\.grid),
                           onionOpacity: onionOpacity, showGrid: showGrid, selection: selectionRect,
                           selectionMask: mask, lasso: lassoTrail, motionPath: path, mirror: mirror,
                           mirrorVertical: mirrorVertical,
                           trace: project.trace?.isVisible == true ? project.trace : nil,
                           guide: pose, guideGhost: neighbours)
    }

    // MARK: Tool switching (Apple Pencil double-tap / squeeze, keyboard)

    /// Eraser on, or back to the tool you were using.
    func toggleEraser() {
        if tool == .eraser {
            tool = previousTool == .eraser ? .pencil : previousTool
        } else {
            tool = .eraser
        }
    }

    func switchToPreviousTool() {
        let p = previousTool
        if p != tool { tool = p }
    }

    /// Previous/next frame, wrapping around (arrow keys).
    func stepFrame(_ delta: Int) {
        guard frameCount > 1 else { return }
        isPlaying = false
        selectFrame(((currentIndex + delta) % frameCount + frameCount) % frameCount)
    }

    // MARK: Colour

    func pickColor(_ c: RGBA) {
        color = RGBA(r: c.r, g: c.g, b: c.b, a: 255)
        if tool == .eraser || tool == .eyedropper { tool = .pencil }
    }

    /// Long-press edit of a palette swatch. Also selects the new colour. Pass `commit: false`
    /// for live updates while the picker is being dragged (shown, not saved yet).
    func setPaletteColor(_ c: RGBA, at index: Int, commit: Bool = true) {
        guard project.palette.indices.contains(index), !isPaletteLocked else { return }
        let opaque = RGBA(r: c.r, g: c.g, b: c.b, a: 255)
        project.palette[index] = opaque
        color = opaque
        if commit { finishEdit() }
    }

    // MARK: Touch input (world pixel coordinates, fractional)

    func touchBegan(at v: Vec2) {
        let p = v.pixel
        promptedThisGesture = false
        switch tool {
        case .pencil where shadeMode != nil:
            beginShade(at: p)

        case .pencil, .eraser:
            let c: RGBA = tool == .pencil ? color : .clear
            gesture = .stroke(last: p, color: c, before: snapshot())
            strokePath = []
            strokePainted = [:]
            revealActiveLayer()
            paintSegment(from: p, to: p, color: c)

        case .fill, .eyedropper:
            gesture = .tap(p)

        case .shape:
            autoCreateShapesLayer()
            revealActiveLayer()
            gesture = .shape(start: p, base: currentLayerGrid, baseBounds: bounds, before: snapshot())
            drawShape(from: p, to: p)

        case .select:
            if let f = floating, f.currentRect.contains(p) {
                gesture = .move(start: v, startOffset: f.exactOffset, pathCount: f.path.points.count)
            } else if let m = marquee, m.contains(p), marqueeMask?.contains(p) ?? true {
                lift(m)
                gesture = .move(start: v, startOffset: .zero, pathCount: 1)
            } else {
                commitSelection()
                switch selectionMode {
                case .box:
                    marquee = PixelRect(corner: p, p)
                    gesture = .marquee(start: p)
                case .lasso:
                    lassoTrail = [p]
                    gesture = .lasso
                case .wand:
                    gesture = .tap(p)
                }
            }
        }
    }

    func touchMoved(to v: Vec2) {
        switch gesture {
        case .none, .tap:
            break
        case let .shape(start, _, _, _):
            drawShape(from: start, to: v.pixel)
        case let .stroke(last, c, before):
            let p = v.pixel
            guard p != last else { return }
            paintSegment(from: last, to: p, color: c)
            gesture = .stroke(last: p, color: c, before: before)
        case let .marquee(start):
            marquee = PixelRect(corner: start, v.pixel)
        case .lasso:
            let p = v.pixel
            if lassoTrail?.last != p { lassoTrail?.append(p) }
        case let .shade(last, ramp, baseIndex, region, before):
            let p = v.pixel
            guard p != last else { return }
            shadeSegment(from: last, to: p, ramp: ramp, baseIndex: baseIndex, region: region)
            gesture = .shade(last: p, ramp: ramp, baseIndex: baseIndex, region: region, before: before)
        case let .move(start, startOffset, _):
            guard var f = floating else { return }
            let next = startOffset + (v - start)
            // The canvas grows to follow the selection, up to the art-size cap; past that the
            // selection stops at the edge.
            if let r = f.opaqueRect(at: next.rounded), !ensureCovers(r) { return }
            if let current = floating { f = current }
            f.exactOffset = next
            f.path.append(next)
            floating = f
            mutateCurrent { $0 = f.composited() }
        }
    }

    func touchEnded() {
        let ended = gesture
        gesture = .none   // first, so finishEdit can trim the canvas
        switch ended {
        case let .stroke(_, _, before), let .shade(_, _, _, _, before):
            pushUndo(before)
            strokePath = []
            strokePainted = [:]
            finishEdit()
        case .lasso:
            let trail = lassoTrail ?? []
            lassoTrail = nil
            // A tap or a tiny scribble selects nothing.
            let mask = Set(trail).count >= 3 ? SelectionMask.lasso(trail)?.clipped(to: bounds) : nil
            marqueeMask = mask
            marquee = mask?.rect
        case .move:
            finishEdit()
        case let .shape(_, _, _, before):
            pushUndo(before)
            contentKnown = false
            finishEdit()
        case let .tap(p):
            if tool == .select {
                // Magic wand: every touching pixel of the tapped colour, on the active layer.
                let mask = SelectionMask.wand(in: currentLayerGrid, at: p - bounds.origin, origin: bounds.origin)
                marqueeMask = mask
                marquee = mask?.rect
            } else if tool == .fill {
                fill(at: p)
            } else {
                let c = currentGrid[p - bounds.origin]
                if !c.isClear {
                    color = c
                    tool = .pencil
                }
            }
        case .marquee, .none:
            break
        }
        offerPendingPro()
    }

    /// The touch turned into a pinch or pan: undo whatever it did.
    func touchCancelled() {
        switch gesture {
        case let .stroke(_, _, before), let .shape(_, _, _, before), let .shade(_, _, _, _, before):
            project.frames = before.frames
            project.bounds = before.bounds
            project.layers = before.layers
            activeLayer = before.activeLayer
            contentKnown = false
        case let .move(_, startOffset, pathCount):
            if var f = floating {
                f.exactOffset = startOffset
                f.path.truncate(toCount: pathCount)
                floating = f
                mutateCurrent { $0 = f.composited() }
            }
        case .marquee:
            marquee = nil
        case .lasso:
            lassoTrail = nil
        case .none, .tap:
            break
        }
        gesture = .none
        offerPendingPro()
    }

    func requestPro(_ feature: ProFeature) {
        if case .none = gesture { onProRequired?(feature) } else { pendingPro = feature }
    }

    private func offerPendingPro() {
        if let f = pendingPro {
            pendingPro = nil
            onProRequired?(f)
        }
    }

    // MARK: Painting on the infinite canvas

    /// Draws a line in world coordinates, growing the canvas as needed (and mirrored if on).
    /// A point and its reflections for the symmetry that's on (left-right, top-bottom or both).
    func symmetric(_ p: PixelPoint) -> [PixelPoint] {
        var out = [p]
        if mirror { out.append(p.mirrored) }
        if mirrorVertical { out += out.map(\.flippedVertically) }
        var seen = Set<PixelPoint>()
        return out.filter { seen.insert($0).inserted }
    }

    /// The pixels the brush covers when centred on `p` (before dither and symmetry).
    func brushFootprint(at p: PixelPoint) -> [PixelPoint] {
        let n = brushSize
        guard n > 1 else { return [p] }
        let lo = -(n - 1) / 2, hi = n / 2
        var out: [PixelPoint] = []
        for dy in lo...hi {
            for dx in lo...hi {
                // Round tips drop the corners.
                if brushRound && n >= 3 && (dx == lo || dx == hi) && (dy == lo || dy == hi) { continue }
                out.append(PixelPoint(x: p.x + dx, y: p.y + dy))
            }
        }
        return out
    }

    /// Pixel-perfect needs a 1-pixel solid brush.
    var pixelPerfectActive: Bool { pixelPerfect && brushSize == 1 && !dither }

    /// Paints a segment of a pixel-perfect stroke: when the last three pixels of the stroke form
    /// an L, the corner pixel goes back to what it was before the stroke.
    private func paintPixelPerfect(from a: PixelPoint, to b: PixelPoint, color c: RGBA, before: Snapshot) {
        for p in PixelGrid.linePoints(from: a, to: b) {
            if strokePath.last == p { continue }
            strokePath.append(p)
            let copies = symmetric(p)
            for s in copies { strokePainted[s, default: 0] += 1 }
            paintPixels(copies, color: c)
            let n = strokePath.count
            guard n >= 3, PixelPerfect.isCorner(strokePath[n - 3], strokePath[n - 2], strokePath[n - 1]) else { continue }
            let corner = strokePath.remove(at: n - 2)
            for s in symmetric(corner) {
                let left = (strokePainted[s] ?? 1) - 1
                strokePainted[s] = left
                // Still part of the stroke somewhere else (it crossed itself): keep it.
                guard left <= 0, bounds.contains(s), before.frames.indices.contains(currentIndex),
                      before.frames[currentIndex].layers.indices.contains(activeLayer) else { continue }
                let old = before.frames[currentIndex].layers[activeLayer][s - before.bounds.origin]
                let o = bounds.origin
                mutateCurrent(dirty: PixelRect(x: s.x, y: s.y, width: 1, height: 1)) { $0[s - o] = old }
                contentKnown = false
            }
        }
    }

    private func paintSegment(from a: PixelPoint, to b: PixelPoint, color c: RGBA) {
        if pixelPerfectActive, case let .stroke(_, _, before) = gesture {
            paintPixelPerfect(from: a, to: b, color: c, before: before)
            return
        }
        // A 1-pixel solid brush with at most left-right symmetry draws whole lines (fast path).
        if brushSize > 1 || dither || mirrorVertical {
            var pixels = Set<PixelPoint>()
            for p in PixelGrid.linePoints(from: a, to: b) {
                for q in brushFootprint(at: p) {
                    for s in symmetric(q) where !dither || ((s.x + s.y) & 1) == 0 { pixels.insert(s) }
                }
            }
            paintPixels(Array(pixels), color: c)
            return
        }
        var segments = [(a, b)]
        if mirror { segments.append((a.mirrored, b.mirrored)) }
        for (s, e) in segments {
            let r = PixelRect(corner: s, e)
            if c.isClear {
                // Erasing never needs to grow the canvas; there's nothing outside it.
                let o = bounds.origin
                mutateCurrent(dirty: r) { $0.drawLine(from: s - o, to: e - o, color: c) }
                contentKnown = false
            } else if ensureCovers(r) {
                let o = bounds.origin
                mutateCurrent(dirty: r) { $0.drawLine(from: s - o, to: e - o, color: c) }
                if contentKnown { cachedContent = cachedContent.map { $0.union(r) } ?? r }
            } else {
                // Part of the segment is past the art-size cap: paint only the pixels that keep
                // the art within it (the canvas's spare margin mustn't let art exceed the cap).
                for p in PixelGrid.linePoints(from: s, to: e) {
                    let one = PixelRect(x: p.x, y: p.y, width: 1, height: 1)
                    guard access.allowsArt(contentBounds.map { $0.union(one) } ?? one), ensureCovers(one) else { continue }
                    let o = bounds.origin
                    mutateCurrent(dirty: one) { $0[p - o] = c }
                    cachedContent = cachedContent.map { $0.union(one) } ?? one
                }
            }
        }
    }

    /// Paints individual pixels (brushes, dither, symmetry), growing the canvas as needed and
    /// skipping any that would take the art past the size cap.
    func paintPixels(_ pixels: [PixelPoint], color c: RGBA) {
        guard let first = pixels.first else { return }
        let rect = pixels.dropFirst().reduce(PixelRect(x: first.x, y: first.y, width: 1, height: 1)) {
            $0.union(PixelRect(x: $1.x, y: $1.y, width: 1, height: 1))
        }
        if c.isClear {
            let o = bounds.origin
            let inside = pixels.filter { bounds.contains($0) }
            guard !inside.isEmpty else { return }
            mutateCurrent(dirty: rect.intersection(bounds)) { g in for p in inside { g[p - o] = c } }
            contentKnown = false
        } else if ensureCovers(rect) {
            let o = bounds.origin
            mutateCurrent(dirty: rect) { g in for p in pixels { g[p - o] = c } }
            if contentKnown { cachedContent = cachedContent.map { $0.union(rect) } ?? rect }
        } else {
            for p in pixels {
                let one = PixelRect(x: p.x, y: p.y, width: 1, height: 1)
                guard access.allowsArt(contentBounds.map { $0.union(one) } ?? one), ensureCovers(one) else { continue }
                let o = bounds.origin
                mutateCurrent(dirty: one) { $0[p - o] = c }
                cachedContent = cachedContent.map { $0.union(one) } ?? one
            }
        }
    }

    func fill(at p: PixelPoint) {
        let targets = symmetric(p)
        var changed = false
        var undoPushed = false
        for t in targets {
            let local = t - bounds.origin
            let target = currentLayerGrid[local]
            // Transparent space is endless, so filling it is limited to the area of the art.
            var limit: PixelRect? = nil
            if target.isClear {
                guard let content = contentBounds, content.contains(t) else { continue }
                limit = content.offsetBy(PixelPoint.zero - bounds.origin)
            }
            guard target != color else { continue }
            if !undoPushed { pushUndo(); undoPushed = true; revealActiveLayer() }
            mutateCurrent { $0.floodFill(from: local, with: color, within: limit) }
            changed = true
        }
        if changed {
            contentKnown = false
            finishEdit()
        }
    }

    /// Makes sure the canvas covers world rect `r`, growing every frame if needed. Returns false
    /// (and offers Pro once, if Pro would allow it) when the art would exceed the size cap or the
    /// memory budget.
    @discardableResult
    func ensureCovers(_ r: PixelRect) -> Bool {
        // Check the cap even when `r` is already on the canvas: the canvas keeps spare margin
        // around the art, and drawing into it must not take the art past the cap.
        let needed = contentBounds.map { $0.union(r) } ?? r
        guard access.allowsArt(needed) else {
            if !access.isPro, FeatureAccess.pro.allowsArt(needed), !promptedThisGesture {
                promptedThisGesture = true
                requestPro(.largeCanvas)
            }
            return false
        }
        if bounds.contains(r) { return true }
        let grown = bounds.union(r.insetBy(-growMargin))
        guard project.frames.count <= FeatureAccess.maxFrames(forArea: grown.width * grown.height * project.layers.count) else { return false }
        reframe(to: grown)
        return true
    }

    /// Moves every frame (and a floating selection) onto a grid covering `newBounds`.
    private func reframe(to newBounds: PixelRect) {
        guard newBounds != bounds, newBounds.width > 0, newBounds.height > 0 else { return }
        let old = bounds
        for i in project.frames.indices {
            project.frames[i].reframe(from: old, to: newBounds)
        }
        project.bounds = newBounds
        if var f = floating {
            f.reframe(to: newBounds)
            floating = f
        }
    }

    /// After an edit, shrink the canvas back to the art plus a small margin, so saved files,
    /// thumbnails and exports stay tight. Never while a selection or gesture is in progress.
    private func trimToContent() {
        guard floating == nil, case .none = gesture else { return }
        let target = contentBounds?.insetBy(-restMargin) ?? SpriteProject.initialBounds
        reframe(to: target)
    }

    // MARK: Shading assistant

    /// The ramp for a base colour with the current settings (dark to light, base included).
    func ramp(for base: RGBA) -> [RGBA] {
        ColorRamp.make(from: base, steps: rampSteps, hueShift: rampHueShift)
    }

    /// Starts a shading stroke on the shape under the finger. The ramp is built from your current
    /// colour if the shape is drawn in it (or already shaded with it); otherwise from the colour
    /// that was touched, which becomes the current colour.
    private func beginShade(at p: PixelPoint) {
        let local = p - bounds.origin
        let touched = currentLayerGrid[local]
        guard !touched.isClear, let box = currentLayerGrid.opaqueRegionBounds(around: local) else {
            gesture = .none
            return
        }
        var base = color
        var steps = ramp(for: base)
        if !steps.contains(touched) {
            base = touched
            color = touched
            steps = ramp(for: base)
        }
        guard let baseIndex = steps.firstIndex(of: base) else { gesture = .none; return }
        let region = box.offsetBy(bounds.origin)
        gesture = .shade(last: p, ramp: steps, baseIndex: baseIndex, region: region, before: snapshot())
        shadeSegment(from: p, to: p, ramp: steps, baseIndex: baseIndex, region: region)
    }

    /// Recolours the ramp-coloured pixels under the brush by how far they are from the light.
    private func shadeSegment(from a: PixelPoint, to b: PixelPoint, ramp: [RGBA], baseIndex: Int, region: PixelRect) {
        guard let mode = shadeMode else { return }
        let o = bounds.origin
        let cel = currentLayerGrid
        var changes: [(PixelPoint, RGBA)] = []
        var seen = Set<PixelPoint>()
        for p in PixelGrid.linePoints(from: a, to: b) {
            for q in brushFootprint(at: p) where seen.insert(q).inserted {
                let current = cel[q - o]
                guard !current.isClear, let index = ramp.firstIndex(of: current) else { continue }
                let target = Shading.step(at: q, in: region, light: lightDirection, count: ramp.count,
                                          baseIndex: baseIndex, mode: mode, current: index)
                if target != index { changes.append((q, ramp[target])) }
            }
        }
        guard let first = changes.first else { return }
        let dirty = changes.dropFirst().reduce(PixelRect(x: first.0.x, y: first.0.y, width: 1, height: 1)) { $0.union($1.0) }
        mutateCurrent(dirty: dirty) { g in for (q, c) in changes { g[q - o] = c } }
    }

    // MARK: Selection

    func lift(_ rect: PixelRect) {
        pushUndo()
        floating = FloatingSelection(lifting: rect, mask: marqueeMask, from: currentLayerGrid, bounds: bounds)
        floatingIsMasked = marqueeMask != nil
        marquee = nil
        marqueeMask = nil
    }

    /// Drops a moved selection where it is.
    func commitSelection() {
        if let f = floating {
            mutateCurrent { $0 = f.composited() }
            floating = nil
            marquee = nil
            contentKnown = false
            finishEdit()
        }
        floating = nil
        marquee = nil
        marqueeMask = nil
        lassoTrail = nil
    }

    func deleteSelection() {
        if let f = floating {
            mutateCurrent { $0 = f.baseGrid }
        } else if let m = marquee {
            pushUndo()
            let local = m.offsetBy(PixelPoint.zero - bounds.origin)
            if let mask = marqueeMask {
                let o = bounds.origin
                mutateCurrent { g in for p in mask.points { g[p - o] = .clear } }
            } else {
                mutateCurrent { $0.clear(local) }
            }
        } else {
            return
        }
        floating = nil
        marquee = nil
        marqueeMask = nil
        contentKnown = false
        finishEdit()
    }

    /// Previews a tween: the start frame followed by every generated frame.
    func tweenPreview(frameCount: Int, easing: Easing, style: TweenPathStyle, mode: TweenMode) -> [PixelGrid] {
        guard let f = floating, let plan = tweenPlan(easing: easing, style: style) else { return [] }
        // Previews show every visible layer, with the moving pixels on the active one.
        let current = project.frames[currentIndex]
        switch mode {
        case .insertFrames:
            return [flattened(current, activeCel: f.originalGrid)]
                + plan.offsets(count: frameCount).map { flattened(current, activeCel: plan.render(onto: f.baseGrid, offset: $0)) }
        case .spreadAcrossFollowing:
            let next = Array(project.frames[(currentIndex + 1)...])
            let offsets = plan.offsets(count: next.count)
            return [flattened(current, activeCel: f.originalGrid)]
                + zip(next, offsets).map { flattened($0, activeCel: plan.move(in: $0.layers[activeLayer], offset: $1)) }
        }
    }

    /// Draws the in-between frames for the selection's journey. The current frame goes back to the
    /// starting position, and the selection ends where it was dropped in the last generated frame.
    func generateTween(frameCount: Int, easing: Easing, style: TweenPathStyle, mode: TweenMode) {
        guard let f = floating, let plan = tweenPlan(easing: easing, style: style) else { return }
        if mode == .spreadAcrossFollowing && followingFrameCount == 0 { return }
        if mode == .insertFrames && !hasRoom(forFrames: max(1, frameCount)) { return }
        pushUndo()
        mutateCurrent { $0 = f.originalGrid }
        switch mode {
        case .insertFrames:
            // New frames copy the other layers (e.g. a background) and move the active one.
            let template = project.frames[currentIndex]
            let frames = plan.offsets(count: max(1, frameCount)).map { offset -> Frame in
                var cels = template.layers
                cels[activeLayer] = plan.render(onto: f.baseGrid, offset: offset)
                return Frame(layers: cels, visible: project.layerVisibility)
            }
            project.frames.insert(contentsOf: frames, at: currentIndex + 1)
            currentIndex += frames.count
        case .spreadAcrossFollowing:
            let offsets = plan.offsets(count: followingFrameCount)
            for (k, offset) in offsets.enumerated() {
                let i = currentIndex + 1 + k
                let visible = project.layerVisibility
                project.frames[i].editLayer(activeLayer, visible: visible) { $0 = plan.move(in: $0, offset: offset) }
            }
            currentIndex = project.frames.count - 1
        }
        floating = nil
        marquee = nil
        marqueeMask = nil
        contentKnown = false
        finishEdit()
    }

    /// The plan works in the grids' local coordinates.
    private func tweenPlan(easing: Easing, style: TweenPathStyle) -> TweenPlan? {
        guard let f = floating, !f.path.isTrivial else { return nil }
        let path = style == .traced ? f.path.refined() : .straight(to: f.path.end)
        let local = f.sourceRect.offsetBy(PixelPoint.zero - f.bounds.origin)
        return TweenPlan(sourceRect: local, patch: f.patch, path: path, easing: easing)
    }

    // MARK: Frames

    /// Adds a blank keyframe after the current one. The previous frame shows through as onion skin.
    @discardableResult
    func addKeyframe() -> Bool {
        isPlaying = false
        guard hasRoom(forFrames: 1) else { return false }
        commitSelection()
        pushUndo()
        project.frames.insert(Frame.blank(width: bounds.width, height: bounds.height, layers: project.layers.count), at: currentIndex + 1)
        currentIndex += 1
        finishEdit()
        return true
    }

    func duplicateFrame(at index: Int) {
        guard project.frames.indices.contains(index), hasRoom(forFrames: 1) else { return }
        commitSelection()
        pushUndo()
        project.frames.insert(Frame(layers: project.frames[index].layers, visible: project.layerVisibility), at: index + 1)
        currentIndex = index + 1
        finishEdit()
    }

    /// A copy of a frame's pixels, for `pasteFrame`.
    func copyFrame(at index: Int) -> FrameClip? {
        guard project.frames.indices.contains(index) else { return nil }
        commitSelection()
        return FrameClip(frame: project.frames[index], frameBounds: bounds, visible: project.layerVisibility)
    }

    /// Pastes a copied frame, in the same place it was copied from. `asNewFrame` inserts it after
    /// the current frame; otherwise it replaces the current frame's pixels. With the same number of
    /// layers each layer goes back to its own layer; otherwise the art lands, flattened, on the
    /// active layer and the other layers are left as they are (or blank, in a new frame).
    /// Returns false if it doesn't fit (frame limit or art size; Pro is offered if it would help).
    @discardableResult
    func pasteFrame(_ clip: FrameClip, asNewFrame: Bool) -> Bool {
        isPlaying = false
        commitSelection()
        if asNewFrame, !hasRoom(forFrames: 1) { return false }
        if let r = clip.bounds {
            promptedThisGesture = false
            guard ensureCovers(r) else { return false }
        }
        pushUndo()
        let blank = blankGrid
        let base = asNewFrame ? Array(repeating: blank, count: project.layers.count) : project.frames[currentIndex].layers
        var cels: [PixelGrid]
        func placed(_ g: PixelGrid) -> PixelGrid { clip.bounds.map { g.reframed(from: $0, to: bounds) } ?? blank }
        if clip.layerCount == project.layers.count {
            cels = clip.isBlank ? base.map { _ in blank } : clip.layers.map(placed)
        } else {
            cels = base
            cels[activeLayer] = clip.flattened.map(placed) ?? blank
        }
        if asNewFrame {
            project.frames.insert(Frame(layers: cels, visible: project.layerVisibility), at: currentIndex + 1)
            currentIndex += 1
        } else {
            project.frames[currentIndex].setLayers(cels, visible: project.layerVisibility)
        }
        contentKnown = false
        finishEdit()
        return true
    }

    /// Flips or rotates the art (every layer) of the current frame, or of every frame, around the
    /// centre of that art, so an animation stays lined up. Undoable. Returns false if there's
    /// nothing to transform or a rotation would take the art past the size cap.
    @discardableResult
    func transform(_ t: FrameTransform, allFrames: Bool) -> Bool {
        isPlaying = false
        commitSelection()
        let indices = allFrames ? Array(project.frames.indices) : [currentIndex]
        // The art being transformed, in world pixels.
        var art: PixelRect?
        for i in indices {
            for cel in project.frames[i].layers {
                guard let r = cel.opaqueBounds?.offsetBy(bounds.origin) else { continue }
                art = art.map { $0.union(r) } ?? r
            }
        }
        guard let r = art else { return false }
        let target = t.destination(of: r)
        promptedThisGesture = false
        guard ensureCovers(target) else { return false }
        pushUndo()
        let o = bounds.origin
        let visible = project.layerVisibility
        for i in indices {
            let cels = project.frames[i].layers.map { cel -> PixelGrid in
                var out = cel
                var moved: [(PixelPoint, RGBA)] = []
                for y in r.y..<r.maxY {
                    for x in r.x..<r.maxX {
                        let p = PixelPoint(x: x, y: y)
                        let c = cel[p - o]
                        guard !c.isClear else { continue }
                        moved.append((t.map(p, in: r), c))
                        out[p - o] = .clear
                    }
                }
                for (p, c) in moved { out[p - o] = c }
                return out
            }
            project.frames[i].setLayers(cels, visible: visible)
        }
        contentKnown = false
        finishEdit()
        return true
    }

    func deleteFrame(at index: Int) {
        guard project.frames.indices.contains(index) else { return }
        commitSelection()
        pushUndo()
        if project.frames.count == 1 {
            project.frames[0] = Frame.blank(width: bounds.width, height: bounds.height, layers: project.layers.count)
        } else {
            project.frames.remove(at: index)
        }
        currentIndex = min(currentIndex, project.frames.count - 1)
        contentKnown = false
        finishEdit()
    }

    func moveFrame(from index: Int, by delta: Int) {
        let target = index + delta
        guard project.frames.indices.contains(index), project.frames.indices.contains(target) else { return }
        commitSelection()
        pushUndo()
        project.frames.swapAt(index, target)
        if currentIndex == index { currentIndex = target } else if currentIndex == target { currentIndex = index }
        finishEdit()
    }

    func selectFrame(_ index: Int) {
        guard project.frames.indices.contains(index), index != currentIndex else { return }
        commitSelection()
        currentIndex = index
    }

    /// Clears the active layer in the current frame.
    func clearCurrentFrame() {
        commitSelection()
        guard !currentLayerGrid.isBlank else { return }
        pushUndo()
        mutateCurrent { $0 = blankGrid }
        contentKnown = false
        finishEdit()
    }

    /// Whether `count` more frames fit. Asks for Pro when the free limit is the reason.
    func hasRoom(forFrames count: Int) -> Bool {
        if project.frames.count + count <= access.frameLimit(forArea: area) { return true }
        // Only offer Pro if Pro would actually allow it (not when the memory budget is the limit).
        if !access.isPro, project.frames.count + count <= FeatureAccess.pro.frameLimit(forArea: area) {
            onProRequired?(.unlimitedFrames)
        }
        return false
    }

    /// Frames that can still be inserted under the current plan.
    var remainingFrameAllowance: Int { max(0, access.frameLimit(forArea: area) - project.frames.count) }

    /// The frame limit for this sprite at its current size.
    var frameLimit: Int { access.frameLimit(forArea: area) }

    /// Pixels per frame across all layers (what the memory budget counts).
    var area: Int { bounds.width * bounds.height * project.layers.count }
    var blankGrid: PixelGrid { PixelGrid(width: bounds.width, height: bounds.height) }

    // MARK: Shapes

    /// Redraws the shape being dragged: the layer as it was, plus the shape (mirrored if on).
    private func drawShape(from a: PixelPoint, to raw: PixelPoint) {
        guard case let .shape(_, base, baseBounds, _) = gesture else { return }
        let b = lockProportions ? ShapeRaster.constrained(shapeKind, from: a, to: raw) : raw
        var pts = ShapeRaster.points(shapeKind, from: a, to: b, filled: shapeFilled, thickness: shapeThickness)
        pts = pts.flatMap(symmetric)
        guard let first = pts.first else { return }
        let box = pts.dropFirst().reduce(PixelRect(x: first.x, y: first.y, width: 1, height: 1)) { $0.union($1) }
        // Grow the canvas for the shape if allowed; otherwise draw what fits within the cap.
        var allowed: (PixelPoint) -> Bool = { _ in true }
        if !ensureCovers(box) {
            let content = contentBounds
            let cap = access
            allowed = { p in
                let one = PixelRect(x: p.x, y: p.y, width: 1, height: 1)
                return cap.allowsArt(content.map { $0.union(one) } ?? one)
            }
        }
        let o = bounds.origin
        let layer = base.reframed(from: baseBounds, to: bounds)
        let c = color
        mutateCurrent {
            $0 = layer
            for p in pts where allowed(p) { $0[p - o] = c }
        }
    }

    /// The first shape on a single-layer sprite goes on a new "Shapes" layer above the art, so
    /// shapes never overwrite your pixels.
    private func autoCreateShapesLayer() {
        guard project.layers.count == 1 else { return }
        addLayer(named: shapesLayerName)
    }

    /// Drawing on a hidden layer would be invisible, so it's shown again.
    func revealActiveLayer() {
        guard project.layers.indices.contains(activeLayer), !project.layers[activeLayer].isVisible else { return }
        project.layers[activeLayer].isVisible = true
        reflattenAll()
    }

    private func reflattenAll() {
        let visible = project.layerVisibility
        for i in project.frames.indices { project.frames[i].reflatten(visible: visible) }
    }

    // MARK: Layers

    /// There is no fixed number of layers. Every layer is kept for every frame, so what stops a
    /// new one is the sprite's size in memory (`FeatureAccess.pixelBudget`).
    var canAddLayer: Bool {
        project.frames.count <= FeatureAccess.maxFrames(forArea: bounds.width * bounds.height * (project.layers.count + 1))
    }

    /// Adds an empty layer above the active one and makes it active.
    func addLayer(named name: String? = nil) {
        guard canAddLayer else { return }
        commitSelection()
        pushUndo()
        let at = activeLayer + 1
        project.layers.insert(LayerInfo(name: name ?? newLayerName(project.layers.count + 1)), at: at)
        let blank = blankGrid, visible = project.layerVisibility
        for i in project.frames.indices {
            var cels = project.frames[i].layers
            cels.insert(blank, at: at)
            project.frames[i].setLayers(cels, visible: visible)
        }
        activeLayer = at
        finishEdit()
    }

    func selectLayer(_ index: Int) {
        guard project.layers.indices.contains(index), index != activeLayer else { return }
        commitSelection()
        activeLayer = index
    }

    func setLayerVisible(_ index: Int, _ visible: Bool) {
        guard project.layers.indices.contains(index), project.layers[index].isVisible != visible else { return }
        commitSelection()
        pushUndo()
        project.layers[index].isVisible = visible
        reflattenAll()
        finishEdit()
    }

    func renameLayer(_ index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard project.layers.indices.contains(index), !trimmed.isEmpty else { return }
        project.layers[index].name = trimmed
        finishEdit()
    }

    /// Moves a layer up (+1, towards the top) or down (-1).
    func moveLayer(_ index: Int, by delta: Int) {
        let target = index + delta
        guard project.layers.indices.contains(index), project.layers.indices.contains(target) else { return }
        commitSelection()
        pushUndo()
        project.layers.swapAt(index, target)
        let visible = project.layerVisibility
        for i in project.frames.indices {
            var cels = project.frames[i].layers
            cels.swapAt(index, target)
            project.frames[i].setLayers(cels, visible: visible)
        }
        if activeLayer == index { activeLayer = target } else if activeLayer == target { activeLayer = index }
        finishEdit()
    }

    /// Deletes a layer from every frame. The last layer can't be deleted.
    func deleteLayer(_ index: Int) {
        guard project.layers.count > 1, project.layers.indices.contains(index) else { return }
        commitSelection()
        pushUndo()
        project.layers.remove(at: index)
        let visible = project.layerVisibility
        for i in project.frames.indices {
            var cels = project.frames[i].layers
            cels.remove(at: index)
            project.frames[i].setLayers(cels, visible: visible)
        }
        activeLayer = min(activeLayer > index ? activeLayer - 1 : activeLayer, project.layers.count - 1)
        contentKnown = false
        finishEdit()
    }

    /// Merges the active layer into the one below it.
    func mergeLayerDown() {
        let top = activeLayer
        guard top > 0 else { return }
        commitSelection()
        pushUndo()
        let visible = project.layers.map { _ in true }
        for i in project.frames.indices {
            var cels = project.frames[i].layers
            let merged = Frame(layers: [cels[top - 1], cels[top]], visible: [visible[top - 1], visible[top]]).grid
            cels[top - 1] = merged
            cels.remove(at: top)
            project.frames[i].setLayers(cels, visible: project.layerVisibility.enumerated().filter { $0.offset != top }.map(\.element))
        }
        project.layers.remove(at: top)
        activeLayer = top - 1
        reflattenAll()
        finishEdit()
    }

    // MARK: Project settings

    func setFPS(_ fps: Int) {
        project.fps = min(max(fps, 1), SpriteProject.maxFPS)
        finishEdit()
    }

    /// Paces playback across the frames. Anything but Linear needs Pro.
    func setPlaybackEasing(_ easing: Easing) {
        guard easing != project.playbackEasing else { return }
        if easing != .linear && !access.allowsEasedPlayback {
            onProRequired?(.timing)
            return
        }
        project.playbackEasing = easing
        finishEdit()
    }

    /// Seconds each frame is shown when playing.
    var frameDurations: [Double] { project.frameDurations }

    /// A sprite setting change that isn't art (no undo step, no trim).
    func updateProject(_ change: (inout SpriteProject) -> Void) {
        change(&project)
        project.modifiedAt = Date()
        onChange?(project)
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.name = trimmed
        finishEdit()
    }

    // MARK: Undo

    func undo() {
        guard let s = undoStack.popLast() else { return }
        undoCount += 1
        discardSelectionState()
        redoStack.append(snapshot())
        restore(s)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        redoCount += 1
        discardSelectionState()
        undoStack.append(snapshot())
        restore(s)
    }

    // MARK: Internals

    func snapshot() -> Snapshot {
        Snapshot(frames: project.frames, bounds: project.bounds, currentIndex: currentIndex,
                 layers: project.layers, activeLayer: activeLayer)
    }

    func pushUndo(_ s: Snapshot? = nil) {
        undoStack.append(s ?? snapshot())
        // Snapshots share unchanged frames, but growing or trimming the canvas copies every frame,
        // so also cap the history by (worst-case) memory: large sprites keep fewer undo steps.
        var bytes = 0
        var keep = 0
        for snap in undoStack.reversed() {
            bytes += snap.frames.count * snap.layers.count * snap.bounds.width * snap.bounds.height * 4
            if keep >= 1 && bytes > undoMemoryBudget { break }
            keep += 1
        }
        let limit = min(undoLimit, keep)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }

    /// 256 MB of frame data across the undo history.
    private let undoMemoryBudget = 256 * 1024 * 1024

    private func restore(_ s: Snapshot) {
        project.frames = s.frames
        project.bounds = s.bounds
        project.layers = s.layers
        activeLayer = min(s.activeLayer, s.layers.count - 1)
        currentIndex = min(s.currentIndex, s.frames.count - 1)
        contentKnown = false
        finishEdit()
    }

    /// Undo while a selection is floating would leave it pointing at a frame that no longer
    /// exists in that form, so it is dropped (the pixels are already in the frame).
    private func discardSelectionState() {
        floating = nil
        marquee = nil
        marqueeMask = nil
        lassoTrail = nil
        adjustBase = nil
        adjustMask = nil
        gesture = .none
    }

    /// Edits the active layer of the current frame. `dirty` (world) limits re-flattening to the
    /// area that changed, which keeps strokes fast on big sprites with several layers.
    func mutateCurrent(dirty: PixelRect? = nil, _ body: (inout PixelGrid) -> Void) {
        let local = dirty.map { $0.offsetBy(PixelPoint.zero - bounds.origin) }
        let visible = project.layerVisibility
        project.frames[currentIndex].editLayer(activeLayer, visible: visible, dirty: local, body)
    }

    /// A frame flattened with its active cel swapped for `activeCel` (for tween previews).
    private func flattened(_ frame: Frame, activeCel: PixelGrid) -> PixelGrid {
        var cels = frame.layers
        cels[activeLayer] = activeCel
        return Frame(layers: cels, visible: project.layerVisibility).grid
    }

    func finishEdit() {
        trimToContent()
        project.modifiedAt = Date()
        onChange?(project)
    }
}
