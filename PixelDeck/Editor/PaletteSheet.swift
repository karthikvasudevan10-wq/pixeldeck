import SwiftUI

/// Colours: the sprite's palette, the full colour picker (Apple's, with grid, spectrum and
/// sliders) for the selected swatch, and ready-made palettes to swap in.
struct PaletteSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SwatchEdit?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Colours", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    current
                    presets
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .sheet(item: $editing) { edit in
            SwatchEditor(initial: model.palette[edit.index],
                         onChange: { c, final in model.setPaletteColor(c, at: edit.index, commit: final) },
                         onDone: {
                             model.setPaletteColor(model.palette[edit.index], at: edit.index)
                             editing = nil
                         })
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: This sprite's palette

    private var current: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This sprite").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(Array(model.palette.enumerated()), id: \.offset) { i, c in
                    let selected = model.selectedPaletteIndex == i && model.tool != .eraser
                    Rectangle()
                        .fill(c.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .overlay {
                            if selected {
                                Rectangle().strokeBorder(Theme.text, lineWidth: 2).padding(-4)
                                Rectangle().strokeBorder(Theme.surface, lineWidth: 2).padding(-2)
                            } else {
                                Rectangle().strokeBorder(Theme.line, lineWidth: 1)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.pickColor(c) }
                        .onLongPressGesture(minimumDuration: 0.4) { editing = SwatchEdit(index: i) }
                        .accessibilityElement()
                        .accessibilityLabel(Text("Colour \(c.hexString)"))
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { model.pickColor(c) }
                        .accessibilityAction(named: Text("Change colour")) { editing = SwatchEdit(index: i) }
                }
            }
            .padding(.horizontal, 4)
            Button {
                let i = model.selectedPaletteIndex ?? 0
                // A colour picked from the art that isn't in the palette goes into the first swatch.
                if model.selectedPaletteIndex == nil { model.setPaletteColor(model.color, at: 0) }
                editing = SwatchEdit(index: i)
            } label: {
                PrimaryActionLabel(title: "Change this colour", icon: .picker, height: 48)
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
            .accessibilityHint("Opens the colour picker with a grid, spectrum and sliders for the selected swatch")
            Text("Tap a swatch to draw with it. Long-press any swatch to change it.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Ready-made palettes

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Palettes").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            ForEach(PalettePreset.allCases) { preset in
                let colors = preset.colors
                let inUse = colors == model.palette
                Button { model.applyPalette(colors) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(preset.title)
                                .font(AppFont.body(15, .bold, relativeTo: .body))
                                .foregroundStyle(Theme.cream)
                            Spacer()
                            if inUse {
                                PixelIcon.check.view(size: 18).foregroundStyle(Theme.accent)
                            }
                        }
                        HStack(spacing: 0) {
                            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                                Rectangle().fill(c.color).frame(maxWidth: .infinity).frame(height: 22)
                            }
                        }
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .padding(10)
                    .background(Theme.surface)
                    .overlay(Rectangle().strokeBorder(inUse ? Theme.accent : Theme.line, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(preset.title))
                .accessibilityAddTraits(inUse ? .isSelected : [])
                .accessibilityHint("Use this palette for this sprite")
            }
            Text("A palette changes the swatches, not colours already in your art.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
    }
}
