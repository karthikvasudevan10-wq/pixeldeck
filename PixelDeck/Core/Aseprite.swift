import Foundation

/// What was read from an .aseprite (or .ase) file.
struct AsepriteFile: Sendable {
    struct Tag: Equatable, Sendable {
        var name: String
        var from: Int
        var to: Int
        var frameCount: Int { to - from + 1 }
    }

    var width: Int
    var height: Int
    /// The drawable layers, bottom first (groups and reference layers are left out).
    var layerNames: [String]
    var layerVisible: [Bool]
    /// One cel per layer, for every frame; all `width × height`.
    var frames: [[PixelGrid]]
    /// Milliseconds each frame is shown.
    var durations: [Int]
    var tags: [Tag]
}

enum AsepriteError: Error, Equatable {
    case notAseprite
    case tooBig
    case damaged
}

/// Reading and writing Aseprite files, so work can move to and from the desktop.
/// Layers, frames, per-frame timing and tags come across; blend modes and partial opacity don't
/// (Pixel Deck pixels are solid or clear), and tilemaps and groups are skipped.
enum Aseprite {
    static let fileExtensions = ["aseprite", "ase"]
    /// Bigger files are refused: they wouldn't fit Pixel Deck's canvas.
    static let maxSide = FeatureAccess.proMaxArtSide
    static let maxFrames = FeatureAccess.absoluteFrameLimit

    // MARK: Reading

    private struct Reader {
        let d: [UInt8]
        var p = 0
        init(_ d: [UInt8]) { self.d = d }

        var left: Int { d.count - p }
        mutating func u8() throws -> Int {
            guard p < d.count else { throw AsepriteError.damaged }
            defer { p += 1 }
            return Int(d[p])
        }
        mutating func u16() throws -> Int { let a = try u8(), b = try u8(); return a | (b << 8) }
        mutating func i16() throws -> Int { let v = try u16(); return v >= 0x8000 ? v - 0x10000 : v }
        mutating func u32() throws -> Int { let a = try u16(), b = try u16(); return a | (b << 16) }
        mutating func skip(_ n: Int) throws {
            guard n >= 0, p + n <= d.count else { throw AsepriteError.damaged }
            p += n
        }
        mutating func bytes(_ n: Int) throws -> [UInt8] {
            guard n >= 0, p + n <= d.count else { throw AsepriteError.damaged }
            defer { p += n }
            return Array(d[p..<(p + n)])
        }
        mutating func string() throws -> String {
            let n = try u16()
            return String(decoding: try bytes(n), as: UTF8.self)
        }
    }

    private struct RawLayer {
        var name: String
        var visible: Bool
        /// Index among the layers we keep, or nil for groups, tilemaps and reference layers.
        var kept: Int?
    }

