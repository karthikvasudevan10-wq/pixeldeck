import SwiftUI

/// First-launch tips. The swipes are the app's signature but are invisible until explained,
/// so they're introduced here and every one also has a visible button alternative.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Tip: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let text: String
    }

    private let tips = [
        Tip(symbol: "square.grid.3x3.fill", title: "Draw pixel by pixel",
            text: "Pick a canvas from 8×8 to 256×256. One finger draws. Pinch with two fingers to zoom and drag with two fingers to move around."),
        Tip(symbol: "hand.draw", title: "Swipe left for a new frame",
            text: "Drag the card's top strip to the left. A fresh frame appears with the previous one faintly underneath, ready to trace."),
        Tip(symbol: "rectangle.stack.badge.plus", title: "Swipe right for a new canvas",
            text: "Drag the card to the right to start a brand-new sprite. Your work is saved automatically."),
        Tip(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Move it, and it animates",
            text: "Use Select to grab some pixels and drag them along any path. Tap Tween and Pixel Deck draws every frame in between."),
        Tip(symbol: "square.and.arrow.up", title: "Export sprites",
            text: "Share sprite sheets with frame data for game engines, individual PNGs, or looping GIFs."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: tip.symbol)
                            .font(.system(size: 64, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                            .frame(height: 90)
                            .accessibilityHidden(true)
                        Text(tip.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(tip.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < tips.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < tips.count - 1 ? "Next" : "Start drawing")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .overlay(alignment: .topTrailing) {
            Button("Skip") { dismiss() }
                .padding()
        }
    }
}
