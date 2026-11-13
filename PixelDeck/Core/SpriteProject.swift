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
