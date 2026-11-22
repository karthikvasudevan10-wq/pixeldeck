import SwiftUI

/// The sprite's layers, top of the stack first. Tap a layer to draw on it; the eye hides it from
/// the canvas, thumbnails and exports. Changes apply to every frame.
struct LayersSheet: View {
    let model: EditorModel
    @Binding var traceImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var showingTrace = false
    @State private var renamingIndex: Int?
    @State private var renameText = ""
    @State private var renamingFolder: LayerFolder?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Layers", onClose: { dismiss() })
            ScrollView {
                VStack(spacing: 6) {
                    // Shown top-down, as they stack on the canvas.
                    ForEach(model.project.layerOutline) { entry in
                        switch entry {
                        case .layer(_, let i):
                            row(i)
                        case .folder(let folder, let indices):
                            LayerFolderRow(model: model, folder: folder, count: indices.count) { renamingFolder = $0 }
                            // A folder's layers, set in a little.
                            if !folder.isCollapsed {
                                ForEach(indices, id: \.self) { i in row(i).padding(.leading, 18) }
                            }
                        }
                    }
                    // Always the bottom of the stack.
                    traceRow
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button { model.addLayer() } label: {
                PrimaryActionLabel(title: "New layer", icon: .plus)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canAddLayer)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            Text(model.canAddLayer ? "New layers go above the selected one. A layer's ••• menu puts it in a folder."
                 : "This sprite is too big in memory for another layer.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 16)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingTrace) { TraceSheet(model: model, image: $traceImage) }
        .modifier(FolderRenameAlert(model: model, renaming: $renamingFolder))
        .alert("Rename layer", isPresented: Binding(get: { renamingIndex != nil }, set: { if !$0 { renamingIndex = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let i = renamingIndex { model.renameLayer(i, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The tracing picture, under every layer.
    private var traceRow: some View {
        let trace = traceImage == nil ? nil : model.trace
        let visible = trace?.isVisible ?? false
        return HStack(spacing: 12) {
            Button { showingTrace = true } label: {
                HStack(spacing: 12) {
                    Group {
                        if let traceImage {
                            Image(uiImage: traceImage).resizable().scaledToFit()
                        } else {
                            PixelIcon.gallery.view(size: 20).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(Theme.ink)
                    .opacity(trace == nil || visible ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tracing image")
                            .font(AppFont.body(15, .bold, relativeTo: .body))
                            .foregroundStyle(trace == nil || visible ? Theme.cream : Theme.muted)
                        if let trace {
                            Text("\(trace.opacity.formatted(.percent.precision(.fractionLength(0)))) · not exported", comment: "Tracing image row: its opacity (formatted for the language), then a note that it's never exported").font(AppFont.pixel(10)).foregroundStyle(Theme.muted)
                        } else {
                            Text("Add a picture to trace over").font(AppFont.pixel(10)).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tracing image")
            .accessibilityHint(trace == nil ? Text("Choose a picture to trace over") : Text("Change the picture, its opacity, size and position"))

            if let trace {
                Button {
                    var t = trace
                    t.isVisible.toggle()
                    model.setTrace(t)
                } label: {
                    (visible ? PixelIcon.eye : .eyeOff).view(size: 20)
                        .foregroundStyle(visible ? Theme.text : Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(visible ? Text("Hide tracing image") : Text("Show tracing image"))
            } else {
                PixelIcon.plus.view(size: 20)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            // Lines up with the layers' "more" buttons.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    private func row(_ i: Int) -> some View {
        let layer = model.layers[i]
        let active = i == model.activeLayer
        let cel = model.project.frames[model.currentIndex].layers[i]
        return HStack(spacing: 12) {
            Button { model.selectLayer(i) } label: {
                HStack(spacing: 12) {
                    PixelImage(grid: cel, checker: true)
                        .frame(width: 40, height: 40)
                        .background(Theme.ink)
                        .opacity(layer.isVisible ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.name)
                            .font(AppFont.body(15, .bold, relativeTo: .body))
                            .foregroundStyle(layer.isVisible ? Theme.cream : Theme.muted)
                            .lineLimit(1)
                        if active {
                            Text("Drawing here").font(AppFont.pixel(10)).foregroundStyle(Theme.accent)
                        }
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
                (layer.isVisible ? PixelIcon.eye : .eyeOff).view(size: 20)
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? Text("Hide layer") : Text("Show layer"))

            Menu {
                Button {
                    renameText = layer.name
                    renamingIndex = i
                } label: { Label("Rename", systemImage: "pencil") }
                Button { model.moveLayer(i, by: 1) } label: { Label("Move up", systemImage: "arrow.up") }
                    .disabled(model.layerMoveTarget(i, by: 1) == nil)
                Button { model.moveLayer(i, by: -1) } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(model.layerMoveTarget(i, by: -1) == nil)
                LayerFolderMenu(model: model, index: i)
                Button {
                    model.selectLayer(i)
                    model.mergeLayerDown()
                } label: { Label("Merge down", systemImage: "square.2.layers.3d.bottom.filled") }
                    .disabled(i == 0)
                Divider()
                Button(role: .destructive) { model.deleteLayer(i) } label: { Label("Delete layer", systemImage: "trash") }
                    .disabled(model.layers.count == 1)
            } label: {
                PixelIcon.more.view(size: 20)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("More for \(layer.name)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(active ? Theme.accent : Theme.line, lineWidth: 2))
    }
}
