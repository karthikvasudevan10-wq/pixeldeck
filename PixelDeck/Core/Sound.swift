import Foundation

/// A sound attached to a frame: it starts when playback reaches that frame, and keeps playing
/// for its own length (over the following frames). The audio itself is a file kept beside the
/// sprite; this is the description saved with the sprite.
struct SoundClip: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// The frame it starts on. Kept by the frame's id, so the sound stays with its frame when
    /// frames are added, moved or duplicated around it.
    var frameID: UUID
    /// Length in seconds.
    var duration: Double
    /// 0 (silent) to 1 (as recorded).
    var volume = 1.0
    /// The audio file's type, e.g. "m4a".
    var fileExtension: String

    static let maxPerSprite = 24
    static let maxPerFrame = 4
    /// Longest sound that can be attached, in seconds.
    static let maxSeconds = 600.0
    static let maxBytes = 40_000_000
    static let maxNameLength = 32
}

/// A sound starting at a moment in the animation.
struct SoundCue: Equatable, Sendable {
    let clipID: UUID
    /// Seconds from the start of one pass of the animation.
    let time: Double
    let volume: Double
}

extension SpriteProject {
    /// The sounds on a frame.
    func sounds(onFrame index: Int) -> [SoundClip] {
        guard frames.indices.contains(index) else { return [] }
        let id = frames[index].id
        return sounds.filter { $0.frameID == id }
    }

    /// Sounds whose frame still exists (a deleted frame's sounds linger until the sprite is
    /// closed, so Undo can bring the frame back with its sound).
    var liveSounds: [SoundClip] {
        let ids = Set(frames.map(\.id))
        return sounds.filter { ids.contains($0.frameID) }
    }

    /// When each sound starts during one pass of the animation as it plays: holds, eased timing
    /// and ping-pong are all taken into account (in ping-pong a frame's sound plays each time
    /// the frame comes round).
    var soundCues: [SoundCue] {
        guard !sounds.isEmpty else { return [] }
        let sequence = playbackSequence
        var byFrame: [UUID: [SoundClip]] = [:]
        for s in sounds { byFrame[s.frameID, default: []].append(s) }
        var cues: [SoundCue] = []
        var time = 0.0
        for (step, index) in sequence.frames.enumerated() {
            for clip in byFrame[frames[index].id] ?? [] where clip.volume > 0 {
                cues.append(SoundCue(clipID: clip.id, time: time, volume: clip.volume))
            }
            time += sequence.durations[step]
        }
        return cues
    }
}

extension EditorModel {
    /// The sounds on a frame (the current one by default).
    func sounds(onFrame index: Int? = nil) -> [SoundClip] { project.sounds(onFrame: index ?? currentIndex) }

    func hasSound(onFrame index: Int) -> Bool { !project.sounds(onFrame: index).isEmpty }

    /// Whether another sound can go on this frame.
    func canAddSound(toFrame index: Int) -> Bool {
        project.frames.indices.contains(index) && project.liveSounds.count < SoundClip.maxPerSprite
            && project.sounds(onFrame: index).count < SoundClip.maxPerFrame
    }

    /// Attaches a sound to a frame. The caller has already put the audio file in place under
    /// `clip.id`. Returns false if the frame or the sprite has as many sounds as it can hold.
    @discardableResult
    func addSound(_ clip: SoundClip, toFrame index: Int) -> Bool {
        guard canAddSound(toFrame: index), clip.duration > 0, clip.duration <= SoundClip.maxSeconds else { return false }
        var c = clip
        c.frameID = project.frames[index].id
        c.volume = min(max(c.volume, 0), 1)
        let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        c.name = name.isEmpty ? "Sound" : String(name.prefix(SoundClip.maxNameLength))
        updateProject { $0.sounds.append(c) }
        return true
    }

    func removeSound(_ id: UUID) {
        guard project.sounds.contains(where: { $0.id == id }) else { return }
        updateProject { $0.sounds.removeAll { $0.id == id } }
    }

    func setSoundVolume(_ volume: Double, for id: UUID) {
        guard let i = project.sounds.firstIndex(where: { $0.id == id }) else { return }
        updateProject { $0.sounds[i].volume = min(max(volume, 0), 1) }
    }

    /// Moves a sound to start on another frame.
    func moveSound(_ id: UUID, toFrame index: Int) {
        guard let i = project.sounds.firstIndex(where: { $0.id == id }), project.frames.indices.contains(index) else { return }
        updateProject { $0.sounds[i].frameID = $0.frames[index].id }
    }

    /// Forgets sounds whose frame no longer exists. Returns them, so their files can be removed.
    /// Called when the sprite is closed (not on every delete, so Undo keeps a frame's sound).
    @discardableResult
    func pruneSounds() -> [SoundClip] {
        let live = Set(project.liveSounds.map(\.id))
        let gone = project.sounds.filter { !live.contains($0.id) }
        if !gone.isEmpty { updateProject { $0.sounds.removeAll { !live.contains($0.id) } } }
        return gone
    }
}

/// Mixing sounds into one soundtrack, as plain samples (-1…1) at a fixed rate.
enum AudioMix {
    static let sampleRate = 44_100

    /// Every time a cue should start in a video that repeats the animation `loops` times,
    /// stopping at `total` seconds.
    static func starts(of cues: [SoundCue], loopSeconds: Double, loops: Int, total: Double) -> [SoundCue] {
        guard loopSeconds > 0 else { return [] }
        var out: [SoundCue] = []
        for l in 0..<max(1, loops) {
            for c in cues {
                let t = Double(l) * loopSeconds + c.time
                if t < total { out.append(SoundCue(clipID: c.clipID, time: t, volume: c.volume)) }
            }
        }
        return out
    }

    /// Adds `samples` into `track` starting at sample `start`, at `volume`. Anything past the
    /// end of the track is dropped.
    static func add(_ samples: [Float], into track: inout [Float], at start: Int, volume: Float) {
        guard start < track.count, volume > 0 else { return }
        let from = max(0, -start)
        let count = min(samples.count, track.count - start)
        guard from < count else { return }
        for i in from..<count { track[start + i] += samples[i] * volume }
    }

    /// Keeps the mix from clipping harshly when several sounds overlap: quiet parts are left
    /// alone, and peaks above 0.8 are eased towards 1.
    static func soften(_ track: inout [Float]) {
        for i in track.indices {
            let v = track[i], a = abs(v)
            guard a > 0.8 else { continue }
            let eased = 0.8 + 0.2 * (1 - 1 / (1 + (a - 0.8) * 5))
            track[i] = v < 0 ? -eased : eased
        }
    }
}
