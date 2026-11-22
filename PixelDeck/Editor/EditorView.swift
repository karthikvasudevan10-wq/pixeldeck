import SwiftUI

/// The Studio: an endless canvas filling the screen above a dock of controls. On wide spaces
/// (an unfolded iPhone Duo, iPad, landscape) the dock becomes a side panel.
struct EditorView: View {
    var store: ProjectStore { Shared.store }
    var purchases: PurchaseManager { Shared.purchases }
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
    /// The tracing picture under every layer, saved per sprite.
    @State var traceImage: UIImage?
    @State var showingTrace = false
    @State var showingPalettes = false
    /// The v2 panels (presets, onion skin and timing, adjust colours).
    @State var panels = StudioPanelState()
    @State var sharingToCommunity = false
    /// This sprite's timelapse, recorded as you draw (saved every few edits and on leaving).
    @State var timelapse = Timelapse()
    @State var timelapseProjectID: UUID?
    @State var timelapseUnsaved = 0
    @State var showingTimelapse = false
    /// The frame image folding over during a page turn.
    @State var turningPage: CGImage?
    @State var turnProgress: CGFloat = 0
    /// Identifies the latest page turn, so an earlier one finishing can't clear it.
    @State var turnToken = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// The guided tour (Core/GuidedTour.swift): which sprite it's on and which step, kept across
    /// launches so leaving and coming back resumes it.
    @AppStorage("tourProjectID") var tourProjectID = ""
    @AppStorage("tourStep") var tourStepRaw = 0
    @AppStorage("tourCompleted") var tourCompleted = false
    @State var tourBaseline = TourBaseline()
    @State var tourCelebrating = false
    @State var tourNudge: String?
    /// A Pixel Academy lesson (Core/Academy.swift): which sprite it runs on, which lesson, and
    /// the step, kept across launches so a lesson can be carried on later.
    @AppStorage("lessonProjectID") var lessonProjectID = ""
    @AppStorage("lessonID") var lessonID = ""
    @AppStorage("lessonStep") var lessonStep = 0
    @State var lessonPlayBaseline = 0
    @State var lessonCelebrating = false

    /// The desk layout is for iPad and Mac (not during the guided tour, which points at the dock).
    static let deskDevice = UIDevice.current.userInterfaceIdiom == .pad || ProcessInfo.processInfo.isMacCatalystApp
    static let isMac = ProcessInfo.processInfo.isMacCatalystApp

    var layout: StudioLayout {
        StudioLayout.choose(for: size, easel: easelMode, desk: Self.deskDevice && tourStep == nil)
    }

    /// Desk layout: the sprite list on the left (shown by default on the Mac), the inspector on
    /// the right, and which of its tabs is open.
    @AppStorage("deskSidebar") var showingSidebar = ProcessInfo.processInfo.isMacCatalystApp
    @AppStorage("deskInspector") var showingInspector = true
    /// Mac: the window is full screen (see `FullScreenWatcher`).
    @State var macFullScreen = false
    @State var inspectorTab: InspectorTab = .layers
    @State var showingCommunity = false
    @State var showingPlayground = false
    /// Desk layout: a file is being dragged over the canvas; a level opened from the sidebar; a
    /// short note after a drop.
    @State var dropTargeted = false
    @State var editingScene: TileScene?
    @State var deskNote: String?
    var router: AppRouter? { Shared.router }

    init(project: SpriteProject) {
        _model = State(initialValue: EditorModel(project: project))
    }

