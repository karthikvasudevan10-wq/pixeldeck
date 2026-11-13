import Foundation

/// Pixels lifted off a frame so they can be dragged around. The route of every drag is recorded
/// in `path`, which is what a tween follows.
struct FloatingSelection: Sendable {
    let sourceRect: PixelRect
    let patch: PixelPatch
    /// The frame exactly as it was before lifting.
    let originalGrid: PixelGrid
    /// The frame with the lifted area cleared.
    let baseGrid: PixelGrid
    /// Unrounded offset, so slow drags still accumulate.
    var exactOffset: Vec2 = .zero
    var path = MotionPath()

    init(lifting rect: PixelRect, from grid: PixelGrid) {
        let r = rect.clipped(toCanvas: grid.size)
        sourceRect = r
        patch = grid.patch(in: r)
        originalGrid = grid
        var base = grid
        base.clear(r)
        baseGrid = base
    }

    var offset: PixelPoint { exactOffset.rounded }
    var currentRect: PixelRect { sourceRect.offsetBy(offset) }

    func composited() -> PixelGrid {
        var g = baseGrid
        g.stamp(patch, at: sourceRect.origin + offset)
        return g
    }
}
