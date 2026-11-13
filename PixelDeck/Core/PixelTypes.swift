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

/// Integer pixel coordinate. Origin is the top-left of the canvas.
struct PixelPoint: Hashable, Codable, Sendable {
    var x: Int
    var y: Int

    static let zero = PixelPoint(x: 0, y: 0)

    static func + (l: PixelPoint, r: PixelPoint) -> PixelPoint { PixelPoint(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: PixelPoint, r: PixelPoint) -> PixelPoint { PixelPoint(x: l.x - r.x, y: l.y - r.y) }

    func clamped(toCanvas size: Int) -> PixelPoint {
        PixelPoint(x: min(max(x, 0), size - 1), y: min(max(y, 0), size - 1))
    }
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

    /// The part of this rectangle that lies on a canvas of the given size.
    func clipped(toCanvas size: Int) -> PixelRect {
        let nx = max(x, 0), ny = max(y, 0)
        let mx = min(maxX, size), my = min(maxY, size)
        return PixelRect(x: nx, y: ny, width: max(0, mx - nx), height: max(0, my - ny))
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

    var isEmpty: Bool { pixels.allSatisfy(\.isClear) }
}
