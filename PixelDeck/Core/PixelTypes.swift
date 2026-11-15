import Foundation

/// A single 8-bit-per-channel colour. `a == 0` means transparent.
struct RGBA: Hashable, Codable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Opaque colour from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }

    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
    static let black = RGBA(r: 0, g: 0, b: 0)
    static let white = RGBA(r: 255, g: 255, b: 255)

    var isClear: Bool { a == 0 }

    var hexString: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Integer pixel coordinate. In the editor these are world coordinates on an unbounded canvas:
/// (0, 0) is just right of and below the centre of a new canvas, and negatives are fine.
struct PixelPoint: Hashable, Codable, Sendable {
    var x: Int
    var y: Int

    static let zero = PixelPoint(x: 0, y: 0)

    static func + (l: PixelPoint, r: PixelPoint) -> PixelPoint { PixelPoint(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: PixelPoint, r: PixelPoint) -> PixelPoint { PixelPoint(x: l.x - r.x, y: l.y - r.y) }

    /// Mirror image across the vertical line between world x = -1 and x = 0 (the centre of a
    /// new canvas), used by the mirror tool.
    var mirrored: PixelPoint { PixelPoint(x: -1 - x, y: y) }
}

/// Continuous 2D vector, measured in canvas pixels.
struct Vec2: Hashable, Codable, Sendable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: Vec2, r: Vec2) -> Vec2 { Vec2(x: l.x - r.x, y: l.y - r.y) }
    static func * (l: Vec2, s: Double) -> Vec2 { Vec2(x: l.x * s, y: l.y * s) }
    static func * (s: Double, l: Vec2) -> Vec2 { l * s }

    var length: Double { (x * x + y * y).squareRoot() }

    /// The pixel this point falls inside.
    var pixel: PixelPoint { PixelPoint(x: Int(x.rounded(.down)), y: Int(y.rounded(.down))) }

    /// Nearest whole-pixel offset.
    var rounded: PixelPoint { PixelPoint(x: Int(x.rounded()), y: Int(y.rounded())) }
}

/// Axis-aligned rectangle of whole pixels. `width`/`height` are pixel counts.
struct PixelRect: Hashable, Codable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Rectangle spanning two corner pixels, inclusive.
    init(corner a: PixelPoint, _ b: PixelPoint) {
        x = min(a.x, b.x)
        y = min(a.y, b.y)
        width = abs(a.x - b.x) + 1
        height = abs(a.y - b.y) + 1
    }

    var origin: PixelPoint { PixelPoint(x: x, y: y) }
    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }
    var center: Vec2 { Vec2(x: Double(x) + Double(width) / 2, y: Double(y) + Double(height) / 2) }

    func contains(_ p: PixelPoint) -> Bool {
        p.x >= x && p.x < maxX && p.y >= y && p.y < maxY
    }

    func offsetBy(_ d: PixelPoint) -> PixelRect {
        PixelRect(x: x + d.x, y: y + d.y, width: width, height: height)
    }

    func contains(_ r: PixelRect) -> Bool {
        r.isEmpty || (r.x >= x && r.y >= y && r.maxX <= maxX && r.maxY <= maxY)
    }

    /// Smallest rectangle containing both. An empty rectangle contributes nothing.
    func union(_ r: PixelRect) -> PixelRect {
        if r.isEmpty { return self }
        if isEmpty { return r }
        let nx = min(x, r.x), ny = min(y, r.y)
        return PixelRect(x: nx, y: ny, width: max(maxX, r.maxX) - nx, height: max(maxY, r.maxY) - ny)
    }

    func union(_ p: PixelPoint) -> PixelRect {
        union(PixelRect(x: p.x, y: p.y, width: 1, height: 1))
    }

    /// Overlap of the two rectangles (empty, with zero size, if they don't meet).
    func intersection(_ r: PixelRect) -> PixelRect {
        let nx = max(x, r.x), ny = max(y, r.y)
        let mx = min(maxX, r.maxX), my = min(maxY, r.maxY)
        return PixelRect(x: nx, y: ny, width: max(0, mx - nx), height: max(0, my - ny))
    }

    /// Grown (positive) or shrunk (negative) by `d` on every side.
    func insetBy(_ d: Int) -> PixelRect {
        PixelRect(x: x + d, y: y + d, width: max(0, width - 2 * d), height: max(0, height - 2 * d))
    }
}

/// A rectangular block of pixels lifted out of a canvas.
struct PixelPatch: Hashable, Sendable {
    let width: Int
    let height: Int
    var pixels: [RGBA]

    subscript(x: Int, y: Int) -> RGBA {
        pixels[y * width + x]
    }
}
