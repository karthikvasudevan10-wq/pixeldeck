import Foundation

enum SpriteSheetLayout: String, CaseIterable, Identifiable, Sendable {
    /// All frames in one row.
    case strip
    /// Frames wrapped into a roughly square grid.
    case grid

    var id: String { rawValue }
    var title: String { self == .strip ? "Row" : "Grid" }

    func columns(forFrameCount n: Int) -> Int {
        switch self {
        case .strip: max(1, n)
        case .grid: max(1, Int(Double(n).squareRoot().rounded(.up)))
        }
    }
}

/// Frames packed into one RGBA image, left to right then top to bottom.
struct SpriteSheet: Sendable {
    let frameSize: Int
    let columns: Int
    let rows: Int
    let frameCount: Int
    let bytes: [UInt8]

    var width: Int { columns * frameSize }
    var height: Int { rows * frameSize }

    static func pixelSize(canvas: Int, frameCount: Int, scale: Int, layout: SpriteSheetLayout) -> (width: Int, height: Int) {
        let cols = layout.columns(forFrameCount: frameCount)
        let rows = Int((Double(frameCount) / Double(cols)).rounded(.up))
        return (cols * canvas * scale, max(1, rows) * canvas * scale)
    }

    init(grids: [PixelGrid], scale: Int, layout: SpriteSheetLayout) {
        let s = max(1, scale)
        let side = (grids.first?.size ?? 1) * s
        let cols = layout.columns(forFrameCount: grids.count)
        let rows = max(1, Int((Double(grids.count) / Double(cols)).rounded(.up)))
        let width = cols * side
        var out = [UInt8](repeating: 0, count: width * rows * side * 4)
        for (i, grid) in grids.enumerated() {
            let frame = grid.rgbaBytes(scale: s)
            let ox = (i % cols) * side, oy = (i / cols) * side
            for y in 0..<side {
                let src = y * side * 4
                let dst = ((oy + y) * width + ox) * 4
                out.replaceSubrange(dst..<(dst + side * 4), with: frame[src..<(src + side * 4)])
            }
        }
        frameSize = side
        columns = cols
        self.rows = rows
        frameCount = grids.count
        bytes = out
    }

    func metadata(fps: Int, imageName: String) -> SpriteSheetMetadata {
        let duration = 1000 / max(1, fps)
        return SpriteSheetMetadata(
            image: imageName,
            width: width,
            height: height,
            frameWidth: frameSize,
            frameHeight: frameSize,
            fps: fps,
            frames: (0..<frameCount).map { i in
                .init(index: i, x: (i % columns) * frameSize, y: (i / columns) * frameSize,
                      w: frameSize, h: frameSize, durationMs: duration)
            }
        )
    }
}

/// JSON sidecar for game engines: where each frame sits in the sheet.
struct SpriteSheetMetadata: Codable, Sendable {
    struct FrameRect: Codable, Sendable {
        var index: Int
        var x: Int
        var y: Int
        var w: Int
        var h: Int
        var durationMs: Int
    }

    var image: String
    var width: Int
    var height: Int
    var frameWidth: Int
    var frameHeight: Int
    var fps: Int
    var frames: [FrameRect]
}
