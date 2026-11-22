#if DEBUG
import AVFoundation
import Foundation

/// Debug builds only: checks the automatic tester (Tools/ci/monkey.py) asks the app to run on
/// itself, where clicking isn't a dependable way to do it.
enum MonkeyHooks {
    /// Makes a movie of the first three sprites, with a one-second tone on the first frame of the
    /// first, writes it as a video, and reports what came out (to the error stream and to a file
    /// in the temporary folder).
    @MainActor static func movieExport() {
        let sprites = Array(Shared.store.projects.prefix(3))
        guard var first = sprites.first, let frame = first.frames.first else { return report("PD-MOVIE no sprites") }
        var movie = Movie(name: "Tester")
        sprites.forEach { movie.add($0.id) }
        movie.setRepeats(2, sceneID: movie.scenes[0].id)

        let clip = SoundClip(name: "Tone", frameID: frame.id, duration: 1, fileExtension: "wav")
        guard let tone = SoundStore.url(for: clip, in: first.id) else { return report("PD-MOVIE no sound folder") }
        try? toneFile().write(to: tone)
        first.sounds = [clip]
        var byID = Dictionary(sprites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        byID[first.id] = first
        let sounds = [clip.id: tone]
        let expected = MovieTimeline(movie: movie, sprite: { byID[$0] }).seconds
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pd-movie-test.mp4")
        try? FileManager.default.removeItem(at: url)
        let lookup = byID

        Task {
            let line: String = await Task.detached {
                do {
                    let soundAdded = try MovieExporter.write(movie: movie, sprite: { lookup[$0] }, soundFile: { c, _ in sounds[c.id] },
                                                             size: .hd, watermark: true, to: url, control: MovieExporter.Control())
                    let asset = AVURLAsset(url: url)
                    let seconds = try await asset.load(.duration).seconds
                    let video = try await asset.loadTracks(withMediaType: .video).count
                    let audio = try await asset.loadTracks(withMediaType: .audio).count
                    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    return "PD-MOVIE made scenes=\(movie.scenes.count) expected=\(expected) seconds=\(seconds) video=\(video) audio=\(audio) soundAdded=\(soundAdded) bytes=\(bytes ?? 0)"
                } catch {
                    return "PD-MOVIE failed \(error)"
                }
            }.value
            try? FileManager.default.removeItem(at: tone)
            report(line)
        }
    }

    private static func report(_ line: String) {
        fputs(line + "\n", stderr)
        try? line.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("pd-movie-test.txt"), atomically: true, encoding: .utf8)
    }

    /// One second of a 440 Hz tone, as a WAV file.
    private static func toneFile() -> Data {
        let rate = 44_100
        var samples = Data(capacity: rate * 2)
        for i in 0..<rate {
            let v = Int16(sin(Double(i) / Double(rate) * 440 * 2 * .pi) * 12_000)
            withUnsafeBytes(of: v.littleEndian) { samples.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(36 + samples.count); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        text("data"); u32(samples.count)
        data.append(samples)
        return data
    }
}
#endif
