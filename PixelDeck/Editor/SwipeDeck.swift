import SwiftUI

/// The canvas as a card you can fling, dating-app style.
/// Swipe left: add a keyframe (the card flies off and a fresh one slides in on top of an onion skin).
/// Swipe right: start a whole new canvas.
///
/// The card's top strip can always be dragged. With `dragAnywhere` on, the whole card can.
///
/// Right-to-left languages: the drag is measured in the deck's own coordinate space, which SwiftUI
/// mirrors along with the layout, so "toward the leading edge" (new frame) becomes a swipe to the
/// right there, and the stamps and header labels flip to match.
struct SwipeDeck<Content: View>: View {
    var title: Text
    var dragAnywhere: Bool
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var swipeCount = 0
    @State private var flying = false
    /// Width of the deck, so fly-off distances work on every screen (iPhone Duo inner display, iPad…).
    @State private var deckWidth: CGFloat = 400
    private let threshold: CGFloat = 110

    var body: some View {
        ZStack {
            // Hint of the deck underneath.
            cardShape
                .fill(Color(.tertiarySystemBackground))
                .rotationEffect(.degrees(-2.5))
                .scaleEffect(0.96)
                .opacity(0.7)
            cardShape
                .fill(Color(.tertiarySystemBackground))
                .rotationEffect(.degrees(1.5))
                .scaleEffect(0.98)

            card
                .offset(offset)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset.width / 22)), anchor: .bottom)
        }
        .padding(.horizontal, 12)
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { deckWidth = max($0, 1) }
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeCount)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
                .contentShape(Rectangle())
                .gesture(drag)
            content()
                .overlay {
                    if dragAnywhere {
                        Color.clear.contentShape(Rectangle()).gesture(drag)
                    }
                }
        }
        .background(Color(.secondarySystemBackground), in: cardShape)
        .clipShape(cardShape)
        .overlay(cardShape.strokeBorder(dragAnywhere ? Color.accentColor : Color(.separator), lineWidth: dragAnywhere ? 2 : 0.5))
        .overlay(alignment: .topTrailing) {
            stamp(LocalizedStringKey("NEW FRAME"), color: .green, angle: 12).opacity(newFrameProgress)
        }
        .overlay(alignment: .topLeading) {
            stamp(LocalizedStringKey("NEW CANVAS"), color: .orange, angle: -12).opacity(newCanvasProgress)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var header: some View {
        HStack {
            Label("New frame", systemImage: "chevron.left.2")
                .labelStyle(.titleAndIcon)
            Spacer()
            VStack(spacing: 3) {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 4)
                title.font(.caption.weight(.semibold).monospacedDigit())
            }
            Spacer()
            HStack(spacing: 4) {
                Text("New canvas")
                Image(systemName: "chevron.right.2")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Swipe left to add a frame, swipe right to start a new canvas")
        .accessibilityAction(named: "New frame") { onSwipeLeft() }
        .accessibilityAction(named: "New canvas") { onSwipeRight() }
    }

    private static var space: String { "SwipeDeck" }
    /// Negative x = toward the leading edge (left in LTR) = new frame.
    private var newFrameProgress: Double { Double(min(max(-offset.width / threshold, 0), 1)) }
    private var newCanvasProgress: Double { Double(min(max(offset.width / threshold, 0), 1)) }

    private func stamp(_ text: LocalizedStringKey, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(.title3, design: .rounded).weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(angle))
            .padding(24)
            .allowsHitTesting(false)
    }

    private var drag: some Gesture {
        // Measured in the stationary deck (not the moving card) so the drag doesn't feed back on itself.
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !flying else { return }
                offset = CGSize(width: value.translation.width, height: value.translation.height * 0.25)
            }
            .onEnded { value in
                guard !flying else { return }
                let projected = value.predictedEndTranslation.width
                if value.translation.width < -threshold || projected < -threshold * 2.5 {
                    flyOff(direction: -1)
                } else if value.translation.width > threshold || projected > threshold * 2.5 {
                    flyOff(direction: 1)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = .zero }
                }
            }
    }

    private func flyOff(direction: CGFloat) {
        flying = true
        swipeCount += 1
        withAnimation(.easeIn(duration: 0.18)) {
            offset = CGSize(width: direction * (deckWidth + 120), height: offset.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            if direction < 0 { onSwipeLeft() } else { onSwipeRight() }
            // The next card comes in from the opposite side.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { offset = CGSize(width: -direction * deckWidth * 0.8, height: 0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { offset = .zero }
                flying = false
            }
        }
    }
}
