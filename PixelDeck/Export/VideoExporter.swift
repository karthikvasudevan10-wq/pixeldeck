import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics

/// The frame a video is made for.
enum VideoShape: String, CaseIterable, Identifiable, Sendable {
    /// 1080 × 1080 (or 2160 × 2160 in 4K): feeds and posts.
    case square
    /// 1080 × 1920: Reels, Shorts and TikTok.
    case vertical
    /// The timelapse of the drawing, 9:16.
    case timelapse

    var id: String { rawValue }
}

/// How a video is laid out.
struct VideoSpec: Sendable {
    var width = VideoExporter.side
    var height = VideoExporter.side
    /// "Made with Pixel Deck" in a band under the art (free exports).
    var watermark = false
    /// Ends with a 1.5 s card: "Pixel Deck · Available on the App Store".
    var endCard = false
    /// Repeat short animations until the video lasts `VideoExporter.minimumSeconds`.
    var loop = true

    static func square(fourK: Bool = false) -> VideoSpec {
        let s = fourK ? VideoExporter.fourKSide : VideoExporter.side
        return VideoSpec(width: s, height: s)
    }

    static let vertical = VideoSpec(width: 1080, height: 1920)
}

/// H.264 MP4 for social video: the art centred on the ink background at the largest whole-number
/// scale that fits, with no smoothing. Short animations repeat so the video lasts at least three
/// seconds.
enum VideoExporter {
    static let side = 1080
    static let fourKSide = 2160
    static let minimumSeconds = 3.0
    static let maximumSeconds = 60.0
    static let endCardSeconds = 1.5
    /// The design's ink colour, as BGRA bytes.
    private static let background: (b: UInt8, g: UInt8, r: UInt8) = (0x1F, 0x0E, 0x12)

    /// Square video, as before v2.
    static func write(grids: [PixelGrid], durations: [Double], side: Int = VideoExporter.side, to url: URL) throws {
        try write(grids: grids, durations: durations, spec: VideoSpec(width: side, height: side), to: url)
    }

    /// How a video of these frames is laid out in time: how long one pass of the animation is,
    /// how many passes there are, and how long the animation part lasts (before any end card).
    static func plan(durations: [Double], frames: Int, spec: VideoSpec) -> (loopSeconds: Double, loops: Int, seconds: Double) {
        let d = (0..<frames).map { i in max(PlaybackTiming.minimumDuration, i < durations.count ? durations[i] : 0.125) }
        let loopSeconds = d.reduce(0, +)
        guard loopSeconds > 0 else { return (0, 1, 0) }
        let loops = spec.loop ? max(1, Int((minimumSeconds / loopSeconds).rounded(.up))) : 1
        // The writer stops adding frames once it passes the longest video allowed.
        var time = 0.0
        outer: for _ in 0..<loops {
            for i in 0..<frames {
                if time >= maximumSeconds { break outer }
                time += d[i]
            }
        }
        return (loopSeconds, loops, time)
    }

    /// Height of the watermark band for a frame.
    static func bandHeight(_ spec: VideoSpec) -> Int {
        spec.watermark ? max(64, Int((Double(min(spec.width, spec.height)) * 0.11).rounded())) : 0
    }

    /// `durations`: seconds per frame (eased timing and holds give frames different lengths).
    static func write(grids: [PixelGrid], durations: [Double], spec: VideoSpec, to url: URL) throws {
        guard let first = grids.first else { throw ExportError.empty }
        let width = spec.width, height = spec.height
        let band = bandHeight(spec)
        let stageHeight = height - band
        guard first.width <= width, first.height <= stageHeight else { throw ExportError.couldNotWrite(url.lastPathComponent) }
        let durations = grids.indices.map { i in max(PlaybackTiming.minimumDuration, i < durations.count ? durations[i] : 0.125) }
        // A fine timescale so each frame can last any length.
        let timescale: CMTimeScale = 600
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(width, height) > 1920 ? 24_000_000 : (height > width ? 9_000_000 : 6_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent) }
        writer.startSession(atSourceTime: .zero)

