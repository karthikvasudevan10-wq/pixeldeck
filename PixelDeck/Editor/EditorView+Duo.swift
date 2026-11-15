import SwiftUI
import PhotosUI
import UIKit

// iPhone Duo layouts from the design handoff (section 8).
//   Closed (outer screen) → the regular Studio ("Pocket").
//   Open flat, landscape  → Flipbook spread: last frame / playback / reference on the left page,
//                           the canvas on the right page, tools and colours by each thumb.
//   Half open on a desk   → Easel: a live "Stage" on the upright half, all input on the "Desk".
// Sizes are never hard-coded: the layout comes from the space the Studio has, and changes the
// moment that space does.

enum StudioLayout: Equatable {
    case pocket, sidePanel, flipbook, easel

    /// The single place the layout is decided. When iOS publishes a fold-posture API, read it here
    /// and return `.easel` for "half open" instead of relying on the menu choice.
    nonisolated static func choose(for size: CGSize, easel: Bool) -> StudioLayout {
        if easel && supportsEasel(size) { return .easel }
        // A big landscape space: an unfolded iPhone Duo (and iPad in landscape).
        if size.width >= 900 && size.height >= 600 && size.width > size.height { return .flipbook }
        if EditorView.prefersSidePanel(size) { return .sidePanel }
        return .pocket
    }

    /// Easel needs room for a stage above a desk.
    nonisolated static func supportsEasel(_ size: CGSize) -> Bool {
        size.height >= 760 && size.width >= 600
    }
}

/// What the Flipbook's left page shows.
enum LeftPage: CaseIterable, Identifiable {
    case lastFrame, playback, reference
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .lastFrame: "Last frame"
        case .playback: "Playback"
        case .reference: "Reference"
        }
    }
}

extension EditorView {

    // MARK: Flipbook spread

