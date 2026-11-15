import Foundation

/// Ready-made 10-colour palettes. Applying one replaces the sprite's palette (the art keeps its
/// colours). Names are localised in the app layer (LocalizedTitles.swift).
enum PalettePreset: String, CaseIterable, Identifiable, Sendable {
    case pixelDeck, sunset, forest, ocean, candy, neon, fire, people, pocketGreens, grayscale

    var id: String { rawValue }

    var colors: [RGBA] {
        let hex: [UInt32]
        switch self {
        case .pixelDeck: return SpriteProject.defaultPalette
        case .sunset: hex = [0x2B1B3D, 0x5B2A5E, 0x9E3D6B, 0xD9576B, 0xF28C5E, 0xFFC36B, 0xFFE7A8, 0x3A2F6B, 0x6C5BA8, 0xFFF6E0]
        case .forest: hex = [0x14231A, 0x234D2C, 0x3E7A3A, 0x6FAE4A, 0xA9D46F, 0xE0EFA0, 0x5A3B22, 0x8E6239, 0xC49A63, 0xF2E6C9]
        case .ocean: hex = [0x0B1A2E, 0x12355B, 0x1D5E8C, 0x2E8FBF, 0x5CC3E0, 0xA6E6F2, 0xE8FBFF, 0x0E6B6B, 0x2FA89A, 0xF2D8A7]
        case .candy: hex = [0x3B2E4A, 0xFF8FAB, 0xFFB3C7, 0xC8B6FF, 0xA0C4FF, 0x9BF6FF, 0xCAFFBF, 0xFDFFB6, 0xFFD6A5, 0xFFFFFF]
        case .neon: hex = [0x0D0221, 0x261447, 0x7B2FF7, 0xFF2A6D, 0xFF6EC7, 0x05D9E8, 0x01FFC3, 0xFFE66D, 0xD1F7FF, 0xFFFFFF]
        case .fire: hex = [0x1A0A0A, 0x4A1010, 0x8C1C13, 0xC9381A, 0xF2661C, 0xFF9A1F, 0xFFC94A, 0xFFF08A, 0x3A3A3A, 0xFFFFFF]
        case .people: hex = [0x2B1A12, 0x5C3A21, 0x8D5A3B, 0xC68C5E, 0xE8B48A, 0xF6D7B8, 0x1B1530, 0x6B2E2E, 0xD9A441, 0xFFF6E0]
        case .pocketGreens: hex = [0x0F1F0F, 0x1E3A1E, 0x2D5A27, 0x3F7A33, 0x5A9A3C, 0x7DB84A, 0xA3D162, 0xC4E584, 0xDDF2AE, 0xF0FADC]
        case .grayscale: hex = [0x000000, 0x1C1C1C, 0x383838, 0x555555, 0x717171, 0x8E8E8E, 0xAAAAAA, 0xC6C6C6, 0xE3E3E3, 0xFFFFFF]
        }
        return hex.map { RGBA(hex: $0) }
    }
}

extension EditorModel {
    /// The swatch matching the current colour, if any.
    var selectedPaletteIndex: Int? { project.palette.firstIndex(of: color) }

    /// Replaces the sprite's palette. The selected swatch position stays selected, so you keep
    /// drawing with "the same slot" in the new colours.
    func applyPalette(_ colors: [RGBA]) {
        guard colors.count == SpriteProject.defaultPalette.count else { return }
        let slot = selectedPaletteIndex
        let opaque = colors.map { RGBA(r: $0.r, g: $0.g, b: $0.b, a: 255) }
        updateProject { $0.palette = opaque }
        if let slot { pickColor(opaque[slot]) }
    }
}
