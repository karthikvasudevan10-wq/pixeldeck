import SwiftUI

/// Options for drawing the in-between frames of a moved selection, with a live preview.
struct TweenSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var frameCount: Int
    @State private var easing: Easing = .easeInOut
    @State private var style: TweenPathStyle = .traced
    @State private var mode: TweenMode = .insertFrames
    @State private var upgrade: ProFeature?

    init(model: EditorModel) {
        self.model = model
        _frameCount = State(initialValue: model.suggestedTweenFrames)
    }

    private var preview: [PixelGrid] {
        model.tweenPreview(frameCount: frameCount, easing: easing, style: style, mode: mode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TweenPreview(frames: preview, fps: model.project.fps)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("Path") {
                    Picker("Route", selection: $style) {
                        ForEach(TweenPathStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Timing", selection: $easing) {
                        ForEach(Easing.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Picker("Frames", selection: $mode) {
                        ForEach(TweenMode.allCases) { Text($0.title).tag($0) }
                    }
                    if mode == .insertFrames {
                        Stepper("\(frameCount) new frame\(frameCount == 1 ? "" : "s")", value: $frameCount, in: 1...60)
                        if !model.access.isPro && frameCount > model.remainingFrameAllowance {
                            Label("Free sprites can have up to \(FeatureAccess.freeFrameLimit) frames. \(model.remainingFrameAllowance) left.",
                                  systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if model.followingFrameCount == 0 {
                        Text("There are no frames after this one yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Moves the selection through the next \(model.followingFrameCount) frame\(model.followingFrameCount == 1 ? "" : "s"), keeping everything else in them.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("This frame goes back to the starting position. The last frame ends where you dropped the selection.")
                }
            }
            .navigationTitle("Tween Movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        // Over the free limit: offer Pro here (the editor can't show a sheet over this one)
                        // and stay open so the user can pick fewer frames instead.
                        if mode == .insertFrames && frameCount > model.remainingFrameAllowance && !model.access.isPro {
                            upgrade = .unlimitedFrames
                            return
                        }
                        model.generateTween(frameCount: frameCount, easing: easing, style: style, mode: mode)
                        dismiss()
                    }
                    .disabled(mode == .spreadAcrossFollowing && model.followingFrameCount == 0)
                }
            }
        }
        .presentationDetents([.large])
        .proUpgradeSheet($upgrade)
    }
}

/// Loops a list of frames.
struct TweenPreview: View {
    let frames: [PixelGrid]
    let fps: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / Double(max(fps, 1)))) { context in
            let i = frames.isEmpty ? 0 : Int(context.date.timeIntervalSinceReferenceDate * Double(max(fps, 1))) % frames.count
            Group {
                if frames.indices.contains(i) {
                    PixelImage(grid: frames[i])
                } else {
                    CheckerBackground()
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
