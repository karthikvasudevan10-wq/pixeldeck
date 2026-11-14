import Foundation
import Observation

/// Drawing tools. Mirror is a mode (`EditorModel.mirror`), not a tool. Display names are
/// localised in the app layer (LocalizedTitles.swift).
enum Tool: String, CaseIterable, Identifiable, Sendable {
    case pencil, eraser, fill, eyedropper, select

    var id: String { rawValue }
}

/// Everything the canvas view needs to draw one state of the editor. Rectangles and points are in
/// world pixel coordinates; `grid` covers `bounds`.
struct CanvasState: Equatable {
    var bounds: PixelRect
    var grid: PixelGrid
    var onion: PixelGrid?
    var onionOpacity: Double
    var showGrid: Bool
    /// Marquee or floating-selection outline.
    var selection: PixelRect?
    /// Path the selection's centre has travelled.
    var motionPath: [Vec2]?
    /// Show the mirror axis (world x = 0).
    var mirror: Bool
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
    private(set) var project: SpriteProject
    private(set) var currentIndex = 0

    var tool: Tool = .pencil {
        didSet { if tool != .select { commitSelection() } }
    }
    /// Mirror drawing across world x = 0 (pencil, eraser and fill).
    var mirror = false
    private(set) var color: RGBA = SpriteProject.defaultPalette[2]
    var showGrid = true
    var onionSkinEnabled = true
    /// The design draws the previous frame as a flat accent tint at 38%.
    var onionOpacity = 0.38
    /// Playing the animation in place on the canvas. Drawing is paused meanwhile.
    var isPlaying = false {
        didSet { if isPlaying { commitSelection() } }
    }

    /// A selected area that hasn't been moved yet (world).
    private(set) var marquee: PixelRect?
    /// A selection that has been lifted and is being moved.
    private(set) var floating: FloatingSelection?

    private struct Snapshot {
        var frames: [Frame]
        var bounds: PixelRect
        var currentIndex: Int
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

    /// What the user has unlocked. Set by the app from the purchase state.
    var access: FeatureAccess = .free
    /// Called when an action needs Pro, so the app can offer the upgrade.
    @ObservationIgnored var onProRequired: ((ProFeature) -> Void)?

    private enum Gesture {
        case none
        case stroke(last: PixelPoint, color: RGBA, before: Snapshot)
        case marquee(start: PixelPoint)
        case move(start: Vec2, startOffset: Vec2, pathCount: Int)
    }
    @ObservationIgnored private var gesture: Gesture = .none
    /// Only offer Pro once per gesture, not on every finger movement.
    @ObservationIgnored private var promptedThisGesture = false
    /// Offered when the finger lifts: presenting the paywall mid-stroke would cancel the touch
    /// and throw the stroke away.
    @ObservationIgnored private var pendingPro: ProFeature?

    /// World rectangle of all drawn pixels, cached because scanning every frame is costly.
    @ObservationIgnored private var cachedContent: PixelRect?
    @ObservationIgnored private var contentKnown = false

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
        floating = nil
        isPlaying = false
        undoStack = []
        redoStack = []
        gesture = .none
        contentKnown = false
    }

    // MARK: Derived state

