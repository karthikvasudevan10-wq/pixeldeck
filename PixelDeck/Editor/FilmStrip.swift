import SwiftUI

/// Thumbnails of every keyframe. Tap to jump; long-press for frame actions.
struct FilmStrip: View {
    let model: EditorModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.project.frames.enumerated()), id: \.element.id) { index, frame in
                        Button { model.selectFrame(index) } label: {
                            thumb(frame: frame, index: index)
                        }
                        .buttonStyle(.plain)
                        .id(frame.id)
                        .contextMenu {
                            Button { model.duplicateFrame(at: index) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button { model.moveFrame(from: index, by: -1) } label: { Label("Move earlier", systemImage: "arrow.left") }
                                .disabled(index == 0)
                            Button { model.moveFrame(from: index, by: 1) } label: { Label("Move later", systemImage: "arrow.right") }
                                .disabled(index == model.frameCount - 1)
                            Button(role: .destructive) { model.deleteFrame(at: index) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Button { model.addKeyframe() } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, height: 52)
                            .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add keyframe")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: model.currentIndex) { _, i in
                guard model.project.frames.indices.contains(i) else { return }
                withAnimation { proxy.scrollTo(model.project.frames[i].id, anchor: .center) }
            }
        }
    }

    private func thumb(frame: Frame, index: Int) -> some View {
        let current = index == model.currentIndex
        return PixelImage(frame: frame)
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(current ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: current ? 3 : 1))
            .overlay(alignment: .bottomTrailing) {
                Text(index + 1, format: .number)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(3)
            }
            .accessibilityLabel(current ? Text("Frame \(index + 1), selected") : Text("Frame \(index + 1)"))
    }
}
