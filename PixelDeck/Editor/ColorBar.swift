import SwiftUI

/// Current colour, the system colour picker, recent colours and a starter palette.
struct ColorBar: View {
    let model: EditorModel

    static let palette: [RGBA] = ([
        0x000000, 0xFFFFFF, 0x7A7A7A, 0xC4C4C4,
        0xD9344A, 0xF28A2E, 0xF5D13D, 0x4DB84A,
        0x2F8F6F, 0x3DB5E6, 0x2E5BD9, 0x6A3DC4,
        0xD957B5, 0x8C5A3C, 0xF2C29B, 0x2B2B45,
    ] as [UInt32]).map { RGBA(hex: $0) }

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("Colour",
                        selection: Binding(get: { model.color.color }, set: { model.pickColor(RGBA($0)) }),
                        supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("Custom colour")

            Circle()
                .fill(model.color.color)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                .accessibilityLabel("Current colour \(model.color.hexString)")

            Divider().frame(height: 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(model.recentColors.enumerated()), id: \.offset) { _, c in
                        swatch(c)
                    }
                    if !model.recentColors.isEmpty {
                        Divider().frame(height: 22)
                    }
                    ForEach(Self.palette, id: \.self) { c in
                        swatch(c)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 12)
    }

    private func swatch(_ c: RGBA) -> some View {
        let selected = c == model.color && model.tool != .eraser
        return Button { model.pickColor(c) } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(c.color)
                .frame(width: 26, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour \(c.hexString)")
    }
}
