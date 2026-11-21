import PhotosUI
import SwiftUI
import UIKit

/// The tabs of the Colours panel.
enum ColourTab: String, CaseIterable, Identifiable {
    case palette, ramps, photo
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .palette: "Palette"
        case .ramps: "Ramps"
        case .photo: "From a photo"
        }
    }
}

/// The sprite's colours beyond the ten swatches. Tap to draw with one; long-press to remove it.
struct MoreColorsSection: View {
    let model: EditorModel

    var body: some View {
        if !model.project.extraColors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("More colours").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 40), spacing: 4)], spacing: 4) {
                    ForEach(Array(model.project.extraColors.enumerated()), id: \.offset) { _, c in
                        let selected = c == model.color && model.tool != .eraser
                        Rectangle()
                            .fill(c.color)
                            .frame(height: 30)
                            .overlay(Rectangle().strokeBorder(selected ? Theme.text : Theme.line, lineWidth: selected ? 2 : 1))
                            .contentShape(Rectangle())
                            .onTapGesture { model.pickColor(c) }
                            .contextMenu {
                                Button(role: .destructive) { model.removeExtraColor(c) } label: {
                                    Label("Remove from my colours", systemImage: "trash")
                                }
                            }
                            .accessibilityElement()
                            .accessibilityLabel(Text("Colour \(c.hexString)"))
                            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { model.pickColor(c) }
                    }
                }
                Text("Ramps, photo colours and adjusted colours land here. Long-press one to remove it.")
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// A gentle nudge when a sprite uses a lot of colours: offer to merge the near-duplicates.
struct ColorCountHint: View {
    let model: EditorModel
    @AppStorage("colourHintDismissedFor") private var dismissedFor = ""
    @State private var histogram: [RGBA: Int] = [:]
    @State private var showingPlan = false

    private var plan: [(from: RGBA, to: RGBA)] {
        ColorTools.mergePlan(histogram).map { (from: $0.key, to: $0.value) }.sorted { $0.from.hexString < $1.from.hexString }
    }

