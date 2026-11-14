import SwiftUI

struct EditorView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @State private var upgrade: ProFeature?
    @State private var model: EditorModel
    @State private var zoom = ZoomCommand()
    @State private var deckMode = false
    @State private var showingNewCanvas = false
    @State private var showingTween = false
    @State private var showingExport = false
    @State private var showingPlayback = false
    @State private var showingRename = false
    @State private var renameText = ""
    /// Canvas beside a tool panel, rather than stacked. Chosen from the space the editor actually
    /// has — never from device type or orientation — so it adapts when iPhone Duo folds or
    /// unfolds, in iPad multitasking, and in landscape.
    @State private var sidePanel = false

    init(project: SpriteProject) {
        _model = State(initialValue: EditorModel(project: project))
    }

    static let sidePanelWidth: CGFloat = 320

    /// Side-by-side when there's clearly more width than height and room for the panel plus a
    /// usefully large canvas.
    nonisolated static func prefersSidePanel(_ size: CGSize) -> Bool {
        size.width > size.height * 1.15 && size.width >= sidePanelWidth + 300
    }

    var body: some View {
        // A VStack (not a Group): modifiers on a Group apply to each branch separately, so
        // switching layout would fire onDisappear (dropping the selection) and dismiss open sheets.
        VStack(spacing: 0) {
            if sidePanel {
                HStack(alignment: .top, spacing: 4) {
                    deck
                    ScrollView {
                        VStack(spacing: 12) {
                            HStack(spacing: 2) { toolButtons }
                            HStack(spacing: 2) { zoomButtons }
                            if model.tool == .select { selectionBar }
                            ColorBar(model: model)
                            FilmStrip(model: model)
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(width: Self.sidePanelWidth)
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 2) {
                        toolButtons
                        Spacer(minLength: 4)
                        zoomButtons
                    }
                    .padding(.horizontal, 12)

                    deck

                    if model.tool == .select {
                        selectionBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    ColorBar(model: model)
                    FilmStrip(model: model)
                }
            }
        }
        .padding(.top, 4)
        .onGeometryChange(for: Bool.self) { Self.prefersSidePanel($0.size) } action: { sidePanel = $0 }
        .animation(.snappy(duration: 0.2), value: model.tool == .select)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            model.onChange = { [store] project in store.save(project) }
            model.access = purchases.access
            model.onProRequired = { feature in upgrade = feature }
        }
        .onChange(of: purchases.isPro) { _, _ in model.access = purchases.access }
        .proUpgradeSheet($upgrade)
        .onDisappear {
            model.commitSelection()
            store.save(model.project)
        }
        .sheet(isPresented: $showingNewCanvas) {
            NewCanvasSheet { size in
                model.commitSelection()
                store.save(model.project)
                model.load(store.create(size: size, baseName: String(localized: "Sprite", comment: "Default name for a new sprite; a number is added after it")))
                zoom = ZoomCommand(action: .fit, nonce: zoom.nonce + 1)
            }
        }
        .sheet(isPresented: $showingTween) { TweenSheet(model: model) }
        .sheet(isPresented: $showingExport) { ExportSheet(project: model.project) }
        .sheet(isPresented: $showingPlayback) { PlaybackSheet(model: model) }
        .alert("Rename sprite", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") { model.rename(renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deck: some View {
        SwipeDeck(title: Text("Frame \(model.currentIndex + 1) of \(model.frameCount)"),
                  dragAnywhere: deckMode,
                  onSwipeLeft: { model.addKeyframe() },
                  onSwipeRight: { showingNewCanvas = true }) {
            PixelCanvas(state: model.canvasState, model: model, zoom: zoom)
                .allowsHitTesting(!deckMode)
                .accessibilityElement()
                .accessibilityLabel("Canvas, \(model.size) by \(model.size) pixels, frame \(model.currentIndex + 1) of \(model.frameCount)")
                .accessibilityHint("Drawing on the canvas needs touch. Use the frame strip and menus for other actions.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Tools

    @ViewBuilder
    private var toolButtons: some View {
        ForEach(Tool.allCases) { tool in
            Button {
                deckMode = false
                model.tool = tool
            } label: {
                Image(systemName: tool.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .background(model.tool == tool && !deckMode ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(model.tool == tool && !deckMode ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(tool.title))
            .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
        }

        Button { deckMode.toggle() } label: {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .background(deckMode ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .foregroundStyle(deckMode ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Swipe mode")
        .accessibilityHint("Lets you swipe the whole canvas card")
    }

    @ViewBuilder
    private var zoomButtons: some View {
        zoomButton("minus.magnifyingglass", .zoomOut, "Zoom out")
        zoomButton("arrow.down.right.and.arrow.up.left", .fit, "Fit canvas")
        zoomButton("plus.magnifyingglass", .zoomIn, "Zoom in")
    }

    private func zoomButton(_ symbol: String, _ action: ZoomAction, _ label: LocalizedStringKey) -> some View {
        Button {
            zoom = ZoomCommand(action: action, nonce: zoom.nonce + 1)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            if model.floating != nil {
                Button {
                    showingTween = true
                } label: {
                    Label("Tween", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canTween)

                Button(role: .destructive) { model.deleteSelection() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete selection")

                Spacer()
                Button("Drop") { model.commitSelection() }
                    .buttonStyle(.bordered)
            } else if model.marquee != nil {
                Text("Drag inside the selection to move it")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { model.deleteSelection() } label: { Image(systemName: "trash") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete selected pixels")
                Button("Deselect") { model.commitSelection() }
                    .buttonStyle(.bordered)
            } else {
                Text("Drag over pixels to select them")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .accessibilityLabel("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .accessibilityLabel("Redo")
            Menu {
                Button { showingPlayback = true } label: { Label("Play animation", systemImage: "play.fill") }
                Button { model.addKeyframe() } label: { Label("New frame", systemImage: "plus.rectangle.on.rectangle") }
                Button { showingNewCanvas = true } label: { Label("New canvas", systemImage: "doc.badge.plus") }
                Button { showingExport = true } label: { Label("Export sprites", systemImage: "square.and.arrow.up") }
                Divider()
                Toggle(isOn: $model.showGrid) { Label("Pixel grid", systemImage: "grid") }
                Toggle(isOn: $model.onionSkinEnabled) { Label("Onion skin", systemImage: "square.2.layers.3d") }
                Picker(selection: $model.onionOpacity) {
                    ForEach([0.15, 0.3, 0.5, 0.7], id: \.self) { v in
                        Text(v, format: .percent).tag(v)
                    }
                } label: {
                    Label("Onion opacity", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                Divider()
                Button {
                    renameText = model.project.name
                    showingRename = true
                } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) { model.clearCurrentFrame() } label: { Label("Clear frame", systemImage: "xmark.square") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }
}
