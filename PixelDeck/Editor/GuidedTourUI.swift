import SwiftUI

// The guided tour's interface: the step card, the pulsing ring that points at a control, and the
// edge arrows for the two swipes. The steps and their checks are in Core/GuidedTour.swift.

private struct TourTargetKey: EnvironmentKey {
    static let defaultValue: TourTarget = .none
}

extension EnvironmentValues {
    /// The control the guided tour is pointing at (none when there's no tour).
    var tourTarget: TourTarget {
        get { self[TourTargetKey.self] }
        set { self[TourTargetKey.self] = newValue }
    }
}

extension View {
    /// Draws a pulsing ring around this control while the tour points at `target`.
    func tourHighlight(_ target: TourTarget) -> some View {
        modifier(TourHighlight(target: target))
    }
}

private struct TourHighlight: ViewModifier {
    let target: TourTarget
    @Environment(\.tourTarget) private var current
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    func body(content: Content) -> some View {
        let on = current == target
        content
            .overlay {
                if on {
                    Rectangle()
                        .strokeBorder(Theme.accent2, lineWidth: 3)
                        .padding(-5)
                        .scaleEffect(pulse ? 1.08 : 1)
                        .opacity(pulse ? 0.55 : 1)
                        .allowsHitTesting(false)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
                        }
                        .onDisappear { pulse = false }
                }
            }
            .zIndex(on ? 1 : 0)
    }
}

/// A big pulsing pixel arrow at the canvas edge for the swipe steps.
struct TourEdgeArrow: View {
    let target: TourTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudge = false

    var body: some View {
        let left = target == .rightEdge          // swipe left, starting at the right edge
        if target == .rightEdge || target == .leftEdge {
            HStack {
                if !left { arrow(pointingRight: true) }
                Spacer()
                if left { arrow(pointingRight: false) }
            }
            .padding(.horizontal, 6)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { nudge = true }
            }
            .accessibilityHidden(true)
        }
    }

    private func arrow(pointingRight: Bool) -> some View {
        (pointingRight ? PixelIcon.arrowRight : .arrowLeft).view(size: 34, lineWidth: 4)
            .foregroundStyle(Theme.onAccent2)
            .frame(width: 58, height: 58)
            .background(Theme.accent2)
            .offset(x: nudge ? (pointingRight ? 12 : -12) : 0)
    }
}

/// The step card: progress, what to do, and Skip (or Next for steps that only explain).
struct TourCard: View {
    let step: TourStep
    var celebrating = false
    var nudge: String?
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                (celebrating ? Text("Done!") : Text("Step \(step.rawValue + 1) of \(TourStep.allCases.count)"))
                    .font(AppFont.pixel(10))
                    .foregroundStyle(Theme.onAccent2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.accent2)
                Spacer()
                if !celebrating {
                    Button("Skip tour", action: onSkip)
                        .font(AppFont.body(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
            }
            (celebrating ? Text("You made your first animation!") : step.title)
                .font(AppFont.body(17, .bold, relativeTo: .headline))
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
            (celebrating ? Text("It's saved in your gallery. Have fun!") : step.detail)
                .font(AppFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let nudge {
                Text(verbatim: nudge)
                    .font(AppFont.body(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if step.hasNextButton && !celebrating {
                HStack {
                    Spacer()
                    Button(action: onNext) {
                        Text("Next").font(AppFont.pixel(13)).padding(.horizontal, 18).frame(height: 40)
                    }
                    .buttonStyle(PrimaryButtonStyle(fill: Theme.accent2, shadow: Theme.accent2Shadow, depth: 3))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 440)
        .background(Theme.surface.opacity(0.97))
        .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }
}

extension TourStep {
    var title: Text {
        switch self {
        case .pickColor: Text("Pick a colour")
        case .drawHeart: Text("Draw a heart")
        case .undoRedo: Text("Undo and redo")
        case .zoom: Text("Zoom and move")
        case .addFrame: Text("Add a frame")
        case .drawSecondHeart: Text("Draw it a little higher")
        case .onion: Text("The onion skin")
        case .duplicate: Text("Copy frame 1")
        case .reorder: Text("Make it bounce")
        case .play: Text("Play it!")
        case .moreTools: Text("More to explore")
        case .newCanvas: Text("Your turn")
        }
    }

    var detail: Text {
        switch self {
        case .pickColor:
            Text("Tap the pink square in the colour palette. Long-press any colour later to change it.")
        case .drawHeart:
            Text("Fill in the blinking dots. Tap a square, or drag your finger to paint several at once.")
        case .undoRedo:
            Text("Tap Undo (the curly arrow) to take back your last change, then Redo to bring it back.")
        case .zoom:
            Text("Pinch with two fingers to make pixels bigger or smaller, drag with two fingers to move around, and tap with two fingers to fit your art.")
        case .addFrame:
            Text("Swipe left, starting at the right edge of the canvas. Each swipe adds a new frame to your animation.")
        case .drawSecondHeart:
            Text("Your first heart shows through in pink: that's the onion skin. Fill in the new dots, two squares higher.")
        case .onion:
            Text("Long-press the onion skin button in the bottom row and pick a strength. The same menu adds a tracing picture you can draw over.")
        case .duplicate:
            Text("Long-press the first frame in the frame strip and choose Duplicate. The same menu copies, pastes and deletes frames.")
        case .reorder:
            Text("Long-press the new copy (frame 2) and choose Move later, so the heart goes down, up, down.")
        case .play:
            Text("Tap Play to watch your heart bounce. Tap it again to stop.")
        case .moreTools:
            Text("The tool row also has fill, shapes, mirror and select (drag pixels along a path, then Tween). The layers button is at the top right, and Export saves GIFs and videos.")
        case .newCanvas:
            Text("Swipe right, starting at the left edge, to start a fresh canvas of your own. Your heart stays in the gallery.")
        }
    }
}
