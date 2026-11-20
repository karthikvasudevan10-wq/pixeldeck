import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case gif, spriteSheet, frames, video
    var id: String { rawValue }

    /// Video has fixed sizes (1080 × 1080, 1080 × 1920, or 2160 × 2160 with 4K), so no scale choice.
    var hasScale: Bool { self != .video }
}

struct ExportOptions {
    var format: ExportFormat = .gif
    var layout: SpriteSheetLayout = .strip
    var scale = 4
    var includeMetadata = true
    /// 4K instead of `scale` (Pro): the largest whole-number scale with the long side up to 3840
    /// px for images and GIFs, and 2160 × 2160 for video. Not offered for sprite sheets.
    var fourK = false
    /// Adds the "Made with Pixel Deck" mark to PNG frames, GIFs and videos (free version).
    var watermark = false
    /// Video: square, 9:16, or the 9:16 timelapse of the drawing.
    var videoShape: VideoShape = .square
    /// Video: finish on the "Pixel Deck · Available on the App Store" card.
    var endCard = true

    /// Formats that offer 4K.
    var offersFourK: Bool { format == .gif || format == .frames || (format == .video && videoShape == .square) }
}

enum ExportError: LocalizedError {
    case couldNotWrite(String)
    case empty
    var errorDescription: String? {
        switch self {
        case .couldNotWrite(let name): String(localized: "Couldn't write \(name).", comment: "Export error; the placeholder is a file name")
        case .empty: String(localized: "There's nothing to export yet. Draw something first.")
        }
    }
}

/// What gets exported: every frame cropped to the art (the union of all frames), so the empty
/// space of the infinite canvas isn't included.
struct ExportSource {
    let name: String
    let fps: Int
    let grids: [PixelGrid]
    /// Seconds per frame, with the sprite's playback easing and holds.
    let durations: [Double]
    /// The frames in the order they play (ping-pong goes there and back), for GIFs and videos.
    let playGrids: [PixelGrid]
    let playDurations: [Double]
    /// False when the animation plays once and stops.
    let repeats: Bool
    let width: Int
    let height: Int
    /// The timelapse of the drawing, if there is one (set by the export screen).
    var timelapse: [PixelGrid] = []

    init(_ project: SpriteProject) {
        // Hidden layers aren't exported, so crop to what's visible.
        let rect = project.visibleContentBounds ?? project.bounds
        name = project.name
        fps = project.fps
        grids = project.grids(croppedTo: rect)
        durations = project.frameDurations
        let sequence = project.playbackSequence
        let all = grids
        playGrids = sequence.frames.map { all[$0] }
        playDurations = sequence.durations
        repeats = sequence.repeats
        width = rect.width
        height = rect.height
    }

    var isBlank: Bool { grids.allSatisfy(\.isBlank) }
}

/// Writes PNG / GIF / MP4 / JSON files to a temporary folder for saving or sharing.
enum SpriteExporter {
    /// Largest image side. A 4096² RGBA image is 64 MB; 8192² can get the app terminated for
    /// memory on older iPhones.
    static let maxSide = 4096
    /// Total decoded size of all GIF frames (ImageIO keeps them until the GIF is finalised).
    static let gifMemoryBudget = 512 * 1024 * 1024
    static let scales = [1, 4, 8, 16]
    /// The long side of a 4K image.
    static let fourKSide = 3840

    /// The scale actually used: the chosen one, or the 4K one.
    static func scale(_ src: ExportSource, _ o: ExportOptions) -> Int {
        guard o.fourK, o.format != .spriteSheet else { return max(1, o.scale) }
        return max(1, fourKSide / max(1, max(src.width, src.height)))
    }

    /// Whether 4K output fits the memory limits for this sprite and format.
    static func fourKFeasible(_ src: ExportSource, options: ExportOptions) -> Bool {
        var o = options
        o.fourK = true
        let size = outputSize(src, options: o)
        switch options.format {
        case .frames: return max(size.width, size.height) <= maxSide
        case .gif: return max(size.width, size.height) <= maxSide && src.grids.count * size.width * size.height * 4 <= gifMemoryBudget
        case .video: return true
        case .spriteSheet: return false
        }
    }

    /// Output size in pixels for a format and scale.
    static func outputSize(_ src: ExportSource, options: ExportOptions) -> (width: Int, height: Int) {
        switch options.format {
        case .spriteSheet:
            return SpriteSheet.pixelSize(frameWidth: src.width, frameHeight: src.height, frameCount: src.grids.count,
                                         scale: options.scale, layout: options.layout)
        case .gif, .frames:
            let s = scale(src, options)
            return (src.width * s, src.height * s)
        case .video:
            let spec = videoSpec(options)
            return (spec.width, spec.height)
        }
    }

    /// The frame for a video with these options.
    static func videoSpec(_ o: ExportOptions) -> VideoSpec {
        var spec = o.videoShape == .square ? VideoSpec.square(fourK: o.fourK) : VideoSpec.vertical
        spec.watermark = o.watermark
        spec.endCard = o.endCard
        // A timelapse plays through once; an animation that plays once isn't repeated either.
        spec.loop = o.videoShape != .timelapse
        return spec
    }