    static func parse(_ data: Data) throws -> AsepriteFile {
        var r = Reader([UInt8](data))
        guard r.left >= 128 else { throw AsepriteError.notAseprite }
        _ = try r.u32()
        guard try r.u16() == 0xA5E0 else { throw AsepriteError.notAseprite }
        let frameCount = try r.u16(), width = try r.u16(), height = try r.u16(), depth = try r.u16()
        guard width > 0, height > 0, frameCount > 0, [8, 16, 32].contains(depth) else { throw AsepriteError.damaged }
        guard width <= maxSide, height <= maxSide, frameCount <= maxFrames else { throw AsepriteError.tooBig }
        _ = try r.u32()                                    // flags
        let speed = try r.u16()
        try r.skip(8)
        let transparentIndex = try r.u8()
        r.p = 128

        var layers: [RawLayer] = []
        var palette = [RGBA](repeating: .black, count: 256)
        var frames: [[PixelGrid]] = []
        var durations: [Int] = []
        var tags: [AsepriteFile.Tag] = []
        // Cels are kept by [frame][raw layer index], so linked cels can find their source.
        var cels: [[Int: PixelGrid]] = []
        let blank = PixelGrid(width: width, height: height)

        for frame in 0..<frameCount {
            let start = r.p
            let size = try r.u32()
            guard try r.u16() == 0xF1FA else { throw AsepriteError.damaged }
            let oldChunks = try r.u16()
            let duration = try r.u16()
            try r.skip(2)
            let newChunks = try r.u32()
            let chunkCount = newChunks != 0 ? newChunks : oldChunks
            durations.append(duration > 0 ? duration : max(1, speed))
            var frameCels: [Int: PixelGrid] = [:]

            for _ in 0..<chunkCount {
                let chunkStart = r.p
                let chunkSize = try r.u32()
                let type = try r.u16()
                guard chunkSize >= 6, chunkStart + chunkSize <= r.d.count else { throw AsepriteError.damaged }
                let end = chunkStart + chunkSize
                switch type {
                case 0x2004:                                // layer
                    let flags = try r.u16(), kind = try r.u16()
                    try r.skip(2 + 2 + 2 + 2 + 1 + 3)
                    let name = try r.string()
                    let reference = flags & 64 != 0
                    let keep = kind == 0 && !reference
                    layers.append(RawLayer(name: name, visible: flags & 1 != 0, kept: keep ? layers.filter { $0.kept != nil }.count : nil))
                case 0x2005:                                // cel
                    let layerIndex = try r.u16(), x = try r.i16(), y = try r.i16()
                    let opacity = try r.u8()
                    let celType = try r.u16()
                    try r.skip(2 + 5)
                    var pixels: [UInt8]?
                    var w = 0, h = 0
                    switch celType {
                    case 0:
                        w = try r.u16(); h = try r.u16()
                        pixels = try r.bytes(w * h * depth / 8)
                    case 1:
                        let source = try r.u16()
                        if source < cels.count, let linked = cels[source][layerIndex] { frameCels[layerIndex] = linked }
                    case 2:
                        w = try r.u16(); h = try r.u16()
                        guard w <= 4096, h <= 4096 else { throw AsepriteError.tooBig }
                        guard let raw = Zlib.inflate(try r.bytes(end - r.p), limit: w * h * depth / 8 + 16),
                              raw.count >= w * h * depth / 8 else { throw AsepriteError.damaged }
                        pixels = raw
                    default:
                        break                               // tilemaps aren't supported
                    }
                    if let pixels, opacity > 0 {
                        var g = frameCels[layerIndex] ?? blank
                        for py in 0..<h {
                            for px in 0..<w {
                                let c: RGBA
                                switch depth {
                                case 32:
                                    let i = (py * w + px) * 4
                                    c = pixels[i + 3] >= 128 ? RGBA(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2]) : .clear
                                case 16:
                                    let i = (py * w + px) * 2
                                    c = pixels[i + 1] >= 128 ? RGBA(r: pixels[i], g: pixels[i], b: pixels[i]) : .clear
                                default:
                                    let index = Int(pixels[py * w + px])
                                    c = index == transparentIndex ? .clear : palette[index]
                                }
                                if !c.isClear { g[x + px, y + py] = c }
                            }
                        }
                        frameCels[layerIndex] = g
                    }
                case 0x2019:                                // palette
                    _ = try r.u32()
                    let first = try r.u32(), last = try r.u32()
                    try r.skip(8)
                    if first <= last {
                        for i in first...last {
                            let flags = try r.u16()
                            let red = try r.u8(), green = try r.u8(), blue = try r.u8(), alpha = try r.u8()
                            if flags & 1 != 0 { _ = try r.string() }
                            if i < 256 { palette[i] = alpha >= 128 ? RGBA(r: UInt8(red), g: UInt8(green), b: UInt8(blue)) : .clear }
                        }
                    }
                case 0x0004:                                // old palette (0–255 per channel)
                    let packets = try r.u16()
                    var index = 0
                    for _ in 0..<packets {
                        index += try r.u8()
                        var n = try r.u8()
                        if n == 0 { n = 256 }
                        for _ in 0..<n {
                            let red = try r.u8(), green = try r.u8(), blue = try r.u8()
                            if index < 256 { palette[index] = RGBA(r: UInt8(red), g: UInt8(green), b: UInt8(blue)) }
                            index += 1
                        }
                    }
                case 0x2018:                                // tags
                    let n = try r.u16()
                    try r.skip(8)
                    for _ in 0..<n {
                        let from = try r.u16(), to = try r.u16()
                        try r.skip(1 + 2 + 6 + 3 + 1)
                        let name = try r.string()
                        if from <= to, to < frameCount { tags.append(AsepriteFile.Tag(name: name, from: from, to: to)) }
                    }
                default:
                    break
                }
                r.p = end
            }
            cels.append(frameCels)
            // Some writers pad frames; trust the frame's own size when it's sensible.
            if size >= 16, start + size <= r.d.count { r.p = max(r.p, start + size) }
            _ = frame
        }

