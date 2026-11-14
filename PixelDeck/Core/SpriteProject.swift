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

/// A sprite: a square canvas size plus an ordered list of frames.
struct SpriteProject: Identifiable, Codable, Sendable {
    static let supportedSizes = [8, 16, 32, 64, 128, 256]

    var id = UUID()
    var name: String
    var size: Int
    var frames: [Frame]
    var fps: Int = 8
    var createdAt = Date()
    var modifiedAt = Date()

    init(name: String, size: Int) {
        self.name = name
        self.size = size
        self.frames = [Frame(grid: PixelGrid(size: size))]
    }

    private enum CodingKeys: String, CodingKey { case id, name, size, frames, fps, createdAt, modifiedAt }

    /// Tolerant decoding: a damaged or hand-edited file loads as something editable instead of
    /// crashing the app (the editor assumes at least one frame, all the same size).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        size = try c.decode(Int.self, forKey: .size)
        guard size > 0, size <= PixelGrid.maxSize else {
            throw DecodingError.dataCorruptedError(forKey: .size, in: c, debugDescription: "Unsupported canvas size")
        }
        let name = (try? c.decode(String.self, forKey: .name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = name.isEmpty ? "Sprite" : name
        // Frame by frame, so one damaged frame doesn't take the others with it.
        let decoded = ((try? c.decode([LossyFrame].self, forKey: .frames)) ?? []).compactMap(\.frame)
        let size = size
        let valid = decoded.filter { $0.grid.size == size }
        frames = valid.isEmpty ? [Frame(grid: PixelGrid(size: size))] : valid
        fps = min(max((try? c.decode(Int.self, forKey: .fps)) ?? 8, 1), 30)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? createdAt
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
