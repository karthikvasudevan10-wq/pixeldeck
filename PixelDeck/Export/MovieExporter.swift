import AVFoundation
import CoreVideo
import Foundation

/// The frame a movie is made for.
enum MovieSize: String, CaseIterable, Identifiable, Sendable {
    case hd, square, vertical, fourK

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .hd: 1920
        case .square, .vertical: 1080
        case .fourK: 3840
        }
    }

    var height: Int {
        switch self {
        case .hd, .square: 1080
        case .vertical: 1920
        case .fourK: 2160
        }
    }
}

/// A whole movie as one H.264 MP4: scene after scene, each centred on the ink background at the
/// largest whole-number scale that fits, then every scene's frame sounds mixed into one
/// soundtrack. Scenes are drawn one at a time and frames one at a time, so a long film takes no
/// more memory than its biggest scene.
enum MovieExporter {
    /// Shared between the screen and the work: how far along it is, and whether to stop.
    final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var done = 0.0

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        /// 0 to 1.
        var fraction: Double {
            lock.lock(); defer { lock.unlock() }
            return done
        }

        func cancel() {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
        }

        func report(_ fraction: Double) {
            lock.lock(); defer { lock.unlock() }
            done = min(max(fraction, 0), 1)
        }
    }

    struct Cancelled: Error {}

    /// Returns false if the picture was made but its sound could not be added.
    /// `sprite` gives a scene's sprite; `soundFile` the audio file of one of its sounds.
    @discardableResult
    static func write(movie: Movie, sprite: (UUID) -> SpriteProject?, soundFile: (SoundClip, UUID) -> URL?,
                      size: MovieSize, watermark: Bool, to url: URL, control: Control) throws -> Bool {
        let timeline = MovieTimeline(movie: movie, sprite: sprite)
        guard !timeline.scenes.isEmpty, timeline.seconds > 0 else { throw ExportError.empty }
        let width = size.width, height = size.height
        let spec = VideoSpec(width: width, height: height, watermark: watermark)
        let band = VideoExporter.bandHeight(spec)
        let stageHeight = height - band
        let timescale: CMTimeScale = 600

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(width, height) > 1920 ? 24_000_000 : 8_000_000,
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
        let bandImage = watermark ? Watermark.band(width: width, height: band) : nil

        func append(_ buffer: CVPixelBuffer, at time: Double) throws {
            while !input.isReadyForMoreMediaData {
                if control.isCancelled { throw Cancelled() }
                // If the encoder fails (app in the background, disk full) it never becomes ready.
                if writer.status != .writing { throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent) }
                Thread.sleep(forTimeInterval: 0.005)
            }
            let at = CMTime(value: CMTimeValue((time * Double(timescale)).rounded()), timescale: timescale)
            guard adaptor.append(buffer, withPresentationTime: at) else {
                throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent)
            }
        }

        var sounds: [MovieSoundCue] = []
        do {
            for (index, scene) in timeline.scenes.enumerated() {
                let start = timeline.starts[index]
                guard let s = sprite(scene.spriteID) else { continue }
                // This scene's sounds, each time it plays through.
                let clips = Dictionary(s.sounds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for pass in 0..<scene.repeats {
                    for cue in scene.cues {
                        guard let clip = clips[cue.clipID], let file = soundFile(clip, s.id),
                              FileManager.default.fileExists(atPath: file.path) else { continue }
                        sounds.append(MovieSoundCue(url: file, time: start + Double(pass) * scene.passSeconds + cue.time,
                                                    seconds: clip.duration, volume: cue.volume))
                    }
                }
                // The scene's frames, cropped to its art.
                let rect = s.visibleContentBounds ?? s.bounds
                let grids = s.grids(croppedTo: rect)
                let sequence = s.playbackSequence
                let fits = !grids.isEmpty && rect.width <= width && rect.height <= stageHeight
                let margin = min(width, stageHeight) / 9
                let scale = max(1, min((width - 2 * margin) / max(rect.width, 1), (stageHeight - 2 * margin) / max(rect.height, 1)))
                let layout = VideoExporter.Layout(width: width, height: height, stageHeight: stageHeight, scale: scale)
                var time = start
                for _ in 0..<scene.repeats {
                    for (step, frame) in sequence.frames.enumerated() {
                        if control.isCancelled { throw Cancelled() }
                        try autoreleasepool {
                            let grid = fits && grids.indices.contains(frame) ? grids[frame] : nil
                            try append(try VideoExporter.makeBuffer(grid, layout: layout, overlay: bandImage, overlayHeight: band), at: time)
                        }
                        time += sequence.durations[step]
                        control.report(time / timeline.seconds * 0.85)
                    }
                }
            }
        } catch {
            input.markAsFinished()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        input.markAsFinished()
        // The last frame stays for its full length.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue((timeline.seconds * Double(timescale)).rounded()), timescale: timescale))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? ExportError.couldNotWrite(url.lastPathComponent) }

        var soundAdded = true
        if !sounds.isEmpty {
            do {
                try VideoSound.add(sounds, to: url, seconds: timeline.seconds) { control.report(0.85 + $0 * 0.15) }
            } catch {
                soundAdded = false
            }
        }
        control.report(1)
        return soundAdded
    }
}
