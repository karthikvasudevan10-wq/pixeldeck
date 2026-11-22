import AVFoundation
import Foundation

/// A sound to put in an exported video.
struct ExportSound {
    let url: URL
    /// Seconds from the start of one pass of the animation.
    let time: Double
    let volume: Double
}

/// One sound in a movie's soundtrack.
struct MovieSoundCue: Sendable {
    let url: URL
    /// Seconds from the start of the movie.
    let time: Double
    /// How long the sound lasts.
    let seconds: Double
    let volume: Double
}

/// Adds a sprite's sounds to an exported video: the sounds are mixed into one soundtrack, which
/// is then joined to the picture (the picture itself isn't re-encoded).
enum VideoSound {
    enum Failure: LocalizedError {
        case couldNotMix
        var errorDescription: String? { String(localized: "The video was made, but its sound couldn't be added.") }
    }

    /// Mixes `sounds` (repeated for each of `loops` passes of `loopSeconds`) into `video`, in place.
    static func add(_ sounds: [ExportSound], to video: URL, loopSeconds: Double, loops: Int, seconds: Double) throws {
        guard !sounds.isEmpty, seconds > 0, loopSeconds > 0 else { return }
        let rate = Double(AudioMix.sampleRate)
        let length = Int(seconds * rate)
        guard length > 0 else { return }
        var left = [Float](repeating: 0, count: length), right = [Float](repeating: 0, count: length)
        var decoded: [URL: (left: [Float], right: [Float])] = [:]
        for l in 0..<max(1, loops) {
            for s in sounds {
                let start = Double(l) * loopSeconds + s.time
                guard start < seconds else { continue }
                if decoded[s.url] == nil { decoded[s.url] = try? samples(of: s.url) }
                guard let audio = decoded[s.url] else { continue }
                AudioMix.add(audio.left, into: &left, at: Int(start * rate), volume: Float(s.volume))
                AudioMix.add(audio.right, into: &right, at: Int(start * rate), volume: Float(s.volume))
            }
        }
        guard !decoded.isEmpty else { throw Failure.couldNotMix }
        AudioMix.soften(&left)
        AudioMix.soften(&right)

        let folder = video.deletingLastPathComponent()
        let track = folder.appendingPathComponent("soundtrack-\(UUID().uuidString).m4a")
        let joined = folder.appendingPathComponent("joined-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: track)
            try? FileManager.default.removeItem(at: joined)
        }
        try write(left: left, right: right, to: track)
        try join(video: video, audio: track, into: joined)
        _ = try FileManager.default.replaceItemAt(video, withItemAt: joined)
    }

