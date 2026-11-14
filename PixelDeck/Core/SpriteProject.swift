import Foundation

/// One keyframe of an animation.
struct Frame: Identifiable, Codable, Sendable {
    var id = UUID()
    var grid: PixelGrid {
        didSet { version = Frame.nextVersion() }
    }
    /// Changes on every pixel change, and is never reused (so restoring an undo snapshot can't
    /// match a stale cached thumbnail). Not persisted.
    private(set) var version = Frame.nextVersion()

    private static var versionCounter = 0
    private static let versionLock = NSLock()
    private static func nextVersion() -> Int {
        versionLock.lock()
        defer { versionLock.unlock() }
        versionCounter += 1
        return versionCounter
    }

    init(id: UUID = UUID(), grid: PixelGrid) {
        self.id = id
        self.grid = grid
    }

    private enum CodingKeys: String, CodingKey { case id, grid }
}

/// A sprite on an unbounded canvas: an ordered list of frames that all cover the same world
/// rectangle (`bounds`), which grows as you draw and shrinks back around the art.
struct SpriteProject: Identifiable, Codable, Sendable {
    /// The design's 10 starter colours. Each sprite keeps its own editable copy.
    static let defaultPalette: [RGBA] = ([
        0x1B1530, 0xFFF6E0, 0x7BE07B, 0x2E9E5B, 0xFFD23F,
        0xFF8B3D, 0xFF5C8A, 0xC8B6FF, 0x3A86FF, 0x9C6B3C,
    ] as [UInt32]).map { RGBA(hex: $0) }

    /// Where a new canvas starts: centred on world (0, 0). Invisible to the user, who sees an
    /// endless checkerboard.
    static let initialBounds = PixelRect(x: -8, y: -8, width: 16, height: 16)

    var id = UUID()
    var name: String
    /// World rectangle covered by every frame's grid.
    var bounds: PixelRect
    var frames: [Frame]
    var fps: Int = 8
    var palette: [RGBA] = SpriteProject.defaultPalette
    var createdAt = Date()
    var modifiedAt = Date()

    init(name: String) {
        self.name = name
        self.bounds = SpriteProject.initialBounds
        self.frames = [Frame(grid: PixelGrid(width: bounds.width, height: bounds.height))]
    }

    /// A sprite from existing frames, which must all be `bounds`-sized.
    init(name: String, bounds: PixelRect, frames: [PixelGrid], fps: Int) {
        self.name = name
        self.bounds = bounds
        self.frames = frames.isEmpty ? [Frame(grid: PixelGrid(width: bounds.width, height: bounds.height))] : frames.map { Frame(grid: $0) }
        self.fps = min(max(fps, 1), 30)
    }

    /// World rectangle holding every opaque pixel in every frame, or nil for a blank sprite.
    var contentBounds: PixelRect? {
        var result: PixelRect?
        for f in frames {
            guard let r = f.grid.opaqueBounds else { continue }
            let w = r.offsetBy(bounds.origin)
            result = result.map { $0.union(w) } ?? w
        }
        return result
    }

    /// Every frame cut to `world` (for export and previews). Areas outside the bounds are clear.
    func grids(croppedTo world: PixelRect) -> [PixelGrid] {
        frames.map { $0.grid.reframed(from: bounds, to: world) }
    }

    private enum CodingKeys: String, CodingKey { case id, name, size, bounds, frames, fps, palette, createdAt, modifiedAt }

    /// Tolerant decoding: a damaged or hand-edited file loads as something editable instead of
    /// crashing the app (the editor assumes at least one frame, all the same size). Files from
    /// before the infinite canvas (a square "size") load with their art at the same place.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        if let b = try? c.decode(PixelRect.self, forKey: .bounds) {
            bounds = b
        } else {
            let size = try c.decode(Int.self, forKey: .size)
            bounds = PixelRect(x: -size / 2, y: -size / 2, width: size, height: size)
        }
        guard bounds.width > 0, bounds.height > 0,
              bounds.width <= PixelGrid.maxSide, bounds.height <= PixelGrid.maxSide else {
            throw DecodingError.dataCorruptedError(forKey: .bounds, in: c, debugDescription: "Unsupported canvas size")
        }
        let name = (try? c.decode(String.self, forKey: .name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = name.isEmpty ? "Sprite" : name
        // Frame by frame, so one damaged frame doesn't take the others with it.
        let decoded = ((try? c.decode([LossyFrame].self, forKey: .frames)) ?? []).compactMap(\.frame)
        let w = bounds.width, h = bounds.height
        let valid = decoded.filter { $0.grid.width == w && $0.grid.height == h }
        frames = valid.isEmpty ? [Frame(grid: PixelGrid(width: w, height: h))] : valid
        fps = min(max((try? c.decode(Int.self, forKey: .fps)) ?? 8, 1), 30)
        let pal = ((try? c.decode([RGBA].self, forKey: .palette)) ?? []).map { RGBA(r: $0.r, g: $0.g, b: $0.b, a: 255) }
        palette = pal.count == SpriteProject.defaultPalette.count ? pal : SpriteProject.defaultPalette
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(bounds, forKey: .bounds)
        try c.encode(frames, forKey: .frames)
        try c.encode(fps, forKey: .fps)
        try c.encode(palette, forKey: .palette)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }

    /// A copy with fresh identifiers, so caches never confuse it with the original.
    func duplicated(name: String) -> SpriteProject {
        var copy = self
        copy.id = UUID()
        copy.name = name
        copy.frames = frames.map { Frame(grid: $0.grid) }
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        return copy
    }
}

private struct LossyFrame: Decodable {
    let frame: Frame?
    init(from decoder: Decoder) throws { frame = try? Frame(from: decoder) }
}
