import AVFoundation
import ReplayKit
import SwiftUI
import UIKit

/// Pixel Playground: plays a level. Left and right to run, Jump to jump (or the arrow keys and
/// Space on a keyboard). Collect every coin, and reach the flag if there is one.
struct PlaygroundPlayView: View {
    let scene: TileScene
    /// Start a screen recording of the run, and offer to share it afterwards.
    var recordRun = false

    @Environment(\.dismiss) private var dismiss
    private var purchases: PurchaseManager { Shared.purchases }
    @State private var game: PlaygroundGame
    @State private var input = PlayInput()
    @State private var paused = false
    @State private var sound: ChipSound?
    @State private var recording = false
    @State private var recorded: ShareItems?
    @FocusState private var focused: Bool

    private let tileImages: [UUID: CGImage]
    private let heroImages: [CGImage]
    private let coinImages: [CGImage]
    private let enemyImages: [CGImage]
    private let heroFPS: Double
    /// How big the hero is drawn, in scene pixels (large sprites are shrunk to fit the level).
    private let heroDraw: CGSize

    init(scene: TileScene, recordRun: Bool = false) {
        self.scene = scene
        self.recordRun = recordRun
        let frames = PlayArt.heroFrames(scene)
        heroImages = PlayArt.images(frames)
        coinImages = PlayArt.images(PlayArt.frames("coin"))
        enemyImages = PlayArt.images(PlayArt.frames("ghost"))
        tileImages = PlayArt.tileImages(scene)
        heroFPS = Double(scene.heroFrames.isEmpty ? 8 : scene.heroFPS)
        let w = CGFloat(frames.first?.width ?? 12), h = CGFloat(frames.first?.height ?? 14)
        let k = min(1, 28 / max(h, 1), 20 / max(w, 1))
        heroDraw = CGSize(width: max(4, (w * k).rounded()), height: max(4, (h * k).rounded()))
        _game = State(initialValue: PlaygroundGame(scene: scene, heroWidth: Int(heroDraw.width) - 2, heroHeight: Int(heroDraw.height)))
    }

    // On the Mac in full screen, clear of the title bar the Mac slides down (see `MacTitleBarInset`).
    var body: some View { screen.clearOfMacTitleBar() }

    private var screen: some View {
        VStack(spacing: 0) {
            hud
            stage
            controls
        }
        .background(Theme.ink.ignoresSafeArea())
        .focusable()
        .focused($focused)
        .onKeyPress(phases: [.down, .up]) { press in handleKey(press) }
        .onAppear {
            focused = true
            if scene.sound && purchases.access.allowsPlaygroundExtras { sound = ChipSound(music: true) }
            if recordRun { startRecording() }
        }
        .onDisappear {
            sound?.stop()
            if recording { RPScreenRecorder.shared().stopRecording { _, _ in } }
        }
        .sheet(item: $recorded) { items in
            ActivityView(items: items.urls) { _ in recorded = nil }.ignoresSafeArea()
        }
    }

    // MARK: HUD

