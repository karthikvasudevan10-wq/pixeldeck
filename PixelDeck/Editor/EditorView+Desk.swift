import SwiftUI

// The desk layout, for iPad and Mac: a top bar, the tool rail on the left of the canvas, an
// inspector (Layers / Colours / Animate) on the right, and a timeline along the bottom. A sprite
// list can slide in on the far left (shown by default on the Mac), so you can hop between sprites
// without going back to the gallery.

/// The inspector's tabs.
enum InspectorTab: String, CaseIterable, Identifiable {
    case layers, colours, animate
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .layers: "Layers"
        case .colours: "Colours"
        case .animate: "Animate"
        }
    }
}

extension EditorView {
    static let sidebarWidth: CGFloat = 230
    static let inspectorWidth: CGFloat = 300

    var desk: some View {
        VStack(spacing: 0) {
            deskTopBar
            Theme.line.frame(height: 2)
            HStack(spacing: 0) {
                if showingSidebar {
                    DeskSidebar(currentID: model.project.id, onOpen: openProject, onNew: newCanvas,
                                onPlayground: { showingPlayground = true },
                                onCommunity: { showingCommunity = true })
                        .frame(width: Self.sidebarWidth)
                    Theme.line.frame(width: 2)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    ToolRow(model: model, columns: 1).padding(.vertical, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: 64)
                .background(Theme.surface)
                Theme.line.frame(width: 2)
                canvasArea(chips: false)
                if showingInspector {
                    Theme.line.frame(width: 2)
                    DeskInspector(model: model, tab: $inspectorTab, traceImage: $traceImage,
                                  onEditSwatch: { editingSwatch = SwatchEdit(index: $0) },
                                  onPalettes: { showingPalettes = true },
                                  onLayers: { showingLayers = true },
                                  onTrace: { showingTrace = true })
                        .frame(width: Self.inspectorWidth)
                }
            }
            Theme.line.frame(height: 2)
            deskTimeline
        }
    }

    /// Sidebar toggle, gallery, the sprite's menu · undo, redo, zoom · export, inspector toggle.
    private var deskTopBar: some View {
        HStack(spacing: 4) {
            deskButton(systemImage: "sidebar.left", "Sprites", active: showingSidebar) {
                withAnimation(.easeOut(duration: 0.15)) { showingSidebar.toggle() }
            }
            barButton(.gallery, "Gallery", tint: Theme.muted) { dismiss() }
            chip
            Spacer(minLength: 8)
            barButton(.undo, "Undo") { model.undo() }.disabled(!model.canUndo)
            barButton(.redo, "Redo") { model.redo() }.disabled(!model.canRedo)
            Theme.line.frame(width: 2, height: 24).padding(.horizontal, 4)
            deskButton(systemImage: "minus.magnifyingglass", "Zoom out") { canvas(.zoomOut) }
            deskButton(systemImage: "arrow.down.right.and.arrow.up.left", "Fit art to screen") { canvas(.fit) }
            deskButton(systemImage: "plus.magnifyingglass", "Zoom in") { canvas(.zoomIn) }
            Theme.line.frame(width: 2, height: 24).padding(.horizontal, 4)
            barButton(.community, "Share to Community", tint: Theme.accent) {
                model.commitSelection()
                sharingToCommunity = true
            }
            barButton(.export, "Export", tint: Theme.muted) { openExport() }
            deskButton(systemImage: "sidebar.right", "Inspector", active: showingInspector) {
                withAnimation(.easeOut(duration: 0.15)) { showingInspector.toggle() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(Theme.surface)
    }

    private func deskButton(systemImage: String, _ label: LocalizedStringKey, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// Play, the frames, and chips for onion skin, the loop mode and the frame rate.
    private var deskTimeline: some View {
        HStack(spacing: 10) {
            FrameRow(model: model, thumb: CGSize(width: 44, height: 58), playSize: 56)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Button { panels.onionTiming = true } label: {
                        HStack(spacing: 8) {
                            PixelIcon.onion.view(size: 16)
                            (model.onionSkinEnabled
                                ? Text(verbatim: "\(model.onionBefore) + \(model.onionAfter)")
                                : Text("Off"))
                                .font(AppFont.pixel(11))
                        }
                        .foregroundStyle(model.onionSkinEnabled ? Theme.accent : Theme.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .overlay(Rectangle().strokeBorder(model.onionSkinEnabled ? Theme.accent : Theme.line, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                            .frame(height: 44)
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("When it ends: \(Text(model.project.loopMode.title))"))
                    fpsMenu(bordered: true)
                }
                if Self.isMac {
                    Text("← → frames · N new frame · Space play")
                        .font(AppFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 92)
        .background(Theme.surface)
    }

    /// Switches the Studio to another sprite (from the sidebar), saving this one first.
    func openProject(_ project: SpriteProject) {
        guard project.id != model.project.id else { return }
        model.isPlaying = false
        model.commitSelection()
        store.save(model.project)
        saveTimelapse()
        // The stored copy is the freshest (another device may have just synced a change).
        model.load(store.project(id: project.id) ?? project)
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

/// The desk's right-hand panel.
struct DeskInspector: View {
    let model: EditorModel
    @Binding var tab: InspectorTab
    @Binding var traceImage: UIImage?
    var onEditSwatch: (Int) -> Void
    var onPalettes: () -> Void
    var onLayers: () -> Void
    var onTrace: () -> Void
    @Environment(StudioPanelState.self) private var panels: StudioPanelState?

    var body: some View {
        VStack(spacing: 0) {
            ChoiceRow(options: InspectorTab.allCases, selection: $tab) { Text($0.title) }
                .padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .layers: layers
                    case .colours: colours
                    case .animate: animate
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.surface)
    }

    // Layers: tap to draw on one, the eye hides it; the full panel has rename, reorder and delete.
    @ViewBuilder
    private var layers: some View {
        VStack(spacing: 6) {
            ForEach(Array(model.layers.indices.reversed()), id: \.self) { i in
                layerRow(i)
            }
        }
        HStack(spacing: 6) {
            Button { model.addLayer() } label: {
                HStack(spacing: 6) {
                    PixelIcon.plus.view(size: 14, lineWidth: 2.5)
                    Text("Add").font(AppFont.pixel(12))
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
            .disabled(!model.canAddLayer)
            .accessibilityLabel("New layer")
            Button { model.mergeLayerDown() } label: {
                HStack(spacing: 6) {
                    PixelIcon.merge.view(size: 14)
                    Text("Merge down").font(AppFont.pixel(12))
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
            .disabled(model.activeLayer == 0)
        }
        Button(action: onLayers) {
            Text("Rename, reorder, delete…").font(AppFont.body(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Button(action: onTrace) {
            (traceImage == nil ? Text("Add a tracing image…") : Text("Tracing image…"))
                .font(AppFont.body(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func layerRow(_ i: Int) -> some View {
        let layer = model.layers[i]
        let active = i == model.activeLayer
        let cel = model.project.frames[model.currentIndex].layers[i]
        return HStack(spacing: 8) {
            Button { model.selectLayer(i) } label: {
                HStack(spacing: 8) {
                    PixelImage(grid: cel, checker: true)
                        .frame(width: 32, height: 32)
                        .opacity(layer.isVisible ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(layer.name)
                            .font(AppFont.body(14, .bold, relativeTo: .subheadline))
                            .foregroundStyle(layer.isVisible ? Theme.cream : Theme.muted)
                            .lineLimit(1)
                        if active { Text("Drawing here").font(AppFont.pixel(9)).foregroundStyle(Theme.accent) }
                    }
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
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.muted)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? Text("Hide layer") : Text("Show layer"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.ink)
        .overlay(Rectangle().strokeBorder(active ? Theme.accent : Theme.line, lineWidth: 2))
    }

    // Colours: the palette, extra colours, the ramp of the current colour.
    @ViewBuilder
    private var colours: some View {
        SectionLabel(text: "Palette")
        PaletteRow(model: model, onEdit: onEditSwatch, onPalettes: nil, columns: 5, swatch: CGSize(width: 46, height: 34))
        MoreColorsSection(model: model)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Ramp")
            HStack(spacing: 0) {
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
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            Button { model.addRampToPalette(from: model.color) } label: {
                Text("Add ramp to the palette").font(AppFont.pixel(11)).frame(maxWidth: .infinity, minHeight: 36).contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
        }
        Button(action: onPalettes) {
            Text("Palettes, ramps, from a photo…").font(AppFont.body(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if let panels {
            Button { panels.adjust = true } label: {
                Text("Adjust colours…").font(AppFont.body(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // Animate: presets, then onion skin, holds and the loop mode.
    @ViewBuilder
    private var animate: some View {
        if let panels {
            Button { panels.presets = true } label: {
                HStack(spacing: 8) {
                    PixelIcon.play.view(size: 14, lineWidth: 2.5)
                    Text("Animate with a preset").font(AppFont.pixel(12))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
            .padding(.bottom, 4)
            Text("Bounce, blink, float, shake, colour cycle and squash, drawn for you as frames.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
        Theme.line.frame(height: 2)
        OnionTimingControls(model: model)
    }
}

// MARK: Sidebar

/// The sprite list beside the Studio: search, Moving and Stills, New canvas and Community.
struct DeskSidebar: View {
    @Environment(ProjectStore.self) private var store
    let currentID: UUID
    var onOpen: (SpriteProject) -> Void
    var onNew: () -> Void
    var onPlayground: () -> Void
    var onCommunity: () -> Void
    @State private var search = ""

    private var matches: [SpriteProject] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? store.projects : store.projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let all = matches
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search", text: $search)
                    .font(AppFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.ink)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            .padding(10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    section("Moving", all.filter { $0.frames.count > 1 })
                    section("Stills", all.filter { $0.frames.count == 1 })
                    if all.isEmpty {
                        Text("No sprites match.").font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(10)
                    }
                }
                .padding(.horizontal, 6)
            }

            Theme.line.frame(height: 2)
            VStack(spacing: 2) {
                footer(.plus, "New canvas", tint: Theme.accent2, action: onNew)
                footer(.play, "Playground", tint: Theme.accent2, action: onPlayground)
                footer(.community, "Community", tint: Theme.accent, action: onCommunity)
            }
            .padding(6)
        }
        .background(Theme.surface)
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ projects: [SpriteProject]) -> some View {
        if !projects.isEmpty {
            Text(title).font(AppFont.pixel(10)).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 2)
            ForEach(projects) { project in
                let on = project.id == currentID
                Button { onOpen(project) } label: {
                    HStack(spacing: 8) {
                        PixelImage(frame: project.frames[0], checker: false)
                            .padding(2)
                            .frame(width: 30, height: 30)
                            .background(Theme.ink)
                        Text(project.name)
                            .font(AppFont.body(14, on ? .bold : .regular, relativeTo: .subheadline))
                            .foregroundStyle(on ? Theme.cream : Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(on ? Theme.tool : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func footer(_ icon: PixelIcon, _ title: LocalizedStringKey, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.view(size: 16).foregroundStyle(tint).frame(width: 30, height: 30)
                Text(title).font(AppFont.body(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
