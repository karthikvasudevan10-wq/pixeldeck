import Foundation

/// One-tap animations: the frames are drawn for you, as ordinary pixels you can then edit.
/// Names are localised in the app layer (LocalizedTitles.swift).
enum AnimationPreset: String, CaseIterable, Identifiable, Sendable {
    case bounce, blink, float, shake, colorCycle, squash

    var id: String { rawValue }

    /// Bounce and Blink are free; the rest come with Pro.
    var isFree: Bool { self == .bounce || self == .blink }

    /// Whether the "how far" slider applies.
    var usesAmount: Bool { self != .blink && self != .colorCycle }

    static let frameRange = 2...24
    static let amountRange = 1...16
    static let defaultFrames = 8
    static let defaultAmount = 6
}

enum AnimationPresets {
    /// The frames of a preset. `subject` holds the pixels to animate and `background` the rest of
    /// the layer (both the same size); each result is the background with the subject drawn in
    /// that frame's pose. The first frame is always the art as it is.
    static func frames(_ preset: AnimationPreset, subject: PixelGrid, background: PixelGrid, count: Int, amount: Int) -> [PixelGrid] {
        let n = min(max(count, AnimationPreset.frameRange.lowerBound), AnimationPreset.frameRange.upperBound)
        let a = min(max(amount, AnimationPreset.amountRange.lowerBound), AnimationPreset.amountRange.upperBound)
        guard let art = subject.opaqueBounds else { return Array(repeating: background, count: n) }
        let patch = subject.patch(in: art)
        func moved(dx: Int, dy: Int) -> PixelGrid {
            var g = background
            g.stamp(patch, at: PixelPoint(x: art.x + dx, y: art.y + dy))
            return g
        }
        switch preset {
        case .bounce:
            // Up and back down along a parabola, like a ball.
            return (0..<n).map { k in
                let t = Double(k) / Double(n)
                return moved(dx: 0, dy: -Int((Double(a) * 4 * t * (1 - t)).rounded()))
            }
        case .float:
            // A slow rise and fall.
            return (0..<n).map { k in
                let t = Double(k) / Double(n)
                return moved(dx: 0, dy: -Int((Double(a) * (1 - cos(2 * .pi * t)) / 2).rounded()))
            }
        case .shake:
            return (0..<n).map { moved(dx: shakeOffset($0, of: n, amount: a), dy: 0) }
        case .colorCycle:
            return (0..<n).map { k in
                var g = background
                let shift = ColorAdjustment(hue: 360 * Double(k) / Double(n))
                let turned = PixelPatch(width: patch.width, height: patch.height, pixels: patch.pixels.map { shift.apply(to: $0) })
                g.stamp(turned, at: art.origin)
                return g
            }
        case .squash:
            // Squash and stretch, standing on the same spot: shorter and wider, then taller and thinner.
            return (0..<n).map { k in
                let q = Int((Double(a) * sin(2 * .pi * Double(k) / Double(n))).rounded())
                guard q != 0 else { return moved(dx: 0, dy: 0) }
                let w = max(1, art.width + q), h = max(1, art.height - q)
                var g = background
                g.stamp(resized(patch, to: w, h), at: PixelPoint(x: art.x + (art.width - w) / 2, y: art.maxY - h))
                return g
            }
        case .blink:
            let closed = blinkClosed(subject: subject, art: art)
            let start = n * 5 / 8, length = max(1, n / 4)
            return (0..<n).map { k in
                var g = background
                let shut = k >= start && k < start + length && k > 0
                g.stamp((shut ? closed : subject).patch(in: art), at: art.origin)
                return g
            }
        }
    }

