import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// Sound on frames: attach a recording or an audio file to a frame. It starts when playback
// reaches that frame and plays for its own length. It's heard in the Studio and in exported
// videos. The audio files live beside the sprites (in iCloud when sync is on), in "Sounds".

/// Where a sprite's sound files are kept: Sounds/<sprite id>_<clip id>.<type>.
enum SoundStore {
    private static var folder: URL? {
        guard let base = ImageStore.root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for clip: SoundClip, in project: UUID) -> URL? {
        folder?.appendingPathComponent("\(project.uuidString)_\(clip.id.uuidString)").appendingPathExtension(clip.fileExtension)
    }

    /// Seconds of audio in a file, or nil if it can't be read as audio.
    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    enum AddError: Error {
        case unreadable, tooLong, tooBig

        var message: String {
            switch self {
            case .unreadable: String(localized: "That file couldn't be read as sound. Try an M4A, MP3 or WAV file.")
            case .tooLong: String(localized: "Sounds can be up to \(Int(SoundClip.maxSeconds / 60)) minutes long.")
            case .tooBig: String(localized: "That sound file is too big.")
            }
        }
    }

    /// Copies an audio file in for a sprite and describes it. The clip isn't on a frame yet:
    /// pass it to `EditorModel.addSound`.
    static func add(from source: URL, name: String, project: UUID) -> Result<SoundClip, AddError> {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let seconds = duration(of: source), seconds > 0 else { return .failure(.unreadable) }
        guard seconds <= SoundClip.maxSeconds else { return .failure(.tooLong) }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= SoundClip.maxBytes else { return .failure(.tooBig) }
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let clip = SoundClip(name: name, frameID: UUID(), duration: seconds, fileExtension: ext)
        guard let target = url(for: clip, in: project) else { return .failure(.unreadable) }
        CloudFiles.copy(from: source, to: target)
        guard FileManager.default.fileExists(atPath: target.path) else { return .failure(.unreadable) }
        return .success(clip)
    }

    static func delete(_ clip: SoundClip, in project: UUID) {
        if let u = url(for: clip, in: project) { CloudFiles.remove(u) }
    }

    private static func files(of project: UUID) -> [URL] {
        guard let folder else { return [] }
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix(project.uuidString + "_") }
    }

    static func deleteAll(for project: UUID) {
        for f in files(of: project) { CloudFiles.remove(f) }
    }

    /// For a duplicated sprite: its clips keep their ids, so only the sprite's id changes.
    static func copyAll(from project: UUID, to newProject: UUID) {
        guard let folder else { return }
        for f in files(of: project) {
            let rest = f.lastPathComponent.dropFirst(project.uuidString.count)
            CloudFiles.copy(from: f, to: folder.appendingPathComponent(newProject.uuidString + rest))
        }
    }
}

/// Plays a sprite's sounds in time with the animation, and previews single sounds.
@MainActor
final class StudioSoundPlayer {
    private var players: [UUID: AVAudioPlayer] = [:]
    private var preview: AVAudioPlayer?
    private var task: Task<Void, Never>?

    /// Starts the sounds for an animation that has just begun playing. `total` is the length of
    /// one pass; with `repeats`, the sounds come round again with each loop.
    func play(cues: [SoundCue], files: [UUID: URL], total: Double, repeats: Bool) {
        stop()
        guard !cues.isEmpty, total > 0 else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for (id, url) in files {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.prepareToPlay()
            players[id] = p
        }
        let ordered = cues.sorted { $0.time < $1.time }
        task = Task { @MainActor [weak self] in
            repeat {
                let start = ContinuousClock.now
                for cue in ordered {
                    try? await Task.sleep(until: start + .seconds(cue.time), clock: .continuous)
                    guard !Task.isCancelled, let self else { return }
                    if let p = self.players[cue.clipID] {
                        p.volume = Float(cue.volume)
                        p.currentTime = 0
                        p.play()
                    }
                }
                try? await Task.sleep(until: start + .seconds(total), clock: .continuous)
            } while repeats && !Task.isCancelled
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        for p in players.values { p.stop() }
        players = [:]
        preview?.stop()
        preview = nil
    }

    /// Plays one sound on its own.
    func preview(_ url: URL, volume: Double) {
        preview?.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = Float(volume)
        p.play()
        preview = p
    }
}

/// Starts and stops a sprite's sounds with playback. Kept out of `EditorView.body`.
struct FrameSoundPlayback: ViewModifier {
    let model: EditorModel
    @State private var player = StudioSoundPlayer()

    func body(content: Content) -> some View {
        content
            .onChange(of: model.playCount) { _, _ in start() }
            .onChange(of: model.isPlaying) { _, playing in if !playing { player.stop() } }
            .onDisappear { player.stop() }
    }

    private func start() {
        let cues = model.project.soundCues
        guard model.isPlaying, !cues.isEmpty else { return }
        var files: [UUID: URL] = [:]
        for clip in model.project.liveSounds {
            if let url = SoundStore.url(for: clip, in: model.project.id) { files[clip.id] = url }
        }
        let sequence = model.playbackSequence
        player.play(cues: cues, files: files, total: sequence.total, repeats: sequence.repeats)
    }
}

/// Records from the microphone into a temporary file.
@Observable
final class SoundRecorder: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    @ObservationIgnored private var recorder: AVAudioRecorder?
    /// Recordings stop by themselves after this long.
    static let maxSeconds = 120.0

    var seconds: Double { recorder?.currentTime ?? 0 }
    /// There's a recording waiting to be added (it's still going, or it reached the time limit).
    var hasTake: Bool { recorder != nil }