    private var hud: some View {
        HStack(spacing: 12) {
            Button { paused.toggle() } label: {
                (paused ? PixelIcon.play : .pause).view(size: 18).frame(width: 44, height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .accessibilityLabel(paused ? Text("Resume") : Text("Pause"))
            Button { dismiss() } label: {
                Text("Quit").font(AppFont.pixel(12)).padding(.horizontal, 12).frame(height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            if recording {
                Text("REC").font(AppFont.pixel(11)).foregroundStyle(Theme.accent).accessibilityLabel("Recording")
            }
            Spacer()
            if let coin = coinImages.first {
                Image(decorative: coin, scale: 1).interpolation(.none).resizable().frame(width: 24, height: 24)
            }
            Text(verbatim: "\(game.coinsCollected) / \(game.coinTotal)")
                .font(AppFont.pixel(16)).foregroundStyle(Theme.accent2).monospacedDigit()
                .accessibilityLabel(Text("\(game.coinsCollected) of \(game.coinTotal) coins"))
            Text(verbatim: Self.clock(game.elapsed))
                .font(AppFont.pixel(16)).foregroundStyle(Theme.cream).monospacedDigit()
                .accessibilityLabel(Text("Time \(Self.clock(game.elapsed))"))
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: paused || game.status == .won)) { timeline in
                Canvas { ctx, size in draw(&ctx, size: size, time: timeline.date.timeIntervalSinceReferenceDate) }
                    .onChange(of: timeline.date) { old, new in
                        game.step(new.timeIntervalSince(old), input: input)
                        if !game.events.isEmpty {
                            for e in game.events { sound?.play(e) }
                            let won = game.events.contains(.win)
                            game.events.removeAll()
                            if won { finished() }
                        }
                    }
            }
            .overlay { if game.status == .won { wonCard } else if paused { pausedCard } }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: scene.name))
    }

    /// Scene pixels to points: the largest whole scale that shows every row.
    private func scale(for size: CGSize) -> CGFloat {
        max(1, floor(size.height / CGFloat(scene.pixelHeight)))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let s = scale(for: size)
        let sceneW = CGFloat(scene.pixelWidth) * s, sceneH = CGFloat(scene.pixelHeight) * s
        // The camera follows the hero, stopping at the level's edges.
        var camX = CGFloat(game.x + game.heroWidth / 2) * s - size.width / 2
        camX = sceneW <= size.width ? -(size.width - sceneW) / 2 : min(max(0, camX), sceneW - size.width)
        let offset = CGSize(width: -camX, height: (size.height - sceneH) / 2)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scene.sky.color))