        // Largest integer scale with a margin; frames are rendered one at a time to keep memory low.
        let margin = min(width, stageHeight) / 9
        let scale = max(1, min((width - 2 * margin) / max(first.width, 1), (stageHeight - 2 * margin) / max(first.height, 1)))
        let loopSeconds = durations.reduce(0, +)
        let loops = spec.loop ? max(1, Int((minimumSeconds / loopSeconds).rounded(.up))) : 1
        // Drawn once, then stamped on every frame.
        let bandImage = spec.watermark ? Watermark.band(width: width, height: band) : nil
        let layout = Layout(width: width, height: height, stageHeight: stageHeight, scale: scale)

        func append(_ buffer: CVPixelBuffer, at time: Double) throws {
            while !input.isReadyForMoreMediaData {
                // If the encoder fails (app backgrounded, disk full) it never becomes ready.
                if writer.status != .writing { throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent) }
                Thread.sleep(forTimeInterval: 0.005)
            }
            let at = CMTime(value: CMTimeValue((time * Double(timescale)).rounded()), timescale: timescale)
            guard adaptor.append(buffer, withPresentationTime: at) else {
                throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent)
            }
        }

        var time = 0.0
        outer: for _ in 0..<loops {
            for (i, grid) in grids.enumerated() {
                if time >= maximumSeconds { break outer }
                try autoreleasepool {
                    try append(try makeBuffer(grid, layout: layout, overlay: bandImage, overlayHeight: band), at: time)
                }
                time += durations[i]
            }
        }
        if spec.endCard, let card = Watermark.endCard(width: width, height: height) {
            try autoreleasepool {
                try append(try makeBuffer(nil, layout: layout, overlay: card, overlayHeight: height), at: time)
            }
            time += endCardSeconds
        }
        input.markAsFinished()
        // Hold the last frame for its full duration.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue((time * Double(timescale)).rounded()), timescale: timescale))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent) }
    }

    private struct Layout {
        let width: Int
        let height: Int
        /// The part above the watermark band, where the art is centred.
        let stageHeight: Int
        let scale: Int
    }

    /// One video frame: ink, the art (if any), then `overlay` across the bottom `overlayHeight` rows.
    private static func makeBuffer(_ grid: PixelGrid?, layout: Layout, overlay: CGImage?, overlayHeight: Int) throws -> CVPixelBuffer {
        let width = layout.width, height = layout.height, scale = layout.scale
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true,
                                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buffer = pb else { throw ExportError.couldNotWrite("video frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw ExportError.couldNotWrite("video frame") }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let row = p + y * rowBytes
            for x in 0..<width {
                row[x * 4] = background.b; row[x * 4 + 1] = background.g; row[x * 4 + 2] = background.r; row[x * 4 + 3] = 255
            }
        }
        if let grid {
            let ox = (width - grid.width * scale) / 2, oy = (layout.stageHeight - grid.height * scale) / 2
            for gy in 0..<grid.height {
                for gx in 0..<grid.width {
                    let c = grid[gx, gy]
                    if c.isClear { continue }
                    for dy in 0..<scale {
                        let row = p + (oy + gy * scale + dy) * rowBytes
                        for dx in 0..<scale {
                            let i = (ox + gx * scale + dx) * 4
                            row[i] = c.b; row[i + 1] = c.g; row[i + 2] = c.r; row[i + 3] = 255
                        }
                    }
                }
            }
        }
        if let overlay, overlayHeight > 0,
           let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                               space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
            // Core Graphics counts rows from the bottom, so y = 0 is the foot of the frame.
            ctx.interpolationQuality = .none
            ctx.draw(overlay, in: CGRect(x: 0, y: 0, width: width, height: overlayHeight))
        }
        return buffer
    }
}
