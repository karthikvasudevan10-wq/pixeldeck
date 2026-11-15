import SwiftUI
import UniformTypeIdentifiers

/// Colours: the sprite's palette, the full colour picker (Apple's, with grid, spectrum and
/// sliders) for the selected swatch, and ready-made palettes to swap in.
struct PaletteSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SwatchEdit?
    @State private var library = PaletteLibrary.forApp()
    /// Naming a palette: nil, or the palette being renamed (an empty id means a new one).
    @State private var naming: CustomPalette?
    @State private var nameText = ""
    @State private var deleting: CustomPalette?
    @State private var importing = false
    @State private var importMessage: String?
    @State private var upgrade: ProFeature?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Colours", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    current
                    mine
                    presets
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .onChange(of: editing) { _, edit in
            guard let edit, model.palette.indices.contains(edit.index) else { return }
            SystemColorPicker.present(
                initial: model.palette[edit.index],
                onChange: { c, final in model.setPaletteColor(c, at: edit.index, commit: final) },
                onDone: {
                    model.setPaletteColor(model.palette[edit.index], at: edit.index)
                    editing = nil
                })
        }
    }

    // MARK: This sprite's palette

    private var current: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This sprite").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(Array(model.palette.enumerated()), id: \.offset) { i, c in
                    let selected = model.selectedPaletteIndex == i && model.tool != .eraser
                    Rectangle()
                        .fill(c.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .overlay {
                            if selected {
                                Rectangle().strokeBorder(Theme.text, lineWidth: 2).padding(-4)
                                Rectangle().strokeBorder(Theme.surface, lineWidth: 2).padding(-2)
                            } else {
                                Rectangle().strokeBorder(Theme.line, lineWidth: 1)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.pickColor(c) }
                        .onLongPressGesture(minimumDuration: 0.4) { editing = SwatchEdit(index: i) }
                        .accessibilityElement()
                        .accessibilityLabel(Text("Colour \(c.hexString)"))
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { model.pickColor(c) }
                        .accessibilityAction(named: Text("Change colour")) { editing = SwatchEdit(index: i) }
                }
            }
            .padding(.horizontal, 4)
            Button {
                let i = model.selectedPaletteIndex ?? 0
                // A colour picked from the art that isn't in the palette goes into the first swatch.
                if model.selectedPaletteIndex == nil { model.setPaletteColor(model.color, at: 0) }
                editing = SwatchEdit(index: i)
            } label: {
                PrimaryActionLabel(title: "Change this colour", icon: .picker, height: 48)
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
            .accessibilityHint("Opens the colour picker with a grid, spectrum and sliders for the selected swatch")
            Text("Tap a swatch to draw with it. Long-press any swatch to change it with the colour picker, then save the set below.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: My palettes

    private var mine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My palettes").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            Button {
                nameText = ""
                naming = CustomPalette(id: UUID(), name: "", colors: model.palette)
            } label: {
                HStack(spacing: 10) {
                    PixelIcon.plus.view(size: 16, lineWidth: 3)
                    Text("Save this sprite's colours as a palette").font(AppFont.body(14, .bold, relativeTo: .body))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.accent2)
                .padding(12)
                .overlay(Rectangle().strokeBorder(Theme.accent2, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(library.isFull)
            Button {
                if model.access.allowsPaletteImport { importing = true } else { upgrade = .paletteImport }
            } label: {
                HStack(spacing: 10) {
                    PixelIcon.download.view(size: 16)
                    Text("Import a palette file").font(AppFont.body(14, .bold, relativeTo: .body))
                    Spacer(minLength: 0)
                    if !model.access.allowsPaletteImport { ProBadge() }
                }
                .foregroundStyle(Theme.text)
                .padding(12)
                .background(Theme.surface)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(library.isFull)
            .accessibilityHint("From Lospec or other apps: .hex, .gpl, .txt or a palette image")
            if let importMessage {
                Text(verbatim: importMessage).font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.accent2)
            }
            ForEach(library.palettes) { saved in
                paletteRow(Text(verbatim: saved.name), colors: saved.colors)
                    .contextMenu {
                        Button {
                            nameText = saved.name
                            naming = saved
                        } label: { Label("Rename", systemImage: "pencil") }
                        Button { library.update(saved.id, colors: model.palette) } label: {
                            Label("Replace with this sprite's colours", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) { deleting = saved } label: { Label("Delete", systemImage: "trash") }
                    }
            }
            if !library.palettes.isEmpty {
                Text("Long-press a saved palette to rename, update or delete it.")
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
        }
        .alert(naming.map { library.palettes.contains($0) } == true ? "Rename palette" : "Save palette",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameText)
            Button("Save") {
                guard let p = naming else { return }
                if library.palettes.contains(where: { $0.id == p.id }) { library.rename(p.id, to: nameText) }
                else { library.add(name: nameText, colors: p.colors) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: PaletteFiles.types, allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importMessage = PaletteFiles.importFile(url, into: library)
        }
        .proUpgradeSheet($upgrade)
        .confirmationDialog("Delete this palette?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let d = deleting { library.delete(d.id) } }
        } message: {
            Text("Sprites keep their colours; only the saved palette is removed.")
        }
    }

    /// A palette you can tap to use: its name and a strip of its colours.
    private func paletteRow(_ title: Text, colors: [RGBA]) -> some View {
        let inUse = colors == model.palette
        return Button { model.applyPalette(colors) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    title
                        .font(AppFont.body(15, .bold, relativeTo: .body))
                        .foregroundStyle(Theme.cream)
                    Spacer()
                    if inUse {
                        PixelIcon.check.view(size: 18).foregroundStyle(Theme.accent)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                        Rectangle().fill(c.color).frame(maxWidth: .infinity).frame(height: 22)
                    }
                }
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            }
            .padding(10)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(inUse ? Theme.accent : Theme.line, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(inUse ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Use this palette for this sprite")
    }

    // MARK: Ready-made palettes

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Palettes").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            ForEach(PalettePreset.allCases) { preset in
                paletteRow(Text(preset.title), colors: preset.colors)
            }
            Text("A palette changes the swatches, not colours already in your art.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
    }
}

extension PaletteLibrary {
    /// Saved palettes live beside the sprites: in iCloud with sync on (so they follow the user to
    /// their other devices), otherwise in Application Support on the device.
    @MainActor static func forApp() -> PaletteLibrary {
        let base = ImageStore.root
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let library = PaletteLibrary(url: base.appendingPathComponent("Palettes", isDirectory: true)
            .appendingPathComponent("palettes.json"))
        library.writeFile = CloudFiles.write
        return library
    }
}

/// Opening palette files picked in the Files app.
enum PaletteFiles {
    static var types: [UTType] {
        var t: [UTType] = [.plainText, .png, .image]
        for ext in ["hex", "gpl", "pal"] { if let u = UTType(filenameExtension: ext) { t.append(u) } }
        return t
    }

    /// Imports `url` into the library. Returns a message saying what happened.
    @MainActor static func importFile(_ url: URL, into library: PaletteLibrary) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            return String(localized: "Couldn't open that file.")
        }
        let baseName = url.deletingPathExtension().lastPathComponent
        var name = baseName
        var colors: [RGBA] = []
        if let image = UIImage(data: data)?.cgImage {
            colors = imageColors(image)
        } else if let parsed = PaletteImport.parse(data, fileName: url.lastPathComponent) {
            name = parsed.name ?? baseName
            colors = parsed.colors
        }
        let sets = PaletteImport.sets(name: name, colors: colors)
        guard !sets.isEmpty else {
            return String(localized: "No colours found. Try a .hex, .gpl or .txt palette, or a palette image.")
        }
        var added = 0
        for set in sets.reversed() where !library.isFull {        // reversed: the first set ends up on top
            if library.add(name: set.name, colors: set.colors) != nil { added += 1 }
        }
        return String(localized: "Added \(added) palettes from \(name).", comment: "Palette import result; plural; the second placeholder is the file's name")
    }

    /// The distinct opaque colours of a palette image, in reading order (left to right, top down).
    static func imageColors(_ image: CGImage) -> [RGBA] {
        let w = image.width, h = image.height
        guard w * h <= 4_000_000 else { return [] }               // a palette, not a photo
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return [] }
        var out: [RGBA] = []
        var seen = Set<RGBA>()
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 200 {
            let c = RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2])
            if seen.insert(c).inserted {
                out.append(c)
                if out.count >= PaletteImport.maxColors { break }
            }
        }
        return out
    }
}
