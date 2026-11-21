import SwiftUI
import UIKit

/// Where scenes are kept: beside the sprites (in iCloud when sync is on).
extension SceneStore {
    @MainActor static func forApp() -> SceneStore {
        let base = ImageStore.root
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let store = SceneStore(directory: base.appendingPathComponent("Scenes", isDirectory: true))
        store.writeFile = CloudFiles.write
        return store
    }
}

/// The pictures the scene and game views draw with.
enum PlayArt {
    /// A CGImage for every tile of a scene, by tile id.
    static func tileImages(_ scene: TileScene) -> [UUID: CGImage] {
        var out: [UUID: CGImage] = [:]
        for t in scene.tiles { if let img = PixelRenderer.cgImage(t.grid) { out[t.id] = img } }
        return out
    }

    static func frames(_ key: String) -> [PixelGrid] { StarterArt.sprite(key)?.frames ?? [] }

    /// The hero's frames: the scene's own, or the starter slime.
    static func heroFrames(_ scene: TileScene) -> [PixelGrid] {
        scene.heroFrames.isEmpty ? frames("slime") : scene.heroFrames
    }

    static func images(_ grids: [PixelGrid]) -> [CGImage] { grids.compactMap { PixelRenderer.cgImage($0) } }

    /// A small picture of the whole scene, for lists.
    static func thumbnail(_ scene: TileScene) -> CGImage? { PixelRenderer.cgImage(scene.rendered()) }
}

/// Draws a scene: sky, tiles, and the level's pieces (start, coins, goal, enemies).
struct SceneCanvas: View {
    let scene: TileScene
    /// Points per art pixel.
    var scale: CGFloat
    /// Where the scene's top-left corner is, in the view.
    var offset: CGSize
    var tileImages: [UUID: CGImage]
    var showGrid = true
    var showPieces = true
    var coinImage: CGImage?
    var heroImage: CGImage?
    var enemyImage: CGImage?

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scene.sky.color))
            let t = CGFloat(TileScene.tileSize) * scale
            let view = CGRect(origin: .zero, size: size)
            func cell(_ p: PixelPoint) -> CGRect {
                CGRect(x: offset.width + CGFloat(p.x) * t, y: offset.height + CGFloat(p.y) * t, width: t, height: t)
            }
            for y in 0..<scene.rows {
                for x in 0..<scene.columns {
                    let p = PixelPoint(x: x, y: y)
                    let rect = cell(p)
                    guard rect.intersects(view), let tile = scene.tile(at: p), let image = tileImages[tile.id] else { continue }
                    ctx.draw(Image(decorative: image, scale: 1).interpolation(.none), in: rect)
                }
            }
            if showGrid {
                var grid = Path()
                for x in 0...scene.columns {
                    let px = offset.width + CGFloat(x) * t
                    grid.move(to: CGPoint(x: px, y: offset.height))
                    grid.addLine(to: CGPoint(x: px, y: offset.height + CGFloat(scene.rows) * t))
                }
                for y in 0...scene.rows {
                    let py = offset.height + CGFloat(y) * t
                    grid.move(to: CGPoint(x: offset.width, y: py))
                    grid.addLine(to: CGPoint(x: offset.width + CGFloat(scene.columns) * t, y: py))
                }
                ctx.stroke(grid, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
            }
            guard showPieces else { return }
            func piece(_ image: CGImage?, at p: PixelPoint, fallback: Color) {
                let rect = cell(p)
                guard rect.intersects(view) else { return }
                if let image {
                    // Standing on the bottom of its cell, at the scene's pixel size.
                    let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
                    let k = min(1, t / max(w, 1), (t * 1.6) / max(h, 1))
                    let r = CGRect(x: rect.midX - w * k / 2, y: rect.maxY - h * k, width: w * k, height: h * k)
                    ctx.draw(Image(decorative: image, scale: 1).interpolation(.none), in: r)
                } else {
                    ctx.fill(Path(rect.insetBy(dx: t * 0.25, dy: t * 0.25)), with: .color(fallback))
                }
            }
            for c in scene.coins { piece(coinImage, at: c, fallback: Theme.accent2) }
            for e in scene.enemies { piece(enemyImage, at: e, fallback: Theme.cream) }
            if let g = scene.goal {
                // A flag: pole and pennant.
                let rect = cell(g)
                var pole = Path()
                pole.addRect(CGRect(x: rect.minX + t * 0.25, y: rect.minY + t * 0.1, width: max(2, t * 0.1), height: t * 0.9))
                var flag = Path()
                flag.move(to: CGPoint(x: rect.minX + t * 0.35, y: rect.minY + t * 0.1))
                flag.addLine(to: CGPoint(x: rect.minX + t * 0.9, y: rect.minY + t * 0.3))
                flag.addLine(to: CGPoint(x: rect.minX + t * 0.35, y: rect.minY + t * 0.5))
                flag.closeSubpath()
                ctx.fill(pole, with: .color(Theme.cream))
                ctx.fill(flag, with: .color(Theme.accent))
            }
            piece(heroImage, at: scene.start, fallback: Theme.accent)
        }
    }
}

