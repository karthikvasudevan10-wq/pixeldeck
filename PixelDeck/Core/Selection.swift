import Foundation

/// How the Select tool picks pixels.
enum SelectionMode: String, CaseIterable, Identifiable, Sendable {
    /// Drag a rectangle.
    case box
    /// Draw around the pixels.
    case lasso
    /// Tap a colour to pick every touching pixel of that colour.
    case wand

    var id: String { rawValue }
}

/// A set of selected pixels of any shape: a world rectangle and one flag per pixel in it.
struct SelectionMask: Equatable, Sendable {
    private(set) var rect: PixelRect
    /// Row-major, `rect.width × rect.height`.
    private(set) var bits: [Bool]

    /// Every pixel of `rect`.
    init(rect: PixelRect) {
        self.rect = rect
        bits = Array(repeating: true, count: max(0, rect.width * rect.height))
    }

    init?(rect: PixelRect, bits: [Bool]) {
        guard rect.width > 0, rect.height > 0, bits.count == rect.width * rect.height else { return nil }
        self.rect = rect
        self.bits = bits
    }

    func contains(_ p: PixelPoint) -> Bool {
        rect.contains(p) && bits[(p.y - rect.y) * rect.width + (p.x - rect.x)]
    }

    var count: Int { bits.reduce(0) { $0 + ($1 ? 1 : 0) } }
    var isEmpty: Bool { !bits.contains(true) }

    var points: [PixelPoint] {
        var out: [PixelPoint] = []
        for y in 0..<rect.height {
            for x in 0..<rect.width where bits[y * rect.width + x] { out.append(PixelPoint(x: rect.x + x, y: rect.y + y)) }
        }
        return out
    }

    func offsetBy(_ d: PixelPoint) -> SelectionMask {
        var m = self
        m.rect = rect.offsetBy(d)
        return m
    }

    /// The same pixels with the rectangle shrunk to fit them; nil if nothing is selected.
    var trimmed: SelectionMask? {
        var box: PixelRect?
        for p in points { box = box.map { $0.union(p) } ?? PixelRect(x: p.x, y: p.y, width: 1, height: 1) }
        guard let box else { return nil }
        if box == rect { return self }
        var out = [Bool](repeating: false, count: box.width * box.height)
        for p in points { out[(p.y - box.y) * box.width + (p.x - box.x)] = true }
        return SelectionMask(rect: box, bits: out)
    }

    /// Only the pixels inside `area`.
    func clipped(to area: PixelRect) -> SelectionMask? {
        let r = rect.intersection(area)
        guard !r.isEmpty else { return nil }
        var out = [Bool](repeating: false, count: r.width * r.height)
        for y in r.y..<r.maxY {
            for x in r.x..<r.maxX { out[(y - r.y) * r.width + (x - r.x)] = contains(PixelPoint(x: x, y: y)) }
        }
        return SelectionMask(rect: r, bits: out)?.trimmed
    }

    /// Lasso: the pixels on the drawn path (closed back to its start) and everything inside it.
    static func lasso(_ path: [PixelPoint]) -> SelectionMask? {
        guard let first = path.first else { return nil }
        var box = PixelRect(x: first.x, y: first.y, width: 1, height: 1)
        for p in path { box = box.union(p) }
        var bits = [Bool](repeating: false, count: box.width * box.height)
        func set(_ p: PixelPoint) { bits[(p.y - box.y) * box.width + (p.x - box.x)] = true }
        // The outline itself.
        var closed = path
        closed.append(first)
        for i in 0..<(closed.count - 1) {
            for p in PixelGrid.linePoints(from: closed[i], to: closed[i + 1]) { set(p) }
        }
        // Inside: even-odd rule on pixel centres, against the polygon through the path's pixels.
        if path.count >= 3 {
            for y in box.y..<box.maxY {
                var xs: [Double] = []
                let cy = Double(y)
                for i in 0..<(closed.count - 1) {
                    let a = closed[i], b = closed[i + 1]
                    guard a.y != b.y else { continue }
                    let (lo, hi) = a.y < b.y ? (a, b) : (b, a)
                    // Half-open, so a vertex shared by two edges is counted once.
                    guard cy >= Double(lo.y), cy < Double(hi.y) else { continue }
                    let t = (cy - Double(lo.y)) / Double(hi.y - lo.y)
                    xs.append(Double(lo.x) + t * Double(hi.x - lo.x))
                }
                xs.sort()
                var i = 0
                while i + 1 < xs.count {
                    let from = max(Int(xs[i].rounded(.up)), box.x), to = min(Int(xs[i + 1].rounded(.down)), box.maxX - 1)
                    if from <= to {
                        for x in from...to { set(PixelPoint(x: x, y: y)) }
                    }
                    i += 2
                }
            }
        }
        return SelectionMask(rect: box, bits: bits)
    }

