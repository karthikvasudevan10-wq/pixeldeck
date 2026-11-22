import Foundation

/// A layer in a sprite's layer stack (the pixels live in each frame's cels).
struct LayerInfo: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var isVisible = true
    /// The folder this layer is kept in, if any (see `LayerFolder`).
    var folderID: UUID?
}

/// A folder of layers: a named group that can be shown, hidden, folded away and moved as one.
/// A folder's layers sit together in the stack. Folders don't hold other folders.
struct LayerFolder: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Hiding a folder hides every layer in it (each layer keeps its own setting for when the
    /// folder is shown again).
    var isVisible = true
    /// Folded away in the layers list. Kept with the sprite.
    var isCollapsed = false
}

/// One keyframe of an animation: one cel per layer (bottom to top), plus the visible layers
/// flattened into `grid`, which is what the canvas, thumbnails, onion skin, playback and export
/// show. Only the cels are saved; `grid` is rebuilt on load.
struct Frame: Identifiable, Sendable {
    var id = UUID()
    /// One per sprite layer, bottom first. All the size of the sprite's bounds.
    private(set) var layers: [PixelGrid]
    /// The visible layers flattened (kept in sync by the methods below).
    private(set) var grid: PixelGrid {
        didSet { version = Frame.nextVersion() }
    }
    /// Changes on every pixel change, and is never reused (so restoring an undo snapshot can't
    /// match a stale cached thumbnail). Not persisted.
    private(set) var version = Frame.nextVersion()
    /// How many beats the frame stays on screen (1 is normal). See `Frame.maxHold`.
    var hold = 1

    private static var versionCounter = 0
    private static let versionLock = NSLock()
    private static func nextVersion() -> Int {
        versionLock.lock()
        defer { versionLock.unlock() }
        versionCounter += 1
        return versionCounter
    }

    /// A single-layer frame.
    init(id: UUID = UUID(), grid: PixelGrid) {
        self.id = id
        self.layers = [grid]
        self.grid = grid
    }

    init(id: UUID = UUID(), layers: [PixelGrid], visible: [Bool]) {
        precondition(!layers.isEmpty, "A frame needs at least one layer")
        self.id = id
        self.layers = layers
        self.grid = layers[0]
        reflatten(visible: visible)
    }

    /// A blank frame with `count` layers.
    static func blank(width: Int, height: Int, layers count: Int) -> Frame {
        let g = PixelGrid(width: width, height: height)
        return Frame(layers: Array(repeating: g, count: max(1, count)), visible: Array(repeating: true, count: max(1, count)))
    }

    /// Rebuilds `grid` from the visible layers: the topmost opaque pixel wins (pixels are either
    /// fully opaque or clear). `rect` (local) limits the work to the part that changed.
    mutating func reflatten(visible: [Bool], in rect: PixelRect? = nil) {
        func isVisible(_ i: Int) -> Bool { i < visible.count ? visible[i] : true }
        if layers.count == 1 {
            grid = isVisible(0) ? layers[0] : PixelGrid(width: layers[0].width, height: layers[0].height)
            return
        }
        let full = layers[0].rect
        var g = (rect == nil || grid.width != full.width || grid.height != full.height)
            ? PixelGrid(width: full.width, height: full.height) : grid
        let area = (rect ?? full).intersection(full)
        guard !area.isEmpty else { grid = g; return }
        // Visible layers, top first; each pixel takes the first opaque one.
        let stack = layers.indices.reversed().filter(isVisible).map { layers[$0].pixels }
        let w = full.width
        g.withUnsafeMutablePixels { out in
            for y in area.y..<area.maxY {
                for x in area.x..<area.maxX {
                    let i = y * w + x
                    var c = RGBA.clear
                    for cel in stack where cel[i].a != 0 { c = cel[i]; break }
                    out[i] = c
                }
            }
        }
        grid = g
    }

    /// Edits one cel, then refreshes the flattened image (only `dirty`, if given).
    mutating func editLayer(_ index: Int, visible: [Bool], dirty: PixelRect? = nil, _ body: (inout PixelGrid) -> Void) {
        guard layers.indices.contains(index) else { return }
        body(&layers[index])
        reflatten(visible: visible, in: dirty)
    }

