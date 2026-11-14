import Foundation

/// A rectangle of pixels, stored row-major from the top-left. Coordinates here are local
/// (0…width-1, 0…height-1); the editor maps world coordinates onto them using the sprite's bounds.
struct PixelGrid: Hashable, Sendable {
    let width: Int
    let height: Int
    private(set) var pixels: [RGBA]

    /// Largest side accepted when loading (the Pro art cap is 512, plus working margin).
    static let maxSide = 2048

    init(width: Int, height: Int, fill: RGBA = .clear) {
        precondition(width > 0 && height > 0, "Canvas size must be positive")
        self.width = width
        self.height = height
        self.pixels = Array(repeating: fill, count: width * height)
    }

    init(size: Int, fill: RGBA = .clear) {
        self.init(width: size, height: size, fill: fill)
    }

    var rect: PixelRect { PixelRect(x: 0, y: 0, width: width, height: height) }

    func contains(_ p: PixelPoint) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
    }

    /// Out-of-bounds reads return `.clear`; out-of-bounds writes are ignored.
    subscript(x: Int, y: Int) -> RGBA {
        get { contains(PixelPoint(x: x, y: y)) ? pixels[y * width + x] : .clear }
        set {
            guard contains(PixelPoint(x: x, y: y)) else { return }
            pixels[y * width + x] = newValue
        }
    }

    subscript(p: PixelPoint) -> RGBA {
        get { self[p.x, p.y] }
        set { self[p.x, p.y] = newValue }
    }

    var isBlank: Bool { pixels.allSatisfy(\.isClear) }

    /// Direct access for hot loops (flattening layers). Index is y × width + x.
    mutating func withUnsafeMutablePixels(_ body: (inout UnsafeMutableBufferPointer<RGBA>) -> Void) {
        pixels.withUnsafeMutableBufferPointer { body(&$0) }
    }

    /// Smallest rectangle (local) holding every opaque pixel, or nil if there are none.
    var opaqueBounds: PixelRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        let w = width
        pixels.withUnsafeBufferPointer { px in
            for y in 0..<height {
                let row = y * w
                for x in 0..<w where px[row + x].a != 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: Drawing

    /// Bresenham line, inclusive of both end points.
    mutating func drawLine(from a: PixelPoint, to b: PixelPoint, color: RGBA) {
        for p in PixelGrid.linePoints(from: a, to: b) { self[p] = color }
    }

    /// The pixels of a Bresenham line, inclusive of both end points.
    static func linePoints(from a: PixelPoint, to b: PixelPoint) -> [PixelPoint] {
        var out: [PixelPoint] = []
        var x0 = a.x, y0 = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            out.append(PixelPoint(x: x0, y: y0))
            if x0 == b.x && y0 == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
        return out
    }

    /// 4-connected flood fill of the region that matches the colour at `start`, limited to
    /// `limit` (local; the whole grid by default).
    mutating func floodFill(from start: PixelPoint, with color: RGBA, within limit: PixelRect? = nil) {
        let area = (limit ?? rect).intersection(rect)
        guard area.contains(start) else { return }
        let target = self[start]
        guard target != color else { return }
        var stack = [start]
        while let p = stack.popLast() {
            guard area.contains(p), self[p] == target else { continue }
            // Scan left and right along the row, then queue the rows above and below.
            var left = p.x
            while left > area.x && self[left - 1, p.y] == target { left -= 1 }
            var right = p.x
            while right < area.maxX - 1 && self[right + 1, p.y] == target { right += 1 }
            for x in left...right {
                self[x, p.y] = color
                if p.y > area.y && self[x, p.y - 1] == target { stack.append(PixelPoint(x: x, y: p.y - 1)) }
                if p.y < area.maxY - 1 && self[x, p.y + 1] == target { stack.append(PixelPoint(x: x, y: p.y + 1)) }
            }
        }
    }

    // MARK: Patches

    /// Pixels inside `rect` (local). Parts outside the grid read as clear.
    func patch(in rect: PixelRect) -> PixelPatch {
        var out: [RGBA] = []
        out.reserveCapacity(max(0, rect.width * rect.height))
        for y in rect.y..<rect.maxY {
            for x in rect.x..<rect.maxX { out.append(self[x, y]) }
        }
        return PixelPatch(width: rect.width, height: rect.height, pixels: out)
    }

    mutating func clear(_ r: PixelRect) {
        let c = r.intersection(rect)
        guard !c.isEmpty else { return }
        for y in c.y..<c.maxY {
            for x in c.x..<c.maxX { pixels[y * width + x] = .clear }
        }
    }

    /// Paints the patch's opaque pixels with its top-left at `origin`. Parts off the grid are dropped.
    mutating func stamp(_ patch: PixelPatch, at origin: PixelPoint) {
        for py in 0..<patch.height {
            for px in 0..<patch.width {
                let c = patch[px, py]
                if !c.isClear { self[origin.x + px, origin.y + py] = c }
            }
        }
    }

    /// Clears every pixel that the patch's opaque pixels would cover at `origin`.
    mutating func erase(_ patch: PixelPatch, at origin: PixelPoint) {
        for py in 0..<patch.height {
            for px in 0..<patch.width where !patch[px, py].isClear {
                self[origin.x + px, origin.y + py] = .clear
            }
        }
    }

    /// The same pixels on a grid covering `newRect`, given that this grid covers `oldRect`
    /// (both in world coordinates). Pixels outside `newRect` are dropped.
    func reframed(from oldRect: PixelRect, to newRect: PixelRect) -> PixelGrid {
        var out = PixelGrid(width: newRect.width, height: newRect.height)
        let overlap = oldRect.intersection(newRect)
        guard !overlap.isEmpty else { return out }
        for wy in overlap.y..<overlap.maxY {
            let src = (wy - oldRect.y) * width + (overlap.x - oldRect.x)
            let dst = (wy - newRect.y) * newRect.width + (overlap.x - newRect.x)
            out.pixels.replaceSubrange(dst..<(dst + overlap.width), with: pixels[src..<(src + overlap.width)])
        }
        return out
    }

    // MARK: Raw bytes

    /// RGBA8 bytes, each pixel enlarged to `scale`×`scale` (nearest neighbour).
    func rgbaBytes(scale: Int = 1) -> [UInt8] {
        let s = max(1, scale)
        let outW = width * s
        var bytes = [UInt8](repeating: 0, count: outW * height * s * 4)
        let w = width
        // Unsafe buffers: this runs for every canvas update, so skip per-pixel bounds checks.
        pixels.withUnsafeBufferPointer { px in
        bytes.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                for x in 0..<w {
                    let c = px[y * w + x]
                    if c.a == 0 { continue }
                    for dy in 0..<s {
                        var i = ((y * s + dy) * outW + x * s) * 4
                        for _ in 0..<s {
                            out[i] = c.r; out[i + 1] = c.g; out[i + 2] = c.b; out[i + 3] = c.a
                            i += 4
                        }
                    }
                }
            }
        }
        }
        return bytes
    }

    init?(width: Int, height: Int, rgbaBytes bytes: [UInt8]) {
        guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        var px: [RGBA] = []
        px.reserveCapacity(width * height)
        var i = 0
        while i < bytes.count {
            px.append(RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3]))
            i += 4
        }
        self.pixels = px
    }
}

