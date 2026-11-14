import Foundation
import Observation

enum Tool: String, CaseIterable, Identifiable, Sendable {
    case pencil, eraser, fill, eyedropper, select

    var id: String { rawValue }

    /// SF Symbol name. (Display names are localised in the app layer: LocalizedTitles.swift.)
    var symbol: String {
        switch self {
        case .pencil: "pencil.tip"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        case .select: "selection.pin.in.out"
        }
    }
}

/// Everything the canvas view needs to draw one state of the editor.
struct CanvasState: Equatable {
    var size: Int
    var grid: PixelGrid
    var onion: PixelGrid?
    var onionOpacity: Double
    var showGrid: Bool
    /// Marquee or floating-selection outline, in canvas pixels.
    var selection: PixelRect?
    /// Path the selection's centre has travelled, in canvas pixels.
    var motionPath: [Vec2]?
}

/// Where the user is looking: zoom relative to "fit", and the canvas point at the centre of the
/// view as a fraction (0…1) of the canvas. Kept across folds, rotations and layout changes.
struct Viewport: Equatable, Sendable {
    var zoom: Double
    var focusX: Double
    var focusY: Double

    static let fit = Viewport(zoom: 1, focusX: 0.5, focusY: 0.5)
}

/// The editing session for one sprite. Platform-independent so it can be unit-tested.
@Observable
final class EditorModel {
    private(set) var project: SpriteProject
    private(set) var currentIndex = 0

    var tool: Tool = .pencil {
        didSet { if tool != .select { commitSelection() } }
    }
    private(set) var color: RGBA = .black
    private(set) var recentColors: [RGBA] = []
    var showGrid = true
    var onionSkinEnabled = true
    var onionOpacity = 0.3

    /// A selected area that hasn't been moved yet.
    private(set) var marquee: PixelRect?
    /// A selection that has been lifted and is being moved.
    private(set) var floating: FloatingSelection?

    private struct Snapshot {
        var frames: [Frame]
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
        undoStack = []
        redoStack = []
        gesture = .none
    }

    // MARK: Derived state

    var size: Int { project.size }
    var frameCount: Int { project.frames.count }
    var currentGrid: PixelGrid { project.frames[currentIndex].grid }

    var onionGrid: PixelGrid? {
        guard onionSkinEnabled, currentIndex > 0 else { return nil }
        return project.frames[currentIndex - 1].grid
    }

    var selectionRect: PixelRect? { floating?.currentRect ?? marquee }

    var canTween: Bool { floating.map { !$0.path.isTrivial } ?? false }

    var followingFrameCount: Int { project.frames.count - currentIndex - 1 }

    var suggestedTweenFrames: Int { floating?.path.refined().suggestedFrameCount ?? 8 }

    var canvasState: CanvasState {
        var path: [Vec2]?
        if let f = floating, !f.path.isTrivial {
            let c = f.sourceRect.center
            path = f.path.refined().points.map { $0 + c }
        }
        return CanvasState(size: size, grid: currentGrid, onion: onionGrid, onionOpacity: onionOpacity,
                           showGrid: showGrid, selection: selectionRect, motionPath: path)
    }

    // MARK: Colour

    func pickColor(_ c: RGBA) {
        color = RGBA(r: c.r, g: c.g, b: c.b, a: 255)
        if tool == .eraser || tool == .eyedropper { tool = .pencil }
    }

    private func rememberColor(_ c: RGBA) {
        recentColors.removeAll { $0 == c }
        recentColors.insert(c, at: 0)
        if recentColors.count > 8 { recentColors.removeLast() }
    }

    // MARK: Touch input (coordinates in canvas pixels, fractional)

