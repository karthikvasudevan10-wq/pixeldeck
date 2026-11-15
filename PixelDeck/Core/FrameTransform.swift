import Foundation

/// Flips and quarter turns for whole frames (see `EditorModel.transform`). Rotations are
/// clockwise as seen on screen (y grows downwards).
enum FrameTransform: String, CaseIterable, Identifiable, Sendable {
    case flipHorizontal, flipVertical, rotateClockwise, rotateCounterClockwise

    var id: String { rawValue }

    /// Where the art in `r` ends up: the same rectangle for flips; for turns, width and height
    /// swap around the same centre.
    func destination(of r: PixelRect) -> PixelRect {
        switch self {
        case .flipHorizontal, .flipVertical:
            return r
        case .rotateClockwise, .rotateCounterClockwise:
            return PixelRect(x: r.x + (r.width - r.height) / 2, y: r.y + (r.height - r.width) / 2,
                             width: r.height, height: r.width)
        }
    }

    /// Where pixel `p` (inside `r`) goes.
    func map(_ p: PixelPoint, in r: PixelRect) -> PixelPoint {
        let u = p.x - r.x, v = p.y - r.y
        let d = destination(of: r)
        switch self {
        case .flipHorizontal: return PixelPoint(x: r.x + r.width - 1 - u, y: p.y)
        case .flipVertical: return PixelPoint(x: p.x, y: r.y + r.height - 1 - v)
        case .rotateClockwise: return PixelPoint(x: d.x + (r.height - 1 - v), y: d.y + u)
        case .rotateCounterClockwise: return PixelPoint(x: d.x + v, y: d.y + (r.width - 1 - u))
        }
    }
}
