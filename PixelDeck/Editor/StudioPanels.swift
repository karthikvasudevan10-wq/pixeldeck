import SwiftUI

/// Which of the Studio's v2 panels are open. Shared through the environment so the dock, the
/// strips, the menus and (on iPad and Mac) the inspector and menu bar can all open them.
@Observable
final class StudioPanelState {
    var presets = false
    var onionTiming = false
    var adjust = false
}

/// Presents the v2 panels. Kept apart from `EditorView.body` so that body stays quick to compile.
struct StudioPanelSheets: ViewModifier {
    let model: EditorModel
    @Bindable var panels: StudioPanelState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $panels.presets) { PresetSheet(model: model) }
            .sheet(isPresented: $panels.onionTiming) { OnionTimingSheet(model: model) }
            .sheet(isPresented: $panels.adjust) { AdjustColorsSheet(model: model) }
    }
}

// MARK: Strip chips

/// A text chip for the option strips above the dock.
struct StripChip: View {
    let title: Text
    var on = false
    var pro = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            title
                .font(AppFont.pixel(11))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(minWidth: 40, minHeight: 36)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) { if pro { ProBadge().scaleEffect(0.75).offset(x: 6, y: -6) } }
        }
        .buttonStyle(TileButtonStyle(active: on))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A strip of chips that scrolls sideways only when it doesn't fit.
struct OptionStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
        .background(Theme.chip)
    }

    private var row: some View {
        HStack(spacing: 6) { content }.padding(6)
    }
}

// MARK: Shading assistant

