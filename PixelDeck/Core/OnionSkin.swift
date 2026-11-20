import Foundation

/// How the previous frame is drawn under the current one. A flat pink silhouette hides the inside
/// of the art (eyes, mouths, buttons), so each pixel's pink follows its brightness (dark → deep
/// pink, light → pale pink), and pixels where two different colours meet are drawn a shade darker,
/// so features keep their outlines even when their colours are equally bright.
enum OnionSkin {
    /// Deepest and lightest pinks of the ramp.
    static let dark = RGBA(hex: 0x8E1F4F)
    static let light = RGBA(hex: 0xFFC9DA)

    /// The blues for frames that come next.
    static let aheadDark = RGBA(hex: 0x1F3F8E)
    static let aheadLight = RGBA(hex: 0xC9DAFF)

    /// How strongly each onion frame shows, nearest first: older (and later) frames fade more.
    static let beforeStrength = [1.0, 0.55, 0.3]
    static let afterStrength = [0.8, 0.45]

    /// Several onion frames in one picture: earlier frames in pink, later ones in blue, each
    /// fainter the further it is from the current frame. `before` and `after` are nearest first
    /// and all the same size. The result is premultiplied (ready to draw), or nil if both are empty.
    static func composite(before: [PixelGrid], after: [PixelGrid]) -> PixelGrid? {
        guard let size = before.first ?? after.first else { return nil }
        let count = size.width * size.height
        // Premultiplied r, g, b, a per pixel, 0…1.
        var acc = [Double](repeating: 0, count: count * 4)
        func add(_ tinted: PixelGrid, strength: Double) {
            guard tinted.width == size.width, tinted.height == size.height else { return }
            for (i, c) in tinted.pixels.enumerated() where c.a != 0 {
                let keep = 1 - strength
                acc[i * 4] = Double(c.r) / 255 * strength + acc[i * 4] * keep
                acc[i * 4 + 1] = Double(c.g) / 255 * strength + acc[i * 4 + 1] * keep
                acc[i * 4 + 2] = Double(c.b) / 255 * strength + acc[i * 4 + 2] * keep
                acc[i * 4 + 3] = strength + acc[i * 4 + 3] * keep
            }
        }
        // Furthest first, so nearer frames sit on top; the previous frame is topmost.
        for (k, g) in after.enumerated().reversed() where k < afterStrength.count {
            add(tint(g, dark: aheadDark, light: aheadLight), strength: afterStrength[k])
        }
        for (k, g) in before.enumerated().reversed() where k < beforeStrength.count {
            add(tint(g), strength: beforeStrength[k])
        }
        func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        var bytes = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<(count * 4) { bytes[i] = byte(acc[i]) }
        return PixelGrid(width: size.width, height: size.height, rgbaBytes: bytes)
    }

    static func tint(_ grid: PixelGrid) -> PixelGrid { tint(grid, dark: dark, light: light) }

    static func tint(_ grid: PixelGrid, dark: RGBA, light: RGBA) -> PixelGrid {
        var out = PixelGrid(width: grid.width, height: grid.height)
        let w = grid.width, h = grid.height
        for y in 0..<h {
            for x in 0..<w {
                let c = grid[x, y]
                guard !c.isClear else { continue }
                // Perceived brightness, 0…1.
                var t = (0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)) / 255
                // Edge of a feature or of the art: a neighbour with a different colour.
                let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in grid[x + dx, y + dy] != c }
                if edge { t *= 0.6 }
                out[x, y] = mix(dark, light, t)
            }
        }
        return out
    }

    private static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        let t = min(max(t, 0), 1)
        func ch(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return RGBA(r: ch(a.r, b.r), g: ch(a.g, b.g), b: ch(a.b, b.b), a: 255)
    }
}
