import SwiftUI
import UIKit

/// How a pattern is drawn.
enum CraftKind: String, CaseIterable, Identifiable {
    case beads, crossStitch
    var id: String { rawValue }
    var title: LocalizedStringKey { self == .beads ? "Fuse beads" : "Cross-stitch" }
}

extension BeadName {
    var title: LocalizedStringResource {
        switch self {
        case .black: "Black"
        case .darkGrey: "Dark grey"
        case .grey: "Grey"
        case .lightGrey: "Light grey"
        case .white: "White"
        case .cream: "Cream"
        case .darkRed: "Dark red"
        case .red: "Red"
        case .pink: "Pink"
        case .lightPink: "Light pink"
        case .brown: "Brown"
        case .tan: "Tan"
        case .orange: "Orange"
        case .peach: "Peach"
        case .darkYellow: "Dark yellow"
        case .yellow: "Yellow"
        case .lightYellow: "Light yellow"
        case .darkGreen: "Dark green"
        case .green: "Green"
        case .lightGreen: "Light green"
        case .teal: "Teal"
        case .turquoise: "Turquoise"
        case .darkBlue: "Dark blue"
        case .blue: "Blue"
        case .lightBlue: "Light blue"
        case .darkPurple: "Dark purple"
        case .purple: "Purple"
        case .lilac: "Lilac"
        }
    }
}

/// Bead and cross-stitch patterns: any frame as a printable chart, one bead or stitch per pixel,
/// with a shopping list of how many of each colour.
struct BeadPatternView: View {
    let project: SpriteProject
    var frame = 0
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CraftKind = .beads
    @State private var shareItems: ShareItems?
    @State private var message: String?

    private var pattern: BeadPattern? {
        guard project.frames.indices.contains(frame) else { return nil }
        return BeadPattern(project.frames[frame].grid)
    }