        let t = CGFloat(TileScene.tileSize) * s
        let first = max(0, Int((camX / t).rounded(.down))), last = min(scene.columns - 1, Int(((camX + size.width) / t).rounded(.down)))
        if first <= last {
            for y in 0..<scene.rows {
                for x in first...last {
                    guard let tile = scene.tile(at: PixelPoint(x: x, y: y)), let image = tileImages[tile.id] else { continue }
                    ctx.draw(Image(decorative: image, scale: 1).interpolation(.none),
                             in: CGRect(x: offset.width + CGFloat(x) * t, y: offset.height + CGFloat(y) * t, width: t, height: t))
                }
            }
        }
        func place(_ image: CGImage, x: Double, y: Double, w: Double, h: Double, flipped: Bool = false) {
            let rect = CGRect(x: offset.width + CGFloat(x) * s, y: offset.height + CGFloat(y) * s, width: CGFloat(w) * s, height: CGFloat(h) * s)
            guard rect.intersects(CGRect(origin: .zero, size: size)) else { return }
            if flipped {
                var c = ctx
                c.translateBy(x: rect.midX, y: 0)
                c.scaleBy(x: -1, y: 1)
                c.draw(Image(decorative: image, scale: 1).interpolation(.none),
                       in: CGRect(x: -rect.width / 2, y: rect.minY, width: rect.width, height: rect.height))
            } else {
                ctx.draw(Image(decorative: image, scale: 1).interpolation(.none), in: rect)
            }
        }
        // Coins spin.
        if !coinImages.isEmpty {
            let coin = coinImages[Int(time * 8) % coinImages.count]
            let side = Double(TileScene.tileSize)
            let w = min(side - 4, Double(coin.width)), h = min(side - 4, Double(coin.height))
            for c in game.coinsLeft {
                place(coin, x: Double(c.x) * side + (side - w) / 2, y: Double(c.y) * side + (side - h) / 2, w: w, h: h)
            }
        }
        if let g = scene.goal {
            let side = Double(TileScene.tileSize)
            let rect = CGRect(x: offset.width + CGFloat(Double(g.x) * side) * s, y: offset.height + CGFloat(Double(g.y) * side) * s, width: t, height: t)
            var pole = Path()
            pole.addRect(CGRect(x: rect.minX + t * 0.25, y: rect.minY + t * 0.1, width: max(2, t * 0.1), height: t * 0.9))
            var flag = Path()
            flag.move(to: CGPoint(x: rect.minX + t * 0.35, y: rect.minY + t * 0.1))
            flag.addLine(to: CGPoint(x: rect.minX + t * 0.9, y: rect.minY + t * 0.3))
            flag.addLine(to: CGPoint(x: rect.minX + t * 0.35, y: rect.minY + t * 0.5))
            flag.closeSubpath()
            ctx.fill(pole, with: .color(Theme.cream))
            ctx.fill(flag, with: .color(game.coinsLeft.isEmpty ? Theme.accent2 : Theme.accent))
        }
        if !enemyImages.isEmpty {
            let ghost = enemyImages[Int(time * 6) % enemyImages.count]
            let size = PlaygroundGame.enemySize
            for e in game.enemies where e.alive {
                place(ghost, x: e.x, y: e.y, w: size, h: size, flipped: e.direction > 0)
            }
        }
        // The hero: its own frames while running, the first one standing still.
        if !heroImages.isEmpty {
            let frame = game.isMoving || !game.onGround ? Int(time * heroFPS) % heroImages.count : 0
            let w = Double(heroDraw.width), h = Double(heroDraw.height)
            place(heroImages[frame], x: game.x + (game.heroWidth - w) / 2, y: game.y + game.heroHeight - h, w: w, h: h, flipped: game.facingLeft)
        }
    }

    private var wonCard: some View {
        VStack(spacing: 12) {
            Text("You did it!").font(AppFont.pixel(26)).foregroundStyle(Theme.accent2)
            Text("\(game.coinTotal) coins in \(Self.clock(game.elapsed))", comment: "Playground result: coins (plural) and time")
                .font(AppFont.body(16, .medium, relativeTo: .body)).foregroundStyle(Theme.cream)
            HStack(spacing: 8) {
                Button { restart() } label: {
                    Text("Play again").font(AppFont.pixel(14)).padding(.horizontal, 16).frame(height: 48)
                }
                .buttonStyle(PrimaryButtonStyle(depth: 4))
                Button { dismiss() } label: {
                    Text("Done").font(AppFont.pixel(14)).padding(.horizontal, 16).frame(height: 48)
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
            }
        }
        .padding(24)
        .background(Theme.ink.opacity(0.92))
        .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
        .accessibilityAddTraits(.isModal)
    }

    private var pausedCard: some View {
        Text("Paused").font(AppFont.pixel(22)).foregroundStyle(Theme.cream)
            .padding(20)
            .background(Theme.ink.opacity(0.9))
    }

    private func restart() {
        game = PlaygroundGame(scene: scene, heroWidth: Int(heroDraw.width) - 2, heroHeight: Int(heroDraw.height))
        input = PlayInput()
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            holdButton(label: "Left", set: { input.left = $0 }) {
                PixelIcon.back.view(size: 30, lineWidth: 4).frame(width: 76, height: 76)
            }
            holdButton(label: "Right", set: { input.right = $0 }) {
                PixelIcon.back.view(size: 30, lineWidth: 4).scaleEffect(x: -1).frame(width: 76, height: 76)
            }
            Spacer()
            holdButton(label: "Jump", set: { input.jump = $0 }, round: true) {
                Text("Jump").font(AppFont.pixel(16)).frame(width: 96, height: 96)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    /// A button that's "down" for as long as it's held (two can be held at once).
    private func holdButton<Label: View>(label: LocalizedStringKey, set: @escaping (Bool) -> Void, round: Bool = false,
                                        @ViewBuilder content: () -> Label) -> some View {
        content()
            .foregroundStyle(round ? Theme.onAccent : Theme.text)
            .background(round ? Theme.accent : Theme.tool)
            .clipShape(RoundedRectangle(cornerRadius: round ? 48 : 0))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in set(true) }
                    .onEnded { _ in set(false) }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                // A tap from VoiceOver or Switch Control: a short press.
                set(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { set(false) }
            }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let down = press.phase != .up
        switch press.key {
        case .leftArrow: input.left = down
        case .rightArrow: input.right = down
        case .space, .upArrow: input.jump = down
        case .escape: if down { paused.toggle() }
        default:
            switch press.characters.lowercased() {
            case "a": input.left = down
            case "d": input.right = down
            case "w": input.jump = down
            default: return .ignored
            }
        }
        return .handled
    }

    // MARK: Recording a run

    private func startRecording() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { return }
        recorder.isMicrophoneEnabled = false
        recorder.startRecording { error in
            DispatchQueue.main.async { recording = error == nil }
        }
    }

    private func finished() {
        guard recording else { return }
        recording = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)-run.mp4")
        // A moment on the "You did it!" card, then stop and offer the video.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            RPScreenRecorder.shared().stopRecording(withOutput: url) { error in
                DispatchQueue.main.async { if error == nil { recorded = ShareItems(urls: [url]) } }
            }
        }
    }
}

