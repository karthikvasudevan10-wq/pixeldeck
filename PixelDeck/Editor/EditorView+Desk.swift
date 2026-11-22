import SwiftUI
import UniformTypeIdentifiers

// The desk layout, as designed for iPad and Mac (Design/v2, sections 8 and 9).
//
// Mac: a toolbar across the top (sidebar, title, undo, redo, play, layers, zoom, share, export,
// inspector); the sprite list down the left (Moving, Stills, Playground, Pixel Academy, with
// Community at the foot); the canvas with the tool rail floating over its corner; the timeline
// under the canvas; and the inspector down the right.
//
// iPad: a top bar (gallery, title, frame counter, undo, redo, zoom, share, export); the tool
// rail and brush sizes down the left; the canvas; the timeline with Play under it; and the same
// inspector down the right.

/// The inspector's tabs. The sections are stacked in one scrolling column and a tab jumps to
/// its section; on the Mac, while an assistant is connected, the third tab becomes AI.
enum InspectorTab: String, CaseIterable, Identifiable {
    case layers, colours, animate, ai
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .layers: "Layers"
        case .colours: "Colours"
        case .animate: "Animate"
        case .ai: "AI"
        }
    }
}

extension EditorView {
    static let sidebarWidth: CGFloat = 250
    static let inspectorWidth: CGFloat = 292
    /// The height of the Mac's title bar, in this app's points.
    static let macTitleBarHeight: CGFloat = 42