    var body: some View {
        let pattern = self.pattern
        return VStack(spacing: 0) {
            SheetHeader(title: kind == .beads ? "Bead pattern" : "Cross-stitch pattern", onClose: { dismiss() })
            if let pattern {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(project.name) · frame \(frame + 1) · \(pattern.total) beads", comment: "Pattern summary: sprite name, frame number, bead count (plural)")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        PatternChart(pattern: pattern, kind: kind)
                            .aspectRatio(CGFloat(pattern.grid.width) / CGFloat(pattern.grid.height), contentMode: .fit)
                            .frame(maxHeight: 320)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                            .accessibilityLabel("Pattern chart")
                        ChoiceRow(options: CraftKind.allCases, selection: $kind) { Text($0.title) }
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Shopping list")
                            ForEach(Array(pattern.entries.enumerated()), id: \.offset) { _, e in
                                HStack(spacing: 10) {
                                    Text(verbatim: String(e.symbol))
                                        .font(AppFont.pixel(12))
                                        .foregroundStyle(e.color.luminance > 0.55 ? Color.black : Color.white)
                                        .frame(width: 28, height: 28)
                                        .background(e.color.color)
                                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                                    Text(e.name.title).font(AppFont.body(15, relativeTo: .body)).foregroundStyle(Theme.text)
                                    Text(verbatim: e.color.hexString).font(AppFont.pixel(9)).foregroundStyle(Theme.muted)
                                    Spacer()
                                    Text(verbatim: "\(e.count)").font(AppFont.pixel(13)).foregroundStyle(Theme.accent2).monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        if let message {
                            Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(16)
                }
                HStack(spacing: 8) {
                    Button { printPattern(pattern) } label: {
                        Text("Print").font(AppFont.pixel(15)).frame(width: 120, height: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle(fill: Theme.surface))
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                    Button { sharePDF(pattern) } label: { PrimaryActionLabel(title: "Share PDF", icon: .share) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            } else {
                Spacer()
                Text("Patterns work for art up to \(BeadPattern.maxSide) × \(BeadPattern.maxSide) pixels. Draw something, or pick a smaller sprite.")
                    .font(AppFont.body(15, relativeTo: .body)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(32)
                Spacer()
            }
        }
        .screenBackground()
        .presentationDetents([.large])
        .sheet(item: $shareItems) { items in ActivityView(items: items.urls) { _ in shareItems = nil }.ignoresSafeArea() }
    }

    private func pdfURL(_ pattern: BeadPattern) -> URL? {
        let data = PatternPDF.make(pattern, kind: kind, title: project.name)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = String(project.name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" })
        let url = dir.appendingPathComponent("\(safe.isEmpty ? "Pattern" : safe) pattern.pdf")
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    private func sharePDF(_ pattern: BeadPattern) {
        if let url = pdfURL(pattern) { shareItems = ShareItems(urls: [url]) }
        else { message = String(localized: "Couldn't make the PDF.") }
    }

    private func printPattern(_ pattern: BeadPattern) {
        guard UIPrintInteractionController.isPrintingAvailable else {
            message = String(localized: "Printing isn't available on this device. Share the PDF instead.")
            return
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = project.name
        controller.printInfo = info
        controller.printingItem = PatternPDF.make(pattern, kind: kind, title: project.name)
        controller.present(animated: true)
    }
}

/// The chart on screen: a bead or a stitch per pixel.
private struct PatternChart: View {
    let pattern: BeadPattern
    let kind: CraftKind

    var body: some View {
        Canvas { ctx, size in
            PatternPDF.draw(pattern, kind: kind, in: CGRect(origin: .zero, size: size), symbols: false) { path, color, stroke in
                if let stroke { ctx.stroke(path, with: .color(color), lineWidth: stroke) } else { ctx.fill(path, with: .color(color)) }
            }
        }
    }
}

/// Drawing a pattern, on screen and as a PDF.
enum PatternPDF {
    /// Draws the chart into `rect` through `paint(path, colour, strokeWidth or nil to fill)`.
    static func draw(_ pattern: BeadPattern, kind: CraftKind, in rect: CGRect, symbols: Bool,
                     paint: (Path, Color, CGFloat?) -> Void) {
        let w = pattern.grid.width, h = pattern.grid.height
        let cell = min(rect.width / CGFloat(w), rect.height / CGFloat(h))
        let ox = rect.minX + (rect.width - cell * CGFloat(w)) / 2, oy = rect.minY + (rect.height - cell * CGFloat(h)) / 2
        var grid = Path()
        for x in 0...w {
            grid.move(to: CGPoint(x: ox + CGFloat(x) * cell, y: oy))
            grid.addLine(to: CGPoint(x: ox + CGFloat(x) * cell, y: oy + CGFloat(h) * cell))
        }
        for y in 0...h {
            grid.move(to: CGPoint(x: ox, y: oy + CGFloat(y) * cell))
            grid.addLine(to: CGPoint(x: ox + CGFloat(w) * cell, y: oy + CGFloat(y) * cell))
        }
        paint(grid, Color(white: 0.8), 0.5)
        for y in 0..<h {
            for x in 0..<w {
                let c = pattern.grid[x, y]
                guard !c.isClear else { continue }
                let r = CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell, height: cell)
                switch kind {
                case .beads:
                    // A ring, like a fuse bead seen from above.
                    paint(Path(ellipseIn: r.insetBy(dx: cell * 0.06, dy: cell * 0.06)), c.color, nil)
                    paint(Path(ellipseIn: r.insetBy(dx: cell * 0.34, dy: cell * 0.34)), Color.white.opacity(0.85), nil)
                case .crossStitch:
                    paint(Path(r), c.color.opacity(0.28), nil)
                    var cross = Path()
                    let i = cell * 0.18
                    cross.move(to: CGPoint(x: r.minX + i, y: r.minY + i)); cross.addLine(to: CGPoint(x: r.maxX - i, y: r.maxY - i))
                    cross.move(to: CGPoint(x: r.maxX - i, y: r.minY + i)); cross.addLine(to: CGPoint(x: r.minX + i, y: r.maxY - i))
                    paint(cross, c.color, max(1, cell * 0.16))
                }
            }
        }
    }

    /// A one- or two-page PDF: the chart with a letter in every square, then the shopping list.
    static func make(_ pattern: BeadPattern, kind: CraftKind, title: String) -> Data {
        // US Letter and A4 are close; this size prints on either with normal margins.
        let page = CGRect(x: 0, y: 0, width: 595, height: 792)
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let titleFont = UIFont(name: AppFont.silkscreen, size: 18) ?? .boldSystemFont(ofSize: 18)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            (title as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: [.font: titleFont, .foregroundColor: UIColor.black])
            let subtitle = kind == .beads
                ? String(localized: "Fuse bead pattern · \(pattern.grid.width) × \(pattern.grid.height) · \(pattern.total) beads", comment: "PDF subtitle; plural")
                : String(localized: "Cross-stitch pattern · \(pattern.grid.width) × \(pattern.grid.height) · \(pattern.total) stitches", comment: "PDF subtitle; plural")
            (subtitle as NSString).draw(at: CGPoint(x: margin, y: margin + 24), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray])

            // The chart, with each colour's letter in its squares.
            let chart = CGRect(x: margin, y: margin + 48, width: page.width - 2 * margin, height: 440)
            draw(pattern, kind: kind, in: chart, symbols: true) { path, color, stroke in
                cg.addPath(path.cgPath)
                if let stroke {
                    cg.setStrokeColor(UIColor(color).cgColor)
                    cg.setLineWidth(stroke)
                    cg.strokePath()
                } else {
                    cg.setFillColor(UIColor(color).cgColor)
                    cg.fillPath()
                }
            }
            let w = pattern.grid.width, h = pattern.grid.height
            let cell = min(chart.width / CGFloat(w), chart.height / CGFloat(h))
            let ox = chart.minX + (chart.width - cell * CGFloat(w)) / 2, oy = chart.minY + (chart.height - cell * CGFloat(h)) / 2
            if cell >= 7 {
                let symbolFont = UIFont.boldSystemFont(ofSize: min(10, cell * 0.55))
                for y in 0..<h {
                    for x in 0..<w {
                        let c = pattern.grid[x, y]
                        guard !c.isClear, let symbol = pattern.symbol(for: c) else { continue }
                        let s = String(symbol) as NSString
                        let attributes: [NSAttributedString.Key: Any] = [.font: symbolFont, .foregroundColor: UIColor.black]
                        let size = s.size(withAttributes: attributes)
                        s.draw(at: CGPoint(x: ox + CGFloat(x) * cell + (cell - size.width) / 2, y: oy + CGFloat(y) * cell + (cell - size.height) / 2),
                               withAttributes: attributes)
                    }
                }
            }

            // The shopping list, in two columns (and onto a second page if it's long).
            var y = chart.maxY + 20
            var column = 0
            let columnWidth = (page.width - 2 * margin) / 2
            (String(localized: "Shopping list") as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.black])
            y += 20
            let top = y
            for e in pattern.entries {
                if y > page.height - margin - 16 {
                    if column == 0 {
                        column = 1
                        y = top
                    } else {
                        context.beginPage()
                        column = 0
                        y = margin
                    }
                }
                let x = margin + CGFloat(column) * columnWidth
                let swatch = CGRect(x: x, y: y, width: 14, height: 14)
                cg.setFillColor(UIColor(e.color.color).cgColor)
                cg.fill(swatch)
                cg.setStrokeColor(UIColor.gray.cgColor)
                cg.setLineWidth(0.5)
                cg.stroke(swatch)
                let line = "\(e.symbol)   \(String(localized: e.name.title))   \(e.color.hexString)   × \(e.count)"
                (line as NSString).draw(at: CGPoint(x: x + 20, y: y), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.black])
                y += 18
            }
            let footer = String(localized: "Made with Pixel Deck", comment: "Watermark on free exports")
            (footer as NSString).draw(at: CGPoint(x: margin, y: page.height - margin + 8), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray])
        }
    }
}