    /// Asks for the microphone if needed, then starts. False if it isn't allowed or can't start.
    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        r.delegate = self
        guard r.record(forDuration: SoundRecorder.maxSeconds) else { return false }
        recorder = r
        isRecording = true
        return true
    }

    /// Stops and returns the recording's file (nil if nothing was recorded).
    func stop() -> URL? {
        guard let r = recorder else { return nil }
        let url = r.url
        let length = r.currentTime
        r.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        return length > 0.1 ? url : nil
    }

    /// The time limit was reached: the file is complete, and Stop will hand it over.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async { self.isRecording = false }
    }
}

/// "Sound on this frame": what's attached, and adding a recording or a file.
struct FrameSoundSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = SoundRecorder()
    @State private var player = StudioSoundPlayer()
    @State private var importing = false
    @State private var message: String?
    @State private var recordedURL: URL?

    private var frame: Int { model.currentIndex }
    private var clips: [SoundClip] { model.sounds(onFrame: frame) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Sound", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Frame \(frame + 1) of \(model.frameCount)", comment: "Which frame the sounds belong to")
                        .font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                    Text("A sound starts when the animation reaches this frame and plays for its own length. You hear it when you press Play, and it's in the videos you export.")
                        .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if clips.isEmpty {
                        Text("No sound on this frame yet.")
                            .font(AppFont.body(15, relativeTo: .body)).foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(clips) { clip in row(clip) }

                    if model.canAddSound(toFrame: frame) {
                        recordControl
                        Button { importing = true } label: {
                            HStack(spacing: 10) {
                                PixelIcon.download.view(size: 16)
                                Text("Choose a sound file").font(AppFont.body(14, .bold, relativeTo: .body))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.text)
                            .padding(12)
                            .background(Theme.surface)
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(recorder.isRecording)
                        .accessibilityHint("Music, a sound effect or speech: M4A, MP3 or WAV")
                    } else {
                        Text("A frame can have \(SoundClip.maxPerFrame) sounds, and a sprite \(SoundClip.maxPerSprite). Remove one to add another.")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }
                    if let message {
                        Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent)
                    }
                    Text("Sounds stay with your sprite, on your devices. They aren't shared to Community, and GIFs are silent.")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            attach(url, name: url.deletingPathExtension().lastPathComponent)
        }
        .onDisappear {
            _ = recorder.stop()
            player.stop()
        }
    }

    private func row(_ clip: SoundClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    if let url = SoundStore.url(for: clip, in: model.project.id) { player.preview(url, volume: clip.volume) }
                } label: {
                    PixelIcon.play.view(size: 16, lineWidth: 2.5).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel(Text("Play \(clip.name)"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: clip.name).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream).lineLimit(1)
                    Text(verbatim: Self.length(clip.duration)).font(AppFont.pixel(10)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                Button {
                    player.stop()
                    model.removeSound(clip.id)
                    SoundStore.delete(clip, in: model.project.id)
                } label: {
                    PixelIcon.trash.view(size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel(Text("Remove \(clip.name)"))
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(Theme.muted)
                Slider(value: Binding(get: { clip.volume }, set: { model.setSoundVolume($0, for: clip.id) }), in: 0...1)
                    .tint(Theme.accent)
                    .accessibilityLabel(Text("Volume of \(clip.name)"))
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.muted)
            }
        }
        .padding(10)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }

    /// Record, with the time while recording; then Stop adds it to the frame.
    private var recordControl: some View {
        Button {
            if recorder.isRecording || recorder.hasTake {
                if let url = recorder.stop() {
                    attach(url, name: String(localized: "Recording \(model.project.liveSounds.count + 1)", comment: "Default name for a recorded sound"))
                }
            } else {
                Task {
                    if !(await recorder.start()) {
                        message = String(localized: "Pixel Deck isn't allowed to use the microphone. You can allow it in Settings, or choose a sound file instead.")
                    }
                }
            }
        } label: {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                HStack(spacing: 10) {
                    Circle().fill(recorder.isRecording ? Theme.onAccent : Theme.accent).frame(width: 14, height: 14)
                    (recorder.isRecording
                        ? Text("Stop · \(Self.length(recorder.seconds))", comment: "Stop recording; the placeholder is the time so far")
                        : recorder.hasTake ? Text("Add the recording") : Text("Record a sound"))
                        .font(AppFont.pixel(14))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(PrimaryButtonStyle(fill: recorder.isRecording ? Theme.accent : Theme.accent2,
                                        shadow: recorder.isRecording ? Theme.accentShadow : Theme.accent2Shadow, depth: 4))
        .accessibilityHint("Uses the microphone. Recordings can be up to two minutes.")
    }

    private func attach(_ url: URL, name: String) {
        switch SoundStore.add(from: url, name: name, project: model.project.id) {
        case .success(let clip):
            if model.addSound(clip, toFrame: frame) {
                message = nil
            } else {
                SoundStore.delete(clip, in: model.project.id)
                message = String(localized: "That sound couldn't be added to this frame.")
            }
        case .failure(let e):
            message = e.message
        }
    }

    static func length(_ seconds: Double) -> String {
        seconds < 60 ? String(format: "%.1f s", seconds) : String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

extension EditorView {
    /// When a sprite is left: sounds whose frame was deleted are let go, with their files.
    func tidySounds() {
        for clip in model.pruneSounds() { SoundStore.delete(clip, in: model.project.id) }
    }
}
