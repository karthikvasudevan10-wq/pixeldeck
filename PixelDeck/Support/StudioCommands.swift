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

/// The Mac menu bar: File, Edit, Sprite, Frame, Layer, Select and View, with every shortcut.
/// (On iPhone and iPad the same shortcuts come from `KeyboardShortcuts`.)
struct StudioCommands: Commands {
    @FocusedValue(\.studio) private var studio

    private var model: EditorModel? { studio?.model }

    /// Runs `body` on the front Studio's model, if there is one.
    private func edit(_ body: (EditorModel) -> Void) {
        if let model { body(model) }
    }

    var body: some Commands {
        // File
        CommandGroup(replacing: .newItem) {
            Button("New Canvas") { studio?.newCanvas() }
                .keyboardShortcut("n", modifiers: .command)
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
            Button("Toggle Eraser") { model?.toggleEraser() }.keyboardShortcut("x", modifiers: [])
            Button("Fill") { model?.tool = .fill }.keyboardShortcut("g", modifiers: [])
            Button("Colour Picker") { model?.tool = .eyedropper }.keyboardShortcut("i", modifiers: [])
            Button("Shapes") { model?.tool = .shape }.keyboardShortcut("u", modifiers: [])
            Button("Select") { model?.tool = .select }.keyboardShortcut("m", modifiers: [])
            Divider()
            Button("Mirror") { model?.mirror.toggle() }.keyboardShortcut("y", modifiers: [])
            Button("Smaller Brush") { model?.brushSize -= 1 }.keyboardShortcut("[", modifiers: [])
            Button("Bigger Brush") { model?.brushSize += 1 }.keyboardShortcut("]", modifiers: [])
            Button("Pixel-perfect Strokes") { model?.pixelPerfect.toggle() }.keyboardShortcut("p", modifiers: [])
            Button("Shading Assistant") {
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
            Button("Colours and Palettes…") { studio?.palettes() }.keyboardShortcut("k", modifiers: .command)
            Button("Adjust Colours…") { studio?.panels.adjust = true }.keyboardShortcut("u", modifiers: .command)
            Button("Tracing Image…") { studio?.trace() }
            Button("Timelapse") { studio?.timelapse() }
        }

        CommandMenu("Frame") {
            Button("New Frame") { model?.addKeyframe() }.keyboardShortcut("n", modifiers: [])
            Button("Duplicate Frame") { edit { $0.duplicateFrame(at: $0.currentIndex) } }
                .keyboardShortcut("d", modifiers: .command)
            Button("Copy Frame") { edit { $0.copyFrameToClipboard(at: $0.currentIndex) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Paste Over Frame") { edit { _ = $0.pasteClipboard(at: $0.currentIndex, asNewFrame: false) } }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Paste as New Frame") { edit { _ = $0.pasteClipboard(at: $0.currentIndex, asNewFrame: true) } }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Divider()
            Button("Previous Frame") { model?.stepFrame(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Frame") { model?.stepFrame(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Play / Pause") { model?.isPlaying.toggle() }.keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Animate with a Preset…") { studio?.panels.presets = true }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Hold This Frame Longer") {
                edit { $0.setHold($0.project.frames[$0.currentIndex].hold + 1, at: $0.currentIndex) }
            }
            .keyboardShortcut("]", modifiers: .command)
            Button("Hold This Frame Shorter") {
                edit { $0.setHold($0.project.frames[$0.currentIndex].hold - 1, at: $0.currentIndex) }
            }
            .keyboardShortcut("[", modifiers: .command)
            Button("Onion Skin Settings…") { studio?.panels.onionTiming = true }
                .keyboardShortcut("o", modifiers: .option)
            Menu("Flip and Rotate") {
                Button("Flip Left to Right") { model?.transform(.flipHorizontal, allFrames: false) }
                Button("Flip Upside Down") { model?.transform(.flipVertical, allFrames: false) }
                Button("Rotate Right") { model?.transform(.rotateClockwise, allFrames: false) }
                Button("Rotate Left") { model?.transform(.rotateCounterClockwise, allFrames: false) }
            }
            Divider()
            Button("Delete Frame") { edit { $0.deleteFrame(at: $0.currentIndex) } }
                .keyboardShortcut(.delete, modifiers: .command)
        }

        CommandMenu("Layer") {
            Button("Layers…") { studio?.layers() }.keyboardShortcut("l", modifiers: .command)
            Button("New Layer") { model?.addLayer() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Merge Down") { model?.mergeLayerDown() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Layer Above") { edit { $0.selectLayer($0.activeLayer + 1) } }
                .keyboardShortcut("]", modifiers: .option)
            Button("Layer Below") { edit { $0.selectLayer($0.activeLayer - 1) } }
                .keyboardShortcut("[", modifiers: .option)
        }

        CommandMenu("Select") {
            Button("Select All") { model?.selectAll() }.keyboardShortcut("a", modifiers: .command)
            Button("Deselect") { model?.commitSelection() }.keyboardShortcut(.escape, modifiers: [])
            Divider()
            Button("Box") { model?.tool = .select; model?.selectionMode = .box }
            Button("Lasso") { model?.tool = .select; model?.selectionMode = .lasso }
                .keyboardShortcut("l", modifiers: [])
            Button("Magic Wand") { model?.tool = .select; model?.selectionMode = .wand }
                .keyboardShortcut("w", modifiers: [])
            Divider()
            Button("Rotate Selection 90°") { model?.rotateSelection(by: 90) }.keyboardShortcut("r", modifiers: .command)
            Button("Flip Selection Left to Right") { model?.flipSelection(horizontal: true) }
            Button("Flip Selection Upside Down") { model?.flipSelection(horizontal: false) }
            Button("Tween Selection…") { studio?.tween() }.keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Delete Selected Pixels") { model?.deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
        }

        // View
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { studio?.canvas(.zoomIn) }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { studio?.canvas(.zoomOut) }.keyboardShortcut("-", modifiers: .command)
            Button("Fit Art to Window") { studio?.canvas(.fit) }.keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Pixel Grid") { model?.showGrid.toggle() }.keyboardShortcut("'", modifiers: .command)
            Button("Onion Skin") { model?.onionSkinEnabled.toggle() }.keyboardShortcut("o", modifiers: [])
        }
    }
}
