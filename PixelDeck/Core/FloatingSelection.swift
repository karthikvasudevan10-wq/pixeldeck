import Foundation

/// Pixels lifted off a frame so they can be dragged around. The route of every drag is recorded
/// in `path`, which is what a tween follows. Rectangles are in world coordinates; the grids cover
/// `bounds` and are re-framed if the canvas grows while the selection is being moved.
struct FloatingSelection: Sendable {
    /// Where the pixels came from (world), clipped to the canvas.
    let sourceRect: PixelRect
    let patch: PixelPatch
    /// Opaque part of the patch, relative to the patch's top-left (nil if it's all transparent).
    let patchOpaque: PixelRect?
    private(set) var bounds: PixelRect
    /// The frame exactly as it was before lifting.
    private(set) var originalGrid: PixelGrid
    /// The frame with the lifted area cleared.
    private(set) var baseGrid: PixelGrid
    /// Unrounded offset, so slow drags still accumulate.
    var exactOffset: Vec2 = .zero
    var path = MotionPath()

    init(lifting rect: PixelRect, from grid: PixelGrid, bounds: PixelRect) {
        let r = rect.intersection(bounds)
        sourceRect = r
        let local = r.offsetBy(PixelPoint.zero - bounds.origin)
        patch = grid.patch(in: local)
        var opaque: PixelRect?
        for py in 0..<patch.height {
            for px in 0..<patch.width where !patch[px, py].isClear {
                opaque = opaque.map { $0.union(PixelPoint(x: px, y: py)) } ?? PixelRect(x: px, y: py, width: 1, height: 1)
            }
        }
        patchOpaque = opaque
        self.bounds = bounds
        originalGrid = grid
        var base = grid
        base.clear(local)
        baseGrid = base
    }

    var offset: PixelPoint { exactOffset.rounded }
    /// The selection's outline at its current position (world).
    var currentRect: PixelRect { sourceRect.offsetBy(offset) }

    /// World rectangle the visible pixels would occupy at `offset`.
    func opaqueRect(at offset: PixelPoint) -> PixelRect? {
        patchOpaque?.offsetBy(sourceRect.origin + offset)
    }

    func composited() -> PixelGrid {
        var g = baseGrid
        g.stamp(patch, at: sourceRect.origin + offset - bounds.origin)
        return g
    }

    mutating func reframe(to newBounds: PixelRect) {
        originalGrid = originalGrid.reframed(from: bounds, to: newBounds)
        baseGrid = baseGrid.reframed(from: bounds, to: newBounds)
        bounds = newBounds
    }
}