    func touchBegan(at v: Vec2) {
        let p = v.pixel
        switch tool {
        case .pencil, .eraser:
            let c: RGBA = tool == .pencil ? color : .clear
            let before = snapshot()
            if tool == .pencil { rememberColor(c) }
            mutateCurrent { $0[p] = c }
            gesture = .stroke(last: p, color: c, before: before)

        case .fill:
            guard currentGrid.contains(p) else { return }
            pushUndo()
            rememberColor(color)
            mutateCurrent { $0.floodFill(from: p, with: color) }
            finishEdit()

        case .eyedropper:
            let c = currentGrid[p]
            if !c.isClear {
                color = c
                rememberColor(c)
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
                let q = p.clamped(toCanvas: size)
                marquee = PixelRect(corner: q, q)
                gesture = .marquee(start: q)
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
            mutateCurrent { $0.drawLine(from: last, to: p, color: c) }
            gesture = .stroke(last: p, color: c, before: before)
        case let .marquee(start):
            marquee = PixelRect(corner: start, v.pixel.clamped(toCanvas: size))
        case let .move(start, startOffset, _):
            guard var f = floating else { return }
            f.exactOffset = startOffset + (v - start)
            f.path.append(f.exactOffset)
            floating = f
            mutateCurrent { $0 = f.composited() }
        }
    }

    func touchEnded() {
        switch gesture {
        case let .stroke(_, _, before):
            pushUndo(before)
            finishEdit()
        case .move:
            finishEdit()
        case .marquee, .none:
            break
        }
        gesture = .none
    }

    /// The touch turned into a pinch or pan: undo whatever it did.
    func touchCancelled() {
        switch gesture {
        case let .stroke(_, _, before):
            project.frames = before.frames
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
    }

    // MARK: Selection

    private func lift(_ rect: PixelRect) {
        pushUndo()
        floating = FloatingSelection(lifting: rect, from: currentGrid)
        marquee = nil
    }

    /// Drops a moved selection where it is.
    func commitSelection() {
        if let f = floating {
            mutateCurrent { $0 = f.composited() }
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
            mutateCurrent { $0.clear(m) }
        } else {
            return
        }
        floating = nil
        marquee = nil
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
        finishEdit()
    }

    private func tweenPlan(easing: Easing, style: TweenPathStyle) -> TweenPlan? {
        guard let f = floating, !f.path.isTrivial else { return nil }
        let path = style == .traced ? f.path.refined() : .straight(to: f.path.end)
        return TweenPlan(sourceRect: f.sourceRect, patch: f.patch, path: path, easing: easing)
    }

    // MARK: Frames

    /// Adds a blank keyframe after the current one. The previous frame shows through as onion skin.
    @discardableResult
    func addKeyframe() -> Bool {
        guard hasRoom(forFrames: 1) else { return false }
        commitSelection()
        pushUndo()
        project.frames.insert(Frame(grid: PixelGrid(size: size)), at: currentIndex + 1)
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
            project.frames[0].grid = PixelGrid(size: size)
        } else {
            project.frames.remove(at: index)
        }
        currentIndex = min(currentIndex, project.frames.count - 1)
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
        mutateCurrent { $0 = PixelGrid(size: size) }
        finishEdit()
    }

    /// Whether `count` more frames fit. Asks for Pro when the free limit is the reason.
    func hasRoom(forFrames count: Int) -> Bool {
        if project.frames.count + count <= access.frameLimit(forCanvas: size) { return true }
        // Only offer Pro if Pro would actually allow it (not when the memory budget is the limit).
        if !access.isPro, project.frames.count + count <= FeatureAccess.pro.frameLimit(forCanvas: size) {
            onProRequired?(.unlimitedFrames)
        }
        return false
    }

    /// Frames that can still be inserted under the current plan.
    var remainingFrameAllowance: Int { max(0, access.frameLimit(forCanvas: size) - project.frames.count) }

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
        Snapshot(frames: project.frames, currentIndex: currentIndex)
    }

    private func pushUndo(_ s: Snapshot? = nil) {
        undoStack.append(s ?? snapshot())
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ s: Snapshot) {
        project.frames = s.frames
        currentIndex = min(s.currentIndex, s.frames.count - 1)
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
        project.modifiedAt = Date()
        onChange?(project)
    }
}
