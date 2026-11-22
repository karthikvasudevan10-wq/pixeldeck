import SwiftUI
import UIKit

// Movies: films made of scenes, where every scene is a sprite. A scene is drawn, animated and
// given sound in the Studio like any other sprite; here the scenes are put in order, played
// through, and made into one video.

/// Where movies are kept: beside the sprites (in iCloud when sync is on).
extension MovieStore {
    @MainActor static func forApp() -> MovieStore {
        let base = ImageStore.root
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let store = MovieStore(directory: base.appendingPathComponent("Movies", isDirectory: true))
        store.writeFile = CloudFiles.write
        return store
    }
}

/// The list of movies.
struct MoviesView: View {
    /// Open a scene's sprite in the Studio (the movie screens close first).
    var onEditSprite: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var movies = MovieStore.forApp()
    @State private var editing: Movie?
    @State private var deleting: Movie?
    private var store: ProjectStore { Shared.store }

    // On the Mac in full screen, clear of the title bar the Mac slides down (see `MacTitleBarInset`).
    var body: some View { screen.clearOfMacTitleBar() }

    private var screen: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    PixelIcon.back.view(size: 20, lineWidth: 2.5).frame(width: 44, height: 44)
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .accessibilityLabel("Back")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Movies").font(AppFont.pixel(22)).foregroundStyle(Theme.cream).lineLimit(1)
                    Text("Join your sprites into a film, scene by scene")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(movies.movies) { movie in row(movie) }
                    if movies.movies.isEmpty {
                        VStack(spacing: 10) {
                            PixelIcon.play.view(size: 30).foregroundStyle(Theme.accent2)
                            Text("No movies yet").font(AppFont.pixel(14)).foregroundStyle(Theme.cream)
                            Text("A movie is a list of scenes. Each scene is one of your sprites, with its own frames and sounds. Put them in order and make one video.")
                                .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 460)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }

            Button {
                editing = movies.create(baseName: String(localized: "Movie", comment: "Default name for a new movie; a number is added after it"))
            } label: {
                PrimaryActionLabel(title: "New movie", icon: .plus)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: 760)
        }
        .screenBackground()
        .fullScreenCover(item: $editing, onDismiss: { movies.load() }) { movie in
            MovieEditorView(movie: movie, movies: movies, onEditSprite: onEditSprite)
        }
        .confirmationDialog("Delete this movie?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete movie", role: .destructive) {
                if let m = deleting { movies.delete(id: m.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its scenes stay in your gallery as sprites.")
        }
    }

    private func row(_ movie: Movie) -> some View {
        let timeline = MovieTimeline(movie: movie, sprite: { store.project(id: $0) })
        return HStack(spacing: 12) {
            Button { editing = movie } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Theme.tool
                        if let first = movie.scenes.lazy.compactMap({ store.project(id: $0.spriteID)?.frames.first }).first {
                            PixelImage(frame: first, checker: false).padding(4)
                        } else {
                            PixelIcon.play.view(size: 18).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: movie.name).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream).lineLimit(1)
                        Text("\(timeline.scenes.count) scenes · \(MovieTimeline.clock(timeline.seconds))",
                             comment: "A movie in the list: how many scenes, and its running time; plural")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { deleting = movie } label: {
                PixelIcon.trash.view(size: 18).frame(width: 44, height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.tool, foreground: Theme.muted))
            .accessibilityLabel(Text("Delete \(movie.name)"))
        }
        .padding(10)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }
}

// MARK: Playing a movie

/// Where a movie is in its running time, and whether it is playing.
@MainActor @Observable
final class MoviePlayback {
    private(set) var isPlaying = false
    /// Seconds in, when paused (or when Play was last pressed).
    private(set) var offset = 0.0
    @ObservationIgnored private var startedAt = Date()
    /// Changes whenever the sound has to start again from a new place (play, pause, jump).
    private(set) var changes = 0

    /// Seconds into the movie at `date`.
    func seconds(at date: Date, of total: Double) -> Double {
        min(total, isPlaying ? offset + max(0, date.timeIntervalSince(startedAt)) : offset)
    }

    func play(total: Double) {
        guard total > 0 else { return }
        if offset >= total - 0.01 { offset = 0 }       // at the end: start again
        startedAt = Date()
        isPlaying = true
        changes += 1
    }

    func pause(total: Double) {
        guard isPlaying else { return }
        offset = seconds(at: Date(), of: total)
        isPlaying = false
        changes += 1
    }