    /// The area (in the grids' local coordinates) the frames can reach, so the canvas can grow first.
    static func extent(_ preset: AnimationPreset, of art: PixelRect, amount: Int) -> PixelRect {
        let a = min(max(amount, AnimationPreset.amountRange.lowerBound), AnimationPreset.amountRange.upperBound)
        switch preset {
        case .bounce, .float:
            return PixelRect(x: art.x, y: art.y - a, width: art.width, height: art.height + a)
        case .shake:
            return PixelRect(x: art.x - a, y: art.y, width: art.width + 2 * a, height: art.height)
        case .squash:
            let side = (a + 1) / 2
            return PixelRect(x: art.x - side, y: art.y - a, width: art.width + 2 * side, height: art.height + a)
        case .blink, .colorCycle:
            return art
        }
    }

    /// Side-to-side, strongest at first and settling down.
    static func shakeOffset(_ k: Int, of n: Int, amount: Int) -> Int {
        guard k > 0 else { return 0 }
        let fade = 1 - Double(k - 1) / Double(max(1, n - 1))
        let d = max(1, Int((Double(amount) * fade).rounded()))
        return k % 2 == 1 ? d : -d
    }

    static func resized(_ p: PixelPatch, to w: Int, _ h: Int) -> PixelPatch {
        var out = [RGBA](repeating: .clear, count: w * h)
        for y in 0..<h {
            let sy = min(p.height - 1, Int((Double(y) + 0.5) * Double(p.height) / Double(h)))
            for x in 0..<w {
                let sx = min(p.width - 1, Int((Double(x) + 0.5) * Double(p.width) / Double(w)))
                out[y * w + x] = p[sx, sy]
            }
        }
        return PixelPatch(width: w, height: h, pixels: out)
    }

    /// The art with its eyes shut. Eyes are small dark shapes inside the art (not part of the
    /// outline): each is painted over with the colour around it, leaving a line along its bottom
    /// row. If no eyes are found the whole subject blinks off instead, like a game sprite.
    static func blinkClosed(subject: PixelGrid, art: PixelRect) -> PixelGrid {
        let eyes = eyeRegions(in: subject, art: art)
        guard !eyes.isEmpty else { return PixelGrid(width: subject.width, height: subject.height) }
        var out = subject
        for eye in eyes {
            // The colour most often found next to the eye: the "skin".
            var around: [RGBA: Int] = [:]
            let inEye = Set(eye)
            for p in eye {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let q = PixelPoint(x: p.x + dx, y: p.y + dy)
                    let c = subject[q]
                    if !inEye.contains(q), !c.isClear { around[c, default: 0] += 1 }
                }
            }
            guard let skin = around.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.hexString > $1.key.hexString })?.key else { continue }
            let bottom = eye.map(\.y).max() ?? 0
            for p in eye where p.y != bottom { out[p] = skin }
        }
        return out
    }

    /// Small dark connected shapes that don't touch the edge of the art.
    static func eyeRegions(in grid: PixelGrid, art: PixelRect) -> [[PixelPoint]] {
        let w = grid.width
        var seen = [Bool](repeating: false, count: grid.width * grid.height)
        let limit = max(2, art.width * art.height / 24)
        var found: [[PixelPoint]] = []
        for y in art.y..<art.maxY {
            for x in art.x..<art.maxX {
                let start = PixelPoint(x: x, y: y)
                let c = grid[start]
                guard !seen[y * w + x], !c.isClear, c.luminance < 0.3 else { continue }
                var region: [PixelPoint] = []
                var touchesEdge = false
                var stack = [start]
                seen[y * w + x] = true
                while let p = stack.popLast() {
                    region.append(p)
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let q = PixelPoint(x: p.x + dx, y: p.y + dy)
                        guard grid.contains(q) else { touchesEdge = true; continue }
                        let qc = grid[q]
                        if qc.isClear { touchesEdge = true; continue }
                        guard !seen[q.y * w + q.x], qc == c else { continue }
                        seen[q.y * w + q.x] = true
                        stack.append(q)
                    }
                }
                let ys = region.map(\.y)
                let tall = (ys.max() ?? 0) - (ys.min() ?? 0) + 1
                if !touchesEdge, region.count <= limit, tall >= 2 { found.append(region) }
            }
        }
        return found
    }
}
