import Foundation

/// The shape tools.
enum ShapeKind: String, CaseIterable, Identifiable, Sendable {
    case line, rectangle, ellipse, triangle
    case diamond, pentagon, hexagon, octagon, parallelogram, star
    var id: String { rawValue }

    /// Corners of the polygon shapes, as fractions (0…1) of the dragged box.
    var polygon: [(Double, Double)]? {
        switch self {
        case .diamond: [(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)]
        case .hexagon: [(0.25, 0), (0.75, 0), (1, 0.5), (0.75, 1), (0.25, 1), (0, 0.5)]
        case .octagon: [(0.3, 0), (0.7, 0), (1, 0.3), (1, 0.7), (0.7, 1), (0.3, 1), (0, 0.7), (0, 0.3)]
        case .parallelogram: [(0.25, 0), (1, 0), (0.75, 1), (0, 1)]
        case .pentagon: ShapeKind.regular(points: 5, inner: nil)
        case .star: ShapeKind.regular(points: 5, inner: 0.382)
        case .line, .rectangle, .ellipse, .triangle: nil
        }
    }

    /// A regular polygon (or star, with an inner radius), point up, stretched to fill the box.
    private static func regular(points n: Int, inner: Double?) -> [(Double, Double)] {
        var pts: [(Double, Double)] = []
        let steps = inner == nil ? n : n * 2
        for k in 0..<steps {
            let r = (inner != nil && k % 2 == 1) ? inner! : 1.0
            let a = -Double.pi / 2 + Double(k) * 2 * Double.pi / Double(steps)
            pts.append((r * cos(a), r * sin(a)))
        }
        let minX = pts.map(\.0).min()!, maxX = pts.map(\.0).max()!
        let minY = pts.map(\.1).min()!, maxY = pts.map(\.1).max()!
        return pts.map { (($0.0 - minX) / (maxX - minX), ($0.1 - minY) / (maxY - minY)) }
    }
}