    /// Timelapse playback speed, and how long the finished art is held.
    static let timelapseFPS = 15.0
    static let timelapseHold = 1.5

    /// Scales whose output fits the memory limits (ignoring Pro, which the UI handles).
    static func feasibleScales(_ src: ExportSource, options: ExportOptions) -> [Int] {
        scales.filter { scale in
            var o = options
            o.scale = scale
            o.fourK = false
            let size = outputSize(src, options: o)
            switch options.format {
            case .spriteSheet: return max(size.width, size.height) <= maxSide
            case .frames: return max(size.width, size.height) <= maxSide
            case .gif: return max(size.width, size.height) <= maxSide && src.grids.count * size.width * size.height * 4 <= gifMemoryBudget
            case .video: return true
            }
        }
    }

    static func export(_ src: ExportSource, options: ExportOptions) throws -> [URL] {
        guard !src.isBlank else { throw ExportError.empty }
        removePreviousExports()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = fileSafe(src.name)
        let scale = Self.scale(src, options)

        switch options.format {
        case .spriteSheet:
            let sheet = SpriteSheet(grids: src.grids, scale: scale, layout: options.layout)
            let name = "\(base)_sheet.png"
            let png = dir.appendingPathComponent(name)
            try writePNG(width: sheet.width, height: sheet.height, rgba: sheet.bytes, to: png)
            var urls = [png]
            if options.includeMetadata {
                let json = dir.appendingPathComponent("\(base)_sheet.json")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(sheet.metadata(fps: src.fps, imageName: name, durations: src.durations)).write(to: json)
                urls.append(json)
            }
            return urls

        case .gif:
            let url = dir.appendingPathComponent("\(base).gif")
            try writeGIF(grids: src.playGrids, scale: scale, durations: src.playDurations, repeats: src.repeats,
                         watermark: options.watermark, to: url)
            return [url]

        case .frames:
            return try src.grids.enumerated().map { i, grid in
                let url = dir.appendingPathComponent(String(format: "%@_%03d.png", base, i + 1))
                try autoreleasepool {
                    guard options.watermark else {
                        try writePNG(width: grid.width * scale, height: grid.height * scale, rgba: grid.rgbaBytes(scale: scale), to: url)
                        return
                    }
                    guard let art = PixelRenderer.cgImage(width: grid.width * scale, height: grid.height * scale, rgba: grid.rgbaBytes(scale: scale)),
                          let marked = Watermark.apply(to: art) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
                    try writePNG(marked, to: url)
                }
                return url
            }

        case .video:
            var spec = videoSpec(options)
            if options.videoShape == .timelapse {
                guard !src.timelapse.isEmpty else { throw ExportError.empty }
                let url = dir.appendingPathComponent("\(base)_timelapse.mp4")
                var durations = Array(repeating: 1 / timelapseFPS, count: src.timelapse.count)
                durations[durations.count - 1] = timelapseHold       // linger on the finished art
                try VideoExporter.write(grids: src.timelapse, durations: durations, spec: spec, to: url)
                return [url]
            }
            let url = dir.appendingPathComponent("\(base).mp4")
            if !src.repeats { spec.loop = false }
            try VideoExporter.write(grids: src.playGrids, durations: src.playDurations, spec: spec, to: url)
            return [url]
        }
    }

    /// Earlier exports are only needed until they've been saved or shared; don't let them pile up.
    static func removePreviousExports() {
        let tmp = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in items where url.lastPathComponent.hasPrefix("Export-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func writePNG(width: Int, height: Int, rgba: [UInt8], to url: URL) throws {
        guard let image = PixelRenderer.cgImage(width: width, height: height, rgba: rgba) else {
            throw ExportError.couldNotWrite(url.lastPathComponent)
        }
        try writePNG(image, to: url)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ExportError.couldNotWrite(url.lastPathComponent) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
    }

    /// Each frame gets its own delay, so eased timing survives in the GIF.
    static func writeGIF(grids: [PixelGrid], scale: Int, durations: [Double], repeats: Bool = true, watermark: Bool = false, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, grids.count, nil)
        else { throw ExportError.couldNotWrite(url.lastPathComponent) }
        let loop: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: repeats ? 0 : 1]]
        CGImageDestinationSetProperties(dest, loop as CFDictionary)
        for (i, grid) in grids.enumerated() {
            let delay = max(PlaybackTiming.minimumDuration, i < durations.count ? durations[i] : 0.125)
            let frameProps: [String: Any] = [kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay,
                kCGImagePropertyGIFUnclampedDelayTime as String: delay,
            ]]
            try autoreleasepool {
                guard let art = PixelRenderer.cgImage(grid, scale: scale),
                      let image = watermark ? Watermark.apply(to: art) : art else { throw ExportError.couldNotWrite(url.lastPathComponent) }
                CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(dest) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
    }

    private static func fileSafe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let s = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return s.isEmpty ? "sprite" : s
    }
}