    var bounds: PixelRect { project.bounds }
    var frameCount: Int { project.frames.count }
    var currentGrid: PixelGrid { project.frames[currentIndex].grid }
    var palette: [RGBA] { project.palette }

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
            return CanvasState(bounds: bounds, grid: project.frames[i].grid, onion: nil, onionOpacity: onionOpacity,
                               showGrid: showGrid, selection: nil, motionPath: nil, mirror: false)
        }
        var path: [Vec2]?
        if let f = floating, !f.path.isTrivial {
            let c = f.sourceRect.center
            path = f.path.refined().points.map { $0 + c }
        }
        return CanvasState(bounds: bounds, grid: currentGrid, onion: onionGrid, onionOpacity: onionOpacity,
                           showGrid: showGrid, selection: selectionRect, motionPath: path, mirror: mirror)
    }

    // MARK: Colour

    func pickColor(_ c: RGBA) {
        color = RGBA(r: c.r, g: c.g, b: c.b, a: 255)
        if tool == .eraser || tool == .eyedropper { tool = .pencil }
    }

    /// Long-press edit of a palette swatch. Also selects the new colour.
    func setPaletteColor(_ c: RGBA, at index: Int) {
        guard project.palette.indices.contains(index) else { return }
        let opaque = RGBA(r: c.r, g: c.g, b: c.b, a: 255)
        project.palette[index] = opaque
        color = opaque
        finishEdit()
    }

    // MARK: Touch input (world pixel coordinates, fractional)

    func touchBegan(at v: Vec2) {
        let p = v.pixel
        promptedThisGesture = false
        switch tool {
        case .pencil, .eraser:
            let c: RGBA = tool == .pencil ? color : .clear
            gesture = .stroke(last: p, color: c, before: snapshot())
            paintSegment(from: p, to: p, color: c)

        case .fill:
            fill(at: p)

        case .eyedropper:
            let c = currentGrid[p - bounds.origin]
            if !c.isClear {
                color = c
                tool = .pencil
            }

        case .select:
            if let f = floating, f.currentRect.contains(p) {
                gesture = .move(start: v, startOffset: f.exactOffset, pathCount: f.path.points.count)
            } else if let m = marquee, m.contains(p) {
                lift(m)
                gesture = .move(start: v, startOffset: .zero, pathCount: 1)
            } else {
                commitSelection()
                marquee = PixelRect(corner: p, p)
                gesture = .marquee(start: p)
            }
        }
    }

    func touchMoved(to v: Vec2) {
        switch gesture {
        case .none:
            break
        case let .stroke(last, c, before):
            let p = v.pixel
            guard p != last else { return }
            paintSegment(from: last, to: p, color: c)
            gesture = .stroke(last: p, color: c, before: before)
        case let .marquee(start):
            marquee = PixelRect(corner: start, v.pixel)
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
        case let .stroke(_, _, before):
            pushUndo(before)
            finishEdit()
        case .move:
            finishEdit()
        case .marquee, .none:
            break
        }
        offerPendingPro()
    }

    /// The touch turned into a pinch or pan: undo whatever it did.
    func touchCancelled() {
        switch gesture {
        case let .stroke(_, _, before):
            project.frames = before.frames
            project.bounds = before.bounds
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
        case .none:
            break
        }
        gesture = .none
        offerPendingPro()
    }

    private func requestPro(_ feature: ProFeature) {
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
    private func paintSegment(from a: PixelPoint, to b: PixelPoint, color c: RGBA) {
        var segments = [(a, b)]
        if mirror { segments.append((a.mirrored, b.mirrored)) }
        for (s, e) in segments {
            let r = PixelRect(corner: s, e)
            if c.isClear {
                // Erasing never needs to grow the canvas; there's nothing outside it.
                let o = bounds.origin
                mutateCurrent { $0.drawLine(from: s - o, to: e - o, color: c) }
                contentKnown = false
            } else if ensureCovers(r) {
                let o = bounds.origin
                mutateCurrent { $0.drawLine(from: s - o, to: e - o, color: c) }
                if contentKnown { cachedContent = cachedContent.map { $0.union(r) } ?? r }
            } else {
                // Part of the segment is past the art-size cap: paint only the pixels that keep
                // the art within it (the canvas's spare margin mustn't let art exceed the cap).
                for p in PixelGrid.linePoints(from: s, to: e) {
                    let one = PixelRect(x: p.x, y: p.y, width: 1, height: 1)
                    guard access.allowsArt(contentBounds.map { $0.union(one) } ?? one), ensureCovers(one) else { continue }
                    let o = bounds.origin
                    mutateCurrent { $0[p - o] = c }
                    cachedContent = cachedContent.map { $0.union(one) } ?? one
                }
            }
        }
    }

    private func fill(at p: PixelPoint) {
        var targets = [p]
        if mirror, p.mirrored != p { targets.append(p.mirrored) }
        var changed = false
        var undoPushed = false
        for t in targets {
            let local = t - bounds.origin
            let target = currentGrid[local]
            // Transparent space is endless, so filling it is limited to the area of the art.
            var limit: PixelRect? = nil
            if target.isClear {
                guard let content = contentBounds, content.contains(t) else { continue }
                limit = content.offsetBy(PixelPoint.zero - bounds.origin)
            }
            guard target != color else { continue }
            if !undoPushed { pushUndo(); undoPushed = true }
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
    private func ensureCovers(_ r: PixelRect) -> Bool {
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
        guard project.frames.count <= FeatureAccess.maxFrames(forArea: grown.width * grown.height) else { return false }
        reframe(to: grown)
        return true
    }

    /// Moves every frame (and a floating selection) onto a grid covering `newBounds`.
    private func reframe(to newBounds: PixelRect) {
        guard newBounds != bounds, newBounds.width > 0, newBounds.height > 0 else { return }
        let old = bounds
        for i in project.frames.indices {
            project.frames[i].grid = project.frames[i].grid.reframed(from: old, to: newBounds)
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

    // MARK: Selection

    private func lift(_ rect: PixelRect) {
        pushUndo()
        floating = FloatingSelection(lifting: rect, from: currentGrid, bounds: bounds)
        marquee = nil
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
    }

    func deleteSelection() {
        if let f = floating {
            mutateCurrent { $0 = f.baseGrid }
        } else if let m = marquee {
            pushUndo()
            let local = m.offsetBy(PixelPoint.zero - bounds.origin)
            mutateCurrent { $0.clear(local) }
        } else {
            return
        }
        floating = nil
        marquee = nil
        contentKnown = false
        finishEdit()
    }

    /// Previews a tween: the start frame followed by every generated frame.
    func tweenPreview(frameCount: Int, easing: Easing, style: TweenPathStyle, mode: TweenMode) -> [PixelGrid] {
        guard let f = floating, let plan = tweenPlan(easing: easing, style: style) else { return [] }
        switch mode {
        case .insertFrames:
            return [f.originalGrid] + plan.offsets(count: frameCount).map { plan.render(onto: f.baseGrid, offset: $0) }
        case .spreadAcrossFollowing:
            let next = project.frames[(currentIndex + 1)...].map(\.grid)
            let offsets = plan.offsets(count: next.count)
            return [f.originalGrid] + zip(next, offsets).map { plan.move(in: $0, offset: $1) }
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
            let frames = plan.offsets(count: max(1, frameCount)).map { Frame(grid: plan.render(onto: f.baseGrid, offset: $0)) }
            project.frames.insert(contentsOf: frames, at: currentIndex + 1)
            currentIndex += frames.count
        case .spreadAcrossFollowing:
            let offsets = plan.offsets(count: followingFrameCount)
            for (k, offset) in offsets.enumerated() {
                let i = currentIndex + 1 + k
                project.frames[i].grid = plan.move(in: project.frames[i].grid, offset: offset)
            }
            currentIndex = project.frames.count - 1
        }
        floating = nil
        marquee = nil
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
        guard hasRoom(forFrames: 1) else { return false }
        commitSelection()
        pushUndo()
        project.frames.insert(Frame(grid: blankGrid), at: currentIndex + 1)
        currentIndex += 1
        finishEdit()
        return true
    }

    func duplicateFrame(at index: Int) {
        guard project.frames.indices.contains(index), hasRoom(forFrames: 1) else { return }
        commitSelection()
        pushUndo()
        project.frames.insert(Frame(grid: project.frames[index].grid), at: index + 1)
        currentIndex = index + 1
        finishEdit()
    }

    func deleteFrame(at index: Int) {
        guard project.frames.indices.contains(index) else { return }
        commitSelection()
        pushUndo()
        if project.frames.count == 1 {
            project.frames[0].grid = blankGrid
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

    func clearCurrentFrame() {
        commitSelection()
        guard !currentGrid.isBlank else { return }
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

    private var area: Int { bounds.width * bounds.height }
    private var blankGrid: PixelGrid { PixelGrid(width: bounds.width, height: bounds.height) }

    // MARK: Project settings

    func setFPS(_ fps: Int) {
        project.fps = min(max(fps, 1), 30)
        finishEdit()
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
        discardSelectionState()
        redoStack.append(snapshot())
        restore(s)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        discardSelectionState()
        undoStack.append(snapshot())
        restore(s)
    }

    // MARK: Internals

    private func snapshot() -> Snapshot {
        Snapshot(frames: project.frames, bounds: project.bounds, currentIndex: currentIndex)
    }

    private func pushUndo(_ s: Snapshot? = nil) {
        undoStack.append(s ?? snapshot())
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ s: Snapshot) {
        project.frames = s.frames
        project.bounds = s.bounds
        currentIndex = min(s.currentIndex, s.frames.count - 1)
        contentKnown = false
        finishEdit()
    }

    /// Undo while a selection is floating would leave it pointing at a frame that no longer
    /// exists in that form, so it is dropped (the pixels are already in the frame).
    private func discardSelectionState() {
        floating = nil
        marquee = nil
        gesture = .none
    }

    private func mutateCurrent(_ body: (inout PixelGrid) -> Void) {
        body(&project.frames[currentIndex].grid)
    }

    private func finishEdit() {
        trimToContent()
        project.modifiedAt = Date()
        onChange?(project)
    }
}
