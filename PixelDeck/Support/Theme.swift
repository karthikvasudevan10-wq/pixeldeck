import SwiftUI
import UIKit
import CoreText

// The visual system from the design handoff: a dark "night" palette, square corners everywhere,
// Silkscreen for labels and numbers, Space Grotesk for body text, and a primary button with a
// hard (unblurred) drop shadow that presses in.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Theme {
    static let ink = Color(hex: 0x120E1F)
    static let surface = Color(hex: 0x1E1833)
    static let line = Color(hex: 0x2E2650)
    static let text = Color(hex: 0xF4EEFF)
    static let cream = Color(hex: 0xFFF6E0)
    static let muted = Color(hex: 0xA89CC8)
    static let accent = Color(hex: 0xFF8B3D)
    static let accentShadow = Color(hex: 0xC25A1A)
    static let accent2 = Color(hex: 0xFFD23F)
    static let accent2Shadow = Color(hex: 0xB08A12)
    static let onAccent = Color(hex: 0x120E1F)
    static let tool = Color(hex: 0x2A2347)
    static let chip = Color(hex: 0x120E1F, opacity: 0.7)

    /// The onion skin tint (drawn at 38%).
    static let onionRGBA = RGBA(hex: 0xFF8B3D)
    static let uiCheckA = UIColor(hex: 0x1A1430)
    static let uiCheckB = UIColor(hex: 0x221B3B)
    static let uiGrid = UIColor(white: 1, alpha: 0.07)
    static let uiAccent = UIColor(hex: 0xFF8B3D)
    static let uiAccent2 = UIColor(hex: 0xFFD23F)
    static let uiInk = UIColor(hex: 0x120E1F)
    static let uiCream = UIColor(hex: 0xFFF6E0)
}

// MARK: Fonts

enum AppFont {
    static let silkscreen = "Silkscreen-Regular"

    /// Registers the bundled fonts. Done in code so no Info.plist entry is needed.
    static func registerBundledFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Silkscreen at a whole-point size (it's a bitmap-style face; fractional sizes blur).
    static func pixel(_ size: CGFloat) -> Font {
        .custom(silkscreen, fixedSize: size.rounded())
    }

    /// Space Grotesk, scaling with Dynamic Type.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold: name = "SpaceGrotesk-Bold"
        case .medium: name = "SpaceGrotesk-Medium"
        default: name = "SpaceGrotesk-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

// MARK: Buttons

/// The design's primary button: flat fill with a solid offset "shadow" that the button presses
/// into (down 4 pt, shadow to 2 pt; 80 ms down, 120 ms release).
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.accent
    var shadow: Color = Theme.accentShadow
    var depth: CGFloat = 6
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(Theme.onAccent)
            .background(fill)
            .background(alignment: .top) {
                shadow.offset(y: pressed ? 2 : depth)
            }
            .offset(y: pressed ? depth - 2 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: pressed ? 0.08 : 0.12), value: pressed)
    }
}

/// Square tile button (tools, secondary actions).
struct TileButtonStyle: ButtonStyle {
    var active = false
    var activeFill: Color = Theme.cream
    var activeForeground: Color = Theme.ink
    var fill: Color = Theme.tool
    var foreground: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, style: self)
    }
}

private struct TileBody: View {
    let configuration: ButtonStyleConfiguration
    let style: TileButtonStyle
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(style.active ? style.activeForeground : style.foreground)
            .background(style.active ? style.activeFill : style.fill)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
    }
}

/// Full-width primary action with a Silkscreen label.
struct PrimaryActionLabel: View {
    let title: LocalizedStringKey
    var icon: PixelIcon?
    var height: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            if let icon { icon.view(size: 20, lineWidth: 2.5) }
            Text(title).font(AppFont.pixel(18))
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .contentShape(Rectangle())
    }
}

/// Small Silkscreen label in the muted colour, used above groups.
struct SectionLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(AppFont.pixel(12)).foregroundStyle(Theme.muted)
    }
}

/// Square-cornered card.
extension View {
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }

    /// Dark screens: the design has a single night theme.
    func screenBackground() -> some View {
        self.background(Theme.ink.ignoresSafeArea())
    }
}

// MARK: Checkerboard

/// Transparent-canvas checkerboard (one cell per `cell` points).
struct Checkerboard: View {
    var cell: CGFloat = 16
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x1A1430)))
            let cols = Int((size.width / cell).rounded(.up)), rows = Int((size.height / cell).rounded(.up))
            var p = Path()
            for y in 0..<rows {
                for x in 0..<cols where (x + y) % 2 == 1 {
                    p.addRect(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
            ctx.fill(p, with: .color(Color(hex: 0x221B3B)))
        }
    }
}

