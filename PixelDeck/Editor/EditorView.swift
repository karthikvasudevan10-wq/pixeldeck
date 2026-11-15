import SwiftUI

/// The Studio: an endless canvas filling the screen above a dock of controls. On wide spaces
/// (an unfolded iPhone Duo, iPad, landscape) the dock becomes a side panel.
struct EditorView: View {
    @Environment(ProjectStore.self) var store
    @Environment(PurchaseManager.self) var purchases
    @Environment(\.dismiss) var dismiss
    @State var model: EditorModel
    @State var fit = FitCommand()
    @State var swipeAnywhere = false
    @State var upgrade: ProFeature?
    @State var showingTween = false
    @State var showingExport = false
    @State var showingRename = false
    @State var renameText = ""
    @State var editingSwatch: SwatchEdit?
    @State var showingLayers = false
    /// Apple Pencil draws and fingers move the canvas. Switched on the first time a Pencil is used.
    @AppStorage("pencilOnly") var pencilOnly = false
    @AppStorage("pencilDetected") var pencilDetected = false
    @State var pencilNotice = false
    /// The space the Studio has. The layout is chosen from it — never from device type or
    /// orientation — so it follows iPhone Duo folding, iPad multitasking and rotation.
    @State var size: CGSize = .zero
    /// Easel mode (iPhone Duo half open on a desk). iOS doesn't document a fold-posture API yet, so
    /// it's chosen in the sprite menu; `StudioLayout.choose` is the one place to hook one in.
    @AppStorage("easelMode") var easelMode = false
    /// What the Flipbook's left page shows.
    @State var leftPage: LeftPage = .lastFrame
    /// A pinned reference image (Flipbook), saved per sprite.
    @State var reference: UIImage?
    /// The frame image folding over during a page turn.
    @State var turningPage: CGImage?
    @State var turnProgress: CGFloat = 0
    /// Identifies the latest page turn, so an earlier one finishing can't clear it.
    @State var turnToken = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var layout: StudioLayout { StudioLayout.choose(for: size, easel: easelMode) }

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
            // The project, frame, tool, colour, onion skin and undo history all live in `model`,
            // so switching layout (folding, unfolding, rotating) changes nothing but the
            // arrangement. A short cross-fade covers the switch.
            switch layout {
            case .pocket:
                VStack(spacing: 0) {
                    canvasArea
                    dock
                        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .top) { Theme.line.frame(height: 2) }
                }
                .transition(.opacity)
            case .sidePanel:
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
                .transition(.opacity)
            case .flipbook:
                flipbook.transition(.opacity)
            case .easel:
                easel.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: layout)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
            if size == .zero {
                // First measurement: place the right layout straight away, without a cross-fade.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { size = newSize }
            } else {
                size = newSize
            }
        }
        .task(id: model.project.id) { reference = ReferenceStore.load(for: model.project.id) }
        .onAppear {
            model.onChange = { [store] project in store.save(project) }
            model.access = purchases.access
            model.onProRequired = { feature in upgrade = feature }
            model.newLayerName = { String(localized: "Layer \($0)", comment: "Default name for a new layer") }
            model.shapesLayerName = String(localized: "Shapes", comment: "Name of the layer created for the first shape")
        }
        .onChange(of: purchases.isPro) { _, _ in model.access = purchases.access }
        .onDisappear {
            model.isPlaying = false
            model.commitSelection()
            store.save(model.project)
        }
        .proUpgradeSheet($upgrade)
        .sheet(isPresented: $showingTween) { TweenSheet(model: model) }
        .sheet(isPresented: $showingLayers) { LayersSheet(model: model) }
        .background { KeyboardShortcuts(model: model, canvas: canvas, onExport: openExport,
                                        onNewCanvas: newCanvas, onLayers: { showingLayers = true }) }
        .overlay(alignment: .top) {
            if pencilNotice {
                Text("Apple Pencil draws. Fingers now move and zoom the canvas.")
                    .font(AppFont.body(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Theme.onAccent2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent2)
                    .padding(.top, 60)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
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

    var dock: some View {
        StudioDock(model: model,
                   onGallery: { dismiss() },
                   onExport: openExport,
                   onEditSwatch: { editingSwatch = SwatchEdit(index: $0) })
    }

    // MARK: Canvas

    var canvasArea: some View {
        SwipeCanvas(swipeAnywhere: swipeAnywhere,
                    onNewFrame: { model.addKeyframe() },   // also stops playback
                    onNewCanvas: newCanvas) {
            canvas
        }
        .overlay(alignment: .topLeading) { chip.padding(.leading, 12).padding(.top, 14) }
        .overlay(alignment: .topTrailing) { layersButton.padding(.trailing, 12).padding(.top, 14) }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if model.tool == .select && !model.isPlaying { selectionStrip }
                if model.tool == .shape && !model.isPlaying { shapeStrip }
                frameDots
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// While playing, the canvas shows each frame in turn at the sprite's frame rate.
    var canvas: some View {
        let durations = model.frameDurations
        return TimelineView(.animation(minimumInterval: PlaybackClock.tick(durations), paused: !model.isPlaying)) { ctx in
            let frame: Int? = model.isPlaying ? PlaybackClock.index(ctx.date, durations: durations) : nil
            PixelCanvas(state: model.canvasState(playingFrame: frame), model: model, fit: fit,
                        drawingEnabled: !swipeAnywhere && !model.isPlaying,
                        pencilOnly: pencilOnly,
                        onPencilDetected: pencilFirstSeen,
                        onPencilAction: pencilAction)
                .accessibilityLabel(Text("Canvas, frame \(model.currentIndex + 1) of \(model.frameCount)"))
                .accessibilityHint(pencilOnly
                    ? Text("Draw with Apple Pencil. Drag with one finger to move, pinch to change the pixel size, tap with two fingers to fit the art.")
                    : Text("Draw with one finger. Pinch to change the pixel size, drag with two fingers to move, tap with two fingers to fit the art."))
        }
    }

    var frameLabel: String {
        String(format: "%02d/%02d", model.currentIndex + 1, model.frameCount)
    }

    /// Project name and frame counter. Tap for the sprite's menu.
    var chip: some View {
        Menu {
            Button {
                renameText = model.project.name
                showingRename = true
            } label: { Label("Rename", systemImage: "pencil") }
            Button { canvas(.fit) } label: { Label("Fit art to screen", systemImage: "arrow.down.right.and.arrow.up.left") }
            TimingPicker(model: model)
            Toggle(isOn: Binding(get: { model.showGrid }, set: { model.showGrid = $0 })) {
                Label("Pixel grid", systemImage: "grid")
            }
            if pencilDetected {
                Toggle(isOn: $pencilOnly) {
                    Label("Draw with Apple Pencil only", systemImage: "applepencil")
                }
            }
            if StudioLayout.supportsEasel(size) {
                Toggle(isOn: $easelMode) {
                    Label("Easel mode", systemImage: "rectangle.split.1x2")
                }
            }
            if layout == .easel {
                Button { openExport() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Button { dismiss() } label: { Label("Back to gallery", systemImage: "square.grid.2x2") }
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
            Button { model.copyFrameToClipboard(at: model.currentIndex) } label: { Label("Copy frame", systemImage: "doc.on.doc") }
            Button { model.pasteClipboard(at: model.currentIndex, asNewFrame: false) } label: {
                Label("Paste over this frame", systemImage: "doc.on.clipboard")
            }
            .disabled(FrameClipboard.shared.clip == nil)
            Button { model.pasteClipboard(at: model.currentIndex, asNewFrame: true) } label: {
                Label("Paste as new frame", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(FrameClipboard.shared.clip == nil)
            Button(role: .destructive) { model.clearCurrentFrame() } label: {
                if model.layers.count > 1 {
                    Label("Clear layer in this frame", systemImage: "xmark.square")
                } else {
                    Label("Clear frame", systemImage: "xmark.square")
                }
            }
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
            .frame(maxWidth: 190, alignment: .leading)
        }
        .accessibilityLabel(Text("\(model.project.name), frame \(model.currentIndex + 1) of \(model.frameCount). Sprite menu"))
    }

    /// The active layer, and the way into the layers panel.
    var layersButton: some View {
        Button { showingLayers = true } label: {
            HStack(spacing: 6) {
                PixelIcon.layers.view(size: 14)
                    .foregroundStyle(Theme.accent)
                Text(model.layers[min(model.activeLayer, model.layers.count - 1)].name)
                    .font(AppFont.body(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if model.layers.count > 1 {
                    Text(verbatim: "\(model.activeLayer + 1)/\(model.layers.count)")
                        .font(AppFont.pixel(11))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.chip)
            .frame(maxWidth: 150, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Layers. Drawing on \(model.layers[min(model.activeLayer, model.layers.count - 1)].name)"))
    }

    /// Shape options, shown while the shape tool is in use.
    var shapeStrip: some View {
        HStack(spacing: 6) {
            // Ten shapes don't fit across a phone, so they scroll; on wider screens the strip
            // is only as wide as the shapes.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ShapeKind.allCases) { kind in
                            let on = model.shapeKind == kind
                            Button { model.shapeKind = kind } label: {
                                kind.icon.view(size: 18).frame(width: 40, height: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(TileButtonStyle(active: on))
                            .accessibilityLabel(Text(kind.title))
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .id(kind)
                        }
                    }
                    .padding(.vertical, 3)                 // room for the tiles' drop shadow
                }
                .frame(maxWidth: CGFloat(ShapeKind.allCases.count) * 46 - 6)
                .onAppear { proxy.scrollTo(model.shapeKind, anchor: .center) }
            }
            Theme.line.frame(width: 2, height: 28)
            Button { model.shapeFilled.toggle() } label: {
                (model.shapeFilled ? Text("Filled") : Text("Outline"))
                    .font(AppFont.pixel(11))
                    .frame(width: 70, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle(active: model.shapeFilled))
            .disabled(model.shapeKind == .line)
            .accessibilityLabel(model.shapeFilled ? Text("Filled shapes") : Text("Outline shapes"))
            Button { model.lockProportions.toggle() } label: {
                Text(verbatim: "1:1")
                    .font(AppFont.pixel(11))
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle(active: model.lockProportions))
            .accessibilityLabel("Lock proportions")
            .accessibilityAddTraits(model.lockProportions ? .isSelected : [])
        }
        .padding(6)
        .background(Theme.chip)
        .padding(.bottom, 3)
        .padding(.horizontal, 12)
    }

    /// One 4×4 dot per frame; the current one is a 12×4 accent bar.
    @ViewBuilder
    var frameDots: some View {
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
    var selectionStrip: some View {
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

    func canvas(_ action: FitCommand.Action) {
        fit = FitCommand(action: action, nonce: fit.nonce + 1)
    }

    func openExport() {
        model.isPlaying = false
        model.commitSelection()
        showingExport = true
    }

    /// The first Pencil touch switches to Pencil-only drawing, like other iPad drawing apps,
    /// and says so once. It can be turned off in the sprite menu.
    func pencilFirstSeen() {
        guard !pencilDetected else { return }
        pencilDetected = true
        pencilOnly = true
        withAnimation { pencilNotice = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { withAnimation { pencilNotice = false } }
    }

    func pencilAction(_ action: PencilAction) {
        switch action {
        case .toggleEraser: model.toggleEraser()
        case .previousTool: model.switchToPreviousTool()
        case .showColorPicker:
            let i = model.palette.firstIndex(of: model.color) ?? 0
            editingSwatch = SwatchEdit(index: i)
        }
    }

    func newCanvas() {
        model.isPlaying = false
        model.commitSelection()
        store.save(model.project)
        model.load(store.create(baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it")))
        canvas(.fit)
    }
}
