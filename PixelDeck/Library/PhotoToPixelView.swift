import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Photo to pixel art (Pro to keep the result; anyone can try it). Two steps: frame the part of
/// the photo you want, then choose the size, colours and tidy-up, and open it in the Studio as a
/// sprite with the art on its own "Photo" layer.
struct PhotoToPixelView: View {
    /// A photo to start with (dragged in from Finder on the Mac, for example).
    var initialPhoto: UIImage? = nil
    /// Called with the finished sprite, to save and open.
    var onOpen: (SpriteProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @State private var photo: UIImage?
    @State private var item: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var step = 1
    // Framing: zoom and offset of the photo inside the square.
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize = .zero
    @State private var cropSide: CGFloat = 300
    // The framed part, and its pixels for the converter.
    @State private var cropped: UIImage?
    @State private var bytes: [UInt8] = []
    @State private var bytesSide = 0
    @State private var options = PhotoOptions()
    @State private var result: PixelGrid?
    @State private var resultColors: [RGBA] = []
    @State private var upgrade: ProFeature?

    /// The framed part is rendered at this size before converting: plenty for a 96-pixel result.
    private static let workingSide = 384

    var body: some View {
        VStack(spacing: 0) {
            header
            if step == 1 { choose } else { adjust }
        }
        .screenBackground()
        .onAppear { if photo == nil { photo = initialPhoto } }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    use(image)
                }
            }
        }
        .onChange(of: options) { _, _ in convert() }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                showingCamera = false
                if let image { use(image) }
            }
            .ignoresSafeArea()
        }
        .proUpgradeSheet($upgrade)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                if step == 2 { step = 1 } else { dismiss() }
            } label: {
                PixelIcon.back.view(size: 20, lineWidth: 2.5).frame(width: 44, height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo to pixel art").font(AppFont.pixel(18)).foregroundStyle(Theme.cream).lineLimit(1).minimumScaleFactor(0.7)
                (step == 1 ? Text("Step 1 of 2 · choose the part you want") : Text("Step 2 of 2 · make it yours"))
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            if !purchases.access.allowsPhotoToPixel { ProBadge() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: Step 1 — choose

    private var choose: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    Checkerboard(cell: 16)
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                            .scaleEffect(zoom)
                            .offset(offset)
                            .accessibilityLabel("Your photo")
                            .accessibilityHint("Pinch and drag to frame the part you want")
                    } else {
                        VStack(spacing: 10) {
                            PixelIcon.picker.view(size: 34).foregroundStyle(Theme.accent2)
                            Text("Choose a photo to begin").font(AppFont.pixel(13)).foregroundStyle(Theme.cream)
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipped()
                .contentShape(Rectangle())
                .gesture(framing(side: side))
                .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { cropSide = side }
                .onChange(of: side) { _, s in cropSide = s }
            }
            .padding(.horizontal, 16)

            Text("Pinch and drag to frame it. Square works best; small, simple subjects make the clearest pixel art.")
                .font(AppFont.body(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: {
                        Text("Take a photo").font(AppFont.pixel(12)).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle(fill: Theme.surface))
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                }
                PhotosPicker(selection: $item, matching: .images) {
                    (photo == nil ? Text("Choose a photo") : Text("Other photo"))
                        .font(AppFont.pixel(12))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.surface)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            Button(action: next) {
                PrimaryActionLabel(title: "Next", icon: .arrowRight)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(photo == nil)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    /// Pinch to zoom, drag to move; the photo always covers the square.
    private func framing(side: CGFloat) -> some Gesture {
        let drag = DragGesture()
            .onChanged { v in
                offset = clamped(CGSize(width: offsetStart.width + v.translation.width, height: offsetStart.height + v.translation.height), side: side)
            }
            .onEnded { _ in offsetStart = offset }
        let pinch = MagnifyGesture()
            .onChanged { v in
                zoom = min(8, max(1, zoomStart * v.magnification))
                offset = clamped(offset, side: side)
            }
            .onEnded { _ in
                zoomStart = zoom
                offsetStart = offset
            }
        return drag.simultaneously(with: pinch)
    }

    private func clamped(_ o: CGSize, side: CGFloat) -> CGSize {
        guard let photo, photo.size.width > 0, photo.size.height > 0 else { return .zero }
        let fill = side / min(photo.size.width, photo.size.height) * zoom
        let maxX = max(0, (photo.size.width * fill - side) / 2), maxY = max(0, (photo.size.height * fill - side) / 2)
        return CGSize(width: min(maxX, max(-maxX, o.width)), height: min(maxY, max(-maxY, o.height)))
    }

    private func use(_ image: UIImage) {
        photo = image
        zoom = 1
        zoomStart = 1
        offset = .zero
        offsetStart = .zero
        step = 1
    }

    /// Cuts out the framed square and moves on to step 2.
    private func next() {
        guard let photo, photo.size.width > 0, photo.size.height > 0, cropSide > 0 else { return }
        // Screen points per photo point, and so how much of the photo the square shows.
        let fill = cropSide / min(photo.size.width, photo.size.height) * zoom
        let visible = cropSide / fill
        let cx = photo.size.width / 2 - offset.width / fill, cy = photo.size.height / 2 - offset.height / fill
        let out = CGFloat(Self.workingSide)
        let k = out / visible
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            photo.draw(in: CGRect(x: -(cx - visible / 2) * k, y: -(cy - visible / 2) * k,
                                  width: photo.size.width * k, height: photo.size.height * k))
        }
        guard let px = PhotoPixels.rgba(from: square, maxSide: Self.workingSide), px.width == px.height else { return }
        cropped = square
        bytes = px.bytes
        bytesSide = px.width
        convert()
        step = 2
    }

    // MARK: Step 2 — adjust

    private func convert() {
        guard bytesSide > 0 else { return }
        let out = PhotoPixelizer.convert(rgba: bytes, width: bytesSide, height: bytesSide, options: options,
                                         palette: SpriteProject.defaultPalette)
        result = out?.grid
        resultColors = out?.colors ?? []
    }

    private var adjust: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        pane(Text("Photo")) {
                            if let cropped { Image(uiImage: cropped).resizable().scaledToFit() }
                        }
                        pane(Text(verbatim: "\(result?.width ?? 0) × \(result?.height ?? 0)")) {
                            if let result { PixelImage(grid: result, checker: false) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Size")
                        HStack(spacing: 6) {
                            ForEach(PhotoOptions.sizes, id: \.self) { s in
                                let on = options.size == s
                                Button { options.size = s } label: {
                                    Text(verbatim: "\(s)").font(AppFont.pixel(15)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(TileButtonStyle(active: on, fill: Theme.surface))
                                .accessibilityLabel(Text("\(s) by \(s) pixels"))
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Colours")
                        ChoiceRow(options: PhotoOptions.Colors.allCases, selection: $options.colors) { Text($0.title) }
                        if options.colors == .own {
                            HStack {
                                Text("How many colours").font(AppFont.body(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.text)
                                Spacer()
                                Text(verbatim: "\(options.colorCount)").font(AppFont.pixel(13)).foregroundStyle(Theme.accent2)
                            }
                            Slider(value: Binding(get: { Double(options.colorCount) }, set: { options.colorCount = Int($0) }),
                                   in: Double(PhotoOptions.colorCountRange.lowerBound)...Double(PhotoOptions.colorCountRange.upperBound), step: 1)
                                .tint(Theme.accent)
                                .accessibilityLabel("How many colours")
                        } else if options.colors == .retro {
                            ChoiceRow(options: RetroMode.allCases, selection: $options.retro, columns: 2) { Text($0.title) }
                        } else {
                            Text("Uses the ten starter colours. You can swap the palette in the Studio.")
                                .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        }
                    }

                    VStack(spacing: 8) {
                        toggle("Clean up stray pixels", detail: nil, isOn: $options.cleanUp)
                        toggle("Dither", detail: "Checkerboard blends between colours", isOn: $options.dither)
                        toggle("Add an outline", detail: nil, isOn: $options.outline)
                    }
                }
                .padding(16)
            }
            Button(action: open) {
                HStack(spacing: 10) {
                    PixelIcon.create.view(size: 20, lineWidth: 2.5)
                    Text("Open in the Studio").font(AppFont.pixel(17))
                    if !purchases.access.allowsPhotoToPixel { ProBadge() }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(result == nil)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func pane<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Theme.surface
                content()
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            title.font(AppFont.pixel(10)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggle(_ title: LocalizedStringKey, detail: LocalizedStringKey?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                if let detail { Text(detail).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }

    private func open() {
        guard let result else { return }
        guard purchases.access.allowsPhotoToPixel else {
            upgrade = .photoToPixel
            return
        }
        let project = PhotoPixels.project(from: result, colors: resultColors,
                                          name: String(localized: "Photo", comment: "Default name of a sprite made from a photo"),
                                          layerName: String(localized: "Photo", comment: "Name of the layer holding art made from a photo"))
        onOpen(project)
    }
}

extension PhotoPixels {
    /// A one-frame sprite holding `grid`, centred on the canvas, on a layer called `layerName`.
    /// Its swatches are spread over the art's colours, and the rest become extra colours.
    static func project(from grid: PixelGrid, colors: [RGBA], name: String, layerName: String) -> SpriteProject {
        let bounds = PixelRect(x: -grid.width / 2, y: -grid.height / 2, width: grid.width, height: grid.height)
        var p = SpriteProject(name: name, bounds: bounds, frames: [grid], fps: 8)
        p.layers[0].name = layerName
        if !colors.isEmpty {
            let swatches = tenSwatches(from: colors)
            p.palette = swatches
            p.extraColors = Array(colors.filter { !swatches.contains($0) }.prefix(SpriteProject.maxExtraColors))
        }
        return p
    }
}

/// The system camera, for "Take a photo".
struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// "New canvas": what to start from.
struct NewCanvasSheet: View {
    var onBlank: () -> Void
    var onPhoto: () -> Void
    /// More ways to start (retro modes, tiles, a Playground level), added by the caller.
    var extras: [NewCanvasOption] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New canvas", onClose: { dismiss() })
            ScrollView {
                VStack(spacing: 8) {
                    row(NewCanvasOption(id: "blank", icon: .create, title: "Blank", detail: "Infinite canvas, grows as you draw", action: onBlank))
                    row(NewCanvasOption(id: "photo", icon: .picker, title: "From a photo", detail: "Turn a photo into pixel art",
                                        pro: !purchases.access.allowsPhotoToPixel, action: onPhoto))
                    ForEach(extras) { row($0) }
                    Text("Or swipe right anywhere in the Studio for a blank canvas.")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
    }

    private func row(_ o: NewCanvasOption) -> some View {
        Button(action: o.action) {
            HStack(spacing: 14) {
                o.icon.view(size: 22)
                    .foregroundStyle(Theme.accent2)
                    .frame(width: 44, height: 44)
                    .background(Theme.tool)
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.title).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                    Text(o.detail).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if o.pro { ProBadge() }
            }
            .padding(12)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// One way to start a new canvas.
struct NewCanvasOption: Identifiable {
    let id: String
    var icon: PixelIcon
    var title: LocalizedStringKey
    var detail: LocalizedStringKey
    var pro = false
    var action: () -> Void
}

/// Presents the New canvas chooser and what it leads to. One sheet closes before the next opens.
struct NewCanvasFlow: ViewModifier {
    @Binding var showingChooser: Bool
    @Binding var showingPhoto: Bool
    var onBlank: () -> Void
    var onOpen: (SpriteProject) -> Void
    /// A picture dragged in (from Finder on the Mac, or another app on iPad).
    @State private var dropped: UIImage?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingChooser) {
                NewCanvasSheet(onBlank: { close { onBlank() } },
                               onPhoto: { close { showingPhoto = true } })
            }
            .fullScreenCover(isPresented: $showingPhoto, onDismiss: { dropped = nil }) {
                PhotoToPixelView(initialPhoto: dropped) { project in
                    showingPhoto = false
                    after { onOpen(project) }
                }
            }
            // Drop a picture on the gallery to turn it into pixel art.
            .onDrop(of: [UTType.image], isTargeted: nil) { providers in
                guard !showingPhoto, let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) }) else { return false }
                _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage else { return }
                    Task { @MainActor in
                        dropped = image
                        showingPhoto = true
                    }
                }
                return true
            }
    }

    private func close(then next: @escaping () -> Void) {
        showingChooser = false
        after(next)
    }

    /// After the sheet has gone, so the next presentation (or navigation push) isn't lost.
    private func after(_ next: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            next()
        }
    }
}
