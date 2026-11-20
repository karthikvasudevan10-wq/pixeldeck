import Foundation
import Observation

/// A picture stored as a small palette and rows of characters ('.' is transparent; 0-9 then a-z
/// index the palette). Used for the starter tiles and stamps.
struct Art: Sendable {
    let name: String
    let palette: [UInt32]
    var solid = false
    var hazard = false
    let rows: [String]

    var grid: PixelGrid {
        let h = max(1, rows.count), w = max(1, rows.map(\.count).max() ?? 1)
        var g = PixelGrid(width: w, height: h)
        let keys = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard ch != ".", let i = keys.firstIndex(of: ch), i < palette.count else { continue }
                g[x, y] = RGBA(hex: palette[i])
            }
        }
        return g
    }
}

/// One square tile of a tileset.
struct Tile: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// `TileScene.tileSize` pixels square.
    var grid: PixelGrid
    /// The hero stands on it and can't pass through it.
    var solid = false
    /// Touching it sends the hero back to the start (water, lava, spikes).
    var hazard = false

    static func blank(name: String) -> Tile {
        Tile(name: name, grid: PixelGrid(size: TileScene.tileSize), solid: true)
    }
}

/// The tiles every new scene starts with (art in StarterTiles.swift).
enum StarterTiles {
    static var tiles: [Tile] {
        art.map { a in
            Tile(id: UUID(stableName: "pixeldeck.tile.\(a.name)"), name: a.name, grid: a.grid, solid: a.solid, hazard: a.hazard)
        }
    }
}

/// A scene painted with tiles, which is also a Pixel Playground level: where the hero starts,
/// the coins to collect, an optional goal, and (with Pro) enemies and sound.
struct TileScene: Identifiable, Codable, Equatable, Sendable {
    static let tileSize = 16
    /// Scene sizes, in tiles. Pro levels can be much longer.
    static let freeColumns = 24
    static let freeRows = 12
    static let proMaxColumns = 96
    static let proMaxRows = 24
    static let maxTiles = 48
    static let maxCoins = 99
    static let maxEnemies = 12

    var id = UUID()
    var name: String
    var tiles: [Tile]
    private(set) var columns: Int
    private(set) var rows: Int
    /// Row-major tile indices; -1 is empty.
    private(set) var cells: [Int]
    var sky = RGBA(hex: 0x241A3E)
    /// The sprite that plays the hero (nil: the starter slime).
    var heroID: UUID?
    /// Tile coordinates.
    var start = PixelPoint(x: 1, y: 8)
    var coins: [PixelPoint] = []
    var goal: PixelPoint?
    var enemies: [PixelPoint] = []
    var sound = false
    /// Who made it (shown when a level is shared).
    var author: String?
    var createdAt = Date()
    var modifiedAt = Date()

    init(name: String, columns: Int = TileScene.freeColumns, rows: Int = TileScene.freeRows, tiles: [Tile] = StarterTiles.tiles) {
        self.name = name
        self.columns = max(4, columns)
        self.rows = max(4, rows)
        self.tiles = tiles
        cells = Array(repeating: -1, count: self.columns * self.rows)
    }

    func contains(_ p: PixelPoint) -> Bool { p.x >= 0 && p.y >= 0 && p.x < columns && p.y < rows }

    /// The tile index at a cell, or -1 when empty or off the scene.
    subscript(x: Int, y: Int) -> Int {
        get { contains(PixelPoint(x: x, y: y)) ? cells[y * columns + x] : -1 }
        set {
            guard contains(PixelPoint(x: x, y: y)) else { return }
            cells[y * columns + x] = tiles.indices.contains(newValue) ? newValue : -1
        }
    }

    func tile(at p: PixelPoint) -> Tile? {
        let i = self[p.x, p.y]
        return tiles.indices.contains(i) ? tiles[i] : nil
    }

    func isSolid(_ x: Int, _ y: Int) -> Bool { tile(at: PixelPoint(x: x, y: y))?.solid ?? false }
    func isHazard(_ x: Int, _ y: Int) -> Bool { tile(at: PixelPoint(x: x, y: y))?.hazard ?? false }

    /// Fills the touching cells that hold the same tile as `p` with `tile` (-1 erases).
    mutating func fill(_ tile: Int, at p: PixelPoint) {
        guard contains(p) else { return }
        let target = self[p.x, p.y]
        let new = tiles.indices.contains(tile) ? tile : -1
        guard target != new else { return }
        var stack = [p]
        while let q = stack.popLast() {
            guard contains(q), self[q.x, q.y] == target else { continue }
            self[q.x, q.y] = new
            stack += [PixelPoint(x: q.x + 1, y: q.y), PixelPoint(x: q.x - 1, y: q.y), PixelPoint(x: q.x, y: q.y + 1), PixelPoint(x: q.x, y: q.y - 1)]
        }
    }