    var desk: some View {
        VStack(spacing: 0) {
            if Self.isMac {
                // Full screen: the Mac slides its menu bar and title bar down over the top of the
                // window when the pointer goes there. That strip is left empty, so they never
                // cover the toolbar.
                if macFullScreen { Theme.surface.frame(height: Self.macTitleBarHeight) }
                macToolbar
            } else {
                padTopBar
            }
            Theme.line.frame(height: 2)
            HStack(spacing: 0) {
                if Self.isMac && showingSidebar {
                    DeskSidebar(currentID: model.project.id, onOpen: openProject,
                                onScene: { editingScene = $0 },
                                onLesson: { router?.request = .lesson($0.id) },
                                onCommunity: { showingCommunity = true },
                                onDeletedCurrent: afterDeletingCurrent)
                        .frame(width: Self.sidebarWidth)
                    Theme.line.frame(width: 2)
                }
                if !Self.isMac {
                    padToolRail
                    Theme.line.frame(width: 2)
                }
                VStack(spacing: 0) {
                    if Self.isMac {
                        macOptionsBar
                        Theme.line.frame(height: 2)
                    }
                    deskCanvas
                    Theme.line.frame(height: 2)
                    if Self.isMac { macTimeline } else { padTimeline }
                }
                if showingInspector || !Self.isMac {
                    Theme.line.frame(width: 2)
                    DeskInspector(model: model, tab: $inspectorTab,
                                  onEditSwatch: { editingSwatch = SwatchEdit(index: $0) },
                                  onLayers: { showingLayers = true })
                        .frame(width: Self.inspectorWidth)
                }
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .background { if Self.isMac { FullScreenWatcher(isFullScreen: $macFullScreen) } }
        // On the Mac the toolbar shares its row with the window's close, minimise and zoom buttons.
        .ignoresSafeArea(edges: Self.isMac ? .top : [])
        .fullScreenCover(item: $editingScene) { SceneEditorView(scene: $0, store: SceneStore.forApp()) }
        .alert("Pixel Deck", isPresented: Binding(get: { deskNote != nil }, set: { if !$0 { deskNote = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: deskNote ?? "")
        }
    }

    // MARK: Canvas, with the Mac's floating tool rail and the drop target

    private var deskCanvas: some View {
        canvasArea(chips: false, strips: !Self.isMac)
            .overlay(alignment: .topLeading) {
                if Self.isMac {
                    // As designed: a narrow rail of 40 pt tools in the canvas's top left corner.
                    ToolRow(model: model, columns: 1, tile: 40, spacing: 2)
                        .padding(4)
                        .background(Theme.surface)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                        .padding(14)
                }
            }
            .overlay(alignment: .top) {
                if Self.isMac { AIBanner(layerName: model.layers[min(model.activeLayer, model.layers.count - 1)].name) }
            }
            .overlay { if dropTargeted { dropTarget } }
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropTargeted, perform: handleDrop)
    }

    /// Mac: the options of the tool in use (brush size, pixel-perfect, shading, shapes, selection
    /// actions), docked above the canvas so nothing sits on top of the art. Always the same
    /// height at least, so the canvas doesn't jump when the tool changes.
    private var macOptionsBar: some View {
        VStack(spacing: 6) {
            if model.isPlaying {
                optionsHint("Playing. Press Space to stop.")
            } else {
                switch model.tool {
                case .fill: optionsHint("Fill: click an area to fill it with your colour.")
                case .eyedropper: optionsHint("Colour picker: click a pixel to pick up its colour.")
                default: toolStrips
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Theme.surface)
    }

    private func optionsHint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.body(14, relativeTo: .subheadline))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .padding(.horizontal, 12)
    }

    /// "Drop to make pixel art", shown while something is dragged over the canvas.
    private var dropTarget: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.accent)
            Text("Drop to make pixel art").font(AppFont.pixel(18)).foregroundStyle(Theme.cream)
            Text("Photos become a new sprite. .aseprite, .gpl and .hex files open too.")
                .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: 560, maxHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Theme.ink.opacity(0.92)
                .overlay(Rectangle().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4])).padding(12))
                .overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: 4))
                .frame(maxWidth: 560, maxHeight: 420)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A photo becomes a new sprite; Aseprite and palette files open.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        // A file from Finder or Files; otherwise a picture dragged out of another app.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier), provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                // Copied at once: a dropped file can only be read while the drop is happening.
                let scoped = url.startAccessingSecurityScopedResource()
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("Drop-\(UUID().uuidString)-\(url.lastPathComponent)")
                try? FileManager.default.copyItem(at: url, to: copy)
                if scoped { url.stopAccessingSecurityScopedResource() }
                Task { @MainActor in dropped(file: copy) }
            }
            return true
        }
        if provider.canLoadObject(ofClass: UIImage.self) {
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in router?.request = .photo(image) }
            }
            return true
        }
        return false
    }

    private func dropped(file url: URL) {
        let ext = url.pathExtension.lowercased()
        if Aseprite.fileExtensions.contains(ext) {
            router?.request = .aseprite(url)
        } else if ["gpl", "hex", "pal", "txt"].contains(ext) {
            deskNote = PaletteFiles.importFile(url, into: PaletteLibrary.forApp())
        } else if let image = UIImage(contentsOfFile: url.path) {
            router?.request = .photo(image)
        } else {
            deskNote = String(localized: "Pixel Deck can't open that kind of file. Try a photo, an .aseprite file or a palette.")
        }
    }

    // MARK: Mac toolbar

    private var macToolbar: some View {
        HStack(spacing: 2) {
            // Room for the window's close, minimise and zoom buttons (they aren't there in full screen).
            if !macFullScreen { Color.clear.frame(width: 76, height: 1) }
            deskButton(systemImage: "sidebar.left", "Sprites", active: showingSidebar) {
                withAnimation(.easeOut(duration: 0.15)) { showingSidebar.toggle() }
            }
            titleMenu(size: 15)
            Spacer(minLength: 8)
            barButton(.undo, "Undo") { model.undo() }.disabled(!model.canUndo)
            barButton(.redo, "Redo") { model.redo() }.disabled(!model.canRedo)
            barButton(model.isPlaying ? .pause : .play, model.isPlaying ? "Pause" : "Play") { model.isPlaying.toggle() }
                .disabled(model.frameCount < 2 && !model.isPlaying)
            barButton(.layers, "Layers") { showingLayers = true }
            zoomMenu
            barButton(.community, "Share to Community") {
                model.commitSelection()
                sharingToCommunity = true
            }
            barButton(.export, "Export") { openExport() }
            deskButton(systemImage: "sidebar.right", "Inspector", active: showingInspector) {
                withAnimation(.easeOut(duration: 0.15)) { showingInspector.toggle() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Theme.surface)
    }

    /// The sprite's name (and "Edited" once it has changes); click for the sprite's menu.
    private func titleMenu(size: CGFloat) -> some View {
        Menu {
            spriteMenuItems
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.project.name)
                    .font(AppFont.body(size, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                if Self.isMac {
                    if model.canUndo {
                        Text("Edited").font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }
                } else {
                    Text(verbatim: frameLabel).font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("\(model.project.name), frame \(model.currentIndex + 1) of \(model.frameCount). Sprite menu"))
    }

    /// The zoom, as a percentage (100% is one screen point for each art pixel).
    private var zoomMenu: some View {
        Menu {
            Button { canvas(.zoomIn) } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
            Button { canvas(.zoomOut) } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
            Button { canvas(.fit) } label: { Label("Fit art to screen", systemImage: "arrow.down.right.and.arrow.up.left") }
        } label: {
            Text(verbatim: "\(Int((model.zoom * 100).rounded()))%")
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 56, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Zoom, \(Int((model.zoom * 100).rounded())) percent"))
    }

    private func deskButton(systemImage: String, _ label: LocalizedStringKey, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? Theme.text : Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: iPad top bar and tool rail

    private var padTopBar: some View {
        HStack(spacing: 6) {
            barButton(.gallery, "Gallery", tint: Theme.muted) { dismiss() }
            titleMenu(size: 19)
            Spacer(minLength: 8)
            barButton(.undo, "Undo") { model.undo() }.disabled(!model.canUndo)
            barButton(.redo, "Redo") { model.redo() }.disabled(!model.canRedo)
            zoomMenu
            barButton(.community, "Share to Community", tint: Theme.accent) {
                model.commitSelection()
                sharingToCommunity = true
            }
            barButton(.export, "Export") { openExport() }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Theme.ink)
    }

    /// The tools, then the brush sizes.
    private var padToolRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ToolRow(model: model, columns: 1)
                Theme.line.frame(width: 40, height: 2).padding(.vertical, 6)
                ForEach(1...EditorModel.maxBrushSize, id: \.self) { n in
                    let on = model.brushSize == n
                    Button { model.brushSize = n } label: {
                        Rectangle()
                            .frame(width: CGFloat(2 + n * 3), height: CGFloat(2 + n * 3))
                            .frame(width: 52, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle(active: on))
                    .accessibilityLabel(Text("Brush size \(n)"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 76)
        .background(Theme.surface)
    }

    // MARK: Timelines

    /// Mac: a header (hints on the left, chips on the right) over numbered frames.
    private var macTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Timeline").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                Text("← → frames · N new frame · Space play")
                    .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 8)
                timelineChips
            }
            FrameRow(model: model, thumb: CGSize(width: 58, height: 68), showsPlay: false, numbered: true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.surface)
    }

    /// iPad: Play, the frames, then the chips.
    private var padTimeline: some View {
        HStack(spacing: 10) {
            FrameRow(model: model, thumb: CGSize(width: 56, height: 64), playSize: 64)
            timelineChips
        }
        .padding(.horizontal, 16)
        .frame(height: 96)
        .background(Theme.surface)
    }

    /// Onion skin (opens its settings), what happens at the end, and the frame rate.
    @ViewBuilder
    private var timelineChips: some View {
        Button { panels.onionTiming = true } label: {
            (model.onionSkinEnabled
                ? Text("Onion \(model.onionBefore) + \(model.onionAfter)", comment: "Onion skin chip: frames before + frames after")
                : Text("Onion off"))
                .font(AppFont.pixel(11))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle(active: model.onionSkinEnabled))
        .accessibilityLabel(Text("Onion skin and timing. \(model.onionBefore) frames before, \(model.onionAfter) after"))
        Menu {
            Picker("When it ends", selection: Binding(get: { model.project.loopMode }, set: { model.setLoopMode($0) })) {
                ForEach(LoopMode.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Text(model.project.loopMode.title)
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.tool)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("When it ends: \(Text(model.project.loopMode.title))"))
        Menu {
            Picker("Frame rate", selection: Binding(get: { model.project.fps }, set: { model.setFPS($0) })) {
                ForEach([1, 2, 3, 4, 6, 8, 10, 12, 15, 24, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
            }
            TimingPicker(model: model)
        } label: {
            Text(verbatim: "\(model.project.fps) fps")
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.tool)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Frame rate, \(model.project.fps) frames per second"))
    }

    // MARK: Moving between sprites

    /// Switches the Studio to another sprite (from the sidebar), saving this one first.
    func openProject(_ project: SpriteProject) {
        guard project.id != model.project.id else { return }
        model.isPlaying = false
        model.commitSelection()
        tidySounds()
        store.save(model.project)
        saveTimelapse()
        // The stored copy is the freshest (another device may have just synced a change).
        model.load(store.project(id: project.id) ?? project)
        loadTimelapse()
        canvas(.fit)
    }

    /// The sprite on screen was deleted from the sidebar: show another (never save the old one back).
    func afterDeletingCurrent() {
        model.isPlaying = false
        let next = store.projects.first
            ?? store.create(baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it"))
        model.load(next)
        loadTimelapse()
        canvas(.fit)
    }

    /// What the menu bar (StudioCommands) can do to this Studio.
    var studioActions: StudioActions {
        StudioActions(model: model, panels: panels, canvas: canvas, export: openExport, newCanvas: newCanvas,
                      layers: { showingLayers = true }, palettes: { showingPalettes = true },
                      trace: { showingTrace = true },
                      timelapse: { saveTimelapse(); showingTimelapse = true },
                      rename: { renameText = model.project.name; showingRename = true },
                      tween: { showingTween = true })
    }
}

// MARK: Inspector

/// The desk's right-hand panel: layers, the palette with its ramp, and animation presets, in one
/// scrolling column. The tabs jump to a section.
struct DeskInspector: View {
    let model: EditorModel
    @Binding var tab: InspectorTab
    var onEditSwatch: (Int) -> Void
    var onLayers: () -> Void
    @Environment(StudioPanelState.self) private var panels: StudioPanelState?
    @State private var bridge = AIBridge.shared

    /// The AI tab appears on the Mac once assistants are switched on and one has connected.
    private var showsAI: Bool {
        ProcessInfo.processInfo.isMacCatalystApp && bridge.enabled && (!bridge.steps.isEmpty || !bridge.pending.isEmpty)
    }

    private var tabs: [InspectorTab] { showsAI ? [.layers, .colours, .ai] : [.layers, .colours, .animate] }

    var body: some View {
        VStack(spacing: 0) {
            ChoiceRow(options: tabs, selection: $tab) { Text($0.title).font(AppFont.pixel(11)) }
                .padding(3)
                .background(Theme.tool)
                .padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if tab == .ai && showsAI {
                            AIInspectorPanel()
                        } else {
                            layers.id(InspectorTab.layers)
                            Theme.line.frame(height: 2)
                            palette.id(InspectorTab.colours)
                            Theme.line.frame(height: 2)
                            presets.id(InspectorTab.animate)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: tab) { _, t in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(t, anchor: .top) }
                }
            }
        }
        .background(Theme.surface)
        // An assistant has started drawing: show what it's doing.
        .onChange(of: bridge.steps.count) { old, new in if showsAI && old == 0 && new > 0 { tab = .ai } }
        .onChange(of: showsAI) { _, on in if !on && tab == .ai { tab = .layers } }
    }

    // Layers: tap to draw on one, the eye hides it. Right-click (or long-press) for more.
    private var layers: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                ForEach(Array(model.layers.indices.reversed()), id: \.self) { i in layerRow(i) }
            }
            HStack(spacing: 6) {
                Button { model.addLayer() } label: {
                    Text("Add").font(AppFont.pixel(11)).padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                .disabled(!model.canAddLayer)
                .accessibilityLabel("New layer")
                Button { model.mergeLayerDown() } label: {
                    Text("Merge down").font(AppFont.pixel(11)).padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                .disabled(model.activeLayer == 0)
                Spacer(minLength: 0)
            }
        }
    }

    private func layerRow(_ i: Int) -> some View {
        let layer = model.layers[i]
        let active = i == model.activeLayer
        let cel = model.project.frames[model.currentIndex].layers[i]
        return HStack(spacing: 10) {
            Button { model.selectLayer(i) } label: {
                HStack(spacing: 10) {
                    PixelImage(grid: cel, checker: true)
                        .frame(width: 38, height: 38)
                        .opacity(layer.isVisible ? 1 : 0.4)
                    Text(layer.name)
                        .font(AppFont.body(16, active ? .bold : .medium, relativeTo: .body))
                        .foregroundStyle(layer.isVisible ? Theme.cream : Theme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(layer.name))
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityHint("Draw on this layer")
            Button { model.setLayerVisible(i, !layer.isVisible) } label: {
                (layer.isVisible ? PixelIcon.eye : .eyeOff).view(size: 18)
                    .foregroundStyle(layer.isVisible ? Theme.muted : Theme.line)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? Text("Hide layer") : Text("Show layer"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(active ? Theme.tool : .clear)
        .overlay(Rectangle().strokeBorder(active ? Theme.accent : .clear, lineWidth: 2))
        .contextMenu {
            Button(action: onLayers) { Label("Rename and more…", systemImage: "pencil") }
            Button { model.moveLayer(i, by: 1) } label: { Label("Move up", systemImage: "arrow.up") }
                .disabled(i == model.layers.count - 1)
            Button { model.moveLayer(i, by: -1) } label: { Label("Move down", systemImage: "arrow.down") }
                .disabled(i == 0)
            Button(role: .destructive) { model.deleteLayer(i) } label: { Label("Delete layer", systemImage: "trash") }
                .disabled(model.layers.count == 1)
        }
    }

    // Palette: the swatches, then the ramp of the colour you're drawing with.
    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Palette").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            PaletteRow(model: model, onEdit: onEditSwatch)
            HStack(spacing: 2) {
                ForEach(Array(model.ramp(for: model.color).enumerated()), id: \.offset) { _, c in
                    Rectangle().fill(c.color).frame(maxWidth: .infinity).frame(height: 30)
                        .contentShape(Rectangle())
                        .onTapGesture { model.pickColor(c) }
                        .accessibilityElement()
                        .accessibilityLabel(Text("Colour \(c.hexString)"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.pickColor(c) }
                }
            }
            .padding(.horizontal, 4)
            Text("Ramp from \(Text(BeadName.name(for: model.color).title)) · hue shift +\(Int(model.rampHueShift))°",
                 comment: "Under the ramp: the colour it starts from (e.g. Blue), and the hue shift in degrees")
                .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
            Button { panels?.adjust = true } label: {
                Text("Adjust colours…").font(AppFont.pixel(11)).padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityHint("Brightness, contrast, hue and saturation of the selection, layer, frame or every frame")
            MoreColorsSection(model: model)
        }
    }

    // Animation presets: tap one to choose the frames and draw them.
    @ViewBuilder
    private var presets: some View {
        let frame = model.project.frames[model.currentIndex]
        VStack(alignment: .leading, spacing: 8) {
            Text("Animation presets").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(AnimationPreset.allCases) { preset in
                    Button {
                        panels?.presetChoice = preset
                        panels?.presets = true
                    } label: {
                        VStack(spacing: 4) {
                            PixelImage(frame: frame, checker: false).frame(width: 34, height: 34)
                            Text(preset.title).font(AppFont.pixel(8)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .overlay(alignment: .topTrailing) {
                            if !model.access.allows(preset) { ProBadge().scaleEffect(0.7).offset(x: 2, y: -2) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityLabel(Text(preset.title))
                }
            }
        }
    }
}

// MARK: Sidebar (Mac)

/// The Mac's sprite list: search, then Moving, Stills, Playground and Pixel Academy, with
/// Community at the foot. Right-click a sprite to rename, duplicate or delete it.
struct DeskSidebar: View {
    private var store: ProjectStore { Shared.store }
    let currentID: UUID
    var onOpen: (SpriteProject) -> Void
    var onScene: (TileScene) -> Void
    var onLesson: (Lesson) -> Void
    var onCommunity: () -> Void
    var onDeletedCurrent: () -> Void
    @State private var search = ""
    @State private var scenes = SceneStore.forApp()
    @State private var renaming: SpriteProject?
    @State private var renameText = ""
    @State private var deleting: SpriteProject?

    private func matches(_ name: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }

    var body: some View {
        let sprites = store.projects.filter { matches($0.name) }
        let levels = scenes.scenes.filter { matches($0.name) }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search", text: $search)
                    .font(AppFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.tool)
            .padding(10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    spriteSection("Moving", sprites.filter { $0.frames.count > 1 })
                    spriteSection("Stills", sprites.filter { $0.frames.count == 1 })
                    if !levels.isEmpty {
                        header("Playground")
                        ForEach(levels) { scene in
                            row(title: Text(verbatim: scene.name), selected: false, action: { onScene(scene) }) {
                                if let tile = scene.tiles.first { PixelImage(grid: tile.grid, checker: false) }
                            }
                        }
                    }
                    header("Pixel Academy")
                    ForEach(Academy.lessons.filter { matches(String(localized: $0.title)) }) { lesson in
                        row(title: Text(lesson.title), selected: false, action: { onLesson(lesson) }) {
                            LessonThumbnail(lesson: lesson)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            Button(action: onCommunity) {
                HStack(spacing: 10) {
                    PixelIcon.community.view(size: 16).foregroundStyle(Theme.muted)
                    Text("Community").font(AppFont.body(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Theme.surface)
        .onAppear { scenes.load() }
        .alert("Rename sprite", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let p = renaming { store.rename(id: p.id, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this sprite?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let p = deleting else { return }
                store.delete(id: p.id)
                ImageStore.deleteAll(for: p.id)
                if p.id == currentID { onDeletedCurrent() }
            }
        } message: {
            Text("All of its frames will be removed. This can't be undone.")
        }
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.body(12, .bold, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func spriteSection(_ title: LocalizedStringKey, _ projects: [SpriteProject]) -> some View {
        if !projects.isEmpty {
            header(title)
            ForEach(projects) { project in
                row(title: Text(verbatim: project.name), selected: project.id == currentID, action: { onOpen(project) }) {
                    PixelImage(frame: project.frames[0], checker: false)
                }
                .contextMenu {
                    Button {
                        renameText = project.name
                        renaming = project
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button {
                        if let copy = store.duplicate(id: project.id, name: { String(localized: "\($0) copy", comment: "Name for a duplicated sprite; the placeholder is the original name") }) {
                            ImageStore.copyAll(from: project.id, to: copy.id)
                        }
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { deleting = project } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    /// A sidebar row: a small picture and a name. The sprite on screen is filled with the accent.
    private func row<Icon: View>(title: Text, selected: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                    .padding(2)
                    .frame(width: 28, height: 28)
                    .background(Theme.ink)
                title
                    .font(AppFont.body(15, selected ? .bold : .regular, relativeTo: .subheadline))
                    .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(selected ? Theme.accent : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
