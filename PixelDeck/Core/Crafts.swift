import Foundation

/// A plain name for a bead or thread colour, for shopping lists. Titles are localised in the app.
enum BeadName: String, CaseIterable, Sendable {
    case black, darkGrey, grey, lightGrey, white, cream
    case darkRed, red, pink, lightPink
    case brown, tan, orange, peach
    case darkYellow, yellow, lightYellow
    case darkGreen, green, lightGreen
    case teal, turquoise
    case darkBlue, blue, lightBlue
    case darkPurple, purple, lilac

    /// The nearest everyday name for a colour.
    static func name(for c: RGBA) -> BeadName {
        let x = c.hsl
        let h = x.h * 360
        if x.s < 0.12 || x.l < 0.06 || x.l > 0.96 {
            switch x.l {
            case ..<0.16: return .black
            case ..<0.4: return .darkGrey
            case ..<0.66: return .grey
            case ..<0.9: return .lightGrey
            default: return .white
            }
        }
        let dark = x.l < 0.32, light = x.l > 0.66
        switch h {
        case ..<15, 345...:
            return dark ? .darkRed : light ? .lightPink : .red
        case ..<45:
            if x.l < 0.42 { return .brown }
            if light { return x.s < 0.6 ? .cream : .peach }
            return x.s < 0.5 ? .tan : .orange
        case ..<70:
            if dark { return .brown }
            if light { return x.s < 0.7 ? .cream : .lightYellow }
            return x.l < 0.45 ? .darkYellow : .yellow
        case ..<165:
            return dark ? .darkGreen : light ? .lightGreen : .green
        case ..<200:
            return light ? .turquoise : .teal
        case ..<255:
            return dark ? .darkBlue : light ? .lightBlue : .blue
        case ..<290:
            return dark ? .darkPurple : light ? .lilac : .purple
        default:
            return dark ? .darkPurple : x.l > 0.8 ? .lightPink : .pink
        }
    }
}

/// A sprite frame as a craft pattern: one bead (or one cross-stitch) per pixel, with a symbol and
/// a count for every colour.
struct BeadPattern: Sendable {
    struct Entry: Equatable, Sendable {
        let color: RGBA
        let count: Int
        /// The letter printed in each of this colour's squares.
        let symbol: Character
        let name: BeadName
    }

    /// The art trimmed to its pixels.
    let grid: PixelGrid
    /// Most-used colour first.
    let entries: [Entry]

    static let symbols = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789abcdefghijkmnopqrstuvwxyz")
    /// Patterns bigger than this are refused: they'd be unreadable on a page.
    static let maxSide = 128

    var total: Int { entries.reduce(0) { $0 + $1.count } }

    /// Nil for blank art, or art too big to print as a pattern.
    init?(_ source: PixelGrid) {
        guard let box = source.opaqueBounds, box.width <= BeadPattern.maxSide, box.height <= BeadPattern.maxSide else { return nil }
        var g = PixelGrid(width: box.width, height: box.height)
        g.stamp(source.patch(in: box), at: .zero)
        grid = g
        let counts = ColorTools.histogram([g]).sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.hexString < $1.key.hexString }
        entries = counts.enumerated().map { i, c in
            Entry(color: c.key, count: c.value, symbol: BeadPattern.symbols[i % BeadPattern.symbols.count], name: BeadName.name(for: c.key))
        }
    }

    func symbol(for c: RGBA) -> Character? { entries.first { $0.color == c }?.symbol }
}
