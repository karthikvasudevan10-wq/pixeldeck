import SwiftUI
import UniformTypeIdentifiers

/// Level files: a scene saved as JSON with its own extension, for sending to family and friends.
enum LevelFile {
    static let fileExtension = "pixeldecklevel"
    static var contentTypes: [UTType] {
        var types: [UTType] = [.json]
        if let own = UTType(filenameExtension: fileExtension) { types.append(own) }
        return types
    }

    /// Writes the level to a temporary file, ready to share.
    static func export(_ scene: TileScene) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = scene.name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == " " ? $0 : "_" }
        let name = String(safe).trimmingCharacters(in: .whitespaces)
        let url = dir.appendingPathComponent(name.isEmpty ? "Level" : name).appendingPathExtension(fileExtension)
        guard let data = try? JSONEncoder().encode(scene) else { return nil }
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    /// Reads a level someone sent. It gets a new id, so it never replaces one of your own.
    static func read(_ url: URL) -> TileScene? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count < 8_000_000,
              var scene = try? JSONDecoder().decode(TileScene.self, from: data) else { return nil }
        scene.id = UUID()
        scene.heroID = nil
        return scene
    }
}

/// The Play tab: your Playground levels and tile scenes.
struct PlaygroundHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @State private var store = SceneStore.forApp()
    @State private var editing: TileScene?
    @State private var playing: TileScene?
    @State private var sharing: TileScene?
    @State private var deleting: TileScene?
    @State private var importing = false
    @State private var message: String?
    @State private var showingCommunity = false
    /// A level file to open straight away (opened from Files or Messages).
    var incoming: URL? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    PixelIcon.back.view(size: 20, lineWidth: 2.5).frame(width: 44, height: 44)
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .accessibilityLabel("Back")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playground").font(AppFont.pixel(22)).foregroundStyle(Theme.cream)
                    Text("Make your sprite the hero of a level").font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 12)], spacing: 12) {
                    Button(action: newLevel) {
                        HStack(spacing: 12) {
                            PixelIcon.plus.view(size: 22, lineWidth: 3)
                                .foregroundStyle(Theme.onAccent2)
                                .frame(width: 48, height: 48)
                                .background(Theme.accent2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New level").font(AppFont.pixel(14)).foregroundStyle(Theme.accent2)
                                Text("Starts with hills, a pond and five coins").font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .overlay(Rectangle().strokeBorder(Theme.accent2, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(store.scenes) { scene in card(scene) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                VStack(spacing: 8) {
                    Button { importing = true } label: {
                        Text("Open a level someone sent you…").font(AppFont.body(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.accent2)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    Button { showingCommunity = true } label: {
                        Text("Find levels in Community").font(AppFont.body(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.accent2)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    if let message {
                        Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .screenBackground()
        .onAppear {
            if let incoming { open(incoming) }
        }
        .fullScreenCover(item: $editing, onDismiss: { store.load() }) { SceneEditorView(scene: $0, store: store) }
        .fullScreenCover(item: $playing) { PlaygroundPlayView(scene: $0) }
        .fullScreenCover(isPresented: $showingCommunity) { CommunityView() }
        .sheet(item: $sharing) { ShareLevelSheet(scene: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: LevelFile.contentTypes, allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { open(url) }
        }
        .confirmationDialog("Delete this level?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let d = deleting { store.delete(id: d.id) } }
        } message: {
            Text("Its tiles and layout are removed. This can't be undone.")
        }
    }

    private func card(_ scene: TileScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { editing = scene } label: {
                ZStack {
                    scene.sky.color
                    PixelImage(image: PlayArt.thumbnail(scene))
                }
                .frame(height: 150)
                .clipped()
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit \(scene.name)"))
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: scene.name).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream).lineLimit(1)
                    Text("Starring \(scene.heroName ?? String(localized: "Slime")) · \(scene.coins.count) coins",
                         comment: "Level summary: the hero's name, and the number of coins (plural)")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Menu {
                    Button { editing = scene } label: { Label("Edit", systemImage: "pencil") }
                    Button { sharing = scene } label: { Label("Share level…", systemImage: "square.and.arrow.up") }
                    Button {
                        var copy = scene
                        copy.id = UUID()
                        copy.name = String(localized: "\(scene.name) copy", comment: "Name for a duplicated sprite; the placeholder is the original name")
                        store.save(copy)
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { deleting = scene } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    PixelIcon.more.view(size: 20).foregroundStyle(Theme.muted).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(Text("More for \(scene.name)"))
                Button { playing = scene } label: {
                    HStack(spacing: 6) {
                        PixelIcon.play.view(size: 14, lineWidth: 2.5)
                        Text("Play").font(AppFont.pixel(13))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                }
                .buttonStyle(PrimaryButtonStyle(depth: 4))
            }
        }
        .padding(10)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }

    private func newLevel() {
        let scene = TileScene.starter(name: String(localized: "Level \(store.scenes.count + 1)", comment: "Default name for a new Playground level"))
        store.save(scene)
        editing = scene
    }

    private func open(_ url: URL) {
        guard let scene = LevelFile.read(url) else {
            message = String(localized: "That file isn't a Pixel Deck level.")
            return
        }
        // Levels with Pro extras still open; the extras stay off until Pro.
        store.save(scene)
        message = nil
        playing = scene
    }
}

/// Share a level: post it to Community, send the file, or record a run.
struct ShareLevelSheet: View {
    let scene: TileScene
    @Environment(\.dismiss) private var dismiss
    @State private var posting = false
    @State private var fileItems: ShareItems?
    @State private var recording = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Share your level", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        scene.sky.color
                        PixelImage(image: PlayArt.thumbnail(scene))
                    }
                    .frame(height: 150)
                    .clipped()
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: scene.name).font(AppFont.body(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                        Text("Starring \(scene.heroName ?? String(localized: "Slime")) · \(scene.coins.count) coins",
                             comment: "Level summary: the hero's name, and the number of coins (plural)")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }
                    row("Post to Community", "Others play it with your hero. Remixes credit you.", icon: .community) { posting = true }
                    row("Send to family", "As a file, by AirDrop or Messages. No account needed to play.", icon: .share) {
                        if let url = LevelFile.export(scene) { fileItems = ShareItems(urls: [url]) }
                        else { message = String(localized: "Couldn't make the level file.") }
                    }
                    row("Record a run", "A video of you playing it, to share when you win", icon: .play) { recording = true }
                    if let message {
                        Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(16)
            }
        }
        .screenBackground()
        .presentationDetents([.large])
        .sheet(isPresented: $posting) { ShareToCommunityView(project: Self.poster(for: scene), level: scene) }
        .sheet(item: $fileItems) { items in ActivityView(items: items.urls) { _ in fileItems = nil }.ignoresSafeArea() }
        .fullScreenCover(isPresented: $recording) { PlaygroundPlayView(scene: scene, recordRun: true) }
    }

    /// The picture a level post shows in the feed: the whole scene (or the part that fits a post).
    static func poster(for scene: TileScene) -> SpriteProject {
        let picture = scene.rendered()
        let w = min(picture.width, PostArt.maxSide), h = min(picture.height, PostArt.maxSide)
        let cropped = picture.reframed(from: picture.rect, to: PixelRect(x: 0, y: 0, width: w, height: h))
        return SpriteProject(name: scene.name, bounds: PixelRect(x: -w / 2, y: -h / 2, width: w, height: h), frames: [cropped], fps: 8)
    }

    private func row(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, icon: PixelIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon.view(size: 22).foregroundStyle(Theme.accent).frame(width: 44, height: 44).background(Theme.tool)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                    Text(detail).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