/// Pixel-perfect shape rasterizers, in world coordinates. Shapes are dragged from `a` to `b`
/// (the corners of their bounding box; the end points for a line).
enum ShapeRaster {
    /// With proportions locked: lines snap to 0°, 45° or 90°; the others get a square box
    /// (squares, circles, and triangles as wide as they are tall).
    static func constrained(_ kind: ShapeKind, from a: PixelPoint, to b: PixelPoint) -> PixelPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        switch kind {
        case .line:
            let ax = abs(dx), ay = abs(dy)
            if ax > 2 * ay { return PixelPoint(x: b.x, y: a.y) }
            if ay > 2 * ax { return PixelPoint(x: a.x, y: b.y) }
            let d = max(ax, ay)
            return PixelPoint(x: a.x + (dx < 0 ? -d : d), y: a.y + (dy < 0 ? -d : d))
        case .rectangle, .ellipse, .triangle, .diamond, .pentagon, .hexagon, .octagon, .parallelogram, .star:
            let d = max(abs(dx), abs(dy))
            return PixelPoint(x: a.x + (dx < 0 ? -d : d), y: a.y + (dy < 0 ? -d : d))
        }
    }

    /// Every pixel of the shape.
    static func points(_ kind: ShapeKind, from a: PixelPoint, to b: PixelPoint, filled: Bool) -> [PixelPoint] {
        if let corners = kind.polygon {
            return polygon(corners, in: PixelRect(corner: a, b), filled: filled)
        }
        switch kind {
        case .line:
            return PixelGrid.linePoints(from: a, to: b)
        case .rectangle:
            let r = PixelRect(corner: a, b)
            var out: [PixelPoint] = []
            for y in r.y..<r.maxY {
                for x in r.x..<r.maxX where filled || x == r.x || x == r.maxX - 1 || y == r.y || y == r.maxY - 1 {
                    out.append(PixelPoint(x: x, y: y))
                }
            }
            return out
        case .ellipse:
            let outline = ellipse(PixelRect(corner: a, b))
            return filled ? fillRows(outline) : outline
        case .diamond, .pentagon, .hexagon, .octagon, .parallelogram, .star:
            return []                                    // handled as polygons above
        case .triangle:
            let r = PixelRect(corner: a, b)
            // Apex on the side the drag started from: dragging down points it up.
            let apexTop = b.y >= a.y
            let midX = r.x + (r.width - 1) / 2
            let apex = PixelPoint(x: midX, y: apexTop ? r.y : r.maxY - 1)
            let baseY = apexTop ? r.maxY - 1 : r.y
            let left = PixelPoint(x: r.x, y: baseY), right = PixelPoint(x: r.maxX - 1, y: baseY)
            let leftEdge = PixelGrid.linePoints(from: apex, to: left)
            // The right edge mirrors the left exactly, so the triangle is symmetrical (an
            // even-width triangle gets a 2-pixel apex).
            let rightEdge = leftEdge.map { PixelPoint(x: r.x + r.maxX - 1 - $0.x, y: $0.y) }
            let outline = leftEdge + rightEdge + PixelGrid.linePoints(from: left, to: right)
            return filled ? fillRows(outline) : dedupe(outline)
        }
    }

    /// Ellipse inscribed in `r` (Zingl's midpoint algorithm, which handles even sizes exactly).
    static func ellipse(_ r: PixelRect) -> [PixelPoint] {
        var x0 = r.x, x1 = r.maxX - 1, y0 = r.y, y1 = r.maxY - 1
        let a = x1 - x0, b = y1 - y0
        if a == 0 || b == 0 {
            return PixelRect(x: x0, y: y0, width: a + 1, height: b + 1).allPoints
        }
        var out: [PixelPoint] = []
        let b1 = b & 1
        var dx = 4.0 * (1.0 - Double(a)) * Double(b * b)
        var dy = 4.0 * Double(b1 + 1) * Double(a * a)
        var err = dx + dy + Double(b1 * a * a)
        y0 += (b + 1) / 2
        y1 = y0 - b1
        let a8 = 8.0 * Double(a * a), b8 = 8.0 * Double(b * b)
        repeat {
            out.append(PixelPoint(x: x1, y: y0)); out.append(PixelPoint(x: x0, y: y0))
            out.append(PixelPoint(x: x0, y: y1)); out.append(PixelPoint(x: x1, y: y1))
            let e2 = 2 * err
            if e2 <= dy { y0 += 1; y1 -= 1; dy += a8; err += dy }
            if e2 >= dx || 2 * err > dy { x0 += 1; x1 -= 1; dx += b8; err += dx }
        } while x0 <= x1
        // Flat ellipses can stop early: finish the tips.
        while y0 - y1 <= b {
            out.append(PixelPoint(x: x0 - 1, y: y0)); out.append(PixelPoint(x: x1 + 1, y: y0)); y0 += 1
            out.append(PixelPoint(x: x0 - 1, y: y1)); out.append(PixelPoint(x: x1 + 1, y: y1)); y1 -= 1
        }
        return dedupe(out)
    }

    /// A polygon given as fractions of `r`. Corners that mirror each other (u and 1 − u) land on
    /// mirrored pixels, so symmetric shapes stay symmetric at any size. Filled shapes use an
    /// even-odd scanline fill, which also handles the concave star.
    static func polygon(_ corners: [(Double, Double)], in r: PixelRect, filled: Bool) -> [PixelPoint] {
        let w = Double(r.width - 1), h = Double(r.height - 1)
        func place(_ f: Double, _ span: Double) -> Int {
            f <= 0.5 ? Int((f * span).rounded()) : Int(span) - Int(((1 - f) * span).rounded())
        }
        let v = corners.map { PixelPoint(x: r.x + place($0.0, w), y: r.y + place($0.1, h)) }
        // Left-right symmetric shapes draw their left edges and mirror them, because a line
        // and its mirror image don't always rasterize to mirrored pixels.
        let symmetric = corners.allSatisfy { c in
            corners.contains { abs($0.0 - (1 - c.0)) < 1e-9 && abs($0.1 - c.1) < 1e-9 }
        }
        func mirror(_ p: PixelPoint) -> PixelPoint { PixelPoint(x: r.x + r.maxX - 1 - p.x, y: p.y) }
        var outline: [PixelPoint] = []
        for i in v.indices {
            let j = (i + 1) % v.count
            let edge = PixelGrid.linePoints(from: v[i], to: v[j])
            guard symmetric else { outline += edge; continue }
            let mid = (corners[i].0 + corners[j].0) / 2
            // Right-half edges are skipped: they're the mirrors of left-half ones.
            if mid <= 0.5 + 1e-9 { outline += edge + edge.map(mirror) }
        }
        guard filled else { return dedupe(outline) }

        // Scanline fill through pixel centres, then add the outline so edges are solid.
        var out = Set(outline)
        for y in r.y..<r.maxY {
            let yc = Double(y)
            var xs: [Double] = []
            for i in v.indices {
                let p = v[i], q = v[(i + 1) % v.count]
                let (y1, y2) = (Double(p.y), Double(q.y))
                // Half-open on y so shared vertices aren't counted twice.
                if (yc >= min(y1, y2)) && (yc < max(y1, y2)) {
                    let t = (yc - y1) / (y2 - y1)
                    xs.append(Double(p.x) + t * Double(q.x - p.x))
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                let from = Int(xs[i].rounded(.up)), to = Int(xs[i + 1].rounded(.down))
                if from <= to { for x in from...to { out.insert(PixelPoint(x: x, y: y)) } }
                i += 2
            }
        }
        if symmetric { out.formUnion(out.map(mirror)) }
        return Array(out)
    }

    /// Fills each row between the outline's leftmost and rightmost pixel (the shapes are convex).
    static func fillRows(_ outline: [PixelPoint]) -> [PixelPoint] {
        var span: [Int: (Int, Int)] = [:]
        for p in outline {
            if let s = span[p.y] { span[p.y] = (min(s.0, p.x), max(s.1, p.x)) } else { span[p.y] = (p.x, p.x) }
        }
        var out: [PixelPoint] = []
        for (y, s) in span.sorted(by: { $0.key < $1.key }) {
            for x in s.0...s.1 { out.append(PixelPoint(x: x, y: y)) }
        }
        return out
    }

    private static func dedupe(_ pts: [PixelPoint]) -> [PixelPoint] {
        var seen = Set<PixelPoint>()
        return pts.filter { seen.insert($0).inserted }
    }
}

extension PixelRect {
    var allPoints: [PixelPoint] {
        var out: [PixelPoint] = []
        for y in self.y..<maxY { for x in self.x..<maxX { out.append(PixelPoint(x: x, y: y)) } }
        return out
    }
}