/// Chiptune sound: square-wave blips for jumps, coins and bumps, and an optional looping tune.
/// Made in code, so there are no sound files.
final class ChipSound {
    private struct Voice {
        var frequency: Double
        /// Multiplied into the frequency every sample (above 1 slides up).
        var slide: Double
        var samplesLeft: Int
        var total: Int
        var phase = 0.0
        var volume: Float
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var voices: [Voice] = []
    private let sampleRate = 44_100.0
    // The tune: one note per step, 0 is a rest.
    private let tune: [Double]
    private var tuneIndex = 0
    private var tuneSamplesLeft = 0
    private var tunePhase = 0.0
    private let stepSamples: Int

    init(music: Bool) {
        // "Night drive": a minor pentatonic arpeggio, two bars.
        let a = 220.0
        let scale = [a, a * 1.2, a * 4 / 3, a * 1.5, a * 1.8, a * 2]
        let pattern = [0, 2, 3, 5, 3, 2, 0, -1, 1, 3, 4, 5, 4, 3, 1, -1]
        tune = music ? pattern.map { $0 < 0 ? 0 : scale[$0] } : []
        stepSamples = Int(sampleRate * 0.16)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            // One channel, so the list holds a single buffer of samples.
            guard let self, let out = audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.lock.lock()
            for i in 0..<Int(frameCount) { out[i] = self.nextSample() }
            self.lock.unlock()
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.5
        // Plays alongside other audio and respects the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    /// Called on the audio thread, with the lock held.
    private func nextSample() -> Float {
        var sample: Float = 0
        if !tune.isEmpty {
            if tuneSamplesLeft <= 0 {
                tuneIndex = (tuneIndex + 1) % tune.count
                tuneSamplesLeft = stepSamples
            }
            let f = tune[tuneIndex]
            if f > 0 {
                tunePhase += f / sampleRate
                if tunePhase >= 1 { tunePhase -= 1 }
                // Each note fades a little, so the tune has a pulse.
                let fade = Float(tuneSamplesLeft) / Float(stepSamples)
                sample += (tunePhase < 0.5 ? 0.07 : -0.07) * (0.4 + 0.6 * fade)
            }
            tuneSamplesLeft -= 1
        }
        var i = 0
        while i < voices.count {
            voices[i].phase += voices[i].frequency / sampleRate
            if voices[i].phase >= 1 { voices[i].phase -= 1 }
            voices[i].frequency *= voices[i].slide
            let fade = Float(voices[i].samplesLeft) / Float(max(1, voices[i].total))
            sample += (voices[i].phase < 0.5 ? voices[i].volume : -voices[i].volume) * fade
            voices[i].samplesLeft -= 1
            if voices[i].samplesLeft <= 0 { voices.remove(at: i) } else { i += 1 }
        }
        return max(-1, min(1, sample))
    }

    private func blip(_ frequency: Double, slide: Double, seconds: Double, volume: Float = 0.18) {
        let n = Int(sampleRate * seconds)
        lock.lock()
        if voices.count < 8 { voices.append(Voice(frequency: frequency, slide: slide, samplesLeft: n, total: n, volume: volume)) }
        lock.unlock()
    }

    func play(_ event: PlayEvent) {
        switch event {
        case .jump: blip(330, slide: 1.00012, seconds: 0.12)
        case .coin:
            blip(988, slide: 1, seconds: 0.07)
            blip(1319, slide: 1, seconds: 0.18, volume: 0.14)
        case .hurt: blip(220, slide: 0.99985, seconds: 0.3)
        case .stomp: blip(160, slide: 1.0002, seconds: 0.1)
        case .win:
            blip(523, slide: 1, seconds: 0.15)
            blip(659, slide: 1, seconds: 0.3, volume: 0.14)
            blip(784, slide: 1, seconds: 0.5, volume: 0.12)
        }
    }

    func stop() {
        engine.stop()
    }
}
