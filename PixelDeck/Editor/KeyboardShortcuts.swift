import SwiftUI

/// Hardware keyboard shortcuts for the Studio (iPad with a Magic Keyboard, or any Bluetooth
/// keyboard). Hold ⌘ to see the ⌘ ones listed. Single-letter keys follow common pixel-art and
/// drawing-app conventions.
struct KeyboardShortcuts: View {
    let model: EditorModel
    var canvas: (FitCommand.Action) -> Void
    var onExport: () -> Void
    var onNewCanvas: () -> Void
    var onLayers: () -> Void

    var body: some View {
        ZStack {
            // Edit
            key("Undo", "z", .command) { model.undo() }
            key("Redo", "z", [.command, .shift]) { model.redo() }

            // Tools
            key("Pencil", "b") { model.tool = .pencil }
            key("Eraser", "e") { model.tool = .eraser }
            key("Toggle eraser", "x") { model.toggleEraser() }
            key("Fill", "g") { model.tool = .fill }
            key("Colour picker", "i") { model.tool = .eyedropper }
            key("Shapes", "u") { model.tool = .shape }
            key("Select", "m") { model.tool = .select }
            key("Mirror", "y") { model.mirror.toggle() }
            key("Onion skin", "o") { model.onionSkinEnabled.toggle() }
            key("Pixel grid", "'", .command) { model.showGrid.toggle() }

            // Palette: 1–9 and 0 pick the ten swatches.
            ForEach(0..<10, id: \.self) { i in
                key("Colour \(i + 1)", KeyEquivalent(Character(String((i + 1) % 10)))) {
                    if model.palette.indices.contains(i) { model.pickColor(model.palette[i]) }
                }
            }

            // Frames
            key("Previous frame", .leftArrow) { model.stepFrame(-1) }
            key("Next frame", .rightArrow) { model.stepFrame(1) }
            key("New frame", "n") { model.addKeyframe() }
            key("Duplicate frame", "d", .command) { model.duplicateFrame(at: model.currentIndex) }
            key("Copy frame", "c", [.command, .shift]) { model.copyFrameToClipboard(at: model.currentIndex) }
            key("Paste over frame", "v", [.command, .shift]) { model.pasteClipboard(at: model.currentIndex, asNewFrame: false) }
            key("Paste as new frame", "v", [.command, .option]) { model.pasteClipboard(at: model.currentIndex, asNewFrame: true) }
            key("Play / pause", .space) { model.isPlaying.toggle() }

            // View
            key("Zoom in", "=", .command) { canvas(.zoomIn) }
            key("Zoom out", "-", .command) { canvas(.zoomOut) }
            key("Fit art", "0", .command) { canvas(.fit) }

            // Sprite
            key("New canvas", "n", .command) { onNewCanvas() }
            key("Layers", "l", .command) { onLayers() }
            key("Export", "e", .command) { onExport() }
            key("Deselect", .escape) { model.commitSelection() }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func key(_ title: LocalizedStringKey, _ k: KeyEquivalent, _ modifiers: EventModifiers = [],
                     action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(k, modifiers: modifiers)
    }
}
