import Foundation
import Observation

// A movie is a list of scenes played one after another. Each scene is a sprite, so a film is
// drawn, animated and given sound scene by scene in the Studio, and only joined up here. That is
// what lets a film be far longer than one sprite can be: no single sprite holds it all.

/// One scene: a sprite, played through `repeats` times.
struct MovieScene: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var spriteID: UUID
    var repeats = 1

    static let maxRepeats = 999

    init(spriteID: UUID, repeats: Int = 1) {
        self.spriteID = spriteID
        self.repeats = min(max(repeats, 1), Self.maxRepeats)
    }

    private enum CodingKeys: String, CodingKey { case id, spriteID, repeats }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        spriteID = try c.decode(UUID.self, forKey: .spriteID)
        repeats = min(max((try? c.decode(Int.self, forKey: .repeats)) ?? 1, 1), Self.maxRepeats)
    }
}

struct Movie: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var scenes: [MovieScene] = []
    var modifiedAt = Date()

    static let maxNameLength = 40

    init(name: String, scenes: [MovieScene] = []) {
        self.name = name
        self.scenes = scenes
    }

    private enum CodingKeys: String, CodingKey { case id, name, scenes, modifiedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        let raw = ((try? c.decode(String.self, forKey: .name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        name = raw.isEmpty ? "Movie" : String(raw.prefix(Self.maxNameLength))
        // Scene by scene, so one damaged entry doesn't lose the rest.
        scenes = ((try? c.decode([Lossy].self, forKey: .scenes)) ?? []).compactMap(\.scene)
        modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? Date()
    }

    private struct Lossy: Decodable {
        let scene: MovieScene?
        init(from decoder: Decoder) throws { scene = try? MovieScene(from: decoder) }
    }

    // MARK: Editing

    mutating func add(_ spriteID: UUID, at index: Int? = nil) {
        let i = min(max(index ?? scenes.count, 0), scenes.count)
        scenes.insert(MovieScene(spriteID: spriteID), at: i)
    }

    mutating func remove(sceneID: UUID) {
        scenes.removeAll { $0.id == sceneID }
    }

    /// Moves a scene one place earlier (-1) or later (+1).
    mutating func move(sceneID: UUID, by delta: Int) {
        guard let i = scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        let j = i + delta
        guard scenes.indices.contains(j) else { return }
        scenes.swapAt(i, j)
    }

    mutating func setRepeats(_ n: Int, sceneID: UUID) {
        guard let i = scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        scenes[i].repeats = min(max(n, 1), MovieScene.maxRepeats)
    }
}

/// What a movie needs to know about a scene to time it, without keeping the sprite: how long one
/// pass of it lasts, how many passes, and when its sounds start in a pass.
struct SceneTiming: Equatable, Sendable {
    let sceneID: UUID
    let spriteID: UUID
    let passSeconds: Double
    let repeats: Int
    /// Sounds in one pass.
    let cues: [SoundCue]

    var seconds: Double { passSeconds * Double(repeats) }

    init(scene: MovieScene, sprite: SpriteProject) {
        sceneID = scene.id
        spriteID = sprite.id
        passSeconds = sprite.playbackSequence.total
        repeats = scene.repeats
        cues = sprite.soundCues
    }
}

/// A sound starting at a moment in a movie.
struct MovieCue: Equatable, Sendable {
    let spriteID: UUID
    let clipID: UUID
    /// Seconds from the start of the movie.
    let time: Double
    let volume: Double
}

/// Where each scene falls in a movie's running time.
struct MovieTimeline: Equatable, Sendable {
    let scenes: [SceneTiming]
    /// When each scene starts, in seconds from the start of the movie.
    let starts: [Double]
    let seconds: Double

    /// Scenes whose sprite is gone (deleted) or empty are left out.
    init(movie: Movie, sprite: (UUID) -> SpriteProject?) {
        var timings: [SceneTiming] = []
        for scene in movie.scenes {
            guard let s = sprite(scene.spriteID), !s.frames.isEmpty else { continue }
            let t = SceneTiming(scene: scene, sprite: s)
            if t.passSeconds > 0 { timings.append(t) }
        }
        scenes = timings
        var at = 0.0
        var begins: [Double] = []
        for t in timings {
            begins.append(at)
            at += t.seconds
        }
        starts = begins
        seconds = at
    }

    /// The scene showing `time` seconds in, which pass of it, and how far into that pass.
    /// Past the end it is the last moment of the last scene. Nil for an empty movie.
    func position(at time: Double) -> (scene: Int, pass: Int, secondsIntoPass: Double)? {
        guard !scenes.isEmpty else { return nil }
        let t = min(max(time, 0), seconds)
        // The last scene that has started.
        var i = scenes.count - 1
        while i > 0 && starts[i] > t { i -= 1 }
        let scene = scenes[i]
        let into = t - starts[i]
        if into >= scene.seconds {
            return (i, scene.repeats - 1, scene.passSeconds)
        }
        let pass = min(scene.repeats - 1, Int(into / scene.passSeconds))
        return (i, pass, into - Double(pass) * scene.passSeconds)
    }

    /// Every sound in the movie, in the order it starts.
    var cues: [MovieCue] {
        var out: [MovieCue] = []
        for (i, scene) in scenes.enumerated() {
            for pass in 0..<scene.repeats {
                let base = starts[i] + Double(pass) * scene.passSeconds
                for c in scene.cues {
                    out.append(MovieCue(spriteID: scene.spriteID, clipID: c.clipID, time: base + c.time, volume: c.volume))
                }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// "1:05" or "2:03:40".
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }
}

/// Movies saved as JSON files, one per movie, in a folder beside the sprites.
@Observable
final class MovieStore {
    private(set) var movies: [Movie] = []
    let directory: URL
    /// The app swaps in a coordinated (iCloud-safe) write.
    @ObservationIgnored var writeFile: (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }

    init(directory: URL) {
        self.directory = directory
        load()
    }

    func load() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        movies = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Movie.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func movie(id: UUID) -> Movie? { movies.first { $0.id == id } }

    /// A new, empty movie called `baseName` (with a number if that name is taken).
    @discardableResult
    func create(baseName: String) -> Movie {
        let taken = Set(movies.map(\.name))
        var name = baseName, n = 2
        while taken.contains(name) {
            name = "\(baseName) \(n)"
            n += 1
        }
        let movie = Movie(name: name)
        save(movie)
        return movie
    }

    func save(_ movie: Movie) {
        var m = movie
        m.modifiedAt = Date()
        if let i = movies.firstIndex(where: { $0.id == m.id }) { movies[i] = m } else { movies.insert(m, at: 0) }
        if let data = try? JSONEncoder().encode(m) { try? writeFile(data, url(m.id)) }
    }

    func delete(id: UUID) {
        movies.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: url(id))
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
