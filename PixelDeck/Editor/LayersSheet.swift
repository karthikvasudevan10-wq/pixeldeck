import SwiftUI

/// The sprite's layers, top of the stack first. Tap a layer to draw on it; the eye hides it from
/// the canvas, thumbnails and exports. Changes apply to every frame.
struct LayersSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var renamingIndex: Int?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Layers", onClose: { dismiss() })
            ScrollView {
                VStack(spacing: 6) {
                    // Shown top-down, as they stack on the canvas.
                    ForEach(Array(model.layers.indices.reversed()), id: \.self) { i in
                        row(i)
                    }
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
            Text(model.canAddLayer ? "New layers go above the selected one." : "This sprite has as many layers as it can hold.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 16)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .alert("Rename layer", isPresented: Binding(get: { renamingIndex != nil }, set: { if !$0 { renamingIndex = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let i = renamingIndex { model.renameLayer(i, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
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
                    .disabled(i == model.layers.count - 1)
                Button { model.moveLayer(i, by: -1) } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(i == 0)
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
