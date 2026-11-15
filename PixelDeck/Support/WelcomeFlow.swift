import SwiftUI

/// First launch: the animated welcome scene, then "Two swipes", then into the Studio.
/// Also reachable from Settings ("How the swipes work"), starting on the tutorial.
struct WelcomeFlow: View {
    var startOnGestures = false
    var onFinish: () -> Void
    @State private var showingGestures = false

    var body: some View {
        Group {
            if showingGestures || startOnGestures {
                GesturesView(onDone: onFinish)
                    .transition(.move(edge: .trailing))
            } else {
                WelcomeView(onStart: onFinish, onShowSwipes: { withAnimation(.easeInOut(duration: 0.25)) { showingGestures = true } })
                    .transition(.move(edge: .leading))
            }
        }
        .screenBackground()
    }
}

// MARK: Welcome

private struct WelcomeView: View {
    var onStart: () -> Void
    var onShowSwipes: () -> Void
    /// Measured heights of the text and the buttons, so the scene can take exactly what's left.
    @State private var textHeight: CGFloat = 320
    @State private var actionsHeight: CGFloat = 140

    /// The design's scene height.
    private let fullScene: CGFloat = 452
    /// Below this (plus the status bar) the slime and campfire would slide under the Dynamic Island.
    private let minimumScene: CGFloat = 250
    private let gap: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            let screen = geo.size.height + top + bottom
            // The scene gets whatever the text and buttons leave, up to the design's height.
            // If even the minimum doesn't leave room (big text on a small phone), the page scrolls.
            let scene = min(fullScene, max(minimumScene + top, screen - textHeight - actionsHeight - gap))

            ScrollView {
                VStack(spacing: 0) {
                    NightScene()
                        .frame(height: scene)
                        .clipped()
                        .overlay(alignment: .topLeading) { logo.padding(.leading, 20).padding(.top, top + 12) }

                    textBlock
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }

                    Spacer(minLength: gap)

                    actions
                        .padding(.bottom, bottom)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
                }
                // Fill the screen so the buttons sit at the bottom when there's room to spare.
                .frame(minHeight: screen)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            (Text("Draw it.\nFlip it.\n") + Text("Make it move.").foregroundStyle(Theme.accent))
                .font(AppFont.pixel(36))
                .foregroundStyle(Theme.cream)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pixel art and frame-by-frame animation, built for your thumb. Swipe left for the next frame — the last one stays underneath as an onion skin.")
                .font(AppFont.body(16, relativeTo: .body))
                .foregroundStyle(Theme.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .readableWidth()
    }

    private var actions: some View {
        VStack(spacing: 6) {
            Button(action: onStart) { PrimaryActionLabel(title: "Start drawing") }
                .buttonStyle(PrimaryButtonStyle())
            Button(action: onShowSwipes) {
                Text("See how the swipes work")
                    .font(AppFont.body(15, .medium, relativeTo: .callout))
                    .foregroundStyle(Theme.accent2)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)          // room for the button's press-in shadow
        .padding(.bottom, 32)
        .readableWidth()
    }

    private var logo: some View {
        HStack(spacing: 10) {
            AnimatedSprite(key: "slime", pixel: 2, playing: false)
                .frame(width: 28, height: 28)
                .background(Theme.accent)
            Text(verbatim: "Pixel Deck").font(AppFont.pixel(18)).foregroundStyle(Theme.Night.cream).tracking(1)
        }
        .accessibilityHidden(true)
    }
}

/// The design's animated pixel night: banded sky, twinkling stars, moon, ghost, coins, a bouncing
/// slime and a campfire on stepped hills. Laid out on a 390-point-wide design, centred.
private struct NightScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// x, y, size of each star.
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (24, 62, 4), (70, 30, 4), (118, 84, 6), (160, 40, 4), (204, 96, 4), (250, 26, 6), (300, 140, 4), (352, 170, 4),
        (140, 150, 4), (190, 190, 6), (30, 210, 4), (90, 176, 4), (340, 230, 4), (226, 130, 4), (60, 250, 4),
    ]

    var body: some View {
        GeometryReader { geo in
            let dx = (geo.size.width - 390) / 2
            ZStack(alignment: .topLeading) {
                Color(hex: 0x1A1430)
                band(0, 120, 0x120E1F, geo.size.width)
                band(120, 100, 0x171129, geo.size.width)
                band(220, 90, 0x1E1736, geo.size.width)

                TimelineView(.periodic(from: .now, by: 0.42)) { ctx in
                    let tick = reduceMotion ? 2 : Int(ctx.date.timeIntervalSinceReferenceDate / 0.42)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(Self.stars.enumerated()), id: \.offset) { i, s in
                            let phase = (tick + i * 3) % 6
                            Rectangle()
                                .fill(i % 4 == 0 ? Theme.accent2 : Theme.cream)
                                .frame(width: s.2, height: s.2)
                                .opacity(phase == 0 ? 0.15 : (phase == 1 ? 0.5 : 1))
                                .offset(x: s.0 + dx, y: s.1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                sprite("moon", px: 7, x: 390 - 40 - 56, y: 56, dx: dx)
                sprite("ghost", px: 5, x: 30, y: 104, dx: dx)
                sprite("coin", px: 4, x: 244, y: 170, dx: dx)
                sprite("coin", px: 3, x: 292, y: 210, dx: dx, fps: 6)

                block(0, 300, 110, 40, 0x2A2148, dx)
                block(0, 280, 60, 20, 0x2A2148, dx)
                block(260, 290, 130, 50, 0x2A2148, dx)
                block(320, 268, 70, 22, 0x2A2148, dx)
                Color(hex: 0x2E2452).frame(width: geo.size.width, height: 112).offset(y: 340)
                Color(hex: 0x4A3B7A).frame(width: geo.size.width, height: 8).offset(y: 340)
                block(40, 372, 16, 8, 0x3B2F63, dx)
                block(180, 400, 24, 8, 0x3B2F63, dx)
                block(320, 384, 16, 8, 0x3B2F63, dx)

                sprite("slime", px: 8, x: 92, y: 212, dx: dx)
                sprite("flame", px: 7, x: 236, y: 256, dx: dx)
            }
            // The scene is drawn for 452 pt; when shorter it keeps its bottom (the ground).
            .frame(width: geo.size.width, height: 452)
            .offset(y: geo.size.height - 452)
        }
        .accessibilityHidden(true)
    }

    private func band(_ y: CGFloat, _ h: CGFloat, _ hex: UInt32, _ w: CGFloat) -> some View {
        Color(hex: hex).frame(width: w, height: h).offset(y: y)
    }

    private func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ dx: CGFloat) -> some View {
        Color(hex: hex).frame(width: w, height: h).offset(x: x + dx, y: y)
    }

    private func sprite(_ key: String, px: CGFloat, x: CGFloat, y: CGFloat, dx: CGFloat, fps: Int? = nil) -> some View {
        AnimatedSprite(key: key, pixel: px, fps: fps).offset(x: x + dx, y: y)
    }
}

