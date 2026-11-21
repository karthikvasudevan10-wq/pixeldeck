import SwiftUI

/// Home: every sprite as a live, looping tile; "New canvas" first. Moving / Stills splits
/// animations from single-frame pictures.
struct ProjectListView: View {
    private var store: ProjectStore { Shared.store }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("starterSpritesAdded") private var starterSpritesAdded = false
    /// The showcase scenes arrived in a later version, so they're added once to every gallery,
    /// new or existing.
    @AppStorage("showcaseSpritesAdded") private var showcaseSpritesAdded = false
    /// The starter stills arrived later too; added once to every gallery.
    @AppStorage("stillSpritesAdded") private var stillSpritesAdded = false
    /// The guided tour: which sprite it runs on (read by the editor), and whether it's been offered.
    @AppStorage("tourProjectID") private var tourProjectID = ""
    @AppStorage("tourStep") private var tourStepRaw = 0
    @AppStorage("tourOffered") private var tourOffered = false
    private var purchases: PurchaseManager { Shared.purchases }
    @State private var path: [UUID] = []
    @State private var filter: GalleryFilter = .moving
    @State private var showingWelcome = false
    @State private var showingSettings = false
    @State private var showingCommunity = false
    /// A Community post to open (from the Home Screen widget).
    @State private var communityPostID: String?
    @State private var sharing: SpriteProject?
    @State private var exporting: SpriteProject?
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var deletingID: UUID?
    /// Multi-select: tiles toggle a check instead of opening, and the bottom bar offers
    /// Select all and Delete.
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var confirmingBulkDelete = false
    /// "New canvas": the chooser, and the photo flow it can lead to.
    @State private var showingNewCanvas = false
    @State private var showingPhoto = false
    @State private var upgrade: ProFeature?
    /// Pixel Playground (the Play tab) and Pixel Academy.
    @State private var showingPlayground = false
    @State private var showingAcademy = false
    @State private var incomingLevel: URL?
    @State private var incomingAseprite: URL?
    @State private var droppedPhoto: UIImage?
    private var router: AppRouter? { Shared.router }
    @State private var beadPattern: SpriteProject?
    @AppStorage("lessonProjectID") private var lessonProjectID = ""
    @AppStorage("lessonID") private var lessonID = ""
    @AppStorage("lessonStep") private var lessonStep = 0

    enum GalleryFilter: Hashable { case moving, stills }

    /// Preview tile backgrounds from the design, cycled.
    static let tileColors: [Color] = [
        Theme.dynamic(0x2B1F47, 0xEAE2F5), Theme.dynamic(0x3A1F2E, 0xF6E2E8), Theme.dynamic(0x3A321C, 0xF4ECD6),
        Theme.dynamic(0x1F3340, 0xDEEAF0), Theme.dynamic(0x1F3A2A, 0xDFECE1), Theme.dynamic(0x171129, 0xE8E3EF),
    ].map { Color(uiColor: $0) }

    /// Live previews run only while the gallery is actually on screen — not under the Studio,
    /// the welcome screens or export, and not in the background.
    private var galleryVisible: Bool {
        path.isEmpty && !showingWelcome && exporting == nil && !showingSettings && !showingPhoto
            && !showingPlayground && !showingAcademy && scenePhase == .active
    }