// Stored run-length encoded: pixel art is mostly long runs of one colour (especially
// transparency), so a frame is typically a few hundred bytes.
// Each run is a little-endian UInt16 count (1…65535) followed by R, G, B, A.
// Older files (square "size", or raw "rgba" bytes) still load.
extension PixelGrid: Codable {
    private enum CodingKeys: String, CodingKey { case width, height, size, rle, rgba }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let w: Int, h: Int
        if let width = try c.decodeIfPresent(Int.self, forKey: .width) {
            w = width
            h = try c.decode(Int.self, forKey: .height)
        } else {
            w = try c.decode(Int.self, forKey: .size)
            h = w
        }
        guard w > 0, h > 0, w <= PixelGrid.maxSide, h <= PixelGrid.maxSide else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: c, debugDescription: "Unsupported canvas size \(w)×\(h)")
        }
        let grid: PixelGrid?
        if let rle = try c.decodeIfPresent(Data.self, forKey: .rle) {
            grid = PixelGrid(width: w, height: h, runLengthEncoded: rle)
        } else {
            grid = PixelGrid(width: w, height: h, rgbaBytes: [UInt8](try c.decode(Data.self, forKey: .rgba)))
        }
        guard let grid else {
            throw DecodingError.dataCorruptedError(forKey: .rle, in: c, debugDescription: "Pixel data does not match canvas size")
        }
        self = grid
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(runLengthEncoded(), forKey: .rle)
    }

    func runLengthEncoded() -> Data {
        var out = Data()
        var i = 0
        while i < pixels.count {
            let c = pixels[i]
            var run = 1
            while i + run < pixels.count, run < Int(UInt16.max), pixels[i + run] == c { run += 1 }
            out.append(UInt8(run & 0xFF))
            out.append(UInt8(run >> 8))
            out.append(contentsOf: [c.r, c.g, c.b, c.a])
            i += run
        }
        return out
    }

    /// Fails (rather than crashing) on truncated or oversized data.
    init?(width: Int, height: Int, runLengthEncoded data: Data) {
        guard width > 0, height > 0, width <= PixelGrid.maxSide, height <= PixelGrid.maxSide,
              data.count % 6 == 0 else { return nil }
        let total = width * height
        var px: [RGBA] = []
        px.reserveCapacity(total)
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let run = Int(bytes[i]) | (Int(bytes[i + 1]) << 8)
            guard run > 0, px.count + run <= total else { return nil }
            px.append(contentsOf: repeatElement(RGBA(r: bytes[i + 2], g: bytes[i + 3], b: bytes[i + 4], a: bytes[i + 5]), count: run))
            i += 6
        }
        guard px.count == total else { return nil }
        self.width = width
        self.height = height
        self.pixels = px
    }

    init?(size: Int, runLengthEncoded data: Data) {
        self.init(width: size, height: size, runLengthEncoded: data)
    }
}