    func jump(to seconds: Double, total: Double) {
        offset = min(max(seconds, 0), total)
        startedAt = Date()
        changes += 1
    }

    /// Reached the end.
    func finish() {
        isPlaying = false
        offset = 0
        changes += 1
    }

    // The scene being shown, kept so its timing isn't worked out again for every screen refresh.
    @ObservationIgnored private var keptScene: UUID?
    @ObservationIgnored private var keptVersion = Date.distantPast
    @ObservationIgnored private var keptSequence = PlaybackSequence(frames: [], durations: [])

    func sequence(for scene: SceneTiming, sprite: SpriteProject) -> PlaybackSequence {
        if keptScene != scene.sceneID || keptVersion != sprite.modifiedAt {
            keptScene = scene.sceneID
            keptVersion = sprite.modifiedAt
            keptSequence = sprite.playbackSequence
        }
        return keptSequence
    }
}

/// The picture, Play, the clock and the position slider.
struct MoviePlayerView: View {
    let timeline: MovieTimeline
    let playback: MoviePlayback
    @State private var sound = StudioSoundPlayer()
    private var store: ProjectStore { Shared.store }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playback.isPlaying)) { context in
            let now = playback.seconds(at: context.date, of: timeline.seconds)
            VStack(spacing: 10) {
                ZStack {
                    // The colour behind the art in the finished video.
                    Color(red: 0x12 / 255.0, green: 0x0E / 255.0, blue: 0x1F / 255.0)
                    if let frame = frame(at: now) {
                        PixelImage(frame: frame, checker: false).padding(14)
                    } else {
                        Text("Add a scene to begin").font(AppFont.pixel(12)).foregroundStyle(Theme.muted)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                .accessibilityLabel("Movie preview")

                HStack(spacing: 10) {
                    Button {
                        if playback.isPlaying { playback.pause(total: timeline.seconds) } else { playback.play(total: timeline.seconds) }
                    } label: {
                        (playback.isPlaying ? PixelIcon.pause : PixelIcon.play).view(size: 20).frame(width: 52, height: 44)
                    }
                    .buttonStyle(TileButtonStyle(active: playback.isPlaying, fill: Theme.surface))
                    .disabled(timeline.seconds <= 0)
                    .accessibilityLabel(playback.isPlaying ? Text("Pause") : Text("Play"))
                    Slider(value: Binding(get: { now }, set: { playback.jump(to: $0, total: timeline.seconds) }),
                           in: 0...max(timeline.seconds, 0.01))
                        .tint(Theme.accent)
                        .disabled(timeline.seconds <= 0)
                        .accessibilityLabel("Position in the movie")
                    Text(verbatim: "\(MovieTimeline.clock(now)) / \(MovieTimeline.clock(timeline.seconds))")
                        .font(AppFont.pixel(11)).foregroundStyle(Theme.muted).monospacedDigit()
                        .fixedSize()
                }
            }
        }
        .onChange(of: playback.changes) { _, _ in restartSound() }
        .task(id: playback.changes) { await stopAtTheEnd() }
        .onDisappear {
            playback.pause(total: timeline.seconds)
            sound.stop()
        }
    }

    /// The frame showing `seconds` into the movie.
    private func frame(at seconds: Double) -> Frame? {
        guard let p = timeline.position(at: seconds) else { return nil }
        let scene = timeline.scenes[p.scene]
        guard let sprite = store.project(id: scene.spriteID), !sprite.frames.isEmpty else { return nil }
        let index = playback.sequence(for: scene, sprite: sprite).frame(at: p.secondsIntoPass)
        return sprite.frames[min(max(index, 0), sprite.frames.count - 1)]
    }

    /// Sounds from where the movie is now, or silence when it is paused.
    private func restartSound() {
        sound.stop()
        guard playback.isPlaying else { return }
        let from = playback.seconds(at: Date(), of: timeline.seconds)
        var cues: [SoundCue] = []
        var files: [UUID: URL] = [:]
        for cue in timeline.cues where cue.time >= from - 0.02 {
            guard let clip = store.project(id: cue.spriteID)?.sounds.first(where: { $0.id == cue.clipID }),
                  let url = SoundStore.url(for: clip, in: cue.spriteID) else { continue }
            files[cue.clipID] = url
            cues.append(SoundCue(clipID: cue.clipID, time: max(0, cue.time - from), volume: cue.volume))
        }
        sound.play(cues: cues, files: files, total: max(0.01, timeline.seconds - from), repeats: false)
    }

    private func stopAtTheEnd() async {
        guard playback.isPlaying else { return }
        let change = playback.changes
        let left = timeline.seconds - playback.seconds(at: Date(), of: timeline.seconds)
        try? await Task.sleep(for: .seconds(max(0, left) + 0.05))
        if !Task.isCancelled, playback.isPlaying, playback.changes == change { playback.finish() }
    }
}

