import Foundation

/// How the previous frame is drawn under the current one. A flat pink silhouette hides the inside
/// of the art (eyes, mouths, buttons), so each pixel's pink follows its brightness (dark → deep
/// pink, light → pale pink), and pixels where two different colours meet are drawn a shade darker,
/// so features keep their outlines even when their colours are equally bright.
enum OnionSkin {
    /// Deepest and lightest pinks of the ramp.
    static let dark = RGBA(hex: 0x8E1F4F)
    static let light = RGBA(hex: 0xFFC9DA)

    static func tint(_ grid: PixelGrid) -> PixelGrid {
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
