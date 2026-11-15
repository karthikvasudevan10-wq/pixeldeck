import Foundation

/// A recording of a sprite being drawn: the frame you were working on, after each edit. Played
/// back from the sprite menu, and saved as a video with Pro. Kept on the device beside the sprite
/// (not in the sprite file, so saving and syncing sprites stays quick).
struct Timelapse: Codable, Equatable, Sendable {
    /// One moment: the art (all visible layers) cropped to where it was, in world pixels.
    struct Shot: Codable, Equatable, Sendable {
        var rect: PixelRect
        var grid: PixelGrid
    }

    private(set) var shots: [Shot] = []

    /// When full, every other shot is dropped, so long sessions still play back from start to end.
    static let maxShots = 400

    var isEmpty: Bool { shots.isEmpty }

    /// Records `grid` (a frame's flattened art, covering `bounds`) unless it's blank or the same
    /// as the last shot.
    mutating func record(_ grid: PixelGrid, bounds: PixelRect) {
        guard let local = grid.opaqueBounds else { return }
        let rect = local.offsetBy(bounds.origin)
        let cropped = grid.reframed(from: bounds, to: rect)
        if let last = shots.last, last.rect == rect, last.grid == cropped { return }
        shots.append(Shot(rect: rect, grid: cropped))
        if shots.count > Self.maxShots {
            let lastIndex = shots.count - 1
            shots = shots.enumerated().filter { $0.offset % 2 == 0 || $0.offset == lastIndex }.map(\.element)
        }
    }

    /// Every shot on one canvas that covers them all, ready to play or turn into a video.
    func playbackFrames() -> [PixelGrid] {
        guard let first = shots.first else { return [] }
        let area = shots.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        return shots.map { $0.grid.reframed(from: $0.rect, to: area) }
    }
}