    var body: some View {
        let merges = plan
        // A stack, not a Group: an empty Group has nothing for onAppear to attach to.
        return VStack(spacing: 0) {
            if histogram.count > ColorTools.hintThreshold, !merges.isEmpty, dismissedFor != model.project.id.uuidString {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(histogram.count) colours in this sprite", comment: "Colour count hint title; plural")
                        .font(AppFont.body(15, .bold, relativeTo: .body))
                        .foregroundStyle(Theme.cream)
                    Text("Pixel art often reads better with fewer. Merge the ones that look almost the same?")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if showingPlan {
                        // Each near-duplicate and the colour it would become.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(Array(merges.prefix(12).enumerated()), id: \.offset) { _, m in
                                HStack(spacing: 2) {
                                    Rectangle().fill(m.from.color).frame(width: 22, height: 22)
                                    PixelIcon.arrowRight.view(size: 12).foregroundStyle(Theme.muted)
                                    Rectangle().fill(m.to.color).frame(width: 22, height: 22)
                                }
                                .accessibilityHidden(true)
                            }
                        }
                        Button {
                            model.mergeSimilarColors()
                            refresh()
                        } label: {
                            Text("Merge \(merges.count) colours", comment: "Button; plural").font(AppFont.pixel(13))
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PrimaryButtonStyle(depth: 4))
                        Text("One undo step puts them back.")
                            .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    } else {
                        HStack(spacing: 8) {
                            Button { showingPlan = true } label: {
                                Text("Show me").font(AppFont.pixel(12)).padding(.horizontal, 14).frame(height: 40).contentShape(Rectangle())
                            }
                            .buttonStyle(TileButtonStyle(active: true, activeFill: Theme.accent2, activeForeground: Theme.onAccent2))
                            Button { dismissedFor = model.project.id.uuidString } label: {
                                Text("Not now").font(AppFont.pixel(12)).padding(.horizontal, 14).frame(height: 40).contentShape(Rectangle())
                            }
                            .buttonStyle(TileButtonStyle())
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() { histogram = model.colorHistogram }
}

/// Ramps: your colour stepped darker and lighter, the way pixel artists shade.
struct RampPanel: View {
    let model: EditorModel
    @State private var message: String?

    var body: some View {
        let ramp = model.ramp(for: model.color)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("From your colour").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                Text("Shadows lean blue-purple, highlights lean warm")
                    .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 4) {
                ForEach(Array(ramp.enumerated()), id: \.offset) { _, c in
                    let base = c == model.color
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(c.color)
                            .frame(height: 48)
                            .overlay(Rectangle().strokeBorder(base ? Theme.text : Theme.line, lineWidth: base ? 2 : 1))
                        Text(verbatim: String(c.hexString.dropFirst()))
                            .font(AppFont.pixel(8))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Colour \(c.hexString)"))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionLabel(text: "Hue shift")
                    Spacer()
                    Text(verbatim: "+\(Int(model.rampHueShift))°").font(AppFont.pixel(12)).foregroundStyle(Theme.accent2)
                }
                Slider(value: Binding(get: { model.rampHueShift }, set: { model.rampHueShift = $0.rounded() }), in: ColorRamp.hueShiftRange, step: 1)
                    .tint(Theme.accent)
                    .accessibilityLabel("Hue shift")
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Steps")
                HStack(spacing: 6) {
                    ForEach([4, 5, 6, 7], id: \.self) { n in
                        let on = model.rampSteps == n
                        Button { model.rampSteps = n } label: {
                            Text(verbatim: "\(n)").font(AppFont.pixel(15)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(TileButtonStyle(active: on, fill: Theme.surface))
                        .accessibilityLabel(Text("\(n) steps"))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Button {
                let added = model.addRampToPalette(from: model.color)
                message = added > 0
                    ? String(localized: "Added \(added) colours. They're under the palette.", comment: "After adding a ramp; plural")
                    : String(localized: "Those colours are already in this sprite.")
            } label: {
                PrimaryActionLabel(title: "Add ramp to the palette", icon: .plus, height: 48)
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
            if let message {
                Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
            }
            Text("Pick the colour to start from in the Palette tab. The Shade brush uses this ramp too.")
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// A palette pulled from any photo: its ten main colours.
struct PhotoPalettePanel: View {
    let model: EditorModel
    @State private var item: PhotosPickerItem?
    @State private var colors: [RGBA] = []
    @State private var thumbnail: UIImage?
    @State private var message: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a photo you love the colours of: a sunset, a toy, a painting. Pixel Deck finds its ten main colours.")
                .font(AppFont.body(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
            PhotosPicker(selection: $item, matching: .images) {
                HStack(spacing: 10) {
                    PixelIcon.picker.view(size: 16)
                    Text(colors.isEmpty ? "Choose a photo" : "Choose another photo").font(AppFont.body(14, .bold, relativeTo: .body))
                    Spacer(minLength: 0)
                    if loading { ProgressView().tint(Theme.muted) }
                }
                .foregroundStyle(Theme.accent2)
                .padding(12)
                .overlay(Rectangle().strokeBorder(Theme.accent2, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !colors.isEmpty {
                HStack(spacing: 10) {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 64, height: 64).clipped()
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                            Rectangle().fill(c.color).frame(maxWidth: .infinity).frame(height: 64)
                                .onTapGesture { model.pickColor(c) }
                        }
                    }
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityLabel("Colours from the photo")
                }
                Button {
                    model.applyPalette(PhotoPixels.tenSwatches(from: colors))
                    message = String(localized: "This sprite's palette now uses the photo's colours.")
                } label: {
                    PrimaryActionLabel(title: "Use as my palette", icon: .swatches, height: 48)
                }
                .buttonStyle(PrimaryButtonStyle(depth: 4))
                .disabled(model.isPaletteLocked)
                Button {
                    let added = model.addColors(colors)
                    message = added > 0
                        ? String(localized: "Added \(added) colours. They're under the palette.", comment: "After adding a ramp; plural")
                        : String(localized: "Those colours are already in this sprite.")
                } label: {
                    Text("Add to my colours instead").font(AppFont.pixel(12)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            }
            if let message {
                Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
            }
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            loading = true
            message = nil
            Task {
                let data = try? await picked.loadTransferable(type: Data.self)
                let image = data.flatMap { UIImage(data: $0) }
                let found = image.flatMap { PhotoPixels.rgba(from: $0, maxSide: 64) }.map { px in
                    PhotoPixelizer.medianCut(PhotoPixelizer.downsample(px.bytes, px.width, px.height, to: px.width, px.height), count: 10)
                } ?? []
                loading = false
                thumbnail = image
                colors = found
                if found.isEmpty { message = String(localized: "Couldn't read that photo. Try another one.") }
            }
        }
    }
}

/// Getting pixels out of photos.
enum PhotoPixels {
    /// The photo's pixels as RGBA bytes, shrunk so its longest side is at most `maxSide`
    /// (turned the right way up, whatever way the camera was held).
    static func rgba(from image: UIImage, maxSide: Int) -> (bytes: [UInt8], width: Int, height: Int)? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let k = min(1, CGFloat(maxSide) / max(size.width, size.height))
        let w = max(1, Int((size.width * k).rounded())), h = max(1, Int((size.height * k).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard let cg = small.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (bytes, w, h) : nil
    }

    /// Exactly ten swatches from a list of colours (dark to light): spread evenly if there are
    /// more, topped up from the starter palette if there are fewer.
    static func tenSwatches(from colors: [RGBA]) -> [RGBA] {
        let n = SpriteProject.defaultPalette.count
        var unique: [RGBA] = []
        for c in colors where !unique.contains(c) { unique.append(c) }
        if unique.count > n {
            return (0..<n).map { unique[$0 * (unique.count - 1) / (n - 1)] }
        }
        for c in SpriteProject.defaultPalette where unique.count < n && !unique.contains(c) { unique.append(c) }
        while unique.count < n { unique.append(.black) }
        return unique
    }
}
