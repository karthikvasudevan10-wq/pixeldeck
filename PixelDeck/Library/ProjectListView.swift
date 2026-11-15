import SwiftUI

/// Home: every sprite as a live, looping tile; "New canvas" first. Moving / Stills splits
/// animations from single-frame pictures.
struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("starterSpritesAdded") private var starterSpritesAdded = false
    @State private var path: [UUID] = []
    @State private var filter: GalleryFilter = .moving
    @State private var showingWelcome = false
    @State private var showingSettings = false
    @State private var exporting: SpriteProject?
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var deletingID: UUID?

    enum GalleryFilter: Hashable { case moving, stills }

    /// Preview tile backgrounds from the design, cycled.
    static let tileColors: [Color] = [
        Theme.dynamic(0x2B1F47, 0xEAE2F5), Theme.dynamic(0x3A1F2E, 0xF6E2E8), Theme.dynamic(0x3A321C, 0xF4ECD6),
        Theme.dynamic(0x1F3340, 0xDEEAF0), Theme.dynamic(0x1F3A2A, 0xDFECE1), Theme.dynamic(0x171129, 0xE8E3EF),
    ].map { Color(uiColor: $0) }

    /// Live previews run only while the gallery is actually on screen — not under the Studio,
    /// the welcome screens or export, and not in the background.
    private var galleryVisible: Bool {
        path.isEmpty && !showingWelcome && exporting == nil && !showingSettings && scenePhase == .active
    }

    private var filtered: [SpriteProject] {
        store.projects.filter { filter == .moving ? $0.frames.count > 1 : $0.frames.count == 1 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    // Two columns on iPhone (as designed); more on iPad as the width allows.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 165, maximum: 260), spacing: 12)], spacing: 12) {
                        newCanvasTile
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, project in
                            NavigationLink(value: project.id) {
                                ProjectTile(project: project, tile: Self.tileColors[i % Self.tileColors.count],
                                            animating: galleryVisible)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: project) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    if filtered.isEmpty {
                        Text(filter == .moving ? "Animations you make show up here." : "Single-frame pictures show up here.")
                            .font(AppFont.body(14, relativeTo: .subheadline))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 8)
                    }
                }
                // The design: "or swipe right anywhere" to start a new canvas.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40).onEnded { v in
                        if v.translation.width > 110 && abs(v.translation.height) < 60 { createAndOpen() }
                    }
                )
                bottomBar
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let project = store.project(id: id) {
                    EditorView(project: project)
                }
            }
        }
        .onAppear(perform: firstLaunch)
        .onChange(of: path) { _, newPath in
            // Back from the Studio: show the tab holding the sprite you just worked on.
            if newPath.isEmpty, let recent = store.projects.first {
                filter = recent.frames.count > 1 ? .moving : .stills
            }
        }
        .fullScreenCover(isPresented: $showingWelcome) {
            WelcomeFlow {
                showingWelcome = false
                createAndOpen()
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .fullScreenCover(item: $exporting) { ExportView(project: $0) }
        .alert("Rename sprite", isPresented: Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let id = renamingID { store.rename(id: id, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this sprite?", isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deletingID {
                    store.delete(id: id)
                    ImageStore.deleteAll(for: id)
                }
            }
        } message: {
            Text("All of its frames will be removed. This can't be undone.")
        }
        .alert("Couldn't save your sprite", isPresented: Binding(get: { store.saveFailed }, set: { if !$0 { store.acknowledgeSaveFailure() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your device may be out of storage. Free up some space; your last saved version is safe, and Pixel Deck will keep trying as you edit.")
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gallery").font(AppFont.pixel(30)).foregroundStyle(Theme.cream)
                Group {
                    if filter == .moving {
                        Text("\(filtered.count) animations", comment: "Gallery count (plural)")
                    } else {
                        Text("\(filtered.count) stills", comment: "Gallery count of single-frame sprites (plural)")
                    }
                }
                .font(AppFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { showingSettings = true } label: {
                PixelIcon.settings.view(size: 20).frame(width: 42, height: 42)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface, foreground: Theme.muted))
            .accessibilityLabel("Settings")
            HStack(spacing: 0) {
                tab("Moving", .moving)
                tab("Stills", .stills)
            }
            .padding(3)
            .background(Theme.surface)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private func tab(_ title: LocalizedStringKey, _ f: GalleryFilter) -> some View {
        let on = filter == f
        return Button { filter = f } label: {
            Text(title)
                .font(AppFont.pixel(11))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle(active: on, fill: .clear, foreground: Theme.muted))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var newCanvasTile: some View {
        Button(action: createAndOpen) {
            VStack(spacing: 10) {
                PixelIcon.plus.view(size: 24, lineWidth: 3)
                    .foregroundStyle(Theme.onAccent2)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent2)
                    .background(alignment: .top) { Theme.accent2Shadow.offset(y: 4) }
                    .padding(.bottom, 4)
                Text("New canvas").font(AppFont.pixel(14)).foregroundStyle(Theme.accent2)
                Text("or swipe right anywhere")
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 202)
            .overlay(Rectangle().strokeBorder(Theme.accent2, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack {
            barItem(.gallery, "Gallery", color: Theme.accent) {}
                .accessibilityAddTraits(.isSelected)
            Button(action: createAndOpen) {
                PixelIcon.create.view(size: 24, lineWidth: 2.5).frame(width: 56, height: 56)
            }
            .buttonStyle(PrimaryButtonStyle(depth: 5))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Create")
            barItem(.export, "Export", color: Theme.muted) { exporting = store.projects.first }
                .disabled(store.projects.isEmpty)
        }
        .frame(height: 76)
        .background(Theme.ink.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Theme.line.frame(height: 2) }
    }

    private func barItem(_ icon: PixelIcon, _ title: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon.view(size: 22)
                Text(title).font(AppFont.pixel(10))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menu(for project: SpriteProject) -> some View {
        Button {
            renameText = project.name
            renamingID = project.id
        } label: { Label("Rename", systemImage: "pencil") }
        Button {
            if let copy = store.duplicate(id: project.id, name: { String(localized: "\($0) copy", comment: "Name for a duplicated sprite; the placeholder is the original name") }) {
                ImageStore.copyAll(from: project.id, to: copy.id)
            }
        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { exporting = project } label: { Label("Export", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { deletingID = project.id } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: Actions

    private func createAndOpen() {
        let project = store.create(baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it"))
        path = [project.id]
    }

    /// First launch: the starter sprites go into the gallery, and the welcome screens show.
    private func firstLaunch() {
        if !starterSpritesAdded {
            starterSpritesAdded = true
            let names: [String: String] = [
                "slime": String(localized: "Slime bounce", comment: "Starter sprite name"),
                "flame": String(localized: "Campfire", comment: "Starter sprite name"),
                "coin": String(localized: "Lucky coin", comment: "Starter sprite name"),
                "ghost": String(localized: "Boo!", comment: "Starter sprite name"),
                "sprout": String(localized: "Sprout", comment: "Starter sprite name"),
                "moon": String(localized: "Moon", comment: "Starter sprite name"),
            ]
            let starters = CharacterSpriteLibrary.order.compactMap { key in
                StarterArt.sprite(key)?.makeProject(name: names[key] ?? key)
            }
            if store.projects.isEmpty { store.add(starters) }
        }
        if !hasSeenOnboarding {
            hasSeenOnboarding = true
            showingWelcome = true
        }
    }
}

/// A gallery tile: the animation looping live (frame 0 with Reduce Motion), its frame rate, name,
/// frame count and art size.
private struct ProjectTile: View {
    let project: SpriteProject
    let tile: Color
    var animating = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sizeText: String {
        let r = ArtSizeCache.size(of: project)
        return "\(r.width)×\(r.height)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                tile
                preview.padding(18)
                Text(verbatim: "\(project.fps) fps")
                    .font(AppFont.pixel(10))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.ink.opacity(0.75))
                    .padding(8)
            }
            .frame(height: 148)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(AppFont.body(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                Text("\(project.frames.count) frames · \(sizeText)", comment: "Gallery tile: frame count (plural) and art size")
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 202, alignment: .top)
        .background(Theme.surface)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preview: some View {
        if project.frames.count > 1 && !reduceMotion && animating {
            FrameLoop(frames: project.frames, durations: project.frameDurations)
        } else {
            PixelImage(frame: project.frames[0], checker: false)
        }
    }
}

/// Scanning every frame for the art's size is costly, and the gallery re-renders after every save
/// while the Studio is open, so sizes are cached per sprite version.
private enum ArtSizeCache {
    private static var cache: [UUID: (modified: Date, size: PixelRect)] = [:]

    static func size(of p: SpriteProject) -> PixelRect {
        if let e = cache[p.id], e.modified == p.modifiedAt { return e.size }
        let r = p.visibleContentBounds ?? PixelRect(x: 0, y: 0, width: 0, height: 0)
        cache[p.id] = (p.modifiedAt, r)
        return r
    }
}