    mutating func setLayers(_ newLayers: [PixelGrid], visible: [Bool]) {
        guard !newLayers.isEmpty else { return }
        layers = newLayers
        reflatten(visible: visible)
    }

    /// Every cel (and the flattened image) moved onto a grid covering `newRect` (world).
    mutating func reframe(from oldRect: PixelRect, to newRect: PixelRect) {
        layers = layers.map { $0.reframed(from: oldRect, to: newRect) }
        grid = grid.reframed(from: oldRect, to: newRect)
    }
}

extension Frame: Codable {
    private enum CodingKeys: String, CodingKey { case id, layers, grid, hold }

    /// Older files have a single `grid`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        if let l = try c.decodeIfPresent([PixelGrid].self, forKey: .layers), let first = l.first {
            let ok = l.allSatisfy { $0.width == first.width && $0.height == first.height }
            layers = ok ? l : [first]
            grid = first
        } else {
            let g = try c.decode(PixelGrid.self, forKey: .grid)
            layers = [g]
            grid = g
        }
        hold = min(max((try? c.decodeIfPresent(Int.self, forKey: .hold)) ?? 1, 1), Frame.maxHold)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(layers, forKey: .layers)
        if hold != 1 { try c.encode(hold, forKey: .hold) }
    }
}

/// The Community post a sprite was remixed from.
struct RemixCredit: Codable, Equatable, Sendable {
    var postID: String
    var title: String
    var author: String
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
    /// How playback is paced across the frames (Pro). Linear: every frame lasts 1/fps.
    var playbackEasing: Easing = .linear
    var palette: [RGBA] = SpriteProject.defaultPalette
    /// Colours added beyond the 10 swatches: ramps, colours from a photo, adjusted colours.
    var extraColors: [RGBA] = []
    static let maxExtraColors = 54
    /// What playback does at the last frame.
    var loopMode: LoopMode = .loop
    /// A retro canvas: the palette is locked to the mode's colours, and dither is free.
    var retroMode: RetroMode?
    /// Set when the sprite was remixed from a Community post, so sharing it credits the original.
    var remix: RemixCredit?
    /// Sounds attached to frames (the audio files are kept beside the sprite).
    var sounds: [SoundClip] = []
    /// Bottom to top. Every frame has one cel per layer.
    var layers: [LayerInfo] = [LayerInfo(name: "Layer 1")]
    /// Frames a second: 1 to this.
    static let maxFPS = 60

