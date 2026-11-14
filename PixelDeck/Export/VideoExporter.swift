import Foundation
import AVFoundation
import CoreVideo

/// Square H.264 MP4 for social video: the art centred on the ink background at the largest
/// whole-number scale that fits, with no smoothing. Short animations repeat so the video lasts
/// at least three seconds.
enum VideoExporter {
    static let side = 1080
    static let minimumSeconds = 3.0
    static let maximumSeconds = 60.0
    /// The design's ink colour, as BGRA bytes.
    private static let background: (b: UInt8, g: UInt8, r: UInt8) = (0x1F, 0x0E, 0x12)

    static func write(grids: [PixelGrid], fps: Int, to url: URL) throws {
        guard let first = grids.first else { throw ExportError.empty }
        let fps = max(1, fps)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: side,
            kCVPixelBufferHeightKey as String: side,
        ])
        guard writer.canAdd(input) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent) }
        writer.startSession(atSourceTime: .zero)

        // Largest integer scale with a margin; frames are rendered one at a time to keep memory low.
        let margin = 120
        let scale = max(1, min((side - 2 * margin) / max(first.width, 1), (side - 2 * margin) / max(first.height, 1)))
        let loopSeconds = Double(grids.count) / Double(fps)
        var loops = max(1, Int((minimumSeconds / loopSeconds).rounded(.up)))
        while Double(loops - 1) * loopSeconds >= maximumSeconds, loops > 1 { loops -= 1 }
        let maxFrames = Int(maximumSeconds * Double(fps))

        var index: Int64 = 0
        outer: for _ in 0..<loops {
            for grid in grids {
                if index >= maxFrames { break outer }
                try autoreleasepool {
                    let buffer = try makeBuffer(grid, scale: scale)
                    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: index, timescale: CMTimeScale(fps))) else {
                        throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent)
                    }
                }
                index += 1
            }
        }
        input.markAsFinished()
        // Hold the last frame for its full duration.
        writer.endSession(atSourceTime: CMTime(value: index, timescale: CMTimeScale(fps)))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent) }
    }

    private static func makeBuffer(_ grid: PixelGrid, scale: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true,
                                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buffer = pb else { throw ExportError.couldNotWrite("video frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw ExportError.couldNotWrite("video frame") }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<side {
            let row = p + y * rowBytes
            for x in 0..<side {
                row[x * 4] = background.b; row[x * 4 + 1] = background.g; row[x * 4 + 2] = background.r; row[x * 4 + 3] = 255
            }
        }
        let ox = (side - grid.width * scale) / 2, oy = (side - grid.height * scale) / 2
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
        return buffer
    }
}
