import Foundation

/// Retro looks: a small fixed palette (and, as canvas modes in the Studio, dither between its
/// shades). Names are localised in the app layer.
enum RetroMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Two colours.
    case oneBit
    /// Four greens, like an old handheld.
    case handheld
    /// Black ink and paper, with two greys.
    case ink
    /// Eight bright colours, like an early home computer.
    case eightColor

    var id: String { rawValue }

    /// Dark to light (for `eightColor`, a fixed set).
    var colors: [RGBA] {
        let hex: [UInt32]
        switch self {
        case .oneBit: hex = [0x1B1530, 0xFFF6E0]
        case .handheld: hex = [0x0F380F, 0x306230, 0x8BAC0F, 0x9BBC0F]
        case .ink: hex = [0x15131A, 0x5A5560, 0xA8A2AE, 0xF4EFE6]
        case .eightColor: hex = [0x000000, 0x1D2BD9, 0xD92B2B, 0xD93BD9, 0x2BC72B, 0x35C9D9, 0xE6DC3C, 0xFFFFFF]
        }
        return hex.map { RGBA(hex: $0) }
    }

    /// Monochrome modes get a tag in Community.
    var isMonochrome: Bool { self != .eightColor }
}

/// Settings for turning a photo into pixel art.
struct PhotoOptions: Equatable, Sendable {
    enum Colors: String, CaseIterable, Identifiable, Sendable {
        /// Colours picked from the photo itself.
        case own
        /// The sprite's palette.
        case palette
        case retro
        var id: String { rawValue }
    }

    /// Tiny icons to detailed pictures. (Anything over 64 needs Pro's bigger canvas, as does
    /// keeping a photo conversion at all.)
    static let sizes = [16, 32, 48, 64, 96, 128]
    static let colorCountRange = 2...32

    /// Longest side of the result, in pixels.
    var size = 48
    var colors: Colors = .own
    /// For "Photo's own".
    var colorCount = 16
    var retro: RetroMode = .handheld
    /// Replaces lone pixels with the colour around them.
    var cleanUp = true
    /// Checkerboard blends between colours.
    var dither = false
    /// Darkens strong edges.
    var outline = false
}

