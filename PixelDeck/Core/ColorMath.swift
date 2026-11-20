import Foundation

/// Hue, saturation and lightness, each 0…1 (hue wraps).
struct HSL: Equatable, Sendable {
    var h: Double
    var s: Double
    var l: Double
}

extension RGBA {
    var hsl: HSL {
        let r = Double(self.r) / 255, g = Double(self.g) / 255, b = Double(self.b) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        guard mx > mn else { return HSL(h: 0, s: 0, l: l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h /= 6
        return HSL(h: h, s: s, l: l)
    }

    /// Opaque colour from hue, saturation and lightness.
    init(hsl c: HSL) {
        let h = c.h - c.h.rounded(.down), s = min(max(c.s, 0), 1), l = min(max(c.l, 0), 1)
        func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        guard s > 0 else { self.init(r: byte(l), g: byte(l), b: byte(l)); return }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        self.init(r: byte(channel(h + 1.0 / 3)), g: byte(channel(h)), b: byte(channel(h - 1.0 / 3)))
    }

    /// Perceived brightness, 0…1.
    var luminance: Double { (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255 }

    /// Squared distance between two colours, weighted roughly as the eye sees it.
    func distanceSquared(to o: RGBA) -> Int {
        let dr = Int(r) - Int(o.r), dg = Int(g) - Int(o.g), db = Int(b) - Int(o.b)
        return 2 * dr * dr + 4 * dg * dg + 3 * db * db
    }

    /// The closest colour in `palette` (which must not be empty).
    func nearest(in palette: [RGBA]) -> RGBA {
        var best = palette[0], bestD = Int.max
        for c in palette {
            let d = distanceSquared(to: c)
            if d < bestD { bestD = d; best = c }
        }
        return best
    }
}

/// Shading ramps: a base colour stepped darker and lighter, with the hue shifting as pixel artists
/// do it (shadows lean towards blue-purple, highlights lean warm), not just more black and white.
enum ColorRamp {
    static let stepRange = 3...9
    /// Degrees.
    static let hueShiftRange = 0.0...40.0

    /// `steps` colours from dark to light, with `base` among them.
    static func make(from base: RGBA, steps: Int, hueShift: Double = 18) -> [RGBA] {
        let n = min(max(steps, stepRange.lowerBound), stepRange.upperBound)
        let darkCount = (n - 1) / 2, lightCount = n - 1 - darkCount
        let c = base.hsl
        let shift = min(max(hueShift, 0), hueShiftRange.upperBound) / 360
        // Shortest way round the wheel from `from` towards `target`, limited to `amount`.
        func lean(_ from: Double, towards target: Double, by amount: Double) -> Double {
            var d = target - from
            if d > 0.5 { d -= 1 }
            if d < -0.5 { d += 1 }
            return from + max(-amount, min(amount, d))
        }
        var out: [RGBA] = []
        for k in stride(from: darkCount, to: 0, by: -1) {
            let t = Double(k) / Double(darkCount)
            let l = c.l * (1 - 0.62 * t * (darkCount == 1 ? 0.6 : 1))
            out.append(RGBA(hsl: HSL(h: lean(c.h, towards: 0.72, by: shift * t), s: min(1, c.s * (1 - 0.15 * t) + 0.05 * t), l: l)))
        }
        out.append(RGBA(r: base.r, g: base.g, b: base.b))
        for k in 1...max(1, lightCount) where lightCount > 0 {
            let t = Double(k) / Double(lightCount)
            let l = c.l + (0.94 - c.l) * t * (lightCount == 1 ? 0.6 : 1)
            out.append(RGBA(hsl: HSL(h: lean(c.h, towards: 0.13, by: shift * t), s: c.s * (1 - 0.35 * t), l: l)))
        }
        return out
    }
}

/// Brightness, contrast, hue and saturation changes for a set of pixels. Each pixel is adjusted
/// from its own colour, so a multi-coloured selection keeps its colour relationships.
struct ColorAdjustment: Equatable, Sendable {
    /// −100…100.
    var brightness = 0.0
    /// −100…100.
    var contrast = 0.0
    /// Degrees, −180…180.
    var hue = 0.0
    /// −100…100.
    var saturation = 0.0

    var isIdentity: Bool { brightness == 0 && contrast == 0 && hue == 0 && saturation == 0 }

    func apply(to c: RGBA) -> RGBA {
        guard !c.isClear, !isIdentity else { return c }
        var x = c.hsl
        x.h += hue / 360
        x.s = saturation >= 0 ? x.s + (1 - x.s) * saturation / 100 : x.s * (1 + saturation / 100)
        // Contrast pushes lightness away from (or towards) the middle; brightness then shifts it.
        let k = contrast >= 0 ? 1 + contrast / 50 : 1 + contrast / 100
        x.l = 0.5 + (x.l - 0.5) * k
        x.l = brightness >= 0 ? x.l + (1 - x.l) * brightness / 100 : x.l * (1 + brightness / 100)
        return RGBA(hsl: x)
    }
}

/// Counting and tidying the colours in a sprite.
enum ColorTools {
    /// Past this many colours the Colours panel gently suggests merging near-duplicates.
    static let hintThreshold = 16

    /// How many times each opaque colour is used.
    static func histogram(_ grids: [PixelGrid]) -> [RGBA: Int] {
        var counts: [RGBA: Int] = [:]
        for g in grids {
            for c in g.pixels where c.a != 0 { counts[c, default: 0] += 1 }
        }
        return counts
    }

    /// Colours that look almost the same, each mapped to the most-used colour of its group.
    /// `tolerance` is a weighted distance (see `distanceSquared`); 600 is "hard to tell apart".
    static func mergePlan(_ counts: [RGBA: Int], tolerance: Int = 600) -> [RGBA: RGBA] {
        // Most-used first, so popular colours become the ones others merge into.
        let ordered = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.hexString < $1.key.hexString }.map(\.key)
        var keepers: [RGBA] = []
        var plan: [RGBA: RGBA] = [:]
        for c in ordered {
            if let k = keepers.first(where: { $0.distanceSquared(to: c) <= tolerance }) {
                plan[c] = k
            } else {
                keepers.append(c)
            }
        }
        return plan
    }
}
