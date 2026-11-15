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

    /// `durations` (seconds per frame) carries eased timing into the JSON; default is 1/fps each.
    func metadata(fps: Int, imageName: String, durations: [Double]? = nil) -> SpriteSheetMetadata {
        let even = 1000 / max(1, fps)
        // Milliseconds per frame: the eased durations when given, otherwise 1/fps each.
        var ms = [Int](repeating: even, count: frameCount)
        if let durations {
            for i in 0..<min(frameCount, durations.count) { ms[i] = Int((durations[i] * 1000).rounded()) }
        }
        var rects: [SpriteSheetMetadata.FrameRect] = []
        for i in 0..<frameCount {
            let x = (i % columns) * frameWidth
            let y = (i / columns) * frameHeight
            rects.append(.init(index: i, x: x, y: y, w: frameWidth, h: frameHeight, durationMs: ms[i]))
        }
        return SpriteSheetMetadata(image: imageName, width: width, height: height,
                                   frameWidth: frameWidth, frameHeight: frameHeight, fps: fps, frames: rects)
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
