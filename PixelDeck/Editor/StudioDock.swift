import SwiftUI
import UIKit

/// The Studio's bottom dock (or side panel when there's room): everything a thumb needs.
///   A: play/pause + frame thumbnails + add frame
///   B: the sprite's 10-colour palette (long-press a swatch to change it)
///   C: tools — pencil, eraser, fill, shapes, picker, mirror, select
///   D: gallery, undo, redo, onion skin, frame rate, export
struct StudioDock: View {
    let model: EditorModel
    var onGallery: () -> Void
    var onExport: () -> Void
    var onEditSwatch: (Int) -> Void
    var onTrace: () -> Void = {}
    var onPalettes: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            FrameRow(model: model)
            PaletteRow(model: model, onEdit: onEditSwatch, onPalettes: onPalettes)
            ExtraColorsRow(model: model)
            ToolRow(model: model)
            ActionRow(model: model, onGallery: onGallery, onExport: onExport, onTrace: onTrace)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}

// MARK: A — frames

/// Play/pause, the frame thumbnails and the dashed "+". `thumb` sets the thumbnail size
/// (40 × 52 in the dock, 44 × 58 in the Flipbook bottom bar).
struct FrameRow: View {
    let model: EditorModel
    @Environment(StudioPanelState.self) private var panels: StudioPanelState?
    var thumb = CGSize(width: 40, height: 52)
    var playSize: CGFloat = 52
    /// The Mac timeline has Play in the toolbar instead, and numbers its frames.
    var showsPlay = true
    var numbered = false