// MARK: Editing a movie

struct MovieEditorView: View {
    @State private var movie: Movie
    let movies: MovieStore
    var onEditSprite: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playback = MoviePlayback()
    @State private var adding = false
    @State private var exporting = false
    @State private var renaming = false
    @State private var renameText = ""
    private var store: ProjectStore { Shared.store }

    init(movie: Movie, movies: MovieStore, onEditSprite: @escaping (UUID) -> Void) {
        _movie = State(initialValue: movie)
        self.movies = movies
        self.onEditSprite = onEditSprite
    }

    // On the Mac in full screen, clear of the title bar the Mac slides down (see `MacTitleBarInset`).
    var body: some View { screen.clearOfMacTitleBar() }

    private var screen: some View {
        let timeline = MovieTimeline(movie: movie, sprite: { store.project(id: $0) })
        return VStack(spacing: 0) {
            header(timeline)
            GeometryReader { geo in
                if geo.size.width > 820 {
                    // Wide (Mac, iPad): the picture on the left, the scenes on the right.
                    HStack(alignment: .top, spacing: 20) {
                        MoviePlayerView(timeline: timeline, playback: playback)
                            .frame(maxWidth: geo.size.width * 0.55)
                        ScrollView { sceneList(timeline) }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            MoviePlayerView(timeline: timeline, playback: playback)
                            sceneList(timeline)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            HStack(spacing: 10) {
                Button { adding = true } label: {
                    HStack(spacing: 8) {
                        PixelIcon.plus.view(size: 18, lineWidth: 2.5)
                        Text("Add scenes").font(AppFont.pixel(14))
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                Button {
                    playback.pause(total: timeline.seconds)
                    exporting = true
                } label: {
                    PrimaryActionLabel(title: "Make the video", icon: .export)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(timeline.scenes.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .sheet(isPresented: $adding) {
            MovieScenePicker { id in change { $0.add(id) } }
        }
        .sheet(isPresented: $exporting) {
            MovieExportSheet(movie: movie)
        }
        .alert("Name this movie", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { change { $0.name = String(name.prefix(Movie.maxNameLength)) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func header(_ timeline: MovieTimeline) -> some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                PixelIcon.back.view(size: 20, lineWidth: 2.5).frame(width: 44, height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .accessibilityLabel("Back")
            Button {
                renameText = movie.name
                renaming = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: movie.name).font(AppFont.pixel(18)).foregroundStyle(Theme.cream).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(timeline.scenes.count) scenes · \(MovieTimeline.clock(timeline.seconds)) · tap to rename",
                         comment: "Under a movie's name: how many scenes and its running time; plural")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Renames the movie")
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Changes the movie, saves it, and stops playback (the running time may have changed).
    private func change(_ body: (inout Movie) -> Void) {
        let total = MovieTimeline(movie: movie, sprite: { store.project(id: $0) }).seconds
        playback.pause(total: total)
        body(&movie)
        movies.save(movie)
    }

    private func sceneList(_ timeline: MovieTimeline) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Scenes, in order")
            if movie.scenes.isEmpty {
                Text("Nothing here yet. Add the sprites that make up your film; each one plays through, then the next begins.")
                    .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    .padding(.vertical, 8)
            }
            ForEach(Array(movie.scenes.enumerated()), id: \.element.id) { index, scene in
                sceneRow(scene, number: index + 1, timeline: timeline)
            }
        }
        .padding(.bottom, 12)
    }

    private func sceneRow(_ scene: MovieScene, number: Int, timeline: MovieTimeline) -> some View {
        let sprite = store.project(id: scene.spriteID)
        let placed = timeline.scenes.firstIndex { $0.sceneID == scene.id }
        return HStack(spacing: 10) {
            Button {
                if let placed { playback.jump(to: timeline.starts[placed], total: timeline.seconds) }
            } label: {
                HStack(spacing: 10) {
                    Text(verbatim: "\(number)").font(AppFont.pixel(11)).foregroundStyle(Theme.muted).frame(width: 26)
                    ZStack {
                        Theme.tool
                        if let frame = sprite?.frames.first {
                            PixelImage(frame: frame, checker: false).padding(3)
                        } else {
                            PixelIcon.trash.view(size: 16).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: sprite?.name ?? String(localized: "Deleted sprite"))
                            .font(AppFont.body(15, .bold, relativeTo: .body))
                            .foregroundStyle(sprite == nil ? Theme.muted : Theme.cream).lineLimit(1)
                        if let placed {
                            Text("\(sprite?.frames.count ?? 0) frames · \(MovieTimeline.clock(timeline.scenes[placed].seconds))",
                                 comment: "A scene in a movie: its frames and how long it plays; plural")
                                .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(1)
                        } else {
                            Text("Left out of the movie").font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows this scene in the preview")

            // How many times the scene plays through.
            HStack(spacing: 2) {
                Button { change { $0.setRepeats(scene.repeats - 1, sceneID: scene.id) } } label: {
                    Text(verbatim: "−").font(AppFont.pixel(14)).frame(width: 34, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(fill: Theme.tool))
                .disabled(scene.repeats <= 1)
                .accessibilityLabel("Play it one time fewer")
                Text(verbatim: "×\(scene.repeats)").font(AppFont.pixel(11)).foregroundStyle(Theme.text).frame(minWidth: 38)
                    .accessibilityLabel(Text("Plays \(scene.repeats) times"))
                Button { change { $0.setRepeats(scene.repeats + 1, sceneID: scene.id) } } label: {
                    Text(verbatim: "+").font(AppFont.pixel(14)).frame(width: 34, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(fill: Theme.tool))
                .disabled(scene.repeats >= MovieScene.maxRepeats)
                .accessibilityLabel("Play it one more time")
            }

            Menu {
                if sprite != nil {
                    Button { onEditSprite(scene.spriteID) } label: { Label("Edit in the Studio", systemImage: "pencil") }
                }
                Button { change { $0.move(sceneID: scene.id, by: -1) } } label: { Label("Move earlier", systemImage: "arrow.up") }
                    .disabled(number == 1)
                Button { change { $0.move(sceneID: scene.id, by: 1) } } label: { Label("Move later", systemImage: "arrow.down") }
                    .disabled(number == movie.scenes.count)
                Button(role: .destructive) { change { $0.remove(sceneID: scene.id) } } label: {
                    Label("Remove from the movie", systemImage: "minus.circle")
                }
            } label: {
                PixelIcon.more.view(size: 18).foregroundStyle(Theme.text).frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .accessibilityLabel(Text("More for scene \(number)"))
        }
        .padding(8)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }
}

/// Choose sprites to add as scenes. It stays open, so several can be added in a row.
struct MovieScenePicker: View {
    var onAdd: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var added = 0
    @State private var search = ""
    private var store: ProjectStore { Shared.store }

    var body: some View {
        let q = search.trimmingCharacters(in: .whitespaces)
        let sprites = store.projects.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
        return VStack(spacing: 0) {
            SheetHeader(title: "Add scenes", onClose: { dismiss() })
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search your sprites", text: $search)
                    .font(AppFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(Theme.tool)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 10)], spacing: 10) {
                    ForEach(sprites) { sprite in
                        Button {
                            onAdd(sprite.id)
                            added += 1
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Theme.tool
                                    if let frame = sprite.frames.first { PixelImage(frame: frame, checker: false).padding(8) }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                Text(verbatim: sprite.name).font(AppFont.body(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.cream).lineLimit(1)
                                Text("\(sprite.frames.count) frames", comment: "Under a sprite in the scene chooser; plural")
                                    .font(AppFont.body(11, relativeTo: .caption2)).foregroundStyle(Theme.muted)
                            }
                            .padding(6)
                            .background(Theme.surface)
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Add \(sprite.name)"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            (added == 0 ? Text("Tap a sprite to add it as the next scene.") : Text("\(added) added. Tap more, or close.", comment: "Scene chooser; plural"))
                .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                .padding(.bottom, 14)
        }
        .screenBackground()
    }
}

// MARK: Making the video

struct MovieExportSheet: View {
    let movie: Movie

    @Environment(\.dismiss) private var dismiss
    @State private var size: MovieSize = .hd
    @State private var control: MovieExporter.Control?
    @State private var finished: URL?
    @State private var note: String?
    @State private var shareItems: ShareItems?
    @State private var saving = false
    @State private var upgrade: ProFeature?
    private var store: ProjectStore { Shared.store }
    private var purchases: PurchaseManager { Shared.purchases }

    var body: some View {
        let timeline = MovieTimeline(movie: movie, sprite: { store.project(id: $0) })
        return VStack(spacing: 0) {
            SheetHeader(title: "Make the video", onClose: {
                control?.cancel()
                dismiss()
            })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(timeline.scenes.count) scenes · \(MovieTimeline.clock(timeline.seconds)) · every scene's sounds included",
                         comment: "Movie export: scenes and running time; plural")
                        .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Shape")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                            ForEach(MovieSize.allCases) { option in
                                let on = size == option
                                Button {
                                    if option == .fourK && !purchases.isPro { upgrade = .largeExport } else { size = option }
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(title(option)).font(AppFont.pixel(12))
                                        Text(verbatim: "\(option.width) × \(option.height)").font(AppFont.body(11, relativeTo: .caption2))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .overlay(alignment: .topTrailing) {
                                        if option == .fourK && !purchases.isPro { ProBadge().scaleEffect(0.75).offset(x: 4, y: -4) }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(TileButtonStyle(active: on, fill: Theme.surface))
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .disabled(control != nil)
                    }

                    if !purchases.isPro {
                        Text("The free version adds a small \"Made with Pixel Deck\" band along the bottom.")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }

                    if let control, finished == nil {
                        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: control.fraction).tint(Theme.accent)
                                Text("Making the video… \(Int(control.fraction * 100))%", comment: "Movie export progress")
                                    .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if let note {
                        Text(verbatim: note).font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.cream)
                    }
                }
                .padding(16)
            }

            VStack(spacing: 8) {
                if let finished {
                    HStack(spacing: 8) {
                        Button { shareItems = ShareItems(urls: [finished]) } label: {
                            Text("Share").font(AppFont.pixel(14)).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(TileButtonStyle(fill: Theme.surface))
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                        Button { saving = true } label: {
                            Text("Save as a file").font(AppFont.pixel(14)).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(TileButtonStyle(fill: Theme.surface))
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                    }
                    Button { saveToPhotos(finished) } label: {
                        PrimaryActionLabel(title: "Save to Photos", icon: .download)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if control != nil {
                    Button {
                        control?.cancel()
                    } label: {
                        Text("Stop").font(AppFont.pixel(14)).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle(fill: Theme.surface))
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                } else {
                    Button { start() } label: {
                        PrimaryActionLabel(title: "Make the video", icon: .export)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(timeline.scenes.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .interactiveDismissDisabled(control != nil && finished == nil)
        .proUpgradeSheet($upgrade)
        .sheet(item: $shareItems) { items in
            ActivityView(items: items.urls) { _ in shareItems = nil }
        }
        .fileMover(isPresented: $saving, file: finished) { result in
            if case .success = result {
                finished = nil
                control = nil
                note = String(localized: "Saved.")
            }
        }
    }

    private func title(_ size: MovieSize) -> LocalizedStringKey {
        switch size {
        case .hd: "Widescreen"
        case .square: "Square"
        case .vertical: "Tall"
        case .fourK: "4K"
        }
    }

    private func start() {
        note = nil
        finished = nil
        let control = MovieExporter.Control()
        self.control = control
        // What the work needs, gathered here: the sprites of this movie's scenes, and where
        // their sound files are.
        var sprites: [UUID: SpriteProject] = [:]
        var files: [UUID: URL] = [:]
        for scene in movie.scenes {
            guard sprites[scene.spriteID] == nil, let sprite = store.project(id: scene.spriteID) else { continue }
            sprites[sprite.id] = sprite
            for clip in sprite.sounds {
                if let url = SoundStore.url(for: clip, in: sprite.id) { files[clip.id] = url }
            }
        }
        let movie = movie, size = size, watermark = !purchases.isPro
        let safeName = movie.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-\(UUID().uuidString.prefix(6)).mp4")
        Task {
            // The work is done off the main thread; the screen hears the result back here.
            let outcome: Result<Bool, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try MovieExporter.write(movie: movie, sprite: { sprites[$0] }, soundFile: { clip, _ in files[clip.id] },
                                                            size: size, watermark: watermark, to: url, control: control))
                } catch {
                    return .failure(error)
                }
            }.value
            switch outcome {
            case .success(let soundAdded):
                finished = url
                note = soundAdded ? String(localized: "Your video is ready.")
                    : String(localized: "Your video is ready, but its sound couldn't be added.")
            case .failure(let error):
                self.control = nil
                note = error is MovieExporter.Cancelled ? String(localized: "Stopped.") : error.localizedDescription
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        Task {
            do {
                try await PhotoSaver.save([url])
                note = String(localized: "Saved to Photos.")
            } catch {
                note = error.localizedDescription
            }
        }
    }
}