    /// nonisolated: a constant, read by the nonisolated `prefersSidePanel` too.
    nonisolated static let sidePanelWidth: CGFloat = 340

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
            case .desk:
                desk.transition(.opacity)
            case .pocket:
                VStack(spacing: 0) {
                    canvasArea()
                    dock
                        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .top) { Theme.line.frame(height: 2) }
                }
                .transition(.opacity)
            case .sidePanel:
                HStack(spacing: 0) {
                    canvasArea()
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
        .environment(panels)
        .modifier(StudioPanelSheets(model: model, panels: panels))
        .task(id: model.playCount) { await stopWhenPlayedOnce() }
        .environment(\.tourTarget, tourTarget)
        .overlay(alignment: .top) {
            if let step = tourStep {
                TourCard(step: step, nudge: tourNudge, onNext: advanceTour, onSkip: skipTour)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(step)
            } else if tourCelebrating {
                TourCard(step: .newCanvas, celebrating: true, onNext: {}, onSkip: {})
                    .padding(.top, 64)
                    .transition(.opacity)
            }
        }
        .overlay { TourEdgeArrow(target: tourTarget) }
        .modifier(LessonOverlay(lesson: activeLesson, step: lessonStep, stepDone: lessonStepDone, celebrating: lessonCelebrating,
                                onAdvance: advanceLesson, onLeave: { dismiss() }, onAppear: prepareLesson))
        .animation(.easeOut(duration: 0.25), value: tourStepRaw)
        .onChange(of: tourStepDone) { _, done in if done { advanceTour() } }
        .sensoryFeedback(.success, trigger: tourStepRaw)
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
        .task(id: model.project.id) {
            reference = ImageStore.references.load(for: model.project.id)
            traceImage = ImageStore.traces.load(for: model.project.id)
        }
        .onAppear {
            prepareTourStep()
            loadTimelapse()
            model.onChange = { [store] project in
                store.save(project)
                recordTimelapse(project)
            }
            model.access = purchases.access
            model.onProRequired = { feature in upgrade = feature }
            model.newLayerName = { String(localized: "Layer \($0)", comment: "Default name for a new layer") }
            model.newFolderName = { String(localized: "Folder \($0)", comment: "Default name for a new folder of layers") }
            model.shapesLayerName = String(localized: "Shapes", comment: "Name of the layer created for the first shape")
        }
        .onChange(of: purchases.isPro) { _, _ in model.access = purchases.access }
        .onDisappear {
            model.isPlaying = false
            model.commitSelection()
            tidySounds()
            store.save(model.project)
            saveTimelapse()
        }
        .sheet(isPresented: $showingTimelapse) {
            TimelapseView(name: model.project.name, timelapse: timelapse)
        }
        .proUpgradeSheet($upgrade)
        .sheet(isPresented: $showingTween) { TweenSheet(model: model) }
        .sheet(isPresented: $showingLayers) { LayersSheet(model: model, traceImage: $traceImage) }
        .sheet(isPresented: $showingTrace) { TraceSheet(model: model, image: $traceImage) }
        .sheet(isPresented: $showingPalettes) { PaletteSheet(model: model) }
        .sheet(isPresented: $sharingToCommunity) { ShareToCommunityView(project: model.project) }
        // On the Mac the menu bar carries every shortcut (StudioCommands); elsewhere, hidden buttons do.
        #if !targetEnvironment(macCatalyst)
        .background { KeyboardShortcuts(model: model, canvas: canvas, onExport: openExport,
                                        onNewCanvas: newCanvas, onLayers: { showingLayers = true }) }
        #endif
        .focusedSceneValue(\.studio, studioActions)
        .fullScreenCover(isPresented: $showingCommunity) { CommunityView() }
        .fullScreenCover(isPresented: $showingPlayground) { PlaygroundHomeView() }
        .modifier(AIStudioLink(model: model, showsBanner: layout != .desk, onNewCanvas: newCanvas))
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
        .onChange(of: editingSwatch) { _, edit in
            guard let edit, model.palette.indices.contains(edit.index) else { return }
            // Retro canvases keep their mode's colours.
            guard !model.isPaletteLocked else { editingSwatch = nil; return }
            SystemColorPicker.present(
                initial: model.palette[edit.index],
                onChange: { c, final in model.setPaletteColor(c, at: edit.index, commit: final) },
                onDone: {
                    model.setPaletteColor(model.palette[edit.index], at: edit.index)   // save the result
                    editingSwatch = nil
                })
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
                   onEditSwatch: { editingSwatch = SwatchEdit(index: $0) },
                   onTrace: { showingTrace = true },
                   onPalettes: { showingPalettes = true })
    }

    // MARK: Canvas

    /// `chips`: the sprite menu and layer chip float over the canvas (the desk layout has them
    /// in its top bar and inspector instead). `strips`: the tool's options float over the foot
    /// of the canvas (the Mac docks them in a bar above the canvas, clear of the art).
    func canvasArea(chips: Bool = true, strips: Bool = true) -> some View {
        SwipeCanvas(swipeAnywhere: swipeAnywhere,
                    onNewFrame: { model.addKeyframe() },   // also stops playback
                    onNewCanvas: newCanvas) {
            canvas
        }
        .overlay(alignment: .topLeading) { if chips { chip.padding(.leading, 12).padding(.top, 14) } }
        .overlay(alignment: .topTrailing) { if chips { layersButton.padding(.trailing, 12).padding(.top, 14) } }
        .overlay(alignment: .bottom) {
            if strips {
                VStack(spacing: 10) {
                    toolStrips
                    frameDots
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The options of the tool in use: selection actions, shapes, or the brush.
    @ViewBuilder
    var toolStrips: some View {
        if model.tool == .select && !model.isPlaying { selectionStrip }
        if model.tool == .shape && !model.isPlaying { shapeStrip }
        if (model.tool == .pencil || model.tool == .eraser) && !model.isPlaying { brushStrip }
    }

    /// While playing, the canvas shows each frame in turn at the sprite's frame rate.
    var canvas: some View {
        // Holds, ping-pong and "play once" all come from the sprite's playback sequence.
        let sequence = model.playbackSequence
        return TimelineView(.animation(minimumInterval: PlaybackClock.tick(sequence.durations), paused: !model.isPlaying)) { ctx in
            // Counted from when Play was pressed, so the animation starts at its first frame
            // and frame sounds stay in step with it.
            let elapsed = max(0, ctx.date.timeIntervalSince(model.playStartedAt))
            let frame: Int? = model.isPlaying ? sequence.frame(at: elapsed) : nil
            PixelCanvas(state: withLessonGuide(withTourGuide(model.canvasState(playingFrame: frame))), model: model, fit: fit,
                        drawingEnabled: !swipeAnywhere && !model.isPlaying,
                        pencilOnly: pencilOnly,
                        onPencilDetected: pencilFirstSeen,
                        onPencilAction: pencilAction,
                        traceImage: traceImage?.cgImage)
                .accessibilityLabel(Text("Canvas, frame \(model.currentIndex + 1) of \(model.frameCount)"))
                .accessibilityHint(pencilOnly
                    ? Text("Draw with Apple Pencil. Drag with one finger to move, pinch to change the pixel size, tap with two fingers to fit the art.")
                    : Text("Draw with one finger. Pinch to change the pixel size, drag with two fingers to move, tap with two fingers to fit the art."))
        }
    }

    var frameLabel: String {
        String(format: "%02d/%02d", model.currentIndex + 1, model.frameCount)
    }

    /// Everything in the sprite's menu (the name chip on iPhone, the title in the desk layout).
    @ViewBuilder
    var spriteMenuItems: some View {
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
        Button { showingTrace = true } label: { Label("Tracing image…", systemImage: "photo") }
        Button { panels.onionTiming = true } label: { Label("Onion skin and timing…", systemImage: "timer") }
        Button { panels.presets = true } label: { Label("Animate with a preset…", systemImage: "wand.and.stars") }
        Button { panels.sound = true } label: { Label("Sound on this frame…", systemImage: "speaker.wave.2") }
        Button { panels.adjust = true } label: { Label("Adjust colours…", systemImage: "slider.horizontal.3") }
        Button { panels.stamps = true } label: { Label("Stamps…", systemImage: "seal") }
        MotionGuideMenu(model: model)
        Button {
            model.commitSelection()
            panels.beads = true
        } label: { Label("Bead or cross-stitch pattern…", systemImage: "circle.grid.3x3") }
        TransformMenu(model: model, frame: nil)
        Button {
            saveTimelapse()
            showingTimelapse = true
        } label: { Label("Timelapse", systemImage: "play.rectangle") }
        Button { showingPalettes = true } label: { Label("Colours & palettes…", systemImage: "paintpalette") }
        Button {
            model.commitSelection()
            sharingToCommunity = true
        } label: { Label("Share to Community…", systemImage: "globe") }
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
    }

    /// Project name and frame counter. Tap for the sprite's menu.
    var chip: some View {
        Menu {
            spriteMenuItems
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
                            .help(Text("\(Text(kind.title)): drag on the canvas to draw it"))
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
            .help("Filled or outline: draw shapes solid, or just their edge")
            // Outline thickness: tap to step through 1 to 4 pixels.
            Button {
                model.shapeThickness = model.shapeThickness >= ShapeRaster.thicknessRange.upperBound ? 1 : model.shapeThickness + 1
            } label: {
                VStack(spacing: 3) {
                    Rectangle().frame(width: 18, height: CGFloat(model.shapeThickness) * 2)
                    Text(verbatim: "\(model.shapeThickness)px").font(AppFont.pixel(9))
                }
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle(active: model.shapeThickness > 1))
            .disabled(model.shapeFilled && model.shapeKind != .line)
            .accessibilityLabel(Text("Outline thickness, \(model.shapeThickness) pixels"))
            .accessibilityHint("Changes how thick shape outlines and lines are drawn")
            .help("Thickness: how thick lines and outlines are, 1 to 4 pixels")
            Button { model.lockProportions.toggle() } label: {
                Text(verbatim: "1:1")
                    .font(AppFont.pixel(11))
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle(active: model.lockProportions))
            .accessibilityLabel("Lock proportions")
            .accessibilityAddTraits(model.lockProportions ? .isSelected : [])
            .help("1:1: keep shapes as wide as they are tall (squares and circles)")
        }
        .padding(6)
        .background(Theme.chip)
        .padding(.bottom, 3)
        .padding(.horizontal, 12)
    }

    /// Brush options while drawing or erasing: size, round tip, pixel-perfect, the shading
    /// assistant, dither and top-bottom symmetry. The shading panel sits above it when shading.
    var brushStrip: some View {
        VStack(spacing: 8) {
            if model.tool == .pencil && model.shadeMode != nil { ShadingPanel(model: model) }
            OptionStrip {
                ForEach(1...EditorModel.maxBrushSize, id: \.self) { n in
                    let on = model.brushSize == n
                    Button { model.brushSize = n } label: {
                        Rectangle()
                            .frame(width: CGFloat(3 + n * 3), height: CGFloat(3 + n * 3))
                            .clipShape(RoundedRectangle(cornerRadius: model.brushRound && n >= 3 ? CGFloat(n) : 0))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle(active: on))
                    .accessibilityLabel(Text("Brush size \(n)"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .help(Text("Brush size \(n): the pencil and eraser are \(n) pixels wide. Keys: [ and ]"))
                }
                Theme.line.frame(width: 2, height: 28)
                stripToggle("Round", on: model.brushRound, tip: "Round: a round brush tip instead of a square one (sizes 3 and 4)") { model.brushRound.toggle() }
                    .accessibilityLabel("Round brush")
                StripChip(title: Text("Pixel-perfect"), on: model.pixelPerfect,
                          tip: "Pixel-perfect: tidies doubled pixels and corners as you draw, so curves stay one pixel wide. Key: P") { model.pixelPerfect.toggle() }
                    .accessibilityHint("Cleans doubled pixels and L-shaped corners as you draw, so curves stay one pixel wide. Works with the smallest brush.")
                if model.tool == .pencil {
                    StripChip(title: Text("Shade"), on: model.shadeMode != nil,
                              tip: "Shade: the brush darkens or lightens what you have drawn, following your light. Key: H") {
                        model.shadeMode = model.shadeMode == nil ? .shade : nil
                    }
                    .accessibilityLabel("Shading assistant")
                    .accessibilityHint("The brush shades or highlights what you've drawn, following your light")
                }
                stripToggle("Dither", on: model.dither, pro: !model.access.allowsArtistBrushes && model.project.retroMode == nil,
                            tip: "Dither: draws every other pixel, a checkerboard that blends two colours") { model.dither.toggle() }
                    .accessibilityLabel("Dither brush")
                // The desk's tool rail has this as its second mirror button.
                if layout != .desk {
                    stripToggle("⇕", on: model.mirrorVertical, pro: !model.access.allowsArtistBrushes,
                                tip: "Top-bottom symmetry: copies what you draw above and below. With Mirror on too, it is four-way.") { model.mirrorVertical.toggle() }
                        .accessibilityLabel("Top-bottom symmetry")
                        .accessibilityHint("With Mirror on too, it's four-way")
                }
            }
        }
        .padding(.bottom, 3)
        .padding(.horizontal, 12)
    }

    private func stripToggle(_ label: String, on: Bool, pro: Bool = false, tip: LocalizedStringKey? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(AppFont.pixel(11))
                .padding(.horizontal, 8)
                .frame(minWidth: 40, minHeight: 36)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) { if pro { ProBadge().scaleEffect(0.75).offset(x: 6, y: -6) } }
        }
        .buttonStyle(TileButtonStyle(active: on))
        .accessibilityAddTraits(on ? .isSelected : [])
        .tip(tip)
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

    /// Selection tools and actions, shown only while the Select tool is in use.
    var selectionStrip: some View {
        SelectionStrip(model: model, onTween: { showingTween = true })
    }

    // MARK: Actions

    /// An animation set to play once stops by itself at the end (and drawing comes back).
    func stopWhenPlayedOnce() async {
        let sequence = model.playbackSequence
        guard model.isPlaying, !sequence.repeats else { return }
        let run = model.playCount
        try? await Task.sleep(for: .seconds(sequence.total + 0.4))
        if !Task.isCancelled, model.isPlaying, model.playCount == run { model.isPlaying = false }
    }

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
        // During the tour, starting a new canvas is the very last step.
        if let step = tourStep {
            guard step == .newCanvas else {
                tourNudge = String(localized: "Starting a new canvas comes last. Finish this step first!")
                return
            }
            finishTour()
        }
        model.isPlaying = false
        model.commitSelection()
        // Already on an empty canvas: stay on it rather than making another.
        if model.project.isBlank {
            canvas(.fit)
            return
        }
        tidySounds()
        store.save(model.project)
        saveTimelapse()
        defer { loadTimelapse() }
        model.load(store.create(baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it")))
        canvas(.fit)
    }
}

// MARK: Guided tour

extension EditorView {
    /// The step showing, if this sprite is the tour's.
    var tourStep: TourStep? {
        guard !tourProjectID.isEmpty, tourProjectID == model.project.id.uuidString else { return nil }
        return TourStep(rawValue: tourStepRaw)
    }

    /// Read in `body`, so SwiftUI re-checks it whenever anything the step depends on changes.
    var tourStepDone: Bool {
        guard let step = tourStep, let id = UUID(uuidString: tourProjectID) else { return false }
        return GuidedTour.isDone(step, model: model, baseline: tourBaseline, tourProjectID: id)
    }

    var tourTarget: TourTarget {
        guard let step = tourStep else { return .none }
        // After Undo, point at Redo.
        if step == .undoRedo && model.undoCount > tourBaseline.undoCount { return .redo }
        return step.target
    }

    func withTourGuide(_ state: CanvasState) -> CanvasState {
        guard let step = tourStep, !model.isPlaying, let guide = GuidedTour.guide(for: step) else { return state }
        var s = state
        s.guide = guide
        return s
    }

    /// Sets up the current step (called when the tour sprite opens, and after each step).
    func prepareTourStep() {
        guard let step = tourStep else { return }
        tourBaseline = TourBaseline(model)
        tourNudge = nil
        switch step {
        case .drawHeart, .drawSecondHeart:
            model.tool = .pencil
            model.onionSkinEnabled = true
            if step == .drawSecondHeart && model.frameCount > 1 && model.currentIndex != 1 { model.selectFrame(1) }
        case .addFrame, .onion:
            model.onionSkinEnabled = true
        default:
            break
        }
        // Already done (e.g. resuming after doing it): move on rather than waiting for a change.
        if tourStepDone {
            Task { @MainActor in advanceTour() }
        }
    }

    func advanceTour() {
        guard let step = tourStep else { return }
        if let next = step.next {
            tourStepRaw = next.rawValue
            prepareTourStep()
        }
    }

    func skipTour() {
        tourProjectID = ""
        tourNudge = nil
    }

    func finishTour() {
        tourProjectID = ""
        tourCompleted = true
        tourNudge = nil
        tourCelebrating = true
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            tourCelebrating = false
        }
    }
}

// MARK: Timelapse

extension EditorView {
    func loadTimelapse() {
        timelapseProjectID = model.project.id
        timelapse = TimelapseStore.load(for: model.project.id)
        timelapseUnsaved = 0
    }

    /// After each edit: remember the frame being worked on.
    func recordTimelapse(_ project: SpriteProject) {
        guard project.id == timelapseProjectID, project.frames.indices.contains(model.currentIndex) else { return }
        timelapse.record(project.frames[model.currentIndex].grid, bounds: project.bounds)
        timelapseUnsaved += 1
        if timelapseUnsaved >= 15 { saveTimelapse() }
    }

    func saveTimelapse() {
        guard let id = timelapseProjectID else { return }
        TimelapseStore.save(timelapse, for: id)
        timelapseUnsaved = 0
    }
}
