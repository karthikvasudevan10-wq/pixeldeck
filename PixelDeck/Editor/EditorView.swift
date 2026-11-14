import SwiftUI

/// The Studio: an endless canvas filling the screen above a dock of controls. On wide spaces
/// (an unfolded iPhone Duo, iPad, landscape) the dock becomes a side panel.
struct EditorView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditorModel
    @State private var fit = FitCommand()
    @State private var swipeAnywhere = false
    @State private var upgrade: ProFeature?
    @State private var showingTween = false
    @State private var showingExport = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var editingSwatch: SwatchEdit?
    /// Chosen from the space the Studio actually has — never from device type or orientation.
    @State private var sidePanel = false

    init(project: SpriteProject) {
        _model = State(initialValue: EditorModel(project: project))
    }

    static let sidePanelWidth: CGFloat = 340

    nonisolated static func prefersSidePanel(_ size: CGSize) -> Bool {
        size.width > size.height * 1.15 && size.width >= sidePanelWidth + 320
    }

    var body: some View {
        // A VStack (not a Group) so the modifiers below attach once and survive layout switches.
        VStack(spacing: 0) {
            if sidePanel {
                HStack(spacing: 0) {
                    canvasArea
                    ScrollView {
                        dock
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: Self.sidePanelWidth)
                    .background(Theme.surface.ignoresSafeArea())
                    .overlay(alignment: .leading) { Theme.line.frame(width: 2).ignoresSafeArea() }
                }
            } else {
                canvasArea
                dock
                    .background(Theme.surface.ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) { Theme.line.frame(height: 2) }
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onGeometryChange(for: Bool.self) { Self.prefersSidePanel($0.size) } action: { sidePanel = $0 }
        .onAppear {
            model.onChange = { [store] project in store.save(project) }
            model.access = purchases.access
            model.onProRequired = { feature in upgrade = feature }
        }
        .onChange(of: purchases.isPro) { _, _ in model.access = purchases.access }
        .onDisappear {
            model.isPlaying = false
            model.commitSelection()
            store.save(model.project)
        }
        .proUpgradeSheet($upgrade)
        .sheet(isPresented: $showingTween) { TweenSheet(model: model) }
        .fullScreenCover(isPresented: $showingExport) { ExportView(project: model.project) }
        .sheet(item: $editingSwatch) { edit in
            SwatchEditor(initial: model.palette[edit.index],
                         onChange: { c, final in model.setPaletteColor(c, at: edit.index, commit: final) },
                         onDone: {
                             model.setPaletteColor(model.palette[edit.index], at: edit.index)   // save the result
                             editingSwatch = nil
                         })
                .presentationDetents([.medium, .large])
        }
        .alert("Rename sprite", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") { model.rename(renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var dock: some View {
        StudioDock(model: model,
                   onGallery: { dismiss() },
                   onExport: {
                       model.isPlaying = false
                       model.commitSelection()
                       showingExport = true
                   },
                   onEditSwatch: { editingSwatch = SwatchEdit(index: $0) })
    }

    // MARK: Canvas

    private var canvasArea: some View {
        SwipeCanvas(swipeAnywhere: swipeAnywhere,
                    onNewFrame: { model.addKeyframe() },   // also stops playback
                    onNewCanvas: newCanvas) {
            canvas
        }
        .overlay(alignment: .topLeading) { chip.padding(.leading, 12).padding(.top, 14) }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if model.tool == .select && !model.isPlaying { selectionStrip }
                frameDots
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// While playing, the canvas shows each frame in turn at the sprite's frame rate.
    private var canvas: some View {
        TimelineView(.animation(minimumInterval: 1 / Double(model.project.fps), paused: !model.isPlaying)) { ctx in
            let frame: Int? = model.isPlaying
                ? Int((ctx.date.timeIntervalSinceReferenceDate * Double(model.project.fps)).rounded(.down)) % max(model.frameCount, 1)
                : nil
            PixelCanvas(state: model.canvasState(playingFrame: frame), model: model, fit: fit,
                        drawingEnabled: !swipeAnywhere && !model.isPlaying)
                .accessibilityLabel(Text("Canvas, frame \(model.currentIndex + 1) of \(model.frameCount)"))
                .accessibilityHint("Draw with one finger. Pinch to change the pixel size, drag with two fingers to move, tap with two fingers to fit the art.")
        }
    }

    private var frameLabel: String {
        String(format: "%02d/%02d", model.currentIndex + 1, model.frameCount)
    }

    /// Project name and frame counter. Tap for the sprite's menu.
    private var chip: some View {
        Menu {
            Button {
                renameText = model.project.name
                showingRename = true
            } label: { Label("Rename", systemImage: "pencil") }
            Button { fit.nonce += 1 } label: { Label("Fit art to screen", systemImage: "arrow.down.right.and.arrow.up.left") }
            Toggle(isOn: Binding(get: { model.showGrid }, set: { model.showGrid = $0 })) {
                Label("Pixel grid", systemImage: "grid")
            }
            Toggle(isOn: $swipeAnywhere) {
                Label("Swipe anywhere", systemImage: "hand.draw")
            }
            Picker(selection: Binding(get: { model.onionOpacity }, set: { model.onionOpacity = $0 })) {
                ForEach([0.2, 0.38, 0.6], id: \.self) { v in Text(v, format: .percent).tag(v) }
            } label: {
                Label("Onion skin strength", systemImage: "square.2.layers.3d")
            }
            .pickerStyle(.menu)
            Divider()
            Button { model.duplicateFrame(at: model.currentIndex) } label: { Label("Duplicate frame", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { model.clearCurrentFrame() } label: { Label("Clear frame", systemImage: "xmark.square") }
            Button(role: .destructive) { model.deleteFrame(at: model.currentIndex) } label: { Label("Delete frame", systemImage: "trash") }
        } label: {
            HStack(spacing: 8) {
                Text(model.project.name)
                    .font(AppFont.body(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(verbatim: frameLabel)
                    .font(AppFont.pixel(11))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.chip)
            .frame(maxWidth: 240, alignment: .leading)
        }
        .accessibilityLabel(Text("\(model.project.name), frame \(model.currentIndex + 1) of \(model.frameCount). Sprite menu"))
    }

    /// One 4×4 dot per frame; the current one is a 12×4 accent bar.
    @ViewBuilder
    private var frameDots: some View {
        if model.frameCount > 1 && model.frameCount <= 30 {
            HStack(spacing: 4) {
                ForEach(0..<model.frameCount, id: \.self) { i in
                    let current = i == model.currentIndex
                    Rectangle()
                        .fill(current ? Theme.accent : Theme.muted)
                        .frame(width: current ? 12 : 4, height: 4)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    /// Selection actions, shown only while the Select tool is in use.
    private var selectionStrip: some View {
        HStack(spacing: 8) {
            if model.floating != nil {
                Button { showingTween = true } label: {
                    HStack(spacing: 6) {
                        PixelIcon.tween.view(size: 16)
                        Text("Tween").font(AppFont.pixel(12))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                }
                .buttonStyle(PrimaryButtonStyle(depth: 3))
                .disabled(!model.canTween)

                Button { model.deleteSelection() } label: {
                    PixelIcon.trash.view(size: 18).frame(width: 36, height: 36)
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel("Delete selection")

                Button { model.commitSelection() } label: {
                    Text("Drop").font(AppFont.pixel(12)).padding(.horizontal, 12).frame(height: 36)
                }
                .buttonStyle(TileButtonStyle())
            } else if model.marquee != nil {
                Text("Drag inside to move")
                    .font(AppFont.body(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(Theme.text)
                Button { model.deleteSelection() } label: {
                    PixelIcon.trash.view(size: 18).frame(width: 36, height: 36)
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel("Delete selected pixels")
                Button { model.commitSelection() } label: {
                    Text("Deselect").font(AppFont.pixel(12)).padding(.horizontal, 12).frame(height: 36)
                }
                .buttonStyle(TileButtonStyle())
            } else {
                Text("Drag over pixels to select them")
                    .font(AppFont.body(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 6)
                    .frame(height: 36)
            }
        }
        .padding(6)
        .background(Theme.chip)
        .padding(.bottom, 3)
    }

    // MARK: Actions

    private func newCanvas() {
        model.isPlaying = false
        model.commitSelection()
        store.save(model.project)
        model.load(store.create(baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it")))
        fit.nonce += 1
    }
}