    /// A movie's soundtrack: mixed and written ten seconds at a time, so the sound of a long film
    /// never has to be held in memory at once. Then joined to the picture, as above.
    static func add(_ cues: [MovieSoundCue], to video: URL, seconds: Double, progress: (Double) -> Void = { _ in }) throws {
        guard !cues.isEmpty, seconds > 0 else { return }
        let rate = Double(AudioMix.sampleRate)
        let total = Int(seconds * rate)
        guard total > 0 else { return }
        let folder = video.deletingLastPathComponent()
        let track = folder.appendingPathComponent("soundtrack-\(UUID().uuidString).m4a")
        let joined = folder.appendingPathComponent("joined-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: track)
            try? FileManager.default.removeItem(at: joined)
        }
        var anySound = false
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: AudioMix.sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000,
            ]
            let file = try AVAudioFile(forWriting: track, settings: settings)
            let format = file.processingFormat
            let piece = AudioMix.sampleRate * 10
            let ordered = cues.sorted { $0.time < $1.time }
            var decoded: [URL: (left: [Float], right: [Float])] = [:]
            var unreadable: Set<URL> = []
            var position = 0
            while position < total {
                let n = min(piece, total - position)
                var left = [Float](repeating: 0, count: n), right = [Float](repeating: 0, count: n)
                var inUse: Set<URL> = []
                for cue in ordered {
                    let start = Int(cue.time * rate)
                    if start >= position + n { break }
                    // Still sounding in this piece? (A second to spare for files a little longer than noted.)
                    guard start + Int((cue.seconds + 1) * rate) > position, !unreadable.contains(cue.url) else { continue }
                    if decoded[cue.url] == nil {
                        if let audio = try? samples(of: cue.url) { decoded[cue.url] = audio } else { unreadable.insert(cue.url) }
                    }
                    guard let audio = decoded[cue.url] else { continue }
                    inUse.insert(cue.url)
                    anySound = true
                    AudioMix.add(audio.left, startingAt: start, intoWindow: &left, windowStart: position, volume: Float(cue.volume))
                    AudioMix.add(audio.right, startingAt: start, intoWindow: &right, windowStart: position, volume: Float(cue.volume))
                }
                // Sounds that have finished are let go.
                for url in Array(decoded.keys) where !inUse.contains(url) { decoded[url] = nil }
                AudioMix.soften(&left)
                AudioMix.soften(&right)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
                      let channels = buffer.floatChannelData else { throw Failure.couldNotMix }
                buffer.frameLength = AVAudioFrameCount(n)
                for i in 0..<n {
                    channels[0][i] = left[i]
                    if format.channelCount > 1 { channels[1][i] = right[i] }
                }
                try file.write(from: buffer)
                position += n
                progress(Double(position) / Double(total))
            }
        }   // the soundtrack file is finished when `file` goes away here
        guard anySound else { throw Failure.couldNotMix }
        try join(video: video, audio: track, into: joined)
        _ = try FileManager.default.replaceItemAt(video, withItemAt: joined)
    }

    /// A sound file as stereo samples at the mix's rate.
    static func samples(of url: URL) throws -> (left: [Float], right: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard file.length > 0,
              let target = AVAudioFormat(standardFormatWithSampleRate: Double(AudioMix.sampleRate), channels: 2),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
              let converter = AVAudioConverter(from: source, to: target) else { throw Failure.couldNotMix }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * target.sampleRate / source.sampleRate) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw Failure.couldNotMix }
        // The converter asks for input until it's told there's no more.
        let fed = Flag()
        var problem: NSError?
        let status = converter.convert(to: output, error: &problem) { _, state in
            if fed.isSet {
                state.pointee = .endOfStream
                return nil
            }
            fed.isSet = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, problem == nil, let channels = output.floatChannelData else { throw Failure.couldNotMix }
        let n = Int(output.frameLength)
        return (Array(UnsafeBufferPointer(start: channels[0], count: n)), Array(UnsafeBufferPointer(start: channels[1], count: n)))
    }

    private final class Flag: @unchecked Sendable {
        var isSet = false
    }

    private final class Outcome: @unchecked Sendable {
        var error: Error?
    }

    /// Writes stereo samples as an AAC file.
    private static func write(left: [Float], right: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: AudioMix.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        let chunk = 32_768
        var position = 0
        while position < left.count {
            let n = min(chunk, left.count - position)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
                  let channels = buffer.floatChannelData else { throw Failure.couldNotMix }
            buffer.frameLength = AVAudioFrameCount(n)
            for i in 0..<n {
                channels[0][i] = left[position + i]
                if format.channelCount > 1 { channels[1][i] = right[position + i] }
            }
            try file.write(from: buffer)
            position += n
        }
    }

    /// Puts the picture and the soundtrack in one file, copying both as they are.
    private static func join(video: URL, audio: URL, into output: URL) throws {
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let picture = AVURLAsset(url: video), sound = AVURLAsset(url: audio)
                let movie = AVMutableComposition()
                let length = try await picture.load(.duration)
                guard let pictureTrack = try await picture.loadTracks(withMediaType: .video).first,
                      let soundTrack = try await sound.loadTracks(withMediaType: .audio).first,
                      let toPicture = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                      let toSound = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw Failure.couldNotMix
                }
                try toPicture.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: pictureTrack, at: .zero)
                let recorded = try await sound.load(.duration)
                let soundLength = min(length, recorded)
                try toSound.insertTimeRange(CMTimeRange(start: .zero, duration: soundLength), of: soundTrack, at: .zero)
                guard let export = AVAssetExportSession(asset: movie, presetName: AVAssetExportPresetPassthrough) else { throw Failure.couldNotMix }
                export.outputURL = output
                export.outputFileType = .mp4
                await export.export()
                if export.status != .completed { throw export.error ?? Failure.couldNotMix }
            } catch {
                outcome.error = error
            }
            done.signal()
        }
        done.wait()
        if let error = outcome.error { throw error }
    }
}
