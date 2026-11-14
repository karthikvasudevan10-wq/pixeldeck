import Foundation

enum SpriteSheetLayout: String, CaseIterable, Identifiable, Sendable {
    /// All frames in one row.
    case strip
    /// Frames wrapped into a roughly square grid.
    case grid

    var id: String { rawValue }

    func columns(forFrameCount n: Int) -> Int {
        switch self {
        case .strip: max(1, n)
        case .grid: max(1, Int(Double(n).squareRoot().rounded(.up)))
        }
    }
}

/// Frames packed into one RGBA image, left to right then top to bottom.
struct SpriteSheet: Sendable {
    let frameWidth: Int
    let frameHeight: Int
    let columns: Int
    let rows: Int
    let frameCount: Int
    let bytes: [UInt8]

    var width: Int { columns * frameWidth }
    var height: Int { rows * frameHeight }

    static func pixelSize(frameWidth: Int, frameHeight: Int, frameCount: Int, scale: Int, layout: SpriteSheetLayout) -> (width: Int, height: Int) {
        let cols = layout.columns(forFrameCount: frameCount)
        let rows = max(1, Int((Double(frameCount) / Double(cols)).rounded(.up)))
        return (cols * frameWidth * scale, rows * frameHeight * scale)
    }

    /// All grids must be the same size.
    init(grids: [PixelGrid], scale: Int, layout: SpriteSheetLayout) {
        let s = max(1, scale)
        let fw = (grids.first?.width ?? 1) * s
        let fh = (grids.first?.height ?? 1) * s
        let cols = layout.columns(forFrameCount: grids.count)
        let rows = max(1, Int((Double(grids.count) / Double(cols)).rounded(.up)))
        let width = cols * fw
        var out = [UInt8](repeating: 0, count: width * rows * fh * 4)
        for (i, grid) in grids.enumerated() where grid.width * s == fw && grid.height * s == fh {
            let frame = grid.rgbaBytes(scale: s)
            let ox = (i % cols) * fw, oy = (i / cols) * fh
            for y in 0..<fh {
                let src = y * fw * 4
                let dst = ((oy + y) * width + ox) * 4
                out.replaceSubrange(dst..<(dst + fw * 4), with: frame[src..<(src + fw * 4)])
            }
        }
        frameWidth = fw
        frameHeight = fh
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
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            fps: fps,
            frames: (0..<frameCount).map { i in
                .init(index: i, x: (i % columns) * frameWidth, y: (i / columns) * frameHeight,
                      w: frameWidth, h: frameHeight, durationMs: duration)
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