/// What a touch on the scene does.
enum SceneTool: String, CaseIterable, Identifiable {
    case paint, fill, erase, pick, move
    case start, coin, enemy, goal
    var id: String { rawValue }

    static let tileTools: [SceneTool] = [.paint, .fill, .erase, .pick, .move]
    static let levelTools: [SceneTool] = [.start, .coin, .enemy, .goal, .move]

    var title: LocalizedStringKey {
        switch self {
        case .paint: "Paint"
        case .fill: "Fill"
        case .erase: "Erase"
        case .pick: "Pick"
        case .move: "Move"
        case .start: "Start"
        case .coin: "Coins"
        case .enemy: "Enemies"
        case .goal: "Goal"
        }
    }
}

/// Tiles and scene builder, and the Playground level editor: paint a scene with tiles, then choose
/// a hero, drop in coins, a goal and (with Pro) enemies, and play it.
struct SceneEditorView: View {
    @State private var scene: TileScene
    let store: SceneStore
    private var sprites: ProjectStore { Shared.store }
    private var purchases: PurchaseManager { Shared.purchases }
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case tiles, level
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .tiles ? "Tiles" : "Level" }
    }

    @State private var mode: Mode = .tiles
    @State private var tool: SceneTool = .paint
    @State private var selectedTile = 0
    @State private var scale: CGFloat = 2
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var canvasSize: CGSize = .zero
    @State private var editingTile: EditingTile?
    @State private var playing = false
    @State private var sharing = false
    @State private var upgrade: ProFeature?
    @State private var renaming = false
    @State private var renameText = ""

    private struct EditingTile: Identifiable {
        let index: Int
        var id: Int { index }
    }

    init(scene: TileScene, store: SceneStore) {
        _scene = State(initialValue: scene)
        self.store = store
    }

    private var access: FeatureAccess { purchases.access }

    // On the Mac in full screen, clear of the title bar the Mac slides down (see `MacTitleBarInset`).
    var body: some View { screen.clearOfMacTitleBar() }

    private var screen: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 820
            VStack(spacing: 0) {
                header
                if wide {
                    HStack(spacing: 0) {
                        canvas
                        Theme.line.frame(width: 2)
                        ScrollView { panel.padding(16) }
                            .frame(width: 360)
                            .background(Theme.surface)
                    }
                } else {
                    canvas.frame(height: max(220, geo.size.height * 0.42))
                    Theme.line.frame(height: 2)
                    ScrollView { panel.padding(16) }
                }
            }
        }
        .screenBackground()
        .onChange(of: scene) { _, s in store.save(s) }
        .onChange(of: mode) { _, m in tool = m == .tiles ? .paint : .coin }
        .sheet(item: $editingTile) { editing in
            // (The index can be gone for a moment after a tile is deleted, while the sheet closes.)
            TileEditorView(tile: scene.tiles.indices.contains(editing.index) ? scene.tiles[editing.index] : .blank(name: ""),
                           canDelete: scene.tiles.count > 1) { result in
                switch result {
                case .save(let tile):
                    if scene.tiles.indices.contains(editing.index) { scene.tiles[editing.index] = tile }
                case .delete:
                    scene.removeTile(at: editing.index)
                    selectedTile = min(selectedTile, scene.tiles.count - 1)
                }
            }
        }
        .fullScreenCover(isPresented: $playing) { PlaygroundPlayView(scene: scene) }
        .sheet(isPresented: $sharing) { ShareLevelSheet(scene: scene) }
        .proUpgradeSheet($upgrade)
        .alert("Rename level", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { scene.name = String(t.prefix(40)) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                PixelIcon.back.view(size: 20, lineWidth: 2.5).frame(width: 44, height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .accessibilityLabel("Back")
            Button {
                renameText = scene.name
                renaming = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: scene.name).font(AppFont.pixel(18)).foregroundStyle(Theme.cream).lineLimit(1)
                    Text("Scene · \(scene.columns) × \(scene.rows) tiles", comment: "Scene size, in tiles")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Rename")
            Spacer(minLength: 4)
            Button { zoom(-1) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 40, height: 44) }
                .buttonStyle(.plain).foregroundStyle(Theme.text).accessibilityLabel("Zoom out")
            Button { zoom(1) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 40, height: 44) }
                .buttonStyle(.plain).foregroundStyle(Theme.text).accessibilityLabel("Zoom in")
            Button { playing = true } label: {
                HStack(spacing: 6) {
                    PixelIcon.play.view(size: 14, lineWidth: 2.5)
                    Text("Play").font(AppFont.pixel(13))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            SceneCanvas(scene: scene, scale: scale, offset: clamped(offset, in: geo.size), tileImages: PlayArt.tileImages(scene),
                        coinImage: PlayArt.images(PlayArt.frames("coin")).first,
                        heroImage: PlayArt.images(PlayArt.heroFrames(scene)).first,
                        enemyImage: PlayArt.images(PlayArt.frames("ghost")).first)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in touch(v, in: geo.size, ended: false) }
                        .onEnded { v in touch(v, in: geo.size, ended: true) }
                )
                .onAppear { canvasSize = geo.size; fit(geo.size) }
                .onChange(of: geo.size) { _, s in canvasSize = s }
                .accessibilityLabel(Text("Scene, \(scene.columns) by \(scene.rows) tiles"))
                .accessibilityHint("Touch to use the selected tool")
        }
        .clipped()
    }

    /// Starts at the largest whole scale that shows every row.
    private func fit(_ size: CGSize) {
        guard size.height > 0 else { return }
        scale = max(1, min(4, floor(size.height / CGFloat(scene.pixelHeight))))
        offset = CGSize(width: 0, height: (size.height - CGFloat(scene.pixelHeight) * scale) / 2)
    }

    private func zoom(_ direction: Int) {
        let steps: [CGFloat] = [1, 1.5, 2, 3, 4]
        let i = steps.firstIndex(of: scale) ?? 2
        scale = steps[min(max(i + direction, 0), steps.count - 1)]
        offset = clamped(offset, in: canvasSize)
    }

    /// Keeps the scene on screen: centred when it's smaller than the view, never scrolled past
    /// its edges otherwise.
    private func clamped(_ o: CGSize, in size: CGSize) -> CGSize {
        let w = CGFloat(scene.pixelWidth) * scale, h = CGFloat(scene.pixelHeight) * scale
        func axis(_ v: CGFloat, _ content: CGFloat, _ view: CGFloat) -> CGFloat {
            content <= view ? (view - content) / 2 : min(0, max(view - content, v))
        }
        return CGSize(width: axis(o.width, w, size.width), height: axis(o.height, h, size.height))
    }

    private func touch(_ v: DragGesture.Value, in size: CGSize, ended: Bool) {
        if tool == .move {
            if panStart == nil { panStart = clamped(offset, in: size) }
            if let start = panStart {
                offset = clamped(CGSize(width: start.width + v.translation.width, height: start.height + v.translation.height), in: size)
            }
            if ended { panStart = nil }
            return
        }
        let o = clamped(offset, in: size)
        let t = CGFloat(TileScene.tileSize) * scale
        let p = PixelPoint(x: Int(((v.location.x - o.width) / t).rounded(.down)), y: Int(((v.location.y - o.height) / t).rounded(.down)))
        guard scene.contains(p) else { return }
        switch tool {
        case .paint:
            if scene[p.x, p.y] != selectedTile { scene[p.x, p.y] = selectedTile }
        case .erase:
            if scene[p.x, p.y] != -1 { scene[p.x, p.y] = -1 }
        case .fill:
            if ended { scene.fill(selectedTile, at: p) }
        case .pick:
            if ended, scene[p.x, p.y] >= 0 {
                selectedTile = scene[p.x, p.y]
                tool = .paint
            }
        case .start:
            if scene.start != p { scene.start = p }
        case .coin:
            if ended { scene.toggleCoin(at: p) }
        case .enemy:
            guard ended else { return }
            if access.allowsPlaygroundExtras { scene.toggleEnemy(at: p) } else { upgrade = .playground }
        case .goal:
            if ended { scene.goal = scene.goal == p ? nil : p }
        case .move:
            break
        }
    }

    // MARK: Panel

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChoiceRow(options: Mode.allCases, selection: $mode) { Text($0.title) }
            if mode == .tiles { tilesPanel } else { levelPanel }
        }
    }

    @ViewBuilder
    private var tilesPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(scene.tiles.enumerated()), id: \.element.id) { i, tile in
                    let on = i == selectedTile
                    Button {
                        selectedTile = i
                        if tool != .fill { tool = .paint }
                    } label: {
                        PixelImage(grid: tile.grid, checker: true)
                            .frame(width: 48, height: 48)
                            .overlay(Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: tile.name))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Button {
                    guard scene.tiles.count < TileScene.maxTiles else { return }
                    scene.tiles.append(.blank(name: String(localized: "Tile \(scene.tiles.count + 1)", comment: "Default name for a new tile")))
                    selectedTile = scene.tiles.count - 1
                    editingTile = EditingTile(index: selectedTile)
                } label: {
                    PixelIcon.plus.view(size: 18, lineWidth: 2.5)
                        .foregroundStyle(Theme.accent2)
                        .frame(width: 48, height: 48)
                        .overlay(Rectangle().strokeBorder(Theme.accent2, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(scene.tiles.count >= TileScene.maxTiles)
                .accessibilityLabel("New tile")
            }
            .padding(.vertical, 2)
        }
        toolRow(SceneTool.tileTools)
        Button { editingTile = EditingTile(index: selectedTile) } label: {
            Text("Edit tile").font(AppFont.pixel(13)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .disabled(!scene.tiles.indices.contains(selectedTile))
        sizeControls
    }

    private func toolRow(_ tools: [SceneTool]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: tools.count), spacing: 6) {
            ForEach(tools) { t in
                let on = tool == t
                let pro = t == .enemy && !access.allowsPlaygroundExtras
                Button { tool = t } label: {
                    Text(t.title)
                        .font(AppFont.pixel(11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .topTrailing) { if pro { ProBadge().scaleEffect(0.7).offset(x: 4, y: -4) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(active: on))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// How long and tall the scene is. Free scenes go up to 24 × 12; Pro ones can be much longer.
    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Scene size")
            stepper("Tiles across", value: scene.columns, step: 4, range: 8...TileScene.proMaxColumns, freeLimit: TileScene.freeColumns) {
                scene.resize(columns: $0, rows: scene.rows)
            }
            stepper("Tiles down", value: scene.rows, step: 2, range: 6...TileScene.proMaxRows, freeLimit: TileScene.freeRows) {
                scene.resize(columns: scene.columns, rows: $0)
            }
        }
    }

    private func stepper(_ title: LocalizedStringKey, value: Int, step: Int, range: ClosedRange<Int>, freeLimit: Int,
                         set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Button { set(max(range.lowerBound, value - step)); offset = clamped(offset, in: canvasSize) } label: {
                Text(verbatim: "−").font(AppFont.pixel(18)).frame(width: 40, height: 40)
            }
            .buttonStyle(TileButtonStyle())
            .disabled(value <= range.lowerBound)
            Text(verbatim: "\(value)").font(AppFont.pixel(14)).foregroundStyle(Theme.accent2).frame(width: 44, height: 40).background(Theme.ink)
            Button {
                let next = min(range.upperBound, value + step)
                if next > freeLimit && !access.allowsPlaygroundExtras { upgrade = .playground } else { set(next) }
            } label: {
                Text(verbatim: "+").font(AppFont.pixel(18)).frame(width: 40, height: 40)
            }
            .buttonStyle(TileButtonStyle())
            .disabled(value >= range.upperBound)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var levelPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Hero · one of your sprites")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    heroTile(nil)
                    ForEach(sprites.projects.filter { !$0.isBlank && ($0.visibleContentBounds.map { max($0.width, $0.height) <= 48 } ?? false) }.prefix(30)) { p in
                        heroTile(p)
                    }
                }
                .padding(.vertical, 2)
            }
            Text("Small sprites make the best heroes. An animated one runs with its own frames.")
                .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Put in the level")
            toolRow(SceneTool.levelTools)
            Text(levelHint).font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
        Toggle(isOn: Binding(get: { scene.sound }, set: { on in
            if on && !access.allowsPlaygroundExtras { upgrade = .playground } else { scene.sound = on }
        })) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound").font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                    Text("A chiptune loop, and blips for jumps and coins")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
                if !access.allowsPlaygroundExtras { ProBadge() }
            }
        }
        .tint(Theme.accent)
        HStack(spacing: 8) {
            Button { sharing = true } label: {
                HStack(spacing: 8) {
                    PixelIcon.share.view(size: 16)
                    Text("Share level").font(AppFont.pixel(12))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            Button { playing = true } label: {
                HStack(spacing: 8) {
                    PixelIcon.play.view(size: 16, lineWidth: 2.5)
                    Text("Play").font(AppFont.pixel(15))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
        }
    }

    private var levelHint: LocalizedStringKey {
        switch tool {
        case .start: "Tap where the hero begins."
        case .coin: "Tap to drop a coin; tap it again to take it away. Collect them all to win."
        case .enemy: "Ghosts walk back and forth on the ground. Jump on one to beat it."
        case .goal: "Tap to plant the flag. With a flag, you win by reaching it after collecting every coin."
        default: "Drag to look around the level."
        }
    }

    private func heroTile(_ project: SpriteProject?) -> some View {
        let on = project.map { $0.id == scene.heroID } ?? scene.heroFrames.isEmpty
        let frame: PixelGrid? = project.map { $0.frames[0].grid } ?? PlayArt.frames("slime").first
        return Button {
            if let project {
                scene.setHero(project)
            } else {
                scene.heroID = nil
                scene.heroName = nil
                scene.heroFrames = []
            }
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let frame { PixelImage(grid: frame, checker: false) } else { Color.clear }
                }
                .frame(width: 52, height: 44)
                (project.map { Text(verbatim: $0.name) } ?? Text("Slime"))
                    .font(AppFont.pixel(9))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .frame(width: 60)
            }
            .padding(4)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 3 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: Tile editor

/// A 16 × 16 pixel editor for one tile, with a 3 × 3 "seamless" preview so edges that should
/// join up can be checked while drawing.
struct TileEditorView: View {
    enum Outcome {
        case save(Tile)
        case delete
    }

    private enum TileTool: String, CaseIterable, Identifiable {
        case pencil, eraser, fill, picker
        var id: String { rawValue }
        var icon: PixelIcon {
            switch self {
            case .pencil: .pencil
            case .eraser: .eraser
            case .fill: .fill
            case .picker: .picker
            }
        }
        var title: LocalizedStringKey {
            switch self {
            case .pencil: "Pencil"
            case .eraser: "Eraser"
            case .fill: "Fill"
            case .picker: "Colour picker"
            }
        }
    }

    @State private var tile: Tile
    let canDelete: Bool
    var onFinish: (Outcome) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tool: TileTool = .pencil
    @State private var color: RGBA = SpriteProject.defaultPalette[2]
    @State private var history: [PixelGrid] = []
    @State private var strokeOpen = false
    @AppStorage("tileSeamlessPreview") private var seamless = true

    init(tile: Tile, canDelete: Bool, onFinish: @escaping (Outcome) -> Void) {
        _tile = State(initialValue: tile)
        self.canDelete = canDelete
        self.onFinish = onFinish
    }

    /// The starter colours, then any others already in the tile.
    private var colors: [RGBA] {
        var out = SpriteProject.defaultPalette
        for c in tile.grid.pixels where !c.isClear && !out.contains(c) { out.append(c) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Edit tile", onClose: { finish() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        editor
                        if seamless {
                            VStack(spacing: 4) {
                                seamlessPreview
                                Text(verbatim: "3 × 3").font(AppFont.pixel(9)).foregroundStyle(Theme.muted)
                            }
                            .frame(width: 96)
                            .accessibilityHidden(true)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(TileTool.allCases) { t in
                            Button { tool = t } label: {
                                t.icon.view(size: 20).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(TileButtonStyle(active: tool == t))
                            .accessibilityLabel(Text(t.title))
                            .accessibilityAddTraits(tool == t ? .isSelected : [])
                        }
                        Button {
                            if let last = history.popLast() { tile.grid = last }
                        } label: {
                            PixelIcon.undo.view(size: 20).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(TileButtonStyle())
                        .disabled(history.isEmpty)
                        .accessibilityLabel("Undo")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 40), spacing: 4)], spacing: 4) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                            let on = c == color && tool != .eraser
                            Rectangle()
                                .fill(c.color)
                                .frame(height: 30)
                                .overlay(Rectangle().strokeBorder(on ? Theme.text : Theme.line, lineWidth: on ? 2 : 1))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    color = c
                                    if tool == .eraser || tool == .picker { tool = .pencil }
                                }
                                .accessibilityElement()
                                .accessibilityLabel(Text("Colour \(c.hexString)"))
                                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    toggle("Solid", detail: "The hero stands on it and can't walk through it", isOn: $tile.solid)
                    toggle("Hurts", detail: "Like water: touching it sends the hero back to the start", isOn: $tile.hazard)
                    toggle("Seamless preview", detail: "Shows the tile repeated 3 × 3 while you edit it", isOn: $seamless)
                    if canDelete {
                        Button(role: .destructive) {
                            onFinish(.delete)
                            dismiss()
                        } label: {
                            Text("Delete this tile").font(AppFont.pixel(12)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(TileButtonStyle(foreground: Theme.accent))
                    }
                }
                .padding(16)
            }
            Button { finish() } label: { PrimaryActionLabel(title: "Done", icon: .check) }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .screenBackground()
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func finish() {
        onFinish(.save(tile))
        dismiss()
    }

    private func toggle(_ title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                Text(detail).font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.accent)
    }

    private var editor: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(TileScene.tileSize)
            ZStack {
                Checkerboard(cell: cell)
                PixelImage(grid: tile.grid, checker: false)
                Canvas { ctx, size in
                    var lines = Path()
                    for i in 0...TileScene.tileSize {
                        let v = CGFloat(i) * cell
                        lines.move(to: CGPoint(x: v, y: 0)); lines.addLine(to: CGPoint(x: v, y: size.height))
                        lines.move(to: CGPoint(x: 0, y: v)); lines.addLine(to: CGPoint(x: size.width, y: v))
                    }
                    ctx.stroke(lines, with: .color(Color.white.opacity(0.1)), lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in draw(at: v.location, cell: cell) }
                    .onEnded { _ in strokeOpen = false }
            )
            .accessibilityLabel(Text(verbatim: tile.name))
            .accessibilityHint("Draw with one finger")
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var seamlessPreview: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        PixelImage(grid: tile.grid, checker: false).frame(width: 32, height: 32)
                    }
                }
            }
        }
        .background(Theme.ink)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }

    private func draw(at location: CGPoint, cell: CGFloat) {
        let p = PixelPoint(x: Int((location.x / cell).rounded(.down)), y: Int((location.y / cell).rounded(.down)))
        guard tile.grid.contains(p) else { return }
        // One undo step per touch.
        if !strokeOpen {
            strokeOpen = true
            history.append(tile.grid)
            if history.count > 40 { history.removeFirst() }
        }
        switch tool {
        case .pencil: tile.grid[p] = color
        case .eraser: tile.grid[p] = .clear
        case .fill: tile.grid.floodFill(from: p, with: color)
        case .picker:
            let c = tile.grid[p]
            if !c.isClear {
                color = c
                tool = .pencil
            }
        }
    }
}