    /// Magic wand: every pixel touching `start` (local to `grid`) with the same colour. `origin`
    /// is the grid's world origin. Nil if `start` is transparent or off the grid.
    static func wand(in grid: PixelGrid, at start: PixelPoint, origin: PixelPoint) -> SelectionMask? {
        guard grid.contains(start), !grid[start].isClear else { return nil }
        let target = grid[start]
        let w = grid.width, h = grid.height
        var seen = [Bool](repeating: false, count: w * h)
        var stack = [start]
        seen[start.y * w + start.x] = true
        while let p = stack.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let q = PixelPoint(x: p.x + dx, y: p.y + dy)
                guard grid.contains(q), !seen[q.y * w + q.x], grid[q] == target else { continue }
                seen[q.y * w + q.x] = true
                stack.append(q)
            }
        }
        return SelectionMask(rect: PixelRect(x: origin.x, y: origin.y, width: w, height: h), bits: seen)?.trimmed
    }

    /// The edges between selected and unselected pixels, as segments between pixel corners
    /// (world), for drawing the "marching ants".
    func outline() -> [(PixelPoint, PixelPoint)] {
        var out: [(PixelPoint, PixelPoint)] = []
        for p in points {
            if !contains(PixelPoint(x: p.x, y: p.y - 1)) { out.append((PixelPoint(x: p.x, y: p.y), PixelPoint(x: p.x + 1, y: p.y))) }
            if !contains(PixelPoint(x: p.x, y: p.y + 1)) { out.append((PixelPoint(x: p.x, y: p.y + 1), PixelPoint(x: p.x + 1, y: p.y + 1))) }
            if !contains(PixelPoint(x: p.x - 1, y: p.y)) { out.append((PixelPoint(x: p.x, y: p.y), PixelPoint(x: p.x, y: p.y + 1))) }
            if !contains(PixelPoint(x: p.x + 1, y: p.y)) { out.append((PixelPoint(x: p.x + 1, y: p.y), PixelPoint(x: p.x + 1, y: p.y + 1))) }
        }
        return out
    }
}

/// Rotating, scaling and flipping a block of pixels. Nearest-neighbour, so no new colours appear
/// and edges stay crisp; quarter turns and flips are exact.
struct PatchTransform: Equatable, Sendable {
    /// Degrees, clockwise on screen.
    var angle = 0.0
    /// 1 is the original size.
    var scale = 1.0
    var flipH = false
    var flipV = false

    static let scaleRange = 0.25...4.0

    var isIdentity: Bool { angle == 0 && scale == 1 && !flipH && !flipV }

    func apply(to src: PixelPatch) -> PixelPatch {
        guard !isIdentity, src.width > 0, src.height > 0 else { return src }
        let s = min(max(scale, PatchTransform.scaleRange.lowerBound), PatchTransform.scaleRange.upperBound)
        let rad = angle * .pi / 180
        let c = cos(rad), sn = sin(rad)
        let w = Double(src.width), h = Double(src.height)
        // Size of the turned, scaled box. The small epsilon stops rounding noise (cos 90° is not
        // quite 0) from adding a row or column.
        let outW = max(1, Int((abs(w * s * c) + abs(h * s * sn) - 1e-6).rounded(.up)))
        let outH = max(1, Int((abs(w * s * sn) + abs(h * s * c) - 1e-6).rounded(.up)))
        var out = [RGBA](repeating: .clear, count: outW * outH)
        for oy in 0..<outH {
            for ox in 0..<outW {
                // From the output pixel's centre back to the source.
                let dx = Double(ox) + 0.5 - Double(outW) / 2, dy = Double(oy) + 0.5 - Double(outH) / 2
                var sx = (dx * c + dy * sn) / s, sy = (-dx * sn + dy * c) / s
                if flipH { sx = -sx }
                if flipV { sy = -sy }
                let px = Int((sx + w / 2).rounded(.down)), py = Int((sy + h / 2).rounded(.down))
                guard px >= 0, py >= 0, px < src.width, py < src.height else { continue }
                out[oy * outW + ox] = src[px, py]
            }
        }
        return PixelPatch(width: outW, height: outH, pixels: out)
    }
}