    /// Changes the scene's size, keeping what fits (anchored at the bottom-left, where the ground is).
    mutating func resize(columns newColumns: Int, rows newRows: Int) {
        let c = min(max(newColumns, 4), TileScene.proMaxColumns), r = min(max(newRows, 4), TileScene.proMaxRows)
        guard c != columns || r != rows else { return }
        var next = Array(repeating: -1, count: c * r)
        let dy = r - rows
        for y in 0..<rows {
            for x in 0..<min(columns, c) where y + dy >= 0 && y + dy < r {
                next[(y + dy) * c + x] = cells[y * columns + x]
            }
        }
        func moved(_ p: PixelPoint) -> PixelPoint? {
            let q = PixelPoint(x: p.x, y: p.y + dy)
            return q.x < c && q.y >= 0 && q.y < r ? q : nil
        }
        columns = c
        rows = r
        cells = next
        coins = coins.compactMap(moved)
        enemies = enemies.compactMap(moved)
        goal = goal.flatMap(moved)
        start = moved(start) ?? PixelPoint(x: min(start.x, c - 1), y: min(max(0, start.y + dy), r - 1))
    }

    /// Removes a tile from the set; cells using it become empty.
    mutating func removeTile(at index: Int) {
        guard tiles.indices.contains(index), tiles.count > 1 else { return }
        tiles.remove(at: index)
        cells = cells.map { $0 == index ? -1 : ($0 > index ? $0 - 1 : $0) }
    }

    /// Puts something (a coin, an enemy) on a cell, or takes it off if it's already there.
    mutating func toggleCoin(at p: PixelPoint) {
        guard contains(p) else { return }
        if let i = coins.firstIndex(of: p) { coins.remove(at: i) } else if coins.count < TileScene.maxCoins { coins.append(p) }
    }

    mutating func toggleEnemy(at p: PixelPoint) {
        guard contains(p) else { return }
        if let i = enemies.firstIndex(of: p) { enemies.remove(at: i) } else if enemies.count < TileScene.maxEnemies { enemies.append(p) }
    }

    /// Size in pixels.
    var pixelWidth: Int { columns * TileScene.tileSize }
    var pixelHeight: Int { rows * TileScene.tileSize }

    /// The whole scene as one picture (sky, then tiles), for thumbnails and export.
    func rendered(includeSky: Bool = true) -> PixelGrid {
        let t = TileScene.tileSize
        var g = PixelGrid(width: pixelWidth, height: pixelHeight, fill: includeSky ? sky : .clear)
        for y in 0..<rows {
            for x in 0..<columns {
                guard let tile = tile(at: PixelPoint(x: x, y: y)) else { continue }
                g.stamp(tile.grid.patch(in: tile.grid.rect), at: PixelPoint(x: x * t, y: y * t))
            }
        }
        return g
    }

    /// Whether the scene is within the free size and uses no Pro extras.
    var needsPro: Bool {
        columns > TileScene.freeColumns || rows > TileScene.freeRows || !enemies.isEmpty || sound
    }

    /// "Night hills": a small ready-made level, so a new scene isn't an empty grid.
    static func starter(name: String) -> TileScene {
        var s = TileScene(name: name)
        let t = Dictionary(uniqueKeysWithValues: s.tiles.enumerated().map { ($0.element.name, $0.offset) })
        let grass = t["grasstop"] ?? 0, dirt = t["dirt"] ?? 0, brick = t["brick"] ?? 0, water = t["water"] ?? 0
        let ground = s.rows - 3
        for x in 0..<s.columns {
            // A pond to jump over, and a raised bank at the far end.
            let pond = (13...15).contains(x)
            let top = x >= 19 ? ground - 1 : ground
            for y in top..<s.rows {
                if pond { if y > ground { s[x, y] = water } } else { s[x, y] = y == top ? grass : dirt }
            }
        }
        for x in 4...7 { s[x, ground - 3] = brick }
        for x in 13...17 { s[x, ground - 5] = brick }
        if let flower = t["flower"] { s[11, ground - 1] = flower }
        if let tree = t["tree"] { s[21, ground - 2] = tree }
        if let cloud = t["cloud"] { s[5, 1] = cloud; s[18, 2] = cloud }
        s.start = PixelPoint(x: 2, y: ground - 1)
        s.coins = [PixelPoint(x: 5, y: ground - 4), PixelPoint(x: 9, y: ground - 1), PixelPoint(x: 14, y: ground - 6),
                   PixelPoint(x: 16, y: ground - 6), PixelPoint(x: 22, y: ground - 2)]
        return s
    }
}

/// Scenes saved as JSON files, one per scene, in a folder beside the sprites.
@Observable
final class SceneStore {
    private(set) var scenes: [TileScene] = []
    let directory: URL
    /// The app swaps in a coordinated (iCloud-safe) write.
    @ObservationIgnored var writeFile: (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }

    init(directory: URL) {
        self.directory = directory
        load()
    }

    func load() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        scenes = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(TileScene.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func scene(id: UUID) -> TileScene? { scenes.first { $0.id == id } }

    func save(_ scene: TileScene) {
        var s = scene
        s.modifiedAt = Date()
        if let i = scenes.firstIndex(where: { $0.id == s.id }) { scenes[i] = s } else { scenes.insert(s, at: 0) }
        if let data = try? JSONEncoder().encode(s) { try? writeFile(data, url(s.id)) }
    }

    func delete(id: UUID) {
        scenes.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: url(id))
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