// MARK: Two swipes

private struct GesturesView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("2 of 2").font(AppFont.pixel(13)).foregroundStyle(Theme.muted).tracking(1)
                Spacer()
                Button("Skip", action: onDone)
                    .font(AppFont.body(15, .medium, relativeTo: .callout))
                    .foregroundStyle(Theme.accent2)
                    .frame(minHeight: 44)
            }
            Text("Two swipes.\nThat’s the whole\nworkflow.")
                .font(AppFont.pixel(28))
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 18) {
                    gestureCard(
                        demo: AnyView(NewFrameDemo()),
                        icon: .arrowLeft, iconFill: Theme.accent,
                        title: "Swipe left · new frame",
                        text: "Your last frame stays underneath in pink, so every pose lines up. Swipe from the right edge of the canvas.")
                    gestureCard(
                        demo: AnyView(NewCanvasDemo()),
                        icon: .arrowRight, iconFill: Theme.accent2,
                        title: "Swipe right · new canvas",
                        text: "Start a fresh piece whenever an idea hits. Swipe from the left edge of the canvas.")
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(action: onDone) { PrimaryActionLabel(title: "Got it") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .readableWidth()
    }

    private func gestureCard(demo: AnyView, icon: PixelIcon, iconFill: Color,
                             title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            demo
            HStack(alignment: .top, spacing: 10) {
                icon.view(size: 20, lineWidth: 2.5)
                    .foregroundStyle(icon == .arrowRight ? Theme.onAccent2 : Theme.onAccent)
                    .frame(width: 36, height: 36)
                    .background(iconFill)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.pixel(16)).foregroundStyle(Theme.cream)
                    Text(text)
                        .font(AppFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Eased 0…1 progress through a looping animation of `period` seconds.
private func loopProgress(_ date: Date, period: Double) -> Double {
    date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
}

private func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

/// A finger sweeping across: opacity 0 → 1 by 15 %, holds to 75 %, fades out by 100 %.
private struct FingerDot: View {
    var fromX: CGFloat
    var toX: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let p = reduceMotion ? 0.5 : loopProgress(ctx.date, period: 1.6)
            let x = fromX + (toX - fromX) * easeInOut(p)
            let o = p < 0.15 ? p / 0.15 : (p < 0.75 ? 1 : (1 - p) / 0.25)
            Circle()
                .fill(Theme.cream.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.cream.opacity(0.18)).padding(-6))
                .offset(x: x)
                .opacity(o)
        }
    }
}

private struct NewFrameDemo: View {
    var body: some View {
        ZStack {
            Checkerboard(cell: 16)
            AnimatedSprite(key: "slime", pixel: 8, fps: 3, onion: true)
            FingerDot(fromX: 70, toX: -70)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 28)
                .padding(.bottom, 20)
            Text("Onion skin on")
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .frame(height: 158)
        .clipped()
    }
}

/// The current canvas slides out to the right as a dashed blank one slides in from the left.
private struct NewCanvasDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let inner = geo.size.width - 140
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
                let p = reduceMotion ? 0 : loopProgress(ctx.date, period: 3.2)
                // 0–30 % hold, 30–60 % slide, 60–92 % hold, 92–100 % slide back.
                let t: Double = p < 0.3 ? 0 : (p < 0.6 ? easeInOut((p - 0.3) / 0.3) : (p < 0.92 ? 1 : 1 - easeInOut((p - 0.92) / 0.08)))
                let shift = CGFloat(t) * inner * 1.2
                ZStack {
                    Theme.ink
                    ZStack {
                        Checkerboard(cell: 16)
                        AnimatedSprite(key: "flame", pixel: 7)
                    }
                    .frame(width: inner, height: geo.size.height - 24)
                    .offset(x: shift)
                    ZStack {
                        Checkerboard(cell: 16)
                        Text("Blank canvas").font(AppFont.pixel(12)).foregroundStyle(Theme.accent2)
                    }
                    .frame(width: inner, height: geo.size.height - 24)
                    .overlay(Rectangle().strokeBorder(Theme.accent2, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    .offset(x: shift - inner * 1.2)
                    FingerDot(fromX: -70, toX: 70)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 28)
                        .padding(.bottom, 18)
                }
            }
        }
        .frame(height: 132)
        .clipped()
    }
}
