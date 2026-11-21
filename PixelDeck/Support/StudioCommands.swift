import SwiftUI

/// What the menu bar can do to the Studio in the front window. The Studio publishes this with
/// `focusedSceneValue`, and `StudioCommands` reads it.
struct StudioActions {
    let model: EditorModel
    let panels: StudioPanelState
    var canvas: (FitCommand.Action) -> Void
    var export: () -> Void
    var newCanvas: () -> Void
    var layers: () -> Void
    var palettes: () -> Void
    var trace: () -> Void
    var timelapse: () -> Void
    var rename: () -> Void
    var tween: () -> Void
}

private struct StudioActionsKey: FocusedValueKey {
    typealias Value = StudioActions
}

extension FocusedValues {
    var studio: StudioActions? {
        get { self[StudioActionsKey.self] }
        set { self[StudioActionsKey.self] = newValue }
    }
}

/// The Mac menu bar, as designed: Pixel Deck, File, Edit, Sprite, Frame, Layer, Select, View,
/// Window, Help, with every shortcut. (On iPhone and iPad the same shortcuts come from
/// `KeyboardShortcuts`.)
struct StudioCommands: Commands {
    /// For the things the gallery presents: Settings, the New canvas chooser, Academy, Playground.
    let router: AppRouter
    @FocusedValue(\.studio) private var studio

    private var model: EditorModel? { studio?.model }

    /// Runs `body` on the front Studio's model, if there is one.
    private func edit(_ body: (EditorModel) -> Void) {
        if let model { body(model) }
    }

