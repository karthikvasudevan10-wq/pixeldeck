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

    private var overFreeLimit: Bool {
        mode == .insertFrames && frameCount > model.remainingFrameAllowance && !model.access.isPro
    }

    private var overMemoryLimit: Bool {
        mode == .insertFrames && frameCount > model.remainingFrameAllowance && model.access.isPro
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Tween", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TweenPreview(frames: preview, fps: model.project.fps)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Route")
                        ChoiceRow(options: TweenPathStyle.allCases, selection: $style) { Text($0.title) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Timing")
                        ChoiceRow(options: Easing.allCases, selection: $easing, columns: 2) { Text($0.title) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Frames")
                        ChoiceRow(options: TweenMode.allCases, selection: $mode) { Text($0.title) }
                        framesDetail
                    }
                    Text("This frame goes back to the starting position. The last frame ends where you dropped the selection.")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
            }

            Button(action: create) {
                PrimaryActionLabel(title: "Create frames", icon: .tween)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled((mode == .spreadAcrossFollowing && model.followingFrameCount == 0) || overMemoryLimit)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .presentationDetents([.large])
        .proUpgradeSheet($upgrade)
    }

    @ViewBuilder
    private var framesDetail: some View {
        if mode == .insertFrames {
            HStack(spacing: 6) {
                stepButton("−", label: "Fewer frames") { frameCount = max(1, frameCount - 1) }
                Text("\(frameCount) new frames", comment: "Tween frame count (plural)")
                    .font(AppFont.pixel(13))
                    .foregroundStyle(Theme.cream)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.surface)
                stepButton("+", label: "More frames") { frameCount = min(60, frameCount + 1) }
            }
            if overFreeLimit {
                note("Free sprites can have up to \(FeatureAccess.freeFrameLimit) frames (\(model.remainingFrameAllowance) left).", color: Theme.muted)
            } else if overMemoryLimit {
                note("This sprite can have up to \(model.frameLimit) frames (\(model.remainingFrameAllowance) left).", color: Theme.accent)
            }
        } else if model.followingFrameCount == 0 {
            note("There are no frames after this one yet.", color: Theme.muted)
        } else {
            note("Moves the selection through the next \(model.followingFrameCount) frames, keeping everything else in them.", color: Theme.muted)
        }
    }

    private func note(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(color)
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: symbol).font(AppFont.pixel(18)).frame(width: 44, height: 44)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(label)
    }

    private func create() {
        // Over the free limit: offer Pro here (the editor can't show a sheet over this one)
        // and stay open so the user can pick fewer frames instead.
        if overFreeLimit {
            upgrade = .unlimitedFrames
            return
        }
        model.generateTween(frameCount: frameCount, easing: easing, style: style, mode: mode)
        dismiss()
    }
}

/// Loops a list of frames on the checkerboard.
struct TweenPreview: View {
    let frames: [PixelGrid]
    let fps: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / Double(max(fps, 1)))) { context in
            let i = frames.isEmpty ? 0 : Int(context.date.timeIntervalSinceReferenceDate * Double(max(fps, 1))) % frames.count
            ZStack {
                Checkerboard(cell: 16)
                if frames.indices.contains(i) {
                    PixelImage(grid: frames[i], checker: false).padding(16)
                }
            }
        }
    }
}

// MARK: Shared sheet pieces

/// Title bar for the app's own sheets: Silkscreen title and a square close button.
struct SheetHeader: View {
    let title: LocalizedStringKey
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(AppFont.pixel(22)).foregroundStyle(Theme.cream)
            Spacer()
            Button(action: onClose) {
                Text(verbatim: "×").font(AppFont.pixel(20)).foregroundStyle(Theme.text).frame(width: 44, height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

/// Square segmented choice: the selected option is a cream tile.
struct ChoiceRow<Option: Hashable & Identifiable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    var columns = 0
    @ViewBuilder var label: (Option) -> Label

    var body: some View {
        let cols = columns > 0 ? columns : options.count
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
            ForEach(options) { o in
                let on = o == selection
                Button { selection = o } label: {
                    label(o)
                        .font(AppFont.body(14, .medium, relativeTo: .subheadline))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(active: on, fill: Theme.surface))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
