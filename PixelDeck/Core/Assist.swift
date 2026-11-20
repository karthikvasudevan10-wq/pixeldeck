import Foundation

// Drawing assistance: pixel-perfect strokes and the shading assistant.

/// Pixel-perfect strokes: when a stroke turns a corner through three pixels in an L, the middle
/// one is dropped, so lines and curves stay one pixel wide with no doubled corners.
enum PixelPerfect {
    /// `b` is the corner of an L between `a` and `c`.
    static func isCorner(_ a: PixelPoint, _ b: PixelPoint, _ c: PixelPoint) -> Bool {
        let ab = abs(a.x - b.x) + abs(a.y - b.y) == 1
        let bc = abs(b.x - c.x) + abs(b.y - c.y) == 1
        let ac = abs(a.x - c.x) == 1 && abs(a.y - c.y) == 1
        return ab && bc && ac
    }

    /// A stroke path with every L-corner removed.
    static func clean(_ path: [PixelPoint]) -> [PixelPoint] {
        var out: [PixelPoint] = []
        for p in path {
            if out.last == p { continue }
            out.append(p)
            let n = out.count
            if n >= 3, isCorner(out[n - 3], out[n - 2], out[n - 1]) { out.remove(at: n - 2) }
        }
        return out
    }
}

/// Where the light comes from, for the shading assistant.
enum LightDirection: String, CaseIterable, Identifiable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    /// Points from the art towards the light (y grows downwards).
    var vector: (dx: Int, dy: Int) {
        switch self {
        case .topLeft: (-1, -1)
        case .top: (0, -1)
        case .topRight: (1, -1)
        case .left: (-1, 0)
        case .right: (1, 0)
        case .bottomLeft: (-1, 1)
        case .bottom: (0, 1)
        case .bottomRight: (1, 1)
        }
    }

    /// Position in the 3 × 3 picker (the middle cell is the art).
    var gridIndex: Int {
        switch self {
        case .topLeft: 0
        case .top: 1
        case .topRight: 2
        case .left: 3
        case .right: 5
        case .bottomLeft: 6
        case .bottom: 7
        case .bottomRight: 8
        }
    }
}

enum ShadeMode: String, CaseIterable, Identifiable, Sendable {
    case shade, highlight
    var id: String { rawValue }
}

/// The shading assistant: instead of shading in rings from the outline ("pillow shading"), a
/// pixel's shade depends on how far it is from the light across the shape it belongs to.
enum Shading {
    /// 0 at the edge of `region` nearest the light, 1 at the farthest.
    static func depth(of p: PixelPoint, in region: PixelRect, light: LightDirection) -> Double {
        let v = light.vector
        let cx = Double(region.x) + Double(region.width - 1) / 2, cy = Double(region.y) + Double(region.height - 1) / 2
        // Distance away from the light, along the light's direction.
        let s = -(Double(p.x) - cx) * Double(v.dx) - (Double(p.y) - cy) * Double(v.dy)
        let extent = Double(abs(v.dx)) * Double(region.width - 1) / 2 + Double(abs(v.dy)) * Double(region.height - 1) / 2
        guard extent > 0 else { return 0.5 }
        return min(max(0.5 + s / (2 * extent), 0), 1)
    }

    /// Which ramp step a pixel should take. The ramp runs dark to light with the base colour at
    /// `baseIndex`; `current` is the step the pixel has now. Shade darkens the half facing away
    /// from the light, in bands, and clears old shading from the lit half; Highlight is the
    /// reverse. Each leaves the other's work alone where it has nothing to add.
    static func step(at p: PixelPoint, in region: PixelRect, light: LightDirection, count: Int,
                     baseIndex: Int, mode: ShadeMode, current: Int) -> Int {
        guard count > 0, (0..<count).contains(baseIndex) else { return current }
        let t = depth(of: p, in: region, light: light)
        switch mode {
        case .shade:
            let darker = baseIndex
            let k = t > 0.5 ? min(darker, Int((t - 0.5) * 2 * Double(darker + 1))) : 0
            if current > baseIndex { return k > 0 ? baseIndex - k : current }
            return baseIndex - k
        case .highlight:
            let lighter = count - 1 - baseIndex
            let k = t < 0.5 ? min(lighter, Int((0.5 - t) * 2 * Double(lighter + 1))) : 0
            if current < baseIndex { return k > 0 ? baseIndex + k : current }
            return baseIndex + k
        }
    }
}

extension PixelGrid {
    /// Bounding box (local) of the connected opaque pixels around `start`, or nil if `start` is
    /// transparent. Used to find "the shape" a shading stroke belongs to.
    func opaqueRegionBounds(around start: PixelPoint) -> PixelRect? {
        guard contains(start), !self[start].isClear else { return nil }
        var seen = [Bool](repeating: false, count: width * height)
        var stack = [start]
        seen[start.y * width + start.x] = true
        var box = PixelRect(x: start.x, y: start.y, width: 1, height: 1)
        while let p = stack.popLast() {
            box = box.union(p)
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let q = PixelPoint(x: p.x + dx, y: p.y + dy)
                guard contains(q), !seen[q.y * width + q.x], !self[q].isClear else { continue }
                seen[q.y * width + q.x] = true
                stack.append(q)
            }
        }
        return box
    }
}
