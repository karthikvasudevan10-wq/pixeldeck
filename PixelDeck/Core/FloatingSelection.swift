import Foundation

/// Pixels lifted off a frame so they can be dragged around, turned, resized or flipped. The route
/// of every drag is recorded in `path`, which is what a tween follows. Rectangles are in world
/// coordinates; the grids cover `bounds` and are re-framed if the canvas grows while the selection
/// is being moved.
struct FloatingSelection: Sendable {
    /// Where the pixels sit before any drag (world). Changes size when the selection is turned or
    /// resized, staying centred on the same spot.
    private(set) var sourceRect: PixelRect
    /// The pixels being moved (after any turn, resize or flip).
    private(set) var patch: PixelPatch
    /// Opaque part of the patch, relative to the patch's top-left (nil if it's all transparent).
    private(set) var patchOpaque: PixelRect?
    private(set) var bounds: PixelRect
    /// The frame exactly as it was before lifting.
    private(set) var originalGrid: PixelGrid
    /// The frame with the lifted pixels cleared.
    private(set) var baseGrid: PixelGrid
    /// Unrounded offset, so slow drags still accumulate.
    var exactOffset: Vec2 = .zero
    var path = MotionPath()

    /// The pixels as lifted, and where they came from: every transform starts from these, so
    /// turning back and forth never wears the art down.
    private let liftedPatch: PixelPatch
    private let liftedRect: PixelRect
    private(set) var transform = PatchTransform()

    /// Lifts the pixels of `rect` (or only those in `mask`, for lasso and wand selections).
    init(lifting rect: PixelRect, mask: SelectionMask? = nil, from grid: PixelGrid, bounds: PixelRect) {
        let r = rect.intersection(bounds)
        sourceRect = r
        liftedRect = r
        let local = r.offsetBy(PixelPoint.zero - bounds.origin)
        var lifted = grid.patch(in: local)
        var base = grid
        if let mask {
            for py in 0..<lifted.height {
                for px in 0..<lifted.width {
                    if mask.contains(PixelPoint(x: r.x + px, y: r.y + py)) {
                        base[local.x + px, local.y + py] = .clear
                    } else {
                        lifted.pixels[py * lifted.width + px] = .clear
                    }
                }
            }
        } else {
            base.clear(local)
        }
        patch = lifted
        liftedPatch = lifted
        patchOpaque = FloatingSelection.opaqueRect(of: lifted)
        self.bounds = bounds
        originalGrid = grid
        baseGrid = base
    }

    /// New pixels (a stamp, a paste) floating over `grid` with their top-left at `origin` (world).
    init(pasting patch: PixelPatch, at origin: PixelPoint, onto grid: PixelGrid, bounds: PixelRect) {
        let r = PixelRect(x: origin.x, y: origin.y, width: patch.width, height: patch.height)
        sourceRect = r
        liftedRect = r
        self.patch = patch
        liftedPatch = patch
        patchOpaque = FloatingSelection.opaqueRect(of: patch)
        self.bounds = bounds
        originalGrid = grid
        baseGrid = grid
    }

    private static func opaqueRect(of patch: PixelPatch) -> PixelRect? {
        var opaque: PixelRect?
        for py in 0..<patch.height {
            for px in 0..<patch.width where !patch[px, py].isClear {
                opaque = opaque.map { $0.union(PixelPoint(x: px, y: py)) } ?? PixelRect(x: px, y: py, width: 1, height: 1)
            }
        }
        return opaque
    }

    var offset: PixelPoint { exactOffset.rounded }
    /// The selection's outline at its current position (world).
    var currentRect: PixelRect { sourceRect.offsetBy(offset) }

    /// World rectangle the visible pixels would occupy at `offset`.
    func opaqueRect(at offset: PixelPoint) -> PixelRect? {
        patchOpaque?.offsetBy(sourceRect.origin + offset)
    }

    /// The opaque pixels at the current position (world), as a mask.
    var currentMask: SelectionMask? {
        let r = currentRect
        guard r.width > 0, r.height > 0 else { return nil }
        return SelectionMask(rect: r, bits: patch.pixels.map { !$0.isClear })?.trimmed
    }

    func composited() -> PixelGrid {
        var g = baseGrid
        g.stamp(patch, at: sourceRect.origin + offset - bounds.origin)
        return g
    }

    /// Turns, resizes or flips the lifted pixels, around their centre.
    mutating func setTransform(_ t: PatchTransform) {
        transform = t
        patch = t.apply(to: liftedPatch)
        patchOpaque = FloatingSelection.opaqueRect(of: patch)
        // Keep the centre where it was (in half pixels, to stay exact).
        let cx2 = 2 * liftedRect.x + liftedRect.width, cy2 = 2 * liftedRect.y + liftedRect.height
        sourceRect = PixelRect(x: Int((Double(cx2 - patch.width) / 2).rounded(.down)),
                               y: Int((Double(cy2 - patch.height) / 2).rounded(.down)),
                               width: patch.width, height: patch.height)
    }

    /// Replaces the lifted pixels' colours (for colour adjustments on a selection).
    mutating func mapColors(_ f: (RGBA) -> RGBA) {
        patch.pixels = patch.pixels.map { $0.isClear ? $0 : f($0) }
    }

    mutating func reframe(to newBounds: PixelRect) {
        originalGrid = originalGrid.reframed(from: bounds, to: newBounds)
        baseGrid = baseGrid.reframed(from: bounds, to: newBounds)
        bounds = newBounds
    }
}