// MARK: Icons

/// The design's icons: a 24-unit grid, 2 pt strokes with square caps and joins. Paths are taken
/// verbatim from the handoff's inline SVGs.
enum PixelIcon {
    case pencil, eraser, fill, picker, mirror, select
    case gallery, undo, redo, onion, export, share, download
    case plus, play, pause, back, arrowLeft, arrowRight, create
    case settings, more, trash, tween, check

    fileprivate var svg: [String] {
        switch self {
        case .pencil: ["M4 20l1-5L16 4l4 4L9 19z", "M13 7l4 4"]
        case .create: ["M4 20l1-5L16 4l4 4L9 19z"]
        case .eraser: ["M9 20h11", "M4 15l9-10 7 7-8 8H9z", "M8 11l6 6"]
        case .fill: ["M4 11l7-7 8 8-7 7z", "M4 11h15", "M20 16v4"]
        case .picker: ["M15 4l5 5-3 1-7 7-4 1 1-4 7-7z", "M4 20l2-2"]
        case .mirror: ["M12 3v18", "M8 7l-5 5 5 5z", "M16 7l5 5-5 5z"]
        case .select: ["M4 4h16v16H4z"]
        case .gallery: ["M4 4h6v6H4z", "M14 4h6v6h-6z", "M4 14h6v6H4z", "M14 14h6v6h-6z"]
        case .undo: ["M9 14L4 9l5-5", "M4 9h10"]          // arc added in path()
        case .redo: ["M15 14l5-5-5-5", "M20 9H10"]
        case .onion: ["M12 4l9 5-9 5-9-5z", "M3 14l9 5 9-5"]
        case .export, .share: ["M12 3v12M7 8l5-5 5 5M5 14v6h14v-6"]
        case .download: ["M12 4v11M7 10l5 5 5-5M5 20h14"]
        case .plus: ["M12 5v14M5 12h14"]
        case .play: ["M6 3l15 9-15 9z"]
        case .pause: ["M5 4h5v16H5z", "M14 4h5v16h-5z"]
        case .back: ["M15 5l-7 7 7 7"]
        case .arrowLeft: ["M20 12H5M11 6l-6 6 6 6"]
        case .arrowRight: ["M4 12h15M13 6l6 6-6 6"]
        case .settings: ["M4 7h16", "M4 17h16", "M8 5h4v4H8z", "M13 15h4v4h-4z"]
        case .more: ["M5 11h2v2H5z", "M11 11h2v2h-2z", "M17 11h2v2h-2z"]
        case .trash: ["M5 7h14", "M9 7V4h6v3", "M7 7l1 13h8l1-13"]
        case .tween: ["M4 19c4-14 12 0 16-14", "M3 18h3v3H3z", "M18 3h3v3h-3z"]
        case .check: ["M5 12l5 5 9-10"]
        }
    }

    /// Filled glyphs (play/pause) rather than stroked.
    var isFilled: Bool { self == .play || self == .pause }
    var isDashed: Bool { self == .select }

    /// The icon in a 24×24 box.
    func path() -> Path {
        var p = Path()
        for d in svg { SVGPath.append(d, to: &p) }
        // Undo/redo end in a half-circle (SVG "a6 6 0 010 12h-3"), drawn as two cubic curves.
        let k = 6 * 0.5523
        switch self {
        case .undo:
            p.move(to: CGPoint(x: 14, y: 9))
            p.addCurve(to: CGPoint(x: 20, y: 15), control1: CGPoint(x: 14 + k, y: 9), control2: CGPoint(x: 20, y: 15 - k))
            p.addCurve(to: CGPoint(x: 14, y: 21), control1: CGPoint(x: 20, y: 15 + k), control2: CGPoint(x: 14 + k, y: 21))
            p.addLine(to: CGPoint(x: 11, y: 21))
        case .redo:
            p.move(to: CGPoint(x: 10, y: 9))
            p.addCurve(to: CGPoint(x: 4, y: 15), control1: CGPoint(x: 10 - k, y: 9), control2: CGPoint(x: 4, y: 15 - k))
            p.addCurve(to: CGPoint(x: 10, y: 21), control1: CGPoint(x: 4, y: 15 + k), control2: CGPoint(x: 10 - k, y: 21))
            p.addLine(to: CGPoint(x: 13, y: 21))
        default:
            break
        }
        return p
    }