    private var filtered: [SpriteProject] {
        store.projects.filter { filter == .moving ? $0.frames.count > 1 : $0.frames.count == 1 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                if !tourOffered && hasSeenOnboarding && !selecting { tourBanner }
                ScrollView {
                    if !selecting {
                        IdeaCard(onDraw: drawIdea)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    // Two columns on iPhone (as designed); more on iPad as the width allows.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 165, maximum: 260), spacing: 12)], spacing: 12) {
                        if !selecting { newCanvasTile }
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, project in
                            let tile = ProjectTile(project: project, tile: Self.tileColors[i % Self.tileColors.count],
                                                   animating: galleryVisible, isPro: purchases.isPro)
                            if selecting {
                                let on = selected.contains(project.id)
                                Button { toggle(project.id) } label: {
                                    tile.overlay { selectionMark(on) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                                .accessibilityHint("Selects this sprite")
                            } else {
                                NavigationLink(value: project.id) { tile }
                                    .buttonStyle(.plain)
                                    .contextMenu { menu(for: project) }
                            }
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
                        if !selecting && v.translation.width > 110 && abs(v.translation.height) < 60 { createAndOpen() }
                    }
                )
                if selecting { selectionBar } else { bottomBar }
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
        .fullScreenCover(isPresented: $showingWelcome) {
            WelcomeFlow {
                showingWelcome = false
                startTour()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(onStartTour: {
                showingSettings = false
                // After the sheet has gone, so the navigation push isn't lost.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    startTour()
                }
            })
        }
        .fullScreenCover(isPresented: $showingCommunity, onDismiss: { communityPostID = nil }) {
            CommunityView(openPostID: communityPostID)
        }
        // pixeldeck://community/<post id>, from the Home Screen widget.
        .onOpenURL { url in
            // A level someone sent, opened from Files or Messages.
            if url.isFileURL {
                if url.pathExtension.lowercased() == LevelFile.fileExtension {
                    if !EditorView.isMac { path = [] }
                    incomingLevel = url
                    showingPlayground = true
                } else if AsepriteFiles.isAseprite(url) {
                    if !EditorView.isMac { path = [] }
                    incomingAseprite = url
                }
                return
            }
            guard url.scheme == "pixeldeck", url.host == "community" else { return }
            if !EditorView.isMac { path = [] }
            communityPostID = url.pathComponents.dropFirst().first
            showingCommunity = true
        }
        .sheet(item: $sharing) { ShareToCommunityView(project: $0) }
        .modifier(NewCanvasFlow(showingChooser: $showingNewCanvas, showingPhoto: $showingPhoto,
                                showingPlayground: $showingPlayground, showingAcademy: $showingAcademy,
                                incomingLevel: $incomingLevel,
                                onBlank: createAndOpen, onOpen: openNew, onStartLesson: startLesson,
                                incomingAseprite: $incomingAseprite, onImport: importSprites, dropped: $droppedPhoto))
        .onChange(of: router?.request) { _, request in
            guard let request else { return }
            router?.request = nil
            answer(request)
        }
        .sheet(item: $beadPattern) { BeadPatternView(project: $0) }
        .proUpgradeSheet($upgrade)
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
        .confirmationDialog(Text("Delete \(selected.count) sprites?", comment: "Gallery multi-delete confirmation title; plural"),
                            isPresented: $confirmingBulkDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: deleteSelected) {
                Text("Delete \(selected.count) sprites", comment: "Gallery multi-delete button; plural")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll be removed with all their frames, from this device and from iCloud on all your devices. This can't be undone.")
        }
        .onChange(of: filter) { _, _ in selected = [] }
        .alert("Couldn't save your sprite", isPresented: Binding(get: { store.saveFailed }, set: { if !$0 { store.acknowledgeSaveFailure() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your device may be out of storage. Free up some space; your last saved version is safe, and Pixel Deck will keep trying as you edit.")
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Gallery")
                    .font(AppFont.pixel(30))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selecting.toggle()
                        selected = []
                    }
                } label: {
                    Text(selecting ? "Done" : "Select")
                        .font(AppFont.pixel(11))
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                }
                .buttonStyle(TileButtonStyle(active: selecting, fill: Theme.surface, foreground: Theme.text))
                .disabled(!selecting && store.projects.isEmpty)
                if !selecting {
                    Button { showingCommunity = true } label: {
                        PixelIcon.community.view(size: 20).frame(width: 42, height: 42)
                    }
                    .buttonStyle(TileButtonStyle(fill: Theme.surface, foreground: Theme.accent))
                    .accessibilityLabel("Community")
                    Button { showingAcademy = true } label: {
                        Image(systemName: "graduationcap.fill").font(.system(size: 17)).frame(width: 42, height: 42)
                    }
                    .buttonStyle(TileButtonStyle(fill: Theme.surface, foreground: Theme.accent2))
                    .accessibilityLabel("Pixel Academy")
                    Button { showingSettings = true } label: {
                        PixelIcon.settings.view(size: 20).frame(width: 42, height: 42)
                    }
                    .buttonStyle(TileButtonStyle(fill: Theme.surface, foreground: Theme.muted))
                    .accessibilityLabel("Settings")
                }
            }
            HStack(spacing: 8) {
                Group {
                    if filter == .moving {
                        Text("\(filtered.count) animations", comment: "Gallery count (plural)")
                    } else {
                        Text("\(filtered.count) stills", comment: "Gallery count of single-frame sprites (plural)")
                    }
                }
                .font(AppFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    tab("Moving", .moving)
                    tab("Stills", .stills)
                }
                .padding(3)
                .background(Theme.surface)
            }
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
        Button { showingNewCanvas = true } label: {
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
            // Same look as the New canvas tile (yellow +), since it does the same thing.
            Button { showingNewCanvas = true } label: {
                PixelIcon.plus.view(size: 24, lineWidth: 3)
                    .foregroundStyle(Theme.onAccent2)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(PrimaryButtonStyle(fill: Theme.accent2, shadow: Theme.accent2Shadow, depth: 5))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("New canvas")
            barItem(.play, "Play", color: Theme.muted) { showingPlayground = true }
                .accessibilityLabel("Playground")
        }
        .frame(height: 76)
        .background(Theme.ink.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Theme.line.frame(height: 2) }
    }

    /// The bottom bar while selecting: Select all (or none), and Delete.
    private var selectionBar: some View {
        let allSelected = !filtered.isEmpty && filtered.allSatisfy { selected.contains($0.id) }
        return HStack(spacing: 12) {
            Button {
                if allSelected { selected.subtract(filtered.map(\.id)) } else { selected.formUnion(filtered.map(\.id)) }
            } label: {
                Text(allSelected ? "Select none" : "Select all")
                    .font(AppFont.pixel(12))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface, foreground: Theme.text))
            .disabled(filtered.isEmpty)
            Button { confirmingBulkDelete = true } label: {
                HStack(spacing: 8) {
                    PixelIcon.trash.view(size: 18)
                    (selected.isEmpty ? Text("Delete") : Text("Delete (\(selected.count))"))
                        .font(AppFont.pixel(12))
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
        .background(Theme.ink.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Theme.line.frame(height: 2) }
    }

    /// Check box and highlight on a tile while selecting.
    private func selectionMark(_ on: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(on ? Theme.accent : .clear, lineWidth: 3)
            ZStack {
                Rectangle().fill(on ? Theme.accent : Theme.ink.opacity(0.7))
                Rectangle().strokeBorder(on ? Theme.accent : Theme.cream, lineWidth: 2)
                if on { PixelIcon.check.view(size: 16, lineWidth: 3).foregroundStyle(Theme.onAccent) }
            }
            .frame(width: 28, height: 28)
            .padding(8)
        }
        .allowsHitTesting(false)
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func deleteSelected() {
        for id in selected {
            store.delete(id: id)
            ImageStore.deleteAll(for: id)
        }
        selected = []
        selecting = false
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
        Button { beadPattern = project } label: { Label("Bead or cross-stitch pattern…", systemImage: "circle.grid.3x3") }
        Button { sharing = project } label: { Label("Share to Community…", systemImage: "globe") }
        Button(role: .destructive) { deletingID = project.id } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: Actions

    /// Starts the guided tour on a fresh sprite: draw a heart and make it bounce in three frames.
    private func startTour() {
        let p = SpriteProject(name: String(localized: "My bouncing heart", comment: "Name of the sprite made in the guided tour"))
        store.save(p)
        tourProjectID = p.id.uuidString
        tourStepRaw = 0
        tourOffered = true
        filter = .moving
        path = [p.id]
    }

    /// Offered once to people who had the app before the tour existed.
    private var tourBanner: some View {
        HStack(spacing: 12) {
            AnimatedSprite(key: "slime", pixel: 3)
                .frame(width: 40, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("New: a 2-minute guided tour").font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                Text("Make a bouncing heart and learn every gesture and hidden menu.")
                    .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button(action: startTour) {
                    Text("Start")
                        .font(AppFont.pixel(12))
                        .foregroundStyle(Theme.onAccent2)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.accent2, shadow: Theme.accent2Shadow, depth: 3))
                Button("Not now") { tourOffered = true }
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// Saves a sprite made elsewhere (from a photo, for example) and opens it in the Studio.
    private func openNew(_ project: SpriteProject) {
        store.save(project)
        filter = project.frames.count > 1 ? .moving : .stills
        path = [project.id]
    }

    /// Something the Studio asked for (from its sidebar, the Mac menu bar or a dropped file).
    private func answer(_ request: AppRouter.Request) {
        switch request {
        case .newCanvas: showingNewCanvas = true
        case .settings: showingSettings = true
        case .academy: showingAcademy = true
        case .playground: showingPlayground = true
        case .community: showingCommunity = true
        case .lesson(let id):
            guard let lesson = Academy.lesson(id: id) else { return }
            if purchases.access.allows(lesson) { startLesson(lesson) } else { upgrade = .academy }
        case .photo(let image):
            droppedPhoto = image
            showingPhoto = true
        case .aseprite(let url):
            incomingAseprite = url
        }
    }

    /// On the Mac the Studio is the main window: open the latest sprite straight away.
    private func openStudioOnMac() {
        guard EditorView.isMac, path.isEmpty, !showingWelcome else { return }
        let project = store.projects.first
            ?? store.create(baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it"))
        path = [project.id]
    }

    /// Adds sprites brought in from a file (an Aseprite import) and opens the first.
    private func importSprites(_ sprites: [SpriteProject]) {
        for p in sprites.reversed() { store.save(p) }
        if let first = sprites.first {
            filter = first.frames.count > 1 ? .moving : .stills
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                path = [first.id]
            }
        }
    }

    /// A new sprite named after today's idea.
    private func drawIdea(_ idea: String) {
        var p = SpriteProject(name: String(idea.prefix(40)))
        p.modifiedAt = Date()
        openNew(p)
    }

    /// Starts a Pixel Academy lesson on a fresh sprite, or carries on with the one in progress.
    private func startLesson(_ lesson: Lesson) {
        if lessonID == lesson.id, let id = UUID(uuidString: lessonProjectID), store.project(id: id) != nil {
            path = [id]
            return
        }
        var p = SpriteProject(name: String(localized: lesson.title))
        p.fps = lesson.fps
        store.save(p)
        lessonID = lesson.id
        lessonStep = 0
        lessonProjectID = p.id.uuidString
        filter = .moving
        path = [p.id]
    }

    private func createAndOpen() {
        let project = store.create(baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it"))
        path = [project.id]
    }

    /// First launch: the starter sprites go into the gallery, and the welcome screens show.
    private func firstLaunch() {
        // Tidy up empty sprites left by earlier versions (new canvases now reuse a blank one).
        for id in store.removeExtraBlanks() { ImageStore.deleteAll(for: id) }
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
            // Fixed dates (and ids): on a second device these merge with the iCloud copies, and
            // any edits made to them win.
            if store.projects.isEmpty { store.add(starters, before: Date(timeIntervalSince1970: 1_600_000_000)) }
        }
        if !showcaseSpritesAdded {
            showcaseSpritesAdded = true
            let names: [String: String] = [
                "highstreet": String(localized: "Spring high street", comment: "Showcase sprite name: a Japanese shopping street with cherry blossom"),
                "valley": String(localized: "Valley mixtape", comment: "Showcase sprite name: a boy with a cassette player above a mountain valley"),
            ]
            let scenes = CharacterSpriteLibrary.showcaseOrder.compactMap { key in
                StarterArt.sprite(key)?.makeProject(name: names[key] ?? key)
            }
            // Fixed release date, newest first; edits made on any device win over a fresh copy.
            store.add(Array(scenes.reversed()), before: Date(timeIntervalSince1970: 1_794_700_800))
        }
        if !stillSpritesAdded {
            stillSpritesAdded = true
            let names: [String: String] = [
                "strawberry": String(localized: "Strawberry", comment: "Starter still picture name"),
                "potion": String(localized: "Potion", comment: "Starter still picture name"),
                "mushroom": String(localized: "Mushroom", comment: "Starter still picture name"),
                "cactus": String(localized: "Cactus", comment: "Starter still picture name"),
                "icecream": String(localized: "Ice cream", comment: "Starter still picture name"),
                "planet": String(localized: "Ringed planet", comment: "Starter still picture name"),
                "cottage": String(localized: "Cottage", comment: "Starter still picture name"),
                "sunset": String(localized: "Sunset sail", comment: "Starter still picture name"),
            ]
            let stills = CharacterSpriteLibrary.stillsOrder.compactMap { key in
                StarterArt.sprite(key)?.makeProject(name: names[key] ?? key)
            }
            // Fixed date and ids, so devices sharing iCloud don't get duplicates.
            store.add(Array(stills.reversed()), before: Date(timeIntervalSince1970: 1_794_700_000))
        }
        if !hasSeenOnboarding {
            hasSeenOnboarding = true
            showingWelcome = true
        }
        openStudioOnMac()
    }
}

/// A gallery tile: the animation looping live (frame 0 with Reduce Motion), its frame rate, name,
/// frame count and art size.
private struct ProjectTile: View {
    let project: SpriteProject
    let tile: Color
    var animating = true
    var isPro = false
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
                if !isPro && ArtSizeCache.size(of: project).exceedsFreeArtSize {
                    // Bigger than free art: it can be watched and exported, but editing needs Pro.
                    Text(verbatim: "PRO")
                        .font(AppFont.pixel(10))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .accessibilityLabel("Pro sprite: editing needs Pixel Deck Pro")
                }
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
            FrameLoop(frames: project.playbackFrames, durations: project.playbackSequence.durations)
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

private extension PixelRect {
    var exceedsFreeArtSize: Bool {
        width > FeatureAccess.freeMaxArtSide || height > FeatureAccess.freeMaxArtSide
    }
}
