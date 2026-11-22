import XCTest
@testable import PixelDeckCore

final class MovieTests: XCTestCase {
    /// A sprite with `frames` frames at `fps`.
    private func sprite(frames: Int, fps: Int, name: String = "S") -> SpriteProject {
        let grids = (0..<frames).map { _ in PixelGrid(width: 4, height: 4) }
        return SpriteProject(name: name, bounds: PixelRect(x: 0, y: 0, width: 4, height: 4), frames: grids, fps: fps)
    }

    func testScenesPlayOneAfterAnother() {
        let a = sprite(frames: 4, fps: 4)           // 1 second
        var b = sprite(frames: 6, fps: 60)          // 0.1 second
        b.frames[0].hold = 55                       // now 1 second (54 more sixtieths)
        var movie = Movie(name: "Film")
        movie.add(a.id)
        movie.add(b.id)
        movie.setRepeats(3, sceneID: movie.scenes[0].id)
        let sprites = [a.id: a, b.id: b]
        let line = MovieTimeline(movie: movie, sprite: { sprites[$0] })
        XCTAssertEqual(line.scenes.count, 2)
        XCTAssertEqual(line.starts[0], 0)
        XCTAssertEqual(line.starts[1], 3, accuracy: 1e-9)
        XCTAssertEqual(line.seconds, 4, accuracy: 1e-9)

        let early = line.position(at: 1.25)!
        XCTAssertEqual(early.scene, 0)
        XCTAssertEqual(early.pass, 1)
        XCTAssertEqual(early.secondsIntoPass, 0.25, accuracy: 1e-9)
        // The frame showing then: the second of four (each lasts a quarter of a second).
        XCTAssertEqual(a.playbackSequence.frame(at: early.secondsIntoPass), 1)

        let late = line.position(at: 3.5)!
        XCTAssertEqual(late.scene, 1)
        XCTAssertEqual(late.pass, 0)
        XCTAssertEqual(late.secondsIntoPass, 0.5, accuracy: 1e-9)

        // Before the start and after the end stay inside the movie.
        XCTAssertEqual(line.position(at: -5)!.scene, 0)
        let end = line.position(at: 99)!
        XCTAssertEqual(end.scene, 1)
        XCTAssertEqual(end.secondsIntoPass, 1, accuracy: 1e-9)
    }

    func testMissingAndEmptyScenesAreLeftOut() {
        let a = sprite(frames: 2, fps: 2)
        var movie = Movie(name: "Film")
        movie.add(UUID())                           // a sprite that was deleted
        movie.add(a.id)
        let line = MovieTimeline(movie: movie, sprite: { $0 == a.id ? a : nil })
        XCTAssertEqual(line.scenes.map(\.spriteID), [a.id])
        XCTAssertEqual(line.seconds, 1, accuracy: 1e-9)
        XCTAssertNil(MovieTimeline(movie: Movie(name: "Empty"), sprite: { _ in nil }).position(at: 0))
    }

    func testSoundsStartWhenTheirSceneComesRound() {
        var a = sprite(frames: 4, fps: 4)
        let clip = SoundClip(name: "Boing", frameID: a.frames[2].id, duration: 0.3, fileExtension: "m4a")
        a.sounds = [clip]
        let b = sprite(frames: 2, fps: 2)
        var movie = Movie(name: "Film")
        movie.add(b.id)                             // 1 second, no sound
        movie.add(a.id)                             // sound half a second into each pass
        movie.setRepeats(2, sceneID: movie.scenes[1].id)
        let sprites = [a.id: a, b.id: b]
        let cues = MovieTimeline(movie: movie, sprite: { sprites[$0] }).cues
        XCTAssertEqual(cues.map(\.clipID), [clip.id, clip.id])
        XCTAssertEqual(cues[0].time, 1.5, accuracy: 1e-9)
        XCTAssertEqual(cues[1].time, 2.5, accuracy: 1e-9)
        XCTAssertEqual(cues[0].spriteID, a.id)
    }

    func testEditingScenes() {
        var movie = Movie(name: "Film")
        let ids = [UUID(), UUID(), UUID()]
        ids.forEach { movie.add($0) }
        movie.move(sceneID: movie.scenes[2].id, by: -1)
        XCTAssertEqual(movie.scenes.map(\.spriteID), [ids[0], ids[2], ids[1]])
        movie.move(sceneID: movie.scenes[0].id, by: -1)          // already first: nothing happens
        XCTAssertEqual(movie.scenes.first?.spriteID, ids[0])
        movie.setRepeats(5000, sceneID: movie.scenes[0].id)
        XCTAssertEqual(movie.scenes[0].repeats, MovieScene.maxRepeats)
        movie.remove(sceneID: movie.scenes[1].id)
        XCTAssertEqual(movie.scenes.map(\.spriteID), [ids[0], ids[1]])
        // The same sprite can be a scene twice.
        movie.add(ids[0])
        XCTAssertEqual(movie.scenes.count, 3)
        XCTAssertNotEqual(movie.scenes[0].id, movie.scenes[2].id)
    }

    func testADamagedSceneDoesNotLoseTheMovie() throws {
        let good = UUID()
        let json = """
        {"id":"\(UUID().uuidString)","name":"   ","scenes":[{"spriteID":"\(good.uuidString)","repeats":-4},{"nonsense":1}]}
        """
        let movie = try JSONDecoder().decode(Movie.self, from: Data(json.utf8))
        XCTAssertEqual(movie.name, "Movie")
        XCTAssertEqual(movie.scenes.map(\.spriteID), [good])
        XCTAssertEqual(movie.scenes[0].repeats, 1)
    }

    func testMoviesAreSavedAndLoaded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("movies-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MovieStore(directory: folder)
        var first = store.create(baseName: "Movie")
        XCTAssertEqual(store.create(baseName: "Movie").name, "Movie 2")
        first.add(UUID())
        store.save(first)
        let again = MovieStore(directory: folder)
        XCTAssertEqual(again.movies.count, 2)
        XCTAssertEqual(again.movie(id: first.id)?.scenes.count, 1)
        again.delete(id: first.id)
        XCTAssertEqual(MovieStore(directory: folder).movies.map(\.name), ["Movie 2"])
    }

    func testClock() {
        XCTAssertEqual(MovieTimeline.clock(0), "0:00")
        XCTAssertEqual(MovieTimeline.clock(65), "1:05")
        XCTAssertEqual(MovieTimeline.clock(3 * 3600 + 4 * 60 + 9), "3:04:09")
    }

    func testMixingASoundtrackAPieceAtATime() {
        // A sound of four samples starting at sample 6 of the soundtrack, mixed in pieces of 4.
        let sound: [Float] = [1, 2, 3, 4]
        var whole: [Float] = []
        for windowStart in stride(from: 0, to: 12, by: 4) {
            var window = [Float](repeating: 0, count: 4)
            AudioMix.add(sound, startingAt: 6, intoWindow: &window, windowStart: windowStart, volume: 0.5)
            whole += window
        }
        XCTAssertEqual(whole, [0, 0, 0, 0, 0, 0, 0.5, 1, 1.5, 2, 0, 0])
    }
}
