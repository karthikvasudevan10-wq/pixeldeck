import SwiftUI

/// The canvas as a card you can fling, dating-app style.
/// Swipe left: add a keyframe (the card flies off and a fresh one slides in on top of an onion skin).
/// Swipe right: start a whole new canvas.
///
/// The card's top strip can always be dragged. With `dragAnywhere` on, the whole card can.
struct SwipeDeck<Content: View>: View {
    var title: String
    var dragAnywhere: Bool
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGSize = .zero
    @State private var swipeCount = 0
    @State private var flying = false
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
                .rotationEffect(.degrees(Double(offset.width / 22)), anchor: .bottom)
        }
        .padding(.horizontal, 12)
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
        .overlay(alignment: .topTrailing) { stamp("NEW FRAME", color: .green, angle: 12).opacity(leftProgress) }
        .overlay(alignment: .topLeading) { stamp("NEW CANVAS", color: .orange, angle: -12).opacity(rightProgress) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var header: some View {
        HStack {
            Label("New frame", systemImage: "chevron.left.2")
                .labelStyle(.titleAndIcon)
            Spacer()
            VStack(spacing: 3) {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 4)
                Text(title).font(.caption.weight(.semibold).monospacedDigit())
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

    private var leftProgress: Double { Double(min(max(-offset.width / threshold, 0), 1)) }
    private var rightProgress: Double { Double(min(max(offset.width / threshold, 0), 1)) }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
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
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
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
            offset = CGSize(width: direction * 650, height: offset.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            if direction < 0 { onSwipeLeft() } else { onSwipeRight() }
            // The next card comes in from the opposite side.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { offset = CGSize(width: -direction * 450, height: 0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { offset = .zero }
                flying = false
            }
        }
    }
}