    func view(size: CGFloat = 22, lineWidth: CGFloat = 2) -> some View {
        PixelIconView(icon: self, lineWidth: lineWidth)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct PixelIconView: View {
    let icon: PixelIcon
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 24
            let path = icon.path().applying(CGAffineTransform(scaleX: s, y: s))
            if icon.isFilled {
                path.fill(.foreground)
            } else {
                // Line width is in the icon's 24-unit grid, like the SVG's stroke-width.
                path.stroke(.foreground, style: StrokeStyle(lineWidth: lineWidth * s, lineCap: .square, lineJoin: .miter,
                                                            dash: icon.isDashed ? [3 * s, 3 * s] : []))
            }
        }
    }
}

/// Minimal SVG path reader for the handoff's icons: M m L l H h V v C c Z z with implicit repeats.
private enum SVGPath {
    static func append(_ d: String, to path: inout Path) {
        var tokens: [String] = []
        var num = ""
        func flush() { if !num.isEmpty { tokens.append(num); num = "" } }
        for ch in d {
            if ch.isLetter {
                flush(); tokens.append(String(ch))
            } else if ch == "-" {
                flush(); num = "-"
            } else if ch == " " || ch == "," {
                flush()
            } else {
                num.append(ch)
            }
        }
        flush()

        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero
        func next() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func hasNumber() -> Bool { i < tokens.count && Double(tokens[i]) != nil }
        while i < tokens.count {
            if let c = tokens[i].first, tokens[i].count == 1, c.isLetter { cmd = c; i += 1 }
            switch cmd {
            case "M", "m":
                guard hasNumber() else { return }
                var p = CGPoint(x: next(), y: next())
                if cmd == "m" { p.x += cur.x; p.y += cur.y }
                path.move(to: p); cur = p; start = p
                cmd = cmd == "m" ? "l" : "L"         // following pairs are line-tos
            case "L", "l":
                guard hasNumber() else { return }
                var p = CGPoint(x: next(), y: next())
                if cmd == "l" { p.x += cur.x; p.y += cur.y }
                path.addLine(to: p); cur = p
            case "H", "h":
                guard hasNumber() else { return }
                let x = next(); cur.x = cmd == "h" ? cur.x + x : x
                path.addLine(to: cur)
            case "V", "v":
                guard hasNumber() else { return }
                let y = next(); cur.y = cmd == "v" ? cur.y + y : y
                path.addLine(to: cur)
            case "C", "c":
                guard hasNumber() else { return }
                var c1 = CGPoint(x: next(), y: next()), c2 = CGPoint(x: next(), y: next()), p = CGPoint(x: next(), y: next())
                if cmd == "c" {
                    c1.x += cur.x; c1.y += cur.y; c2.x += cur.x; c2.y += cur.y; p.x += cur.x; p.y += cur.y
                }
                path.addCurve(to: p, control1: c1, control2: c2); cur = p
            case "Z", "z":
                path.closeSubpath(); cur = start
                if hasNumber() { cmd = "L" }          // numbers after Z: keep going as line-tos
                else if i < tokens.count, !(tokens[i].first?.isLetter ?? false) { i += 1 }   // skip junk
            default:
                i += 1
            }
        }
    }
}

// MARK: Starter sprite data

/// The handoff's animated characters, loaded once from the bundle.
enum StarterArt {
    static let library: [String: CharacterSprite] = {
        guard let url = Bundle.main.url(forResource: "sprites", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return CharacterSpriteLibrary.parse(data)
    }()

    static func sprite(_ key: String) -> CharacterSprite? { library[key] }
}

/// A looping character sprite at an integer pixel size. Pauses on frame 0 with Reduce Motion.
struct AnimatedSprite: View {
    let key: String
    var pixel: CGFloat
    var fps: Int?
    var playing = true
    var onion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let sprite = StarterArt.sprite(key) {
            let w = CGFloat(sprite.width) * pixel, h = CGFloat(sprite.height) * pixel
            if playing && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 1 / Double(fps ?? sprite.fps))) { ctx in
                    frameView(sprite, index: index(sprite, ctx.date))
                }
                .frame(width: w, height: h)
            } else {
                frameView(sprite, index: 0).frame(width: w, height: h)
            }
        }
    }

    private func index(_ s: CharacterSprite, _ date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate * Double(fps ?? s.fps)).rounded(.down)) % s.frames.count
    }

    @ViewBuilder
    private func frameView(_ s: CharacterSprite, index: Int) -> some View {
        ZStack {
            if onion {
                let prev = (index - 1 + s.frames.count) % s.frames.count
                PixelImage(grid: PixelRenderer.tinted(s.frames[prev], with: Theme.onionRGBA), checker: false)
                    .opacity(0.38)
            }
            PixelImage(grid: s.frames[index], checker: false)
        }
    }
}
