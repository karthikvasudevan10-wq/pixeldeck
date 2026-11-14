import SwiftUI

/// The canvas as a card you can fling. Swipe **left** from the right edge: a new keyframe slides
/// in with the previous one as an onion skin. Swipe **right** from the left edge: a new canvas.
///
/// One finger on the canvas draws, so swipes start in a thin zone along each side edge, marked by
/// a subtle pixel chevron. In swipe mode (`swipeAnywhere`) the whole card can be dragged instead.
///
/// Right-to-left languages: the drag is measured in this view's own coordinate space, which
/// SwiftUI mirrors with the layout, so the directions and hints flip together.
struct SwipeCanvas<Content: View>: View {
    var swipeAnywhere: Bool
    /// false: a left swipe springs back and calls `onNewFrame` (the Flipbook turns a page instead
    /// of flinging the card away).
    var flingsNewFrame = true
    var onNewFrame: () -> Void
    var onNewCanvas: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var flying = false
    @State private var width: CGFloat = 390
    @State private var swipeCount = 0
    @GestureState private var dragging = false

    private let edgeZone: CGFloat = 24
    private var threshold: CGFloat { min(110, width * 0.28) }

    var body: some View {
        ZStack {
            content()
                .offset(x: offset)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset / 40)), anchor: .bottom)

            dragLabel

            if swipeAnywhere {
                Color.clear.contentShape(Rectangle()).gesture(drag)
                    .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2).allowsHitTesting(false))
            } else {
                HStack(spacing: 0) {
                    edge(direction: .newCanvas)
                    Spacer(minLength: 0)
                    edge(direction: .newFrame)
                }
            }
        }
        .clipped()
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeCount)
        .onChange(of: dragging) { _, isDragging in
            guard !isDragging else { return }
            // Runs after onEnded for a normal drag; only acts if the drag was cancelled.
            DispatchQueue.main.async {
                if !flying && offset != 0 { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = 0 } }
            }
        }
        .accessibilityAction(named: Text("New frame")) { onNewFrame() }
        .accessibilityAction(named: Text("New canvas")) { onNewCanvas() }
    }

    private static var space: String { "SwipeCanvas" }

    private enum Direction { case newFrame, newCanvas }

    /// A thin strip along the side that starts swipes, with the idle chevron hint.
    private func edge(direction: Direction) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            EdgeChevron(pointsLeading: direction == .newFrame,
                        color: direction == .newFrame ? Theme.accent : Theme.accent2)
                .opacity(offset == 0 ? 1 : 0)
        }
        .frame(width: edgeZone)
        .gesture(drag)
        .accessibilityHidden(true)
    }

    /// Shown only while dragging past the threshold, so idle hints stay text-free.
    private var dragLabel: some View {
        let progress = min(abs(offset) / threshold, 1)
        let newFrame = offset < 0
        return Text(newFrame ? "New frame" : "New canvas")
            .font(AppFont.pixel(13))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(newFrame ? Theme.accent : Theme.accent2)
            .opacity(Double(progress))
            .scaleEffect(0.9 + 0.1 * progress)
            .allowsHitTesting(false)
    }

    private var drag: some Gesture {
        // Measured in the stationary container (not the moving card) so it doesn't feed back.
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard !flying else { return }
                offset = value.translation.width
            }
            .onEnded { value in
                guard !flying else { return }
                let projected = value.predictedEndTranslation.width
                if value.translation.width < -threshold || projected < -threshold * 2.5 {
                    if flingsNewFrame {
                        flyOff(direction: -1)
                    } else {
                        swipeCount += 1
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                        onNewFrame()
                    }
                } else if value.translation.width > threshold || projected > threshold * 2.5 {
                    flyOff(direction: 1)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = 0 }
                }
            }
    }

    private func flyOff(direction: CGFloat) {
        flying = true
        swipeCount += 1
        withAnimation(.easeIn(duration: 0.18)) { offset = direction * (width + 80) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            if direction < 0 { onNewFrame() } else { onNewCanvas() }
            // The next card comes in from the opposite side.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { offset = -direction * width * 0.8 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { offset = 0 }
                flying = false
            }
        }
    }
}

/// The 3×5-pixel chevron hint (9×15 pt), 6 pt in from the edge. Idles on a 2.4 s loop: opacity
/// 0.35 → 0.6 → 0.35 with a 3 pt nudge in the swipe direction. Still with Reduce Motion.
///
/// Driven by a repeating SwiftUI animation, which Core Animation runs on the render server: no
/// view updates per frame, unlike a TimelineView (that kept the CPU busy 30 times a second).
private struct EdgeChevron: View {
    /// true: "‹" on the trailing edge (swipe toward leading = new frame).
    var pointsLeading: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        shape
            .frame(width: 9, height: 15)
            .opacity(up ? 0.6 : 0.35)
            .offset(x: up ? (pointsLeading ? -3 : 3) : 0)
            .frame(maxWidth: .infinity, alignment: pointsLeading ? .trailing : .leading)
            .padding(pointsLeading ? .trailing : .leading, 6)
            .onAppear { start() }
            .onChange(of: reduceMotion) { _, _ in start() }
    }

    private func start() {
        guard !reduceMotion else {
            withAnimation(nil) { up = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { up = true }
    }

    private var shape: some View {
        Canvas { ctx, size in
            let u = size.width / 3
            // Pixel cells of the chevron, pointing right (›); mirrored for ‹.
            let cells = [(0, 0), (1, 1), (2, 2), (1, 3), (0, 4)]
            var p = Path()
            for (cx, cy) in cells {
                let x = pointsLeading ? 2 - cx : cx
                p.addRect(CGRect(x: CGFloat(x) * u, y: CGFloat(cy) * u, width: u, height: u))
            }
            ctx.fill(p, with: .color(color))
        }
    }
}
