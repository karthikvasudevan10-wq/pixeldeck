import SwiftUI

/// Plays the animation and sets its speed.
struct PlaybackSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var fps: Double

    init(model: EditorModel) {
        self.model = model
        _fps = State(initialValue: Double(model.project.fps))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1 / fps)) { context in
                    let frames = model.project.frames
                    let i = Int(context.date.timeIntervalSinceReferenceDate * fps) % max(frames.count, 1)
                    PixelImage(frame: frames[min(i, frames.count - 1)])
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(min(i, frames.count - 1) + 1)/\(frames.count)")
                                .font(.caption.monospacedDigit())
                                .padding(6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                }
                .padding(.horizontal, 32)

                VStack {
                    Text("\(Int(fps)) frames per second", comment: "Playback speed (plural)")
                        .font(.headline.monospacedDigit())
                    Slider(value: $fps, in: 1...30, step: 1) {
                        Text("Speed")
                    } onEditingChanged: { editing in
                        if !editing, Int(fps) != model.project.fps { model.setFPS(Int(fps)) }
                    }
                }
                .padding(.horizontal, 32)
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onDisappear {
            if Int(fps) != model.project.fps { model.setFPS(Int(fps)) }
        }
    }
}