/// Photo → pixel art: shrink, reduce the colours, tidy.
enum PhotoPixelizer {
    /// `rgba` is `width × height` RGBA8 (any size; it is averaged down). `palette` is used for the
    /// "My palette" option. Returns the art and the colours it uses.
    static func convert(rgba: [UInt8], width: Int, height: Int, options o: PhotoOptions, palette: [RGBA]) -> (grid: PixelGrid, colors: [RGBA])? {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        let side = PhotoOptions.sizes.contains(o.size) ? o.size : 48
        let scale = Double(side) / Double(max(width, height))
        let w = max(1, min(side, Int((Double(width) * scale).rounded()))), h = max(1, min(side, Int((Double(height) * scale).rounded())))
        let small = downsample(rgba, width, height, to: w, h)

        var colors: [RGBA]
        switch o.colors {
        case .own:
            let n = min(max(o.colorCount, PhotoOptions.colorCountRange.lowerBound), PhotoOptions.colorCountRange.upperBound)
            colors = medianCut(small, count: n)
        case .palette:
            colors = palette.isEmpty ? SpriteProject.defaultPalette : palette
        case .retro:
            colors = o.retro.colors
        }
        guard !colors.isEmpty else { return nil }

        var grid = PixelGrid(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let c = small[y * w + x]
                grid[x, y] = o.dither ? dithered(c, x: x, y: y, in: colors) : c.nearest(in: colors)
            }
        }
        if o.cleanUp { grid = cleanedUp(grid) }
        if o.outline { grid = outlined(grid, ink: colors.min { $0.luminance < $1.luminance } ?? .black) }
        let used = ColorTools.histogram([grid])
        return (grid, colors.filter { used[$0] != nil })
    }

    /// Box-average shrink (or nearest-neighbour growth) to `w × h`, opaque.
    static func downsample(_ rgba: [UInt8], _ width: Int, _ height: Int, to w: Int, _ h: Int) -> [RGBA] {
        var out = [RGBA](repeating: .black, count: w * h)
        for y in 0..<h {
            let y0 = y * height / h, y1 = max(y0 + 1, (y + 1) * height / h)
            for x in 0..<w {
                let x0 = x * width / w, x1 = max(x0 + 1, (x + 1) * width / w)
                var r = 0, g = 0, b = 0, n = 0
                for sy in y0..<min(y1, height) {
                    for sx in x0..<min(x1, width) {
                        let i = (sy * width + sx) * 4
                        r += Int(rgba[i]); g += Int(rgba[i + 1]); b += Int(rgba[i + 2]); n += 1
                    }
                }
                if n > 0 { out[y * w + x] = RGBA(r: UInt8(r / n), g: UInt8(g / n), b: UInt8(b / n)) }
            }
        }
        return out
    }

    /// Up to `count` colours that represent `pixels`: repeatedly split the box of colours with the
    /// widest spread at its median, then average each box.
    static func medianCut(_ pixels: [RGBA], count: Int) -> [RGBA] {
        let opaque = pixels.filter { !$0.isClear }
        guard !opaque.isEmpty, count > 0 else { return [] }
        var boxes: [[RGBA]] = [opaque]
        func spread(_ box: [RGBA]) -> (range: Int, channel: Int) {
            var lo = [255, 255, 255], hi = [0, 0, 0]
            for c in box {
                let v = [Int(c.r), Int(c.g), Int(c.b)]
                for i in 0..<3 { lo[i] = min(lo[i], v[i]); hi[i] = max(hi[i], v[i]) }
            }
            // Green counts most to the eye, blue least.
            let ranges = [(hi[0] - lo[0]) * 3, (hi[1] - lo[1]) * 4, (hi[2] - lo[2]) * 2]
            let ch = ranges.indices.max { ranges[$0] < ranges[$1] } ?? 0
            return (ranges[ch], ch)
        }
        while boxes.count < count {
            // Split the box with the widest spread that still has more than one colour in it.
            var best = -1, bestRange = 0, bestChannel = 0
            for (i, box) in boxes.enumerated() where box.count > 1 {
                let s = spread(box)
                if s.range > bestRange { best = i; bestRange = s.range; bestChannel = s.channel }
            }
            guard best >= 0 else { break }
            let ch = bestChannel
            func key(_ c: RGBA) -> UInt8 { ch == 0 ? c.r : ch == 1 ? c.g : c.b }
            let sorted = boxes[best].sorted { key($0) < key($1) }
            let mid = sorted.count / 2
            boxes[best] = Array(sorted[..<mid])
            boxes.append(Array(sorted[mid...]))
        }
        var out: [RGBA] = []
        for box in boxes where !box.isEmpty {
            var r = 0, g = 0, b = 0
            for c in box { r += Int(c.r); g += Int(c.g); b += Int(c.b) }
            let c = RGBA(r: UInt8(r / box.count), g: UInt8(g / box.count), b: UInt8(b / box.count))
            if !out.contains(c) { out.append(c) }
        }
        return out.sorted { $0.luminance < $1.luminance }
    }

    /// Ordered dither: between its two nearest colours, a pixel takes one or the other in a fixed
    /// 2 × 2 pattern, so in-between shades become checkerboards.
    static func dithered(_ c: RGBA, x: Int, y: Int, in colors: [RGBA]) -> RGBA {
        let first = c.nearest(in: colors)
        guard colors.count > 1 else { return first }
        let rest = colors.filter { $0 != first }
        let second = c.nearest(in: rest)
        let d1 = Double(c.distanceSquared(to: first)).squareRoot(), d2 = Double(c.distanceSquared(to: second)).squareRoot()
        guard d1 + d2 > 0 else { return first }
        // 0 at `first`, 0.5 half-way to `second`.
        let t = d1 / (d1 + d2)
        let threshold = [0.125, 0.375, 0.5, 0.25][(y & 1) * 2 + (x & 1)]
        return t > threshold ? second : first
    }

    /// Lone pixels (no neighbour of the same colour) take the most common colour around them.
    static func cleanedUp(_ grid: PixelGrid) -> PixelGrid {
        var out = grid
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let c = grid[x, y]
                guard !c.isClear else { continue }
                var around: [RGBA: Int] = [:]
                var alone = true
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                    let p = PixelPoint(x: x + dx, y: y + dy)
                    guard grid.contains(p) else { continue }
                    let n = grid[p]
                    if n == c { alone = false; break }
                    if !n.isClear { around[n, default: 0] += 1 }
                }
                guard alone, let best = around.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.hexString > $1.key.hexString }) else { continue }
                out[x, y] = best.key
            }
        }
        return out
    }

    /// Draws `ink` where the picture steps sharply from light to dark (on the darker side).
    static func outlined(_ grid: PixelGrid, ink: RGBA, threshold: Double = 0.28) -> PixelGrid {
        var out = grid
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let c = grid[x, y]
                guard !c.isClear else { continue }
                let l = c.luminance
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let p = PixelPoint(x: x + dx, y: y + dy)
                    guard grid.contains(p) else { continue }
                    if grid[p].luminance - l > threshold { out[x, y] = ink; break }
                }
            }
        }
        return out
    }
}

extension SpriteProject {
    /// A blank canvas in a retro mode: its palette is the mode's colours.
    static func retro(name: String, mode: RetroMode) -> SpriteProject {
        var p = SpriteProject(name: name)
        p.retroMode = mode
        p.palette = mode.colors
        return p
    }
}
