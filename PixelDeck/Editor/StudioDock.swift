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

    var body: some View {
        VStack(spacing: 10) {
            FrameRow(model: model)
            PaletteRow(model: model, onEdit: onEditSwatch)
            ToolRow(model: model)
            ActionRow(model: model, onGallery: onGallery, onExport: onExport)
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
    var thumb = CGSize(width: 40, height: 52)
    var playSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 8) {
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
                    }
                }
                .onChange(of: model.currentIndex) { _, i in
                    guard model.project.frames.indices.contains(i) else { return }
                    withAnimation { proxy.scrollTo(model.project.frames[i].id, anchor: .center) }
                }
            }
        }
        .frame(height: max(playSize, thumb.height))
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { model.duplicateFrame(at: index) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { model.moveFrame(from: index, by: -1) } label: { Label("Move earlier", systemImage: "arrow.left") }
                .disabled(index == 0)
            Button { model.moveFrame(from: index, by: 1) } label: { Label("Move later", systemImage: "arrow.right") }
                .disabled(index == model.frameCount - 1)
            Button(role: .destructive) { model.deleteFrame(at: index) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityLabel(current ? Text("Frame \(index + 1), selected") : Text("Frame \(index + 1)"))
    }
}

// MARK: B — palette

/// The sprite's palette. A full-width row in the dock; a vertical rail or a grid in the iPhone Duo
/// layouts (`columns` set, with fixed-size swatches).
struct PaletteRow: View {
    let model: EditorModel
    var onEdit: (Int) -> Void
    /// nil: one row filling the width. Otherwise a grid this many columns wide.
    var columns: Int? = nil
    var swatch = CGSize(width: 52, height: 40)

    var body: some View {
        Group {
            if let columns {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(swatch.width), spacing: 6), count: columns), spacing: 6) {
                    swatches(fixed: true)
                }
                .padding(4)
            } else {
                HStack(spacing: 6) { swatches(fixed: false) }
                    .padding(.horizontal, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette")
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
        }
    }
}

// MARK: C — tools

/// The tools. A row in the dock; a vertical rail or a 2-column grid in the iPhone Duo layouts.
struct ToolRow: View {
    let model: EditorModel
    /// nil: one row filling the width. Otherwise a grid of fixed 52 pt tiles this many columns wide.
    var columns: Int? = nil

    var body: some View {
        if let columns {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 6), count: columns), spacing: 6) {
                tiles(fixed: true)
            }
        } else {
            HStack(spacing: 6) { tiles(fixed: false) }
        }
    }

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
            PixelIcon.mirror.view(size: 22).tileFrame(fixed: fixed)
        }
        .buttonStyle(TileButtonStyle(active: model.mirror))
        .accessibilityLabel("Mirror")
        .accessibilityAddTraits(model.mirror ? .isSelected : [])
        tool(.select, icon: .select, fixed: fixed)
    }

    private func tool(_ t: Tool, icon: PixelIcon, fixed: Bool) -> some View {
        let active = model.tool == t
        return Button {
            model.isPlaying = false
            model.tool = t
        } label: {
            icon.view(size: 22).tileFrame(fixed: fixed)
        }
        .buttonStyle(TileButtonStyle(active: active))
        .accessibilityLabel(Text(t.title))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private extension View {
    func tileFrame(fixed: Bool) -> some View {
        frame(width: fixed ? 52 : nil, height: 52)
            .frame(maxWidth: fixed ? 52 : .infinity)
            .contentShape(Rectangle())
    }
}

// MARK: D — actions

private struct ActionRow: View {
    let model: EditorModel
    var onGallery: () -> Void
    var onExport: () -> Void

    static let fpsChoices = [1, 2, 3, 4, 6, 8, 10, 12, 15, 24, 30]

    var body: some View {
        HStack(spacing: 6) {
            action(.gallery, color: Theme.muted, label: "Gallery", action: onGallery)
            action(.undo, color: Theme.text, label: "Undo") { model.undo() }
                .disabled(!model.canUndo)
            action(.redo, color: Theme.text, label: "Redo") { model.redo() }
                .disabled(!model.canRedo)
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

/// The system colour picker for changing a palette swatch.
struct SwatchEditor: UIViewControllerRepresentable {
    let initial: RGBA
    /// Called with `final == false` while dragging (show it) and `true` when settled (save it).
    var onChange: (RGBA, _ final: Bool) -> Void
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange, onDone: onDone) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let vc = UIColorPickerViewController()
        vc.supportsAlpha = false
        vc.selectedColor = UIColor(red: CGFloat(initial.r) / 255, green: CGFloat(initial.g) / 255,
                                   blue: CGFloat(initial.b) / 255, alpha: 1)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIColorPickerViewController, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onDone = onDone
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var onChange: (RGBA, Bool) -> Void
        var onDone: () -> Void
        init(onChange: @escaping (RGBA, Bool) -> Void, onDone: @escaping () -> Void) {
            self.onChange = onChange
            self.onDone = onDone
        }

        func colorPickerViewController(_ vc: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            onChange(RGBA(Color(uiColor: color)), !continuously)
        }

        /// The picker's own close button dismisses it; tell SwiftUI so the sheet state resets.
        func colorPickerViewControllerDidFinish(_ vc: UIColorPickerViewController) {
            onDone()
        }
    }
}

/// Identifies which swatch is being edited (for `.sheet(item:)`).
struct SwatchEdit: Identifiable {
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
        }
    }
}