    var flipbook: some View {
        VStack(spacing: 0) {
            // Top bar, 60 pt: what the left page shows · sprite, counter, undo, redo, export.
            HStack(spacing: 32) {
                HStack(spacing: 4) {
                    ForEach(LeftPage.allCases) { page in
                        let on = leftPage == page
                        Button { leftPage = page } label: {
                            Text(page.title).font(AppFont.pixel(11)).padding(.horizontal, 12).frame(height: 36)
                        }
                        .buttonStyle(TileButtonStyle(active: on, fill: .clear, foreground: Theme.muted))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(Theme.surface)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    chip
                    barButton(.undo, "Undo") { model.undo() }.disabled(!model.canUndo)
                    barButton(.redo, "Redo") { model.redo() }.disabled(!model.canRedo)
                    layersButton
                    barButton(.export, "Export", tint: Theme.muted) { openExport() }
                    barButton(.gallery, "Gallery", tint: Theme.muted) { dismiss() }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)

            // The two pages, with the hinge gutter between them kept empty.
            HStack(spacing: 32) {
                HStack(spacing: 10) {
                    ScrollView(.vertical, showsIndicators: false) {
                        ToolRow(model: model, columns: 1)
                    }
                    .frame(width: 52)
                    .scrollBounceBehavior(.basedOnSize)
                    leftPagePanel
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    rightPage(caption: Text("Drawing frame \(String(format: "%02d", model.currentIndex + 1))"))
                    ScrollView(.vertical, showsIndicators: false) {
                        PaletteRow(model: model, onEdit: { editingSwatch = SwatchEdit(index: $0) }, onPalettes: { showingPalettes = true }, columns: 1)
                    }
                    .frame(width: 60)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            // The hinge line: faint white on night, faint ink on paper.
            .overlay { Theme.uiGrid.color.frame(width: 2).accessibilityHidden(true) }

            // Bottom bar, 84 pt: play, frames, onion, fps.
            HStack(spacing: 10) {
                FrameRow(model: model, thumb: CGSize(width: 44, height: 58), playSize: 56)
                onionToggle
                fpsMenu(bordered: true)
            }
            .padding(.horizontal, 20)
            .frame(height: 84)
        }
    }

    /// Left page: the previous frame, the live loop, or a pinned reference image.
    var leftPagePanel: some View {
        ZStack(alignment: .topLeading) {
            Checkerboard(cell: 24, a: Theme.viewerA, b: Theme.viewerB)
            Group {
                switch leftPage {
                case .lastFrame:
                    if model.currentIndex > 0 {
                        PixelImage(frame: model.project.frames[model.currentIndex - 1], checker: false).padding(24)
                    } else {
                        Text("This is the first frame. Turn the page to start the next one.")
                            .font(AppFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(32)
                    }
                case .playback:
                    FrameLoop(frames: model.project.frames, durations: model.frameDurations).padding(24)
                case .reference:
                    ReferencePanel(image: $reference, model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(leftCaption)
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.chip)
                .padding(10)
        }
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
        .clipped()
    }

    private var leftCaption: LocalizedStringKey {
        switch leftPage {
        case .lastFrame: model.currentIndex > 0 ? "Frame \(String(format: "%02d", model.currentIndex))" : "Last frame"
        case .playback: "Playback · \(model.project.fps) fps"
        case .reference: "Reference"
        }
    }

    /// The drawing page (Flipbook right page, Easel desk): canvas, caption, page-turn corner.
    func rightPage(caption: Text, accentBorder: Bool = true, showsCaption: Bool = true) -> some View {
        SwipeCanvas(swipeAnywhere: swipeAnywhere, flingsNewFrame: false,
                    onNewFrame: turnPage, onNewCanvas: newCanvas) {
            canvas
        }
        .overlay(alignment: .topLeading) {
            if showsCaption {
                caption
                    .font(AppFont.pixel(11))
                    .foregroundStyle(accentBorder ? Theme.onAccent : Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentBorder ? Theme.accent : Theme.chip)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) { PageCorner(action: turnPage) }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if model.tool == .select && !model.isPlaying { selectionStrip }
                if model.tool == .shape && !model.isPlaying { shapeStrip }
                if (model.tool == .pencil || model.tool == .eraser) && !model.isPlaying { brushStrip }
            }
            .padding(.bottom, 52)
        }
        .overlay { turningOverlay }
        .overlay(Rectangle().strokeBorder(accentBorder ? Theme.accent : Theme.line, lineWidth: 2).allowsHitTesting(false))
        .clipped()
    }

    /// The page you just drew folding over to the left (a cross-fade with Reduce Motion).
    @ViewBuilder
    private var turningOverlay: some View {
        if let page = turningPage {
            ZStack {
                Checkerboard(cell: 24)
                PixelImage(image: page).padding(24)
            }
            .modifier(PageTurnEffect(progress: turnProgress, crossFade: reduceMotion))
            .allowsHitTesting(false)
        }
    }

    /// Turn the page: the frame you drew becomes the left page; a blank one (with onion skin)
    /// takes its place on the right.
    func turnPage() {
        let drawn = ThumbnailCache.shared.image(for: model.project.frames[model.currentIndex])
        guard model.addKeyframe() else { return }
        leftPage = leftPage == .reference ? .reference : .lastFrame
        turnToken += 1
        let token = turnToken
        // Show the page at the start position first; animate on the next run-loop turn, or
        // SwiftUI would only ever see the end state.
        turningPage = drawn
        turnProgress = 0
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.35)) {
                turnProgress = 1
            } completion: {
                if token == turnToken { turningPage = nil }
            }
        }
    }

    var onionToggle: some View {
        Button { model.onionSkinEnabled.toggle() } label: {
            HStack(spacing: 8) {
                PixelIcon.onion.view(size: 16)
                Text("Onion").font(AppFont.pixel(11))
            }
            .foregroundStyle(model.onionSkinEnabled ? Theme.accent : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(model.onionSkinEnabled ? Theme.accent.opacity(0.14) : .clear)
            .overlay(Rectangle().strokeBorder(model.onionSkinEnabled ? Theme.accent : Theme.line, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Onion skin")
        .accessibilityAddTraits(model.onionSkinEnabled ? .isSelected : [])
        .contextMenu { OnionMenu(model: model, onTrace: { showingTrace = true }) }
        .accessibilityAction(named: "Tracing image") { showingTrace = true }
        .tourHighlight(.onion)
    }

    func fpsMenu(bordered: Bool) -> some View {
        Menu {
            Picker("Frame rate", selection: Binding(get: { model.project.fps }, set: { model.setFPS($0) })) {
                ForEach([1, 2, 3, 4, 6, 8, 10, 12, 15, 24, 30], id: \.self) { Text("\($0) fps").tag($0) }
            }
            TimingPicker(model: model)
        } label: {
            Text(verbatim: "\(model.project.fps) fps")
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .overlay(Rectangle().strokeBorder(bordered ? Theme.line : .clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Frame rate, \(model.project.fps) frames per second"))
    }

    private func barButton(_ icon: PixelIcon, _ label: LocalizedStringKey, tint: Color = Theme.text,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.view(size: 20).foregroundStyle(tint).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Easel

    var easel: some View {
        GeometryReader { geo in
            let hinge: CGFloat = 16
            let half = max(0, (geo.size.height - hinge) / 2)
            VStack(spacing: 0) {
                // Upright half: display only.
                EaselStage(model: model)
                    .frame(height: half)
                    .clipped()
                // Hinge band: kept empty.
                ZStack {
                    Theme.hinge
                    Theme.line.frame(width: 64, height: 4)
                }
                .frame(height: hinge)
                .accessibilityHidden(true)
                // Flat half: all input.
                HStack(spacing: 14) {
                    VStack(spacing: 10) {
                        ToolRow(model: model, columns: 2)
                        HStack(spacing: 6) {
                            barButton(.undo, "Undo") { model.undo() }.disabled(!model.canUndo)
                            barButton(.redo, "Redo") { model.redo() }.disabled(!model.canRedo)
                        }
                    }
                    rightPage(caption: Text(verbatim: "Frame \(frameLabel)"), accentBorder: false, showsCaption: false)
                        // The sprite chip holds Export, Back to gallery and the Easel switch.
                        .overlay(alignment: .topLeading) { chip.padding(10) }
                        .overlay(alignment: .topTrailing) { layersButton.padding(10) }
                    VStack(spacing: 10) {
                        PaletteRow(model: model, onEdit: { editingSwatch = SwatchEdit(index: $0) }, onPalettes: { showingPalettes = true }, columns: 2)
                        HStack(spacing: 6) {
                            fpsStep("−", label: "Slower", by: -1)
                            fpsStep("+", label: "Faster", by: 1)
                        }
                    }
                }
                .padding(16)
                .frame(height: half)
            }
        }
    }

    private func fpsStep(_ symbol: String, label: LocalizedStringKey, by delta: Int) -> some View {
        Button { model.setFPS(min(30, max(1, model.project.fps + delta))) } label: {
            Text(verbatim: symbol).font(AppFont.pixel(16)).foregroundStyle(Theme.text)
                .frame(width: 52, height: 44)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: Pieces

/// The page-turn hint: a folded corner (diagonal half cream at 55%, half ink) that pulses to 1.35×
/// on a 3 s loop. Still with Reduce Motion. Tapping it turns the page.
struct PageCorner: View {
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            Canvas { ctx, size in
                var light = Path(); light.move(to: .zero); light.addLine(to: CGPoint(x: size.width, y: 0)); light.addLine(to: CGPoint(x: 0, y: size.height)); light.closeSubpath()
                var dark = Path(); dark.move(to: CGPoint(x: size.width, y: 0)); dark.addLine(to: CGPoint(x: size.width, y: size.height)); dark.addLine(to: CGPoint(x: 0, y: size.height)); dark.closeSubpath()
                ctx.fill(light, with: .color(Theme.cream))
                ctx.fill(dark, with: .color(Theme.ink))
            }
            .frame(width: 22, height: 22)
            .opacity(0.55)
            .scaleEffect(pulse ? 1.35 : 1, anchor: .bottomTrailing)
            .frame(width: 44, height: 44, alignment: .bottomTrailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Turn the page: new frame")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Easel's upright half: the welcome night backdrop with the animation looping live, standing on
/// the ground, plus the sprite's name, size, frame rate and frame count. Display only.
struct EaselStage: View {
    let model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, w = geo.size.width
            // The design's bands, scaled from its 504 pt stage.
            let k = h / 504
            let ground = 440 * k
            ZStack(alignment: .topLeading) {
                Color(hex: 0x1A1430)
                Color(hex: 0x120E1F).frame(height: 150 * k)
                Color(hex: 0x171129).frame(height: 120 * k).offset(y: 150 * k)
                Color(hex: 0x1E1736).frame(height: 110 * k).offset(y: 270 * k)
                ForEach(0..<14, id: \.self) { i in
                    Theme.Night.cream.frame(width: 4, height: 4)
                        .opacity(i % 3 == 0 ? 0.5 : 0.9)
                        .offset(x: CGFloat((i * 137) % 100) / 100 * w, y: CGFloat((i * 61) % 100) / 100 * 260 * k)
                }
                Color(hex: 0x2E2452).frame(height: max(0, h - ground)).offset(y: ground)
                Color(hex: 0x4A3B7A).frame(height: 8).offset(y: ground)

                loop(width: w, ground: ground)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Easel mode")
                            .font(AppFont.pixel(11))
                            .foregroundStyle(Theme.Night.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.Night.accent)
                        Text("Live loop of everything you draw below")
                            .font(AppFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(Theme.Night.muted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.project.name).font(AppFont.body(15, .bold, relativeTo: .headline)).foregroundStyle(Theme.Night.cream)
                        Text(verbatim: "\(model.bounds.width)×\(model.bounds.height) px")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.Night.muted)
                    }
                    .padding(.top, 50 * k)
                }
                .padding(.leading, 24)
                .padding(.top, 20)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: "\(model.project.fps)").font(AppFont.pixel(44)).foregroundStyle(Theme.Night.cream)
                    Text("fps").font(AppFont.pixel(12)).foregroundStyle(Theme.Night.muted)
                    Text(verbatim: "\(model.frameCount)").font(AppFont.pixel(28)).foregroundStyle(Theme.Night.cream).padding(.top, 18)
                    Text("frames").font(AppFont.pixel(12)).foregroundStyle(Theme.Night.muted)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 28)
                .padding(.top, 120 * k)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stage: \(model.project.name) playing at \(model.project.fps) frames per second"))
    }

    /// The animation at the largest whole-point pixel size that fits (22 pt for the design's
    /// 12×16 slime), standing on the ground. Updates as soon as a pixel changes below.
    @ViewBuilder
    private func loop(width w: CGFloat, ground: CGFloat) -> some View {
        let b = model.bounds
        let px = max(1, min(22, floor(min(w * 0.4 / CGFloat(b.width), (ground - 40) / CGFloat(b.height)))))
        let size = CGSize(width: CGFloat(b.width) * px, height: CGFloat(b.height) * px)
        let frames = model.project.frames
        Group {
            if frames.count > 1 && !reduceMotion {
                FrameLoop(frames: frames, durations: model.frameDurations)
            } else {
                PixelImage(frame: frames[model.currentIndex], checker: false)
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: (w - size.width) / 2, y: ground - size.height)
    }
}

/// A photo or sketch pinned beside the canvas (Flipbook left page). With the colour picker tool,
/// tapping it samples a colour. Chosen with the system photo picker, which needs no photo-library
/// permission; saved per sprite (and synced with it through iCloud when sync is on).
struct ReferencePanel: View {
    @Binding var image: UIImage?
    let model: EditorModel
    @State private var item: PhotosPickerItem?

    var body: some View {
        Group {
            if let image {
                GeometryReader { geo in
                    let fit = fittedRect(image.size, in: geo.size)
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard model.tool == .eyedropper, fit.contains(location) else { return }
                            let p = CGPoint(x: (location.x - fit.minX) / fit.width * image.size.width,
                                            y: (location.y - fit.minY) / fit.height * image.size.height)
                            if let c = image.pixelColor(at: p) { model.pickColor(c) }
                        }
                }
                .padding(16)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 6) {
                        PhotosPicker(selection: $item, matching: .images) {
                            Text("Replace").font(AppFont.pixel(11)).padding(.horizontal, 10).frame(height: 32)
                        }
                        .buttonStyle(TileButtonStyle(fill: Theme.surface))
                        Button { setImage(nil) } label: {
                            Text("Remove").font(AppFont.pixel(11)).padding(.horizontal, 10).frame(height: 32)
                        }
                        .buttonStyle(TileButtonStyle(fill: Theme.surface))
                    }
                    .padding(10)
                }
                .accessibilityLabel("Reference image")
                .accessibilityHint("With the colour picker tool, tap to sample a colour")
            } else {
                PhotosPicker(selection: $item, matching: .images) {
                    VStack(spacing: 12) {
                        PixelIcon.gallery.view(size: 40, lineWidth: 1.5)
                        Text("Add reference").font(AppFont.pixel(13)).foregroundStyle(Theme.text)
                        Text("Pin a photo or sketch here while you draw on the right page. Tap it with the picker to sample colours.")
                            .font(AppFont.body(13, relativeTo: .footnote))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 220)
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(24)
                    .frame(maxWidth: 300, maxHeight: 360)
                    .overlay(Rectangle().strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    setImage(img.downscaled(maxSide: 1600))
                }
                item = nil
            }
        }
    }

    private func setImage(_ img: UIImage?) {
        image = img
        ImageStore.references.save(img, for: model.project.id)
    }

    private func fittedRect(_ imageSize: CGSize, in box: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let s = min(box.width / imageSize.width, box.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }
}

/// Pictures kept beside a sprite, one per sprite: the Flipbook's reference image and the tracing
/// picture. In Application Support on the device, or in the iCloud container with iCloud sync on
/// (`root`), so they follow the sprite to the user's other devices.
struct ImageStore {
    static let references = ImageStore(folder: "References", png: false)
    /// PNG, so transparent sketches stay transparent.
    static let traces = ImageStore(folder: "Trace", png: true)
    static let all = [references, traces]
    /// Folders moved between the device and iCloud when sync is switched (saved palettes too).
    private static let movable = all + [ImageStore(folder: "Palettes", png: false)]

    /// The iCloud container, when syncing; nil for the device.
    nonisolated(unsafe) static var root: URL?

    let folder: String
    let png: Bool

    private static var localRoot: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private func directory(in base: URL?) -> URL? {
        guard let base = base ?? Self.localRoot else { return nil }
        let dir = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func url(_ id: UUID, in base: URL? = ImageStore.root) -> URL? {
        directory(in: base)?.appendingPathComponent(id.uuidString).appendingPathExtension(png ? "png" : "jpg")
    }

    func load(for id: UUID) -> UIImage? {
        guard let u = url(id), let data = try? Data(contentsOf: u) else { return nil }
        return UIImage(data: data)
    }

    func save(_ image: UIImage?, for id: UUID) {
        guard let u = url(id) else { return }
        if let data = png ? image?.pngData() : image?.jpegData(compressionQuality: 0.85) {
            try? CloudFiles.write(data, to: u)
        } else if FileManager.default.fileExists(atPath: u.path) {
            CloudFiles.remove(u)
        }
    }

    func delete(for id: UUID) { save(nil, for: id) }

    func copy(from id: UUID, to newID: UUID) {
        guard let a = url(id), let b = url(newID), FileManager.default.fileExists(atPath: a.path) else { return }
        CloudFiles.copy(from: a, to: b)
    }

    /// Removes every picture kept for a sprite that was deleted.
    static func deleteAll(for id: UUID) {
        for s in all { s.delete(for: id) }
        TimelapseStore.delete(for: id)
    }

    static func copyAll(from id: UUID, to newID: UUID) {
        for s in all { s.copy(from: id, to: newID) }
        TimelapseStore.copy(from: id, to: newID)
    }

    /// Switches between the device and iCloud (`newRoot`), copying pictures that aren't there yet.
    static func move(to newRoot: URL?, removingOld: Bool) {
        let oldRoot = root
        guard oldRoot?.standardizedFileURL != newRoot?.standardizedFileURL else { return }
        for s in movable {
            guard let from = s.directory(in: oldRoot), let to = s.directory(in: newRoot) else { continue }
            let files = (try? FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? []
            for f in files {
                let target = to.appendingPathComponent(f.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) { CloudFiles.copy(from: f, to: target) }
                if removingOld { CloudFiles.remove(f) }
            }
        }
        root = newRoot
    }
}

extension UIImage {
    /// Smaller copy, drawn upright (EXIF rotation applied), so pixel sampling matches what's shown.
    func downscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide || imageOrientation != .up else { return self }
        let s = min(1, maxSide / longest)
        let target = CGSize(width: (size.width * s).rounded(), height: (size.height * s).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// The colour at a point (in the image's point coordinates), opaque.
    func pixelColor(at p: CGPoint) -> RGBA? {
        guard let cg = cgImage else { return nil }
        let x = min(max(Int(p.x * scale), 0), cg.width - 1), y = min(max(Int(p.y * scale), 0), cg.height - 1)
        var px = [UInt8](repeating: 0, count: 4)
        // The context writes into `px`, so it must only be used while the buffer is pinned.
        let drew = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return true
        }
        guard drew else { return nil }
        return RGBA(r: px[0], g: px[1], b: px[2], a: 255)
    }
}

/// The page-turn: rotates about the spine and disappears once it's past 90° (it's then edge-on
/// and would show mirrored). An Animatable modifier, so the cut happens at the real halfway point
/// rather than being interpolated as a fade. With Reduce Motion, a plain cross-fade.
struct PageTurnEffect: ViewModifier, Animatable {
    var progress: CGFloat
    var crossFade: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(crossFade ? 0 : -180 * Double(progress)),
                              axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.45)
            .opacity(crossFade ? Double(1 - progress) : (progress < 0.5 ? 1 : 0))
    }
}

/// Loops a sprite's frames using the cached frame images (cheap enough to sit beside a canvas
/// that updates on every touch). Shows the first frame with Reduce Motion.
struct FrameLoop: View {
    let frames: [Frame]
    /// Seconds per frame (the sprite's eased timing).
    let durations: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if frames.count > 1 && !reduceMotion {
            TimelineView(.periodic(from: .now, by: PlaybackClock.tick(durations))) { ctx in
                let i = min(PlaybackClock.index(ctx.date, durations: durations), frames.count - 1)
                PixelImage(frame: frames[i], checker: false)
            }
        } else if let first = frames.first {
            PixelImage(frame: first, checker: false)
        }
    }
}