/// Shown above the brush strip while the shading brush is on: where the light comes from, the
/// ramp it steps through, and Shade or Highlight.
struct ShadingPanel: View {
    let model: EditorModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            lightGrid
            VStack(alignment: .leading, spacing: 6) {
                Text(model.lightDirection.title)
                    .font(AppFont.body(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(Theme.cream)
                HStack(spacing: 0) {
                    ForEach(Array(model.ramp(for: model.color).enumerated()), id: \.offset) { _, c in
                        Rectangle().fill(c.color).frame(width: 18, height: 14)
                    }
                }
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                .accessibilityHidden(true)
                Text("Ramp from your colour · \(model.rampSteps) steps", comment: "Shading assistant; plural")
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    ForEach(ShadeMode.allCases) { mode in
                        StripChip(title: Text(mode.title), on: model.shadeMode == mode) { model.shadeMode = mode }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 380)
        .background(Theme.chip)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shading assistant")
    }

    /// A 3 × 3 picker: the middle is the art, the eight around it are where the light can be.
    private var lightGrid: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { col in
                        cell(row * 3 + col)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if let direction = LightDirection.allCases.first(where: { $0.gridIndex == index }) {
            let on = model.lightDirection == direction
            Button { model.lightDirection = direction } label: {
                Rectangle()
                    .fill(on ? Theme.accent2 : Theme.tool)
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().strokeBorder(on ? Theme.accent2 : Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(direction.title))
            .accessibilityAddTraits(on ? .isSelected : [])
        } else {
            Rectangle()
                .fill(model.color.color)
                .frame(width: 26, height: 26)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}

// MARK: Selection

/// Selection tools: how to select (box, lasso, wand) and, once something is selected, what to do
/// with it (rotate, scale, flip, animate, recolour, tween, delete).
struct SelectionStrip: View {
    let model: EditorModel
    var onTween: () -> Void
    @Environment(StudioPanelState.self) private var panels: StudioPanelState?
    @State private var dial: Dial?

    private enum Dial { case rotate, scale }

    var body: some View {
        VStack(spacing: 8) {
            if model.hasSelection {
                if let dial { dialRow(dial) }
                OptionStrip {
                    StripChip(title: Text("Rotate"), on: dial == .rotate) { dial = dial == .rotate ? nil : .rotate }
                    StripChip(title: Text("Scale"), on: dial == .scale) { dial = dial == .scale ? nil : .scale }
                    Menu {
                        Button { model.flipSelection(horizontal: true) } label: {
                            Label { Text(FrameTransform.flipHorizontal.title) } icon: { Image(systemName: FrameTransform.flipHorizontal.systemImage) }
                        }
                        Button { model.flipSelection(horizontal: false) } label: {
                            Label { Text(FrameTransform.flipVertical.title) } icon: { Image(systemName: FrameTransform.flipVertical.systemImage) }
                        }
                    } label: {
                        Text("Flip")
                            .font(AppFont.pixel(11))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 40, minHeight: 36)
                            .background(Theme.tool)
                            .contentShape(Rectangle())
                    }
                    Theme.line.frame(width: 2, height: 28)
                    if model.floating != nil {
                        Button(action: onTween) {
                            PixelIcon.tween.view(size: 16).frame(width: 36, height: 36).contentShape(Rectangle())
                        }
                        .buttonStyle(TileButtonStyle())
                        .disabled(!model.canTween)
                        .accessibilityLabel("Tween")
                        .accessibilityHint("Draws the in-between frames along the way you dragged the selection")
                    }
                    if let panels {
                        StripChip(title: Text("Animate")) { panels.presets = true }
                        StripChip(title: Text("Colours")) { panels.adjust = true }
                    }
                    Button { model.deleteSelection(); dial = nil } label: {
                        PixelIcon.trash.view(size: 18).frame(width: 36, height: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityLabel("Delete selected pixels")
                    Button { model.commitSelection(); dial = nil } label: {
                        Text("Done").font(AppFont.pixel(12)).padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(PrimaryButtonStyle(depth: 3))
                }
            }
            OptionStrip {
                ForEach(SelectionMode.allCases) { mode in
                    StripChip(title: Text(mode.title), on: model.selectionMode == mode) {
                        model.selectionMode = mode
                    }
                }
                if !model.hasSelection {
                    Text(model.selectionMode.hint)
                        .font(AppFont.body(12, .medium, relativeTo: .caption))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.bottom, 3)
        .padding(.horizontal, 12)
        .onChange(of: model.hasSelection) { _, has in if !has { dial = nil } }
    }

    private func dialRow(_ dial: Dial) -> some View {
        let t = model.selectionTransform
        return HStack(spacing: 8) {
            // The design's read-out: "−12° · 82%".
            Text(verbatim: "\(Int(t.angle.rounded()))° · \(Int((t.scale * 100).rounded()))%")
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.accent2)
                .frame(minWidth: 86, alignment: .leading)
            switch dial {
            case .rotate:
                Slider(value: Binding(get: { model.selectionTransform.angle }, set: { v in
                    var next = model.selectionTransform
                    next.angle = v.rounded()
                    model.setSelectionTransform(next)
                }), in: -180...180, step: 1)
                .tint(Theme.accent)
                .accessibilityLabel("Rotation")
                Button { model.rotateSelection(by: 90) } label: {
                    Image(systemName: "rotate.right").frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel("Quarter turn")
            case .scale:
                Slider(value: Binding(get: { model.selectionTransform.scale }, set: { v in
                    var next = model.selectionTransform
                    next.scale = (v * 20).rounded() / 20
                    model.setSelectionTransform(next)
                }), in: PatchTransform.scaleRange)
                .tint(Theme.accent)
                .accessibilityLabel("Size")
                Button {
                    var next = model.selectionTransform
                    next.scale = 1
                    model.setSelectionTransform(next)
                } label: {
                    Text(verbatim: "1:1").font(AppFont.pixel(11)).frame(width: 40, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel("Original size")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 420)
        .background(Theme.chip)
    }
}

// MARK: Animation presets

/// "Animate this": pick a preset, the number of frames and how far, and the frames are drawn.
struct PresetSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var preset: AnimationPreset = .bounce
    @State private var frames = AnimationPreset.defaultFrames
    @State private var amount = Double(AnimationPreset.defaultAmount)
    @State private var upgrade: ProFeature?

    private var preview: [PixelGrid] { model.presetPreview(preset, frames: frames, amount: Int(amount)) }
    private var locked: Bool { !model.access.allows(preset) }
    private var overFreeLimit: Bool { frames - 1 > model.remainingFrameAllowance && !model.access.isPro }
    private var overMemoryLimit: Bool { frames - 1 > model.remainingFrameAllowance && model.access.isPro }

    var body: some View {
        let shown = preview
        return VStack(spacing: 0) {
            SheetHeader(title: "Animate this", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if shown.isEmpty {
                        Text("Draw something first, then come back and it will move.")
                            .font(AppFont.body(15, relativeTo: .body))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .multilineTextAlignment(.center)
                    } else {
                        TweenPreview(frames: shown, fps: model.project.fps)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                            .id(preset)
                    }
                    Text("Applies to the selection, or the whole layer. The frames are drawn for you, as real pixels you can edit.")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(AnimationPreset.allCases) { p in
                            let on = p == preset
                            Button { preset = p } label: {
                                Text(p.title)
                                    .font(AppFont.body(14, .medium, relativeTo: .subheadline))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .overlay(alignment: .topTrailing) {
                                        if !model.access.allows(p) { ProBadge().padding(3) }
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(TileButtonStyle(active: on, fill: Theme.surface))
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Frames")
                        HStack(spacing: 6) {
                            stepButton("−", label: "Fewer frames") { frames = max(AnimationPreset.frameRange.lowerBound, frames - 1) }
                            Text("\(frames) frames", comment: "Animation preset frame count (plural)")
                                .font(AppFont.pixel(13))
                                .foregroundStyle(Theme.cream)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Theme.surface)
                            stepButton("+", label: "More frames") { frames = min(AnimationPreset.frameRange.upperBound, frames + 1) }
                        }
                        if overFreeLimit {
                            note("Free sprites can have up to \(FeatureAccess.freeFrameLimit) frames (\(model.remainingFrameAllowance) left).")
                        } else if overMemoryLimit {
                            note("This sprite can have up to \(model.frameLimit) frames (\(model.remainingFrameAllowance) left).")
                        }
                    }

                    if preset.usesAmount {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SectionLabel(text: LocalizedStringKey(String(localized: preset.amountTitle)))
                                Spacer()
                                Text(verbatim: "\(Int(amount)) px").font(AppFont.pixel(12)).foregroundStyle(Theme.accent2)
                            }
                            Slider(value: $amount, in: Double(AnimationPreset.amountRange.lowerBound)...Double(AnimationPreset.amountRange.upperBound), step: 1)
                                .tint(Theme.accent)
                                .accessibilityLabel(Text(preset.amountTitle))
                        }
                    }
                }
                .padding(16)
            }

            Button(action: create) {
                HStack(spacing: 10) {
                    PixelIcon.play.view(size: 18, lineWidth: 2.5)
                    Text("Draw \(frames) frames", comment: "Button that draws the animation preset's frames (plural)").font(AppFont.pixel(17))
                    if locked { ProBadge() }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(shown.isEmpty || overMemoryLimit)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .presentationDetents([.large])
        .proUpgradeSheet($upgrade)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: symbol).font(AppFont.pixel(18)).frame(width: 44, height: 44)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(label)
    }

    private func create() {
        // Offer Pro here (the editor can't show a sheet over this one), and stay open so a free
        // preset or fewer frames can be chosen instead.
        if locked { upgrade = .animationPresets; return }
        if overFreeLimit { upgrade = .unlimitedFrames; return }
        if model.applyPreset(preset, frames: frames, amount: Int(amount)) { dismiss() }
    }
}

// MARK: Onion skin and timing

/// How many frames the onion skin shows, how long this frame is held, and what happens at the end.
struct OnionTimingSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Onion skin and timing", onClose: { dismiss() })
            ScrollView {
                OnionTimingControls(model: model).padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
    }
}

/// The controls of the Onion skin and timing panel (also shown in the desk inspector).
struct OnionTimingControls: View {
    let model: EditorModel

    /// The blue used for "frames after", matching the onion skin's blue.
    private static let ahead = Color(red: 0x5B / 255, green: 0x8D / 255, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { model.onionSkinEnabled }, set: { model.onionSkinEnabled = $0 })) {
                    Text("Onion skin").font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                }
                .tint(Theme.accent)
                counter("Frames before", value: model.onionBefore, range: 0...EditorModel.maxOnionBefore, tint: Theme.accent) {
                    model.onionBefore = $0
                }
                counter("Frames after", value: model.onionAfter, range: 0...EditorModel.maxOnionAfter, tint: Self.ahead) {
                    model.onionAfter = $0
                }
                Text("Older frames fade more. Pink looks back, blue looks ahead.")
                    .font(AppFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    SectionLabel(text: "Strength")
                    Spacer()
                    ForEach([0.2, 0.38, 0.6], id: \.self) { v in
                        StripChip(title: Text(v, format: .percent), on: model.onionOpacity == v) { model.onionOpacity = v }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                let hold = model.project.frames[model.currentIndex].hold
                SectionLabel(text: "Hold")
                counter(LocalizedStringKey(String(localized: "Hold frame \(model.currentIndex + 1)", comment: "Per-frame hold; the placeholder is the frame number")),
                        value: hold, range: 1...Frame.maxHold, tint: Theme.accent2, prefix: "×") {
                    model.setHold($0, at: model.currentIndex)
                }
                Text("Stays on screen for \(hold) beats", comment: "Per-frame hold; plural")
                    .font(AppFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "When it ends")
                ChoiceRow(options: LoopMode.allCases,
                          selection: Binding(get: { model.project.loopMode }, set: { model.setLoopMode($0) })) { Text($0.title) }
            }
        }
    }

    private func counter(_ title: LocalizedStringKey, value: Int, range: ClosedRange<Int>, tint: Color, prefix: String = "",
                         set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(AppFont.body(15, relativeTo: .body)).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Button { set(max(range.lowerBound, value - 1)) } label: {
                Text(verbatim: "−").font(AppFont.pixel(18)).frame(width: 40, height: 40)
            }
            .buttonStyle(TileButtonStyle())
            .disabled(value <= range.lowerBound)
            Text(verbatim: "\(prefix)\(value)")
                .font(AppFont.pixel(15))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Theme.ink)
            Button { set(min(range.upperBound, value + 1)) } label: {
                Text(verbatim: "+").font(AppFont.pixel(18)).frame(width: 40, height: 40)
            }
            .buttonStyle(TileButtonStyle())
            .disabled(value >= range.upperBound)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: "\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min(range.upperBound, value + 1))
            case .decrement: set(max(range.lowerBound, value - 1))
            @unknown default: break
            }
        }
    }
}

// MARK: Adjust colours

/// Brightness, contrast, hue and saturation for the selection, the layer, the frame or every
/// frame, previewed live on the canvas behind the sheet.
struct AdjustColorsSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var adjustment = ColorAdjustment()
    @State private var scope: AdjustScope = .layer
    @State private var snap = false
    @State private var newColors = 0
    @State private var before: CGImage?
    @State private var applied = false
    @State private var upgrade: ProFeature?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Adjust colours", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        pane(Text("Before"), image: before)
                        pane(Text("After"), image: PixelRenderer.cgImage(model.currentGrid))
                    }
                    Text("Each pixel keeps its own light and dark")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)

                    slider("Brightness", value: $adjustment.brightness, range: -100...100, unit: "")
                    slider("Contrast", value: $adjustment.contrast, range: -100...100, unit: "")
                    slider("Hue", value: $adjustment.hue, range: -180...180, unit: "°")
                    slider("Saturation", value: $adjustment.saturation, range: -100...100, unit: "")

                    ChoiceRow(options: model.adjustScopes, selection: $scope) { s in
                        HStack(spacing: 4) {
                            Text(s.title)
                            if s == .allFrames && !model.access.allowsAdjustAllFrames { ProBadge().scaleEffect(0.8) }
                        }
                    }

                    Toggle(isOn: $snap) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Snap to my palette").font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                            (snap
                                ? Text("On: every pixel takes the nearest colour you already have")
                                : Text("Off: \(newColors) new colours will be added to the palette", comment: "Adjust colours; plural"))
                                .font(AppFont.body(13, relativeTo: .footnote))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.accent)
                }
                .padding(16)
            }
            HStack(spacing: 8) {
                Button { adjustment = ColorAdjustment(); snap = false } label: {
                    Text("Reset").font(AppFont.pixel(15)).frame(width: 110, height: 56).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                Button(action: apply) {
                    PrimaryActionLabel(title: "Apply", icon: .check)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(adjustment.isIdentity && !snap)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .presentationDetents([.large])
        .proUpgradeSheet($upgrade)
        .onAppear {
            model.beginAdjustment()
            scope = model.adjustScopes.first ?? .layer
            before = PixelRenderer.cgImage(model.currentGrid)
        }
        .onChange(of: adjustment) { _, _ in refresh() }
        .onChange(of: scope) { _, _ in refresh() }
        .onChange(of: snap) { _, _ in refresh() }
        .onDisappear { if !applied { model.cancelAdjustment() } }
    }

    private func refresh() {
        newColors = model.previewAdjustment(adjustment, scope: scope, snapToPalette: snap)
    }

    private func apply() {
        if scope == .allFrames && !model.access.allowsAdjustAllFrames {
            upgrade = .adjustAllFrames
            return
        }
        applied = true
        model.commitAdjustment(adjustment, scope: scope, snapToPalette: snap)
        dismiss()
    }

    private func pane(_ title: Text, image: CGImage?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Checkerboard(cell: 10)
                PixelImage(image: image).padding(8)
            }
            .frame(height: 120)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            title.font(AppFont.pixel(10)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(AppFont.body(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.text)
                Spacer()
                Text(verbatim: "\(value.wrappedValue > 0 ? "+" : "")\(Int(value.wrappedValue))\(unit)")
                    .font(AppFont.pixel(12))
                    .foregroundStyle(value.wrappedValue == 0 ? Theme.muted : Theme.accent2)
            }
            Slider(value: value, in: range, step: 1)
                .tint(Theme.accent)
                .accessibilityLabel(Text(title))
        }
    }
}