    var body: some View {
        HStack(spacing: 8) {
            if showsPlay {
                Button {
                    model.isPlaying.toggle()
                } label: {
                    (model.isPlaying ? PixelIcon.pause : .play).view(size: 18)
                        .frame(width: playSize, height: playSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PrimaryButtonStyle(depth: 4))
                .disabled(model.frameCount < 2 && !model.isPlaying)
                .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
                .help("Play or pause the animation. Key: Space")
                .tourHighlight(.play)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 5) {
                        ForEach(Array(model.project.frames.enumerated()), id: \.element.id) { index, frame in
                            thumbnail(frame, index: index).id(frame.id)
                        }
                        Button { model.addKeyframe() } label: {
                            PixelIcon.plus.view(size: 16, lineWidth: 2.5)
                                .foregroundStyle(Theme.accent)
                                .frame(width: thumb.width, height: thumb.height)
                                .overlay(Rectangle().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add frame")
                        .help("New frame: add a frame after this one. Key: N")
                    }
                }
                .onChange(of: model.currentIndex) { _, i in
                    guard model.project.frames.indices.contains(i) else { return }
                    withAnimation { proxy.scrollTo(model.project.frames[i].id, anchor: .center) }
                }
            }
        }
        .frame(height: showsPlay ? max(playSize, thumb.height) : thumb.height)
        .padding(.bottom, 4)          // room for the play button's pressed-in shadow
    }

    private func thumbnail(_ frame: Frame, index: Int) -> some View {
        let current = index == model.currentIndex
        return Button {
            model.isPlaying = false
            model.selectFrame(index)
        } label: {
            PixelImage(frame: frame, checker: false)
                .padding(4)
                .frame(width: thumb.width, height: thumb.height)
                .background(Theme.ink)
                .overlay(Rectangle().strokeBorder(current ? Theme.accent : (index == model.currentIndex - 1 ? Theme.muted : Theme.line), lineWidth: 2))
                .overlay(alignment: .topLeading) {
                    if numbered {
                        Text(verbatim: "\(index + 1)").font(AppFont.pixel(8)).foregroundStyle(Theme.muted).padding(3)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    // A frame with a sound on it.
                    if model.hasSound(onFrame: index) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(2)
                            .background(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // Frames held for more than one beat say so.
                    if frame.hold > 1 {
                        Text(verbatim: "×\(frame.hold)")
                            .font(AppFont.pixel(8))
                            .foregroundStyle(Theme.onAccent2)
                            .padding(.horizontal, 2)
                            .background(Theme.accent2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tourHighlight(.frame(index))
        .contextMenu {
            Button { model.duplicateFrame(at: index) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Picker(selection: Binding(get: { frame.hold }, set: { model.setHold($0, at: index) })) {
                ForEach(Array(Set(Frame.holdChoices + [frame.hold])).sorted(), id: \.self) { n in Text(verbatim: "×\(n)").tag(n) }
            } label: {
                Label("Hold this frame", systemImage: "timer")
            }
            .pickerStyle(.menu)
            if let panels {
                Button {
                    model.isPlaying = false
                    model.selectFrame(index)
                    panels.sound = true
                } label: { Label("Sound…", systemImage: "speaker.wave.2") }
            }
            TransformMenu(model: model, frame: index)
            Button { model.copyFrameToClipboard(at: index) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { model.pasteClipboard(at: index, asNewFrame: false) } label: {
                Label("Paste over this frame", systemImage: "doc.on.clipboard")
            }
            .disabled(FrameClipboard.shared.clip == nil)
            Button { model.pasteClipboard(at: index, asNewFrame: true) } label: {
                Label("Paste as new frame after", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(FrameClipboard.shared.clip == nil)
            Button { model.moveFrame(from: index, by: -1) } label: { Label("Move earlier", systemImage: "arrow.left") }
                .disabled(index == 0)
            Button { model.moveFrame(from: index, by: 1) } label: { Label("Move later", systemImage: "arrow.right") }
                .disabled(index == model.frameCount - 1)
            Button(role: .destructive) { model.deleteFrame(at: index) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityLabel(current ? Text("Frame \(index + 1), selected") : Text("Frame \(index + 1)"))
        .help(Text("Frame \(index + 1): click to work on it. Right-click to duplicate, hold, add sound or delete."))
        .accessibilityValue(model.hasSound(onFrame: index) ? Text("Has sound") : Text(verbatim: ""))
    }
}

/// The colours beyond the ten swatches (ramps, photo colours, adjusted colours), as a thin
/// scrolling row under the palette. Hidden until there are some.
struct ExtraColorsRow: View {
    let model: EditorModel

    var body: some View {
        if !model.project.extraColors.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.project.extraColors.enumerated()), id: \.offset) { _, c in
                        let selected = c == model.color && model.tool != .eraser
                        Rectangle()
                            .fill(c.color)
                            .frame(width: 26, height: 22)
                            .overlay(Rectangle().strokeBorder(selected ? Theme.text : Theme.line, lineWidth: selected ? 2 : 1))
                            .contentShape(Rectangle())
                            .onTapGesture { model.pickColor(c) }
                            .contextMenu {
                                Button(role: .destructive) { model.removeExtraColor(c) } label: {
                                    Label("Remove from my colours", systemImage: "trash")
                                }
                            }
                            .accessibilityElement()
                            .accessibilityLabel(Text("Colour \(c.hexString)"))
                            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { model.pickColor(c) }
                    }
                }
                .padding(.horizontal, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("More colours")
        }
    }
}

// MARK: B — palette

/// The sprite's palette. A full-width row in the dock; a vertical rail or a grid in the iPhone Duo
/// layouts (`columns` set, with fixed-size swatches).
struct PaletteRow: View {
    let model: EditorModel
    var onEdit: (Int) -> Void
    /// Opens the Colours panel (colour picker and ready-made palettes).
    var onPalettes: (() -> Void)? = nil
    /// nil: one row filling the width. Otherwise a grid this many columns wide.
    var columns: Int? = nil
    var swatch = CGSize(width: 52, height: 40)

    var body: some View {
        Group {
            if let columns {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(swatch.width), spacing: 6), count: columns), spacing: 6) {
                    swatches(fixed: true)
                    palettesButton(fixed: true)
                }
                .padding(4)
            } else {
                HStack(spacing: 6) {
                    swatches(fixed: false)
                    palettesButton(fixed: false)
                }
                    .padding(.horizontal, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette")
    }

    @ViewBuilder
    private func palettesButton(fixed: Bool) -> some View {
        if let onPalettes {
            Button(action: onPalettes) {
                PixelIcon.swatches.view(size: 16)
                    .foregroundStyle(Theme.text)
                    .frame(width: fixed ? swatch.width : 30, height: fixed ? swatch.height : 34)
                    .background(Theme.tool)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colours and palettes")
        }
    }

    @ViewBuilder
    private func swatches(fixed: Bool) -> some View {
        ForEach(Array(model.palette.enumerated()), id: \.offset) { i, c in
            let selected = c == model.color && model.tool != .eraser
            Rectangle()
                .fill(c.color)
                .frame(maxWidth: fixed ? swatch.width : .infinity)
                .frame(width: fixed ? swatch.width : nil, height: fixed ? swatch.height : 34)
                .overlay {
                    if selected {
                        // 2 pt gap in the surface colour, then a 2 pt ring in the text colour.
                        Rectangle().strokeBorder(Theme.text, lineWidth: 2).padding(-4)
                        Rectangle().strokeBorder(Theme.surface, lineWidth: 2).padding(-2)
                    } else {
                        Rectangle().strokeBorder(Theme.line, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.pickColor(c) }
                .onLongPressGesture(minimumDuration: 0.4) { onEdit(i) }
                .accessibilityElement()
                .accessibilityLabel(Text("Colour \(c.hexString)"))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { model.pickColor(c) }
                .accessibilityAction(named: Text("Change colour")) { onEdit(i) }
                .help(Text("Colour \(i + 1): click to draw with it, press and hold to change it. Keys: 1 to 0"))
                .tourHighlight(.swatch(i))
        }
    }
}

// MARK: C — tools

/// The tools. A row in the dock; a vertical rail or a 2-column grid in the iPhone Duo layouts.
struct ToolRow: View {
    let model: EditorModel
    /// nil: one row filling the width. Otherwise a grid of fixed tiles this many columns wide.
    var columns: Int? = nil
    /// The side of a fixed tile, and the gap between tiles.
    var tile: CGFloat = 52
    var spacing: CGFloat = 6
    /// Shows the second mirror (top and bottom) beside the first. Rails have room for it; the
    /// iPhone's row of seven doesn't, and keeps it in the brush options.
    private var bothMirrors: Bool { columns != nil }

    var body: some View {
        if let columns {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: spacing), count: columns), spacing: spacing) {
                tiles(fixed: true)
            }
            // Only as wide as its tiles: a grid otherwise stretches across whatever it is put in.
            .frame(width: CGFloat(columns) * tile + CGFloat(columns - 1) * spacing)
        } else {
            HStack(spacing: 6) { tiles(fixed: false) }
        }
    }

    private var iconSize: CGFloat { tile < 48 ? 20 : 22 }

    @ViewBuilder
    private func tiles(fixed: Bool) -> some View {
        tool(.pencil, icon: .pencil, fixed: fixed)
        tool(.eraser, icon: .eraser, fixed: fixed)
        tool(.fill, icon: .fill, fixed: fixed)
        // One tile for all shapes; its options strip picks which one.
        tool(.shape, icon: model.shapeKind.icon, fixed: fixed)
        tool(.eyedropper, icon: .picker, fixed: fixed)
        // Mirror is a mode that works with pencil, eraser, fill and shapes.
        Button { model.mirror.toggle() } label: {
            PixelIcon.mirror.view(size: iconSize).tileFrame(fixed ? tile : nil)
        }
        .buttonStyle(TileButtonStyle(active: model.mirror))
        .accessibilityLabel("Mirror")
        .accessibilityAddTraits(model.mirror ? .isSelected : [])
        .help("Mirror left and right: what you draw on one side is copied on the other. Key: Y")
        if bothMirrors {
            Button { model.mirrorVertical.toggle() } label: {
                PixelIcon.mirror.view(size: iconSize).rotationEffect(.degrees(90)).tileFrame(fixed ? tile : nil)
                    .overlay(alignment: .topTrailing) {
                        if !model.access.allowsArtistBrushes { ProBadge().scaleEffect(0.6).offset(x: 3, y: -3) }
                    }
            }
            .buttonStyle(TileButtonStyle(active: model.mirrorVertical))
            .accessibilityLabel("Mirror top and bottom")
            .accessibilityHint("With Mirror left and right on too, you draw one quarter and the other three are drawn for you")
            .accessibilityAddTraits(model.mirrorVertical ? .isSelected : [])
            .help("Mirror top and bottom: what you draw above is copied below. With both mirrors on, draw one quarter and the other three are drawn for you: good for tiles and patterns. Key: Shift-Y")
        }
        tool(.select, icon: .select, fixed: fixed)
    }

    private func tool(_ t: Tool, icon: PixelIcon, fixed: Bool) -> some View {
        let active = model.tool == t
        return Button {
            model.isPlaying = false
            model.tool = t
        } label: {
            icon.view(size: iconSize).tileFrame(fixed ? tile : nil)
        }
        .buttonStyle(TileButtonStyle(active: active))
        .accessibilityLabel(Text(t.title))
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(t.tip)
    }
}

private extension View {
    /// `side`: a square tile of that size; nil: 52 pt high, sharing the width.
    func tileFrame(_ side: CGFloat?) -> some View {
        frame(width: side, height: side ?? 52)
            .frame(maxWidth: side ?? .infinity)
            .contentShape(Rectangle())
    }
}

// MARK: D — actions

private struct ActionRow: View {
    let model: EditorModel
    var onGallery: () -> Void
    var onExport: () -> Void
    var onTrace: () -> Void

    static let fpsChoices = [1, 2, 3, 4, 6, 8, 10, 12, 15, 24, 30, 60]

    var body: some View {
        HStack(spacing: 6) {
            action(.gallery, color: Theme.muted, label: "Gallery", action: onGallery)
            action(.undo, color: Theme.text, label: "Undo") { model.undo() }
                .disabled(!model.canUndo)
                .tourHighlight(.undo)
            action(.redo, color: Theme.text, label: "Redo") { model.redo() }
                .disabled(!model.canRedo)
                .tourHighlight(.redo)
            Button { model.onionSkinEnabled.toggle() } label: {
                PixelIcon.onion.view(size: 20)
                    .foregroundStyle(model.onionSkinEnabled ? Theme.accent : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(model.onionSkinEnabled ? Theme.tool : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Onion skin")
            .accessibilityAddTraits(model.onionSkinEnabled ? .isSelected : [])
            .contextMenu { OnionMenu(model: model, onTrace: onTrace) }
            .accessibilityAction(named: "Tracing image") { onTrace() }
            .tourHighlight(.onion)
            Menu {
                Picker("Frame rate", selection: Binding(get: { model.project.fps }, set: { model.setFPS($0) })) {
                    ForEach(Self.fpsChoices, id: \.self) { Text("\($0) fps").tag($0) }
                }
                TimingPicker(model: model)
            } label: {
                Text(verbatim: "\(model.project.fps)fps")
                    .font(AppFont.pixel(11))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Frame rate, \(model.project.fps) frames per second"))
            action(.export, color: Theme.muted, label: "Export", action: onExport)
        }
    }

    private func action(_ icon: PixelIcon, color: Color, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.view(size: 20)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(DimWhenDisabled())
        .accessibilityLabel(label)
    }
}

private struct DimWhenDisabled: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.3)
    }
}

// MARK: Colour editor

/// Apple's colour picker (grid, spectrum, sliders and eyedropper) for changing a palette swatch,
/// presented modally by UIKit. It mustn't be embedded in a SwiftUI sheet: its eyedropper hides the
/// picker by dismissing its own presentation, which crashes when it isn't the presented controller.
@MainActor
final class SystemColorPicker: NSObject, UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    /// Kept alive while the picker is on screen (it's the picker's delegate).
    private static var current: SystemColorPicker?
    private let onChange: (RGBA, Bool) -> Void
    private let onDone: () -> Void
    private var finished = false

    private init(onChange: @escaping (RGBA, Bool) -> Void, onDone: @escaping () -> Void) {
        self.onChange = onChange
        self.onDone = onDone
    }

    /// `onChange(colour, final)`: final is false while dragging (show it), true once settled (save it).
    static func present(initial: RGBA, onChange: @escaping (RGBA, _ final: Bool) -> Void, onDone: @escaping () -> Void) {
        guard current == nil, let top = topViewController() else { onDone(); return }
        let picker = SystemColorPicker(onChange: onChange, onDone: onDone)
        let vc = UIColorPickerViewController()
        vc.supportsAlpha = false
        vc.selectedColor = UIColor(red: CGFloat(initial.r) / 255, green: CGFloat(initial.g) / 255,
                                   blue: CGFloat(initial.b) / 255, alpha: 1)
        vc.delegate = picker
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        vc.presentationController?.delegate = picker
        current = picker
        top.present(vc, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
        Self.current = nil
    }

    func colorPickerViewController(_ vc: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        onChange(RGBA(Color(uiColor: color)), !continuously)
    }

    /// The picker's close button.
    func colorPickerViewControllerDidFinish(_ vc: UIColorPickerViewController) { finish() }

    /// Swiped down.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
}

/// Identifies which swatch is being edited (for `.sheet(item:)`).
struct SwatchEdit: Identifiable, Equatable {
    let index: Int
    var id: Int { index }
}

extension ShapeKind {
    var icon: PixelIcon {
        switch self {
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .circle
        case .triangle: .triangle
        case .diamond: .diamond
        case .pentagon: .pentagon
        case .hexagon: .hexagon
        case .octagon: .octagon
        case .parallelogram: .parallelogram
        case .star: .star
        }
    }
}

/// Long-press menu for the onion skin buttons: strength, and the tracing picture.
struct OnionMenu: View {
    let model: EditorModel
    var onTrace: () -> Void
    @Environment(StudioPanelState.self) private var panels: StudioPanelState?

    var body: some View {
        Picker(selection: Binding(get: { model.onionOpacity }, set: { model.onionOpacity = $0 })) {
            ForEach([0.2, 0.38, 0.6], id: \.self) { v in Text(v, format: .percent).tag(v) }
        } label: {
            Label("Onion skin strength", systemImage: "square.2.layers.3d")
        }
        .pickerStyle(.menu)
        if let panels {
            Button { panels.onionTiming = true } label: { Label("Onion skin and timing…", systemImage: "timer") }
        }
        Button(action: onTrace) { Label("Tracing image…", systemImage: "photo") }
    }
}

/// Flip and rotate. For a frame's long-press menu (`frame` set) it turns that frame; in the
/// sprite menu it offers the current frame or every frame.
struct TransformMenu: View {
    let model: EditorModel
    let frame: Int?

    var body: some View {
        Menu {
            if let frame {
                ForEach(FrameTransform.allCases) { t in
                    Button {
                        model.selectFrame(frame)
                        model.transform(t, allFrames: false)
                    } label: { Label { Text(t.title) } icon: { Image(systemName: t.systemImage) } }
                }
            } else {
                Section("This frame") {
                    ForEach(FrameTransform.allCases) { t in
                        Button { model.transform(t, allFrames: false) } label: { Label { Text(t.title) } icon: { Image(systemName: t.systemImage) } }
                    }
                }
                Section("All frames") {
                    ForEach(FrameTransform.allCases) { t in
                        Button { model.transform(t, allFrames: true) } label: { Label { Text(t.title) } icon: { Image(systemName: t.systemImage) } }
                    }
                }
            }
        } label: {
            Label("Flip & rotate", systemImage: "rotate.right")
        }
    }
}