        let kept = layers.enumerated().filter { $0.element.kept != nil }
        guard !kept.isEmpty else { throw AsepriteError.damaged }
        for frameCels in cels {
            frames.append(kept.map { frameCels[$0.offset] ?? blank })
        }
        return AsepriteFile(width: width, height: height, layerNames: kept.map(\.element.name),
                            layerVisible: kept.map(\.element.visible), frames: frames, durations: durations, tags: tags)
    }

    // MARK: Into sprites

    /// The sprites a file becomes. With `splitTags`, each tag is its own sprite ("idle", "run");
    /// otherwise (or with no tags) the whole file is one. Up to eight layers are kept; with more,
    /// the visible ones are flattened into one.
    static func projects(from file: AsepriteFile, name: String, splitTags: Bool = true, keepLayers: Bool = true) -> [SpriteProject] {
        let ranges: [(String, ClosedRange<Int>)] = splitTags && !file.tags.isEmpty
            ? file.tags.map { ("\(name) \($0.name)", $0.from...$0.to) }
            : [(name, 0...(file.frames.count - 1))]
        let bounds = PixelRect(x: -file.width / 2, y: -file.height / 2, width: file.width, height: file.height)
        let layered = keepLayers && file.layerNames.count <= SpriteProject.maxLayers
        return ranges.map { title, range in
            let indices = Array(range)
            var p = SpriteProject(name: title, bounds: bounds, frames: [], fps: 8)
            if layered {
                p.layers = zip(file.layerNames, file.layerVisible).map { LayerInfo(name: $0.isEmpty ? "Layer" : $0, isVisible: $1) }
            }
            // The quickest frame sets the frame rate; slower ones are held for whole beats.
            let shortest = max(1, indices.map { file.durations[$0] }.min() ?? 100)
            p.fps = min(max(Int((1000.0 / Double(shortest)).rounded()), 1), 30)
            let beat = 1000.0 / Double(p.fps)
            p.frames = indices.map { i in
                var f = layered
                    ? Frame(layers: file.frames[i], visible: file.layerVisible)
                    : Frame(grid: Frame(layers: file.frames[i], visible: file.layerVisible).grid)
                f.hold = min(max(Int((Double(file.durations[i]) / beat).rounded()), 1), Frame.maxHold)
                return f
            }
            return p
        }
    }

    // MARK: Writing

    private struct Writer {
        var d: [UInt8] = []
        mutating func u8(_ v: Int) { d.append(UInt8(truncatingIfNeeded: v)) }
        mutating func u16(_ v: Int) { u8(v); u8(v >> 8) }
        mutating func u32(_ v: Int) { u16(v); u16(v >> 16) }
        mutating func zeros(_ n: Int) { d += [UInt8](repeating: 0, count: n) }
        mutating func string(_ s: String) {
            let b = Array(s.utf8.prefix(255))
            u16(b.count)
            d += b
        }
        /// A chunk: its size, type and body.
        mutating func chunk(_ type: Int, _ body: [UInt8]) {
            u32(body.count + 6)
            u16(type)
            d += body
        }
    }

    /// The sprite as an .aseprite file: RGBA, every layer and frame, with per-frame durations.
    static func encode(_ project: SpriteProject) -> Data {
        let area = project.contentBounds ?? project.bounds
        let w = area.width, h = area.height
        let durations = project.frameDurations.map { max(1, Int(($0 * 1000).rounded())) }
        var body = Writer()
        for (i, frame) in project.frames.enumerated() {
            var chunks = Writer()
            var count = 0
            if i == 0 {
                for layer in project.layers {
                    var c = Writer()
                    c.u16(layer.isVisible ? 3 : 2)          // visible, editable
                    c.u16(0); c.u16(0); c.u16(0); c.u16(0); c.u16(0)
                    c.u8(255)
                    c.zeros(3)
                    c.string(layer.name)
                    chunks.chunk(0x2004, c.d)
                    count += 1
                }
            }
            for (l, cel) in frame.layers.enumerated() {
                let world = cel.reframed(from: project.bounds, to: area)
                guard let box = world.opaqueBounds else { continue }
                var c = Writer()
                c.u16(l)
                c.u16(box.x); c.u16(box.y)
                c.u8(255)
                c.u16(2)                                    // compressed image
                c.u16(0)
                c.zeros(5)
                c.u16(box.width); c.u16(box.height)
                var raw: [UInt8] = []
                raw.reserveCapacity(box.width * box.height * 4)
                for y in box.y..<box.maxY {
                    for x in box.x..<box.maxX {
                        let px = world[x, y]
                        raw += [px.r, px.g, px.b, px.a]
                    }
                }
                c.d += Zlib.store(raw)
                chunks.chunk(0x2005, c.d)
                count += 1
            }
            body.u32(chunks.d.count + 16)
            body.u16(0xF1FA)
            body.u16(min(count, 0xFFFF))
            body.u16(i < durations.count ? min(durations[i], 0xFFFF) : 100)
            body.zeros(2)
            body.u32(count)
            body.d += chunks.d
        }
        var out = Writer()
        out.u32(128 + body.d.count)
        out.u16(0xA5E0)
        out.u16(project.frames.count)
        out.u16(w); out.u16(h)
        out.u16(32)
        out.u32(1)                                          // layer opacity is valid
        out.u16(durations.first ?? 100)
        out.u32(0); out.u32(0)
        out.u8(0)
        out.zeros(3)
        out.u16(0)
        out.u8(1); out.u8(1)                                // square pixels
        out.u16(0); out.u16(0); out.u16(16); out.u16(16)    // grid
        out.zeros(84)
        out.d += body.d
        return Data(out.d)
    }
}