    var body: some Commands {
        // Pixel Deck › Settings…
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { router.request = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }

        // File
        CommandGroup(replacing: .newItem) {
            Button("New canvas") { studio?.newCanvas() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New from a photo, retro mode, tiles…") { router.request = .newCanvas }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Playground") { router.request = .playground }
            Button("Pixel Academy") { router.request = .academy }
            Divider()
            Button("Export…") { studio?.export() }
                .keyboardShortcut("e", modifiers: .command)
        }

        // Edit
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model?.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { model?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandMenu("Sprite") {
            Button("Rename…") { studio?.rename() }
            Divider()
            Button("Pencil") { model?.tool = .pencil }.keyboardShortcut("b", modifiers: [])
            Button("Eraser") { model?.tool = .eraser }.keyboardShortcut("e", modifiers: [])
            Button("Toggle eraser") { model?.toggleEraser() }.keyboardShortcut("x", modifiers: [])
            Button("Fill") { model?.tool = .fill }.keyboardShortcut("g", modifiers: [])
            Button("Colour picker") { model?.tool = .eyedropper }.keyboardShortcut("i", modifiers: [])
            Button("Shapes") { model?.tool = .shape }.keyboardShortcut("u", modifiers: [])
            Button("Select") { model?.tool = .select }.keyboardShortcut("m", modifiers: [])
            Divider()
            Button("Mirror") { model?.mirror.toggle() }.keyboardShortcut("y", modifiers: [])
            Button("Smaller brush") { model?.brushSize -= 1 }.keyboardShortcut("[", modifiers: [])
            Button("Bigger brush") { model?.brushSize += 1 }.keyboardShortcut("]", modifiers: [])
            Button("Pixel-perfect strokes") { model?.pixelPerfect.toggle() }.keyboardShortcut("p", modifiers: [])
            Button("Shading assistant") {
                guard let model else { return }
                model.tool = .pencil
                model.shadeMode = model.shadeMode == nil ? .shade : nil
            }
            .keyboardShortcut("h", modifiers: [])
            Menu("Swatch") {
                // 1–9 and 0 pick the ten swatches.
                ForEach(0..<10, id: \.self) { i in
                    Button("Colour \(i + 1)") {
                        edit { if $0.palette.indices.contains(i) { $0.pickColor($0.palette[i]) } }
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String((i + 1) % 10))), modifiers: [])
                }
            }
            Divider()
            Button("Colours and palettes…") { studio?.palettes() }.keyboardShortcut("k", modifiers: .command)
            Button("Adjust colours…") { studio?.panels.adjust = true }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Stamps…") { studio?.panels.stamps = true }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Bead or cross-stitch pattern…") { studio?.panels.beads = true }
            Button("Tracing image…") { studio?.trace() }
            Button("Timelapse") { studio?.timelapse() }
        }

        CommandMenu("Frame") {
            Button("New frame") { model?.addKeyframe() }.keyboardShortcut("n", modifiers: [])
            Button("Duplicate frame") { edit { $0.duplicateFrame(at: $0.currentIndex) } }
                .keyboardShortcut("d", modifiers: .command)
            Button("Copy frame") { edit { $0.copyFrameToClipboard(at: $0.currentIndex) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Paste over frame") { edit { _ = $0.pasteClipboard(at: $0.currentIndex, asNewFrame: false) } }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Paste as new frame") { edit { _ = $0.pasteClipboard(at: $0.currentIndex, asNewFrame: true) } }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Divider()
            Button("Previous frame") { model?.stepFrame(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next frame") { model?.stepFrame(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Play / pause") { model?.isPlaying.toggle() }.keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Animate with a preset…") { studio?.panels.presets = true }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Hold this frame longer") {
                edit { $0.setHold($0.project.frames[$0.currentIndex].hold + 1, at: $0.currentIndex) }
            }
            .keyboardShortcut("]", modifiers: .command)
            Button("Hold this frame shorter") {
                edit { $0.setHold($0.project.frames[$0.currentIndex].hold - 1, at: $0.currentIndex) }
            }
            .keyboardShortcut("[", modifiers: .command)
            Button("Onion skin settings…") { studio?.panels.onionTiming = true }
                .keyboardShortcut("o", modifiers: .option)
            Button("Sound on this frame…") { studio?.panels.sound = true }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Menu("Flip and rotate") {
                Button("Flip left to right") { model?.transform(.flipHorizontal, allFrames: false) }
                Button("Flip upside down") { model?.transform(.flipVertical, allFrames: false) }
                Button("Rotate right") { model?.transform(.rotateClockwise, allFrames: false) }
                Button("Rotate left") { model?.transform(.rotateCounterClockwise, allFrames: false) }
            }
            Divider()
            // ⌫ deletes the selected pixels when there's a selection, otherwise the frame.
            Button("Delete frame") {
                edit { if $0.hasSelection { $0.deleteSelection() } else { $0.deleteFrame(at: $0.currentIndex) } }
            }
            .keyboardShortcut(.delete, modifiers: [])
        }

        CommandMenu("Layer") {
            Button("Layers…") { studio?.layers() }.keyboardShortcut("l", modifiers: .command)
            Button("New layer") { model?.addLayer() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Merge down") { model?.mergeLayerDown() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Layer above") { edit { $0.selectLayer($0.activeLayer + 1) } }
                .keyboardShortcut("]", modifiers: .option)
            Button("Layer below") { edit { $0.selectLayer($0.activeLayer - 1) } }
                .keyboardShortcut("[", modifiers: .option)
        }

        CommandMenu("Select") {
            // ⇧⌘A: plain ⌘A stays with Edit › Select All, for text fields.
            Button("Select all pixels") { model?.selectAll() }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Deselect") { model?.commitSelection() }.keyboardShortcut(.escape, modifiers: [])
            Divider()
            Button("Box") { model?.tool = .select; model?.selectionMode = .box }
            Button("Lasso") { model?.tool = .select; model?.selectionMode = .lasso }
                .keyboardShortcut("l", modifiers: [])
            Button("Magic wand") { model?.tool = .select; model?.selectionMode = .wand }
                .keyboardShortcut("w", modifiers: [])
            Divider()
            Button("Rotate selection 90°") { model?.rotateSelection(by: 90) }.keyboardShortcut("r", modifiers: .command)
            Button("Flip selection left to right") { model?.flipSelection(horizontal: true) }
            Button("Flip selection upside down") { model?.flipSelection(horizontal: false) }
            Button("Tween selection…") { studio?.tween() }.keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Delete selected pixels") { model?.deleteSelection() }
        }

        // The standard Format menu (fonts, bigger, smaller) has nothing to act on here, and its
        // shortcuts would take ⌘- and ⌘+ from zooming.
        CommandGroup(replacing: .textFormatting) {}

        // View
        CommandGroup(after: .toolbar) {
            Button("Zoom in") { studio?.canvas(.zoomIn) }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom out") { studio?.canvas(.zoomOut) }.keyboardShortcut("-", modifiers: .command)
            Button("Fit art to window") { studio?.canvas(.fit) }.keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Pixel grid") { model?.showGrid.toggle() }.keyboardShortcut("'", modifiers: .command)
            Button("Onion skin") { model?.onionSkinEnabled.toggle() }.keyboardShortcut("o", modifiers: [])
        }
    }
}
