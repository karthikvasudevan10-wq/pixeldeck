import Foundation

/// A square canvas of pixels, stored row-major from the top-left.
struct PixelGrid: Hashable, Sendable {
    let size: Int
    private(set) var pixels: [RGBA]

    init(size: Int, fill: RGBA = .clear) {
        precondition(size > 0, "Canvas size must be positive")
        self.size = size
        self.pixels = Array(repeating: fill, count: size * size)
    }

    func contains(_ p: PixelPoint) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < size && p.y < size
    }

    /// Out-of-bounds reads return `.clear`; out-of-bounds writes are ignored.
    subscript(x: Int, y: Int) -> RGBA {
        get { contains(PixelPoint(x: x, y: y)) ? pixels[y * size + x] : .clear }
        set {
            guard contains(PixelPoint(x: x, y: y)) else { return }
            pixels[y * size + x] = newValue
        }
    }

    subscript(p: PixelPoint) -> RGBA {
        get { self[p.x, p.y] }
        set { self[p.x, p.y] = newValue }
    }

    var isBlank: Bool { pixels.allSatisfy(\.isClear) }

    // MARK: Drawing

    /// Bresenham line, inclusive of both end points.
    mutating func drawLine(from a: PixelPoint, to b: PixelPoint, color: RGBA) {
        var x0 = a.x, y0 = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            self[x0, y0] = color
            if x0 == b.x && y0 == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }

    /// 4-connected flood fill of the region that matches the colour at `start`.
    mutating func floodFill(from start: PixelPoint, with color: RGBA) {
        guard contains(start) else { return }
        let target = self[start]
        guard target != color else { return }
        var stack = [start]
        while let p = stack.popLast() {
            guard contains(p), self[p] == target else { continue }
            // Scan left and right along the row, then queue the rows above and below.
            var left = p.x
            while left > 0 && self[left - 1, p.y] == target { left -= 1 }
            var right = p.x
            while right < size - 1 && self[right + 1, p.y] == target { right += 1 }
            for x in left...right {
                self[x, p.y] = color
                if p.y > 0 && self[x, p.y - 1] == target { stack.append(PixelPoint(x: x, y: p.y - 1)) }
                if p.y < size - 1 && self[x, p.y + 1] == target { stack.append(PixelPoint(x: x, y: p.y + 1)) }
            }
        }
    }

    // MARK: Patches

    func patch(in rect: PixelRect) -> PixelPatch {
        var out: [RGBA] = []
        out.reserveCapacity(max(0, rect.width * rect.height))
        for y in rect.y..<rect.maxY {
            for x in rect.x..<rect.maxX { out.append(self[x, y]) }
        }
        return PixelPatch(width: rect.width, height: rect.height, pixels: out)
    }

    mutating func clear(_ rect: PixelRect) {
        let r = rect.clipped(toCanvas: size)
        guard !r.isEmpty else { return }
        for y in r.y..<r.maxY {
            for x in r.x..<r.maxX { pixels[y * size + x] = .clear }
        }
    }

    /// Paints the patch's opaque pixels with its top-left at `origin`. Parts off the canvas are dropped.
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

    // MARK: Raw bytes

    /// RGBA8 bytes, each canvas pixel enlarged to `scale`×`scale` (nearest neighbour).
    func rgbaBytes(scale: Int = 1) -> [UInt8] {
        let s = max(1, scale)
        let side = size * s
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBufferPointer { out in
            for y in 0..<size {
                for x in 0..<size {
                    let c = pixels[y * size + x]
                    if c.isClear { continue }
                    for dy in 0..<s {
                        var i = ((y * s + dy) * side + x * s) * 4
                        for _ in 0..<s {
                            out[i] = c.r; out[i + 1] = c.g; out[i + 2] = c.b; out[i + 3] = c.a
                            i += 4
                        }
                    }
                }
            }
        }
        return bytes
    }

    init?(size: Int, rgbaBytes bytes: [UInt8]) {
        guard size > 0, bytes.count == size * size * 4 else { return nil }
        self.size = size
        var px: [RGBA] = []
        px.reserveCapacity(size * size)
        var i = 0
        while i < bytes.count {
            px.append(RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3]))
            i += 4
        }
        self.pixels = px
    }
}

// Stored run-length encoded: pixel art is mostly long runs of one colour (especially
// transparency), so a 256×256 frame is typically a few hundred bytes instead of 256 KB.
// Each run is a little-endian UInt16 count (1…65535) followed by R, G, B, A.
// Files written before RLE (key "rgba", raw bytes) still load.
extension PixelGrid: Codable {
    private enum CodingKeys: String, CodingKey { case size, rle, rgba }

    static let maxSize = 1024

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let size = try c.decode(Int.self, forKey: .size)
        guard size > 0, size <= PixelGrid.maxSize else {
            throw DecodingError.dataCorruptedError(forKey: .size, in: c, debugDescription: "Unsupported canvas size \(size)")
        }
        let grid: PixelGrid?
        if let rle = try c.decodeIfPresent(Data.self, forKey: .rle) {
            grid = PixelGrid(size: size, runLengthEncoded: rle)
        } else {
            grid = PixelGrid(size: size, rgbaBytes: [UInt8](try c.decode(Data.self, forKey: .rgba)))
        }
        guard let grid else {
            throw DecodingError.dataCorruptedError(forKey: .rle, in: c, debugDescription: "Pixel data does not match canvas size")
        }
        self = grid
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(size, forKey: .size)
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
    init?(size: Int, runLengthEncoded data: Data) {
        guard size > 0, size <= PixelGrid.maxSize, data.count % 6 == 0 else { return nil }
        let total = size * size
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
        self.size = size
        self.pixels = px
    }
}
