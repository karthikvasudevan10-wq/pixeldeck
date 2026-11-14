import SwiftUI

/// Pick a canvas size: 8, 16, 32, 64, 128 or 256 pixels square.
struct NewCanvasSheet: View {
    var onCreate: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @State private var upgrade: ProFeature?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SpriteProject.supportedSizes, id: \.self) { size in
                        let locked = !purchases.access.allowsCanvas(size: size)
                        Button {
                            if locked {
                                upgrade = .largeCanvas
                            } else {
                                dismiss()
                                onCreate(size)
                            }
                        } label: {
                            VStack(spacing: 8) {
                                GridGlyph(cells: min(size, 16))
                                    .frame(width: 56, height: 56)
                                Text("\(size) × \(size)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if locked { ProBadge().padding(8) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(size) by \(size) pixels\(locked ? ", requires Pro" : "")")
                    }
                }
                .padding()
            }
            .navigationTitle("New Canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .proUpgradeSheet($upgrade)
    }
}

/// A little grid icon whose density hints at the canvas size.
private struct GridGlyph: View {
    let cells: Int

    var body: some View {
        Canvas { ctx, size in
            let step = size.width / CGFloat(cells)
            var path = Path()
            for i in 0...cells {
                let p = CGFloat(i) * step
                path.move(to: CGPoint(x: p, y: 0)); path.addLine(to: CGPoint(x: p, y: size.height))
                path.move(to: CGPoint(x: 0, y: p)); path.addLine(to: CGPoint(x: size.width, y: p))
            }
            ctx.stroke(path, with: .color(.secondary.opacity(0.6)), lineWidth: 0.75)
        }
    }
}