    /// Folders that layers are grouped in (see `LayerFolder`).
    var folders: [LayerFolder] = []
    /// Whether each layer shows: its own setting, and its folder's.
    var layerVisibility: [Bool] {
        guard !folders.isEmpty else { return layers.map(\.isVisible) }
        let hidden = Set(folders.filter { !$0.isVisible }.map(\.id))
        return layers.map { $0.isVisible && !($0.folderID.map(hidden.contains) ?? false) }
    }
    /// A picture under every layer to trace over (the picture itself is stored separately).
    var trace: TraceSettings?
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
        self.fps = min(max(fps, 1), SpriteProject.maxFPS)
    }

    /// World rectangle holding every opaque pixel in every frame and layer (hidden ones too, since
    /// the canvas has to keep them), or nil for a blank sprite.
    var contentBounds: PixelRect? {
        var result: PixelRect?
        for f in frames {
            for layer in f.layers {
                guard let r = layer.opaqueBounds else { continue }
                let w = r.offsetBy(bounds.origin)
                result = result.map { $0.union(w) } ?? w
            }
        }
        return result
    }

    /// World rectangle of what's visible (hidden layers left out): what export and the gallery use.
    var visibleContentBounds: PixelRect? {
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

    private enum CodingKeys: String, CodingKey { case id, name, size, bounds, frames, fps, playbackEasing, palette, extraColors, loopMode, retroMode, remix, sounds, layers, folders, trace, createdAt, modifiedAt }

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
        var decodedLayers = (try? c.decode([LayerInfo].self, forKey: .layers)) ?? []
        if decodedLayers.isEmpty { decodedLayers = [LayerInfo(name: "Layer 1")] }
        var decodedFolders = (try? c.decode([LayerFolder].self, forKey: .folders)) ?? []
        SpriteProject.tidyFolders(layers: &decodedLayers, folders: &decodedFolders)
        layers = decodedLayers
        folders = decodedFolders
        // Every frame gets exactly one cel per layer (padding with blanks, dropping extras).
        let hiddenFolders = Set(decodedFolders.filter { !$0.isVisible }.map(\.id))
        let n = layers.count, visible = layers.map { $0.isVisible && !($0.folderID.map(hiddenFolders.contains) ?? false) }
        let blank = PixelGrid(width: w, height: h)
        let normalized = valid.map { f -> Frame in
            var cels = Array(f.layers.prefix(n))
            while cels.count < n { cels.append(blank) }
            var frame = Frame(id: f.id, layers: cels, visible: visible)
            frame.hold = f.hold
            return frame
        }
        frames = normalized.isEmpty ? [Frame.blank(width: w, height: h, layers: n)] : normalized
        fps = min(max((try? c.decode(Int.self, forKey: .fps)) ?? 8, 1), SpriteProject.maxFPS)
        playbackEasing = (try? c.decode(Easing.self, forKey: .playbackEasing)) ?? .linear
        let pal = ((try? c.decode([RGBA].self, forKey: .palette)) ?? []).map { RGBA(r: $0.r, g: $0.g, b: $0.b, a: 255) }
        retroMode = try? c.decodeIfPresent(RetroMode.self, forKey: .retroMode)
        remix = try? c.decodeIfPresent(RemixCredit.self, forKey: .remix)
        sounds = Array(((try? c.decodeIfPresent([SoundClip].self, forKey: .sounds)) ?? []).prefix(SoundClip.maxPerSprite * 2))
        // Ten swatches, except retro canvases, which have just their mode's colours.
        if let mode = retroMode {
            palette = mode.colors
        } else {
            palette = pal.count == SpriteProject.defaultPalette.count ? pal : SpriteProject.defaultPalette
        }
        extraColors = Array(((try? c.decode([RGBA].self, forKey: .extraColors)) ?? [])
            .map { RGBA(r: $0.r, g: $0.g, b: $0.b, a: 255) }.prefix(SpriteProject.maxExtraColors))
        loopMode = (try? c.decode(LoopMode.self, forKey: .loopMode)) ?? .loop
        trace = (try? c.decodeIfPresent(TraceSettings.self, forKey: .trace))?.sanitized
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
        try c.encode(playbackEasing, forKey: .playbackEasing)
        try c.encode(palette, forKey: .palette)
        if !extraColors.isEmpty { try c.encode(extraColors, forKey: .extraColors) }
        if loopMode != .loop { try c.encode(loopMode, forKey: .loopMode) }
        try c.encodeIfPresent(retroMode, forKey: .retroMode)
        try c.encodeIfPresent(remix, forKey: .remix)
        if !sounds.isEmpty { try c.encode(sounds, forKey: .sounds) }
        try c.encode(layers, forKey: .layers)
        if !folders.isEmpty { try c.encode(folders, forKey: .folders) }
        try c.encodeIfPresent(trace, forKey: .trace)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }

    /// Nothing drawn yet: one frame, no pixels on any layer, no tracing picture. New canvases reuse
    /// a blank sprite instead of piling up empty ones.
    var isBlank: Bool {
        frames.count == 1 && trace == nil && retroMode == nil && frames[0].layers.allSatisfy { $0.opaqueBounds == nil }
    }

    /// A copy with fresh identifiers, so caches never confuse it with the original.
    func duplicated(name: String) -> SpriteProject {
        var copy = self
        copy.id = UUID()
        copy.name = name
        // Frames get new ids, and each sound follows its frame to the new one.
        var newIDs: [UUID: UUID] = [:]
        copy.frames = frames.map {
            var f = Frame(layers: $0.layers, visible: layerVisibility)
            f.hold = $0.hold
            newIDs[$0.id] = f.id
            return f
        }
        copy.sounds = sounds.compactMap { clip in
            guard let frame = newIDs[clip.frameID] else { return nil }
            var c = clip
            c.frameID = frame
            return c
        }
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        return copy
    }
}

private struct LossyFrame: Decodable {
    let frame: Frame?
    init(from decoder: Decoder) throws { frame = try? Frame(from: decoder) }
}
