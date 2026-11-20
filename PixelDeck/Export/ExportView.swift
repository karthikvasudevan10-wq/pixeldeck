import SwiftUI
import UIKit
import StoreKit
import UniformTypeIdentifiers

/// Export: a looping preview, scale chips with the live output size, a format list, then
/// Save (to Photos) or Share (Files, AirDrop, other apps — including the sheet's JSON).
struct ExportView: View {
    let project: SpriteProject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(PurchaseManager.self) private var purchases
    @AppStorage("completedExports") private var completedExports = 0
    @AppStorage("reviewRequestedForVersion") private var reviewRequestedForVersion = ""
    @State private var options = ExportOptions()
    @State private var source: ExportSource
    @State private var upgrade: ProFeature?
    @State private var shareItems: ShareItems?
    @State private var errorMessage: String?
    @State private var working = false
    @State private var savedToast = false
    /// Copy "Made with #PixelDeck" and the link when sharing a video, ready to paste as the caption.
    @AppStorage("shareCaption") private var shareCaption = true
    @State private var captionToast = false

    init(project: SpriteProject) {
        self.project = project
        _source = State(initialValue: ExportSource(project))
    }

    private var access: FeatureAccess { purchases.access }
    private var feasible: [Int] { SpriteExporter.feasibleScales(source, options: options) }

    private var outputText: String {
        let s = SpriteExporter.outputSize(source, options: options)
        return "\(s.width) × \(s.height) px"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    preview
                    Text("\(project.name) · \(source.width)×\(source.height) px · \(source.grids.count) frames · \(project.fps) fps",
                         comment: "Export summary: name, art size, frame count (plural), frame rate")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, -6)
                    if options.format.hasScale { scaleSection }
                    if options.format == .video { videoOptions }
                    if options.format == .video && options.videoShape == .square { videoResolution }
                    formatSection
                    if options.format != .spriteSheet && access.addsWatermark { watermarkNote }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .readableWidth(640)
        .screenBackground()
        .overlay(alignment: .top) { if savedToast { toast } else if captionToast { captionNotice } }
        .task { source.timelapse = TimelapseStore.load(for: project.id).playbackFrames() }
        .onChange(of: options.videoShape) { _, _ in clampScale() }
        .onAppear(perform: chooseStartingFormat)
        // Purchases are checked at launch; don't move a Pro user off GIF before that finishes.
        .onChange(of: purchases.entitlementsLoaded) { _, _ in chooseStartingFormat() }
        .onChange(of: options.format) { _, _ in clampScale() }
        .onChange(of: options.layout) { _, _ in clampScale() }
        .proUpgradeSheet($upgrade)
        .sheet(item: $shareItems) { items in
            ActivityView(items: items.urls) { completed in
                shareItems = nil
                if completed { exportSucceeded() }
            }
                .ignoresSafeArea()
        }
        .alert("Export", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                PixelIcon.back.view(size: 20, lineWidth: 2.5).frame(width: 44, height: 44)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .accessibilityLabel("Back")
            Text("Export").font(AppFont.pixel(22)).foregroundStyle(Theme.cream)
            Spacer()
        }
        .frame(height: 52)
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            Checkerboard(cell: 20)
            TweenPreview(frames: source.playGrids, fps: project.fps, durations: source.playDurations)
                .padding(24)
            Text("Loop preview")
                .font(AppFont.pixel(11))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accent)
                .padding(10)
        }
        .frame(height: 260)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
        .onDrag(dragProvider)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation preview")
        .accessibilityHint("Drag into another app to drop the exported file")
    }

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Scale")
                Spacer()
                Text(verbatim: outputText).font(AppFont.pixel(12)).foregroundStyle(Theme.accent2)
            }
            HStack(spacing: 6) {
                ForEach(SpriteExporter.scales, id: \.self) { s in
                    let on = !options.fourK && s == options.scale
                    let locked = s > access.maxExportScale
                    Button {
                        if locked { upgrade = .largeExport } else { options.scale = s; options.fourK = false }
                    } label: {
                        Text(verbatim: "\(s)×")
                            .font(AppFont.pixel(15))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(on ? Theme.onAccent2 : Theme.text)
                            .background(on ? Theme.accent2 : Theme.surface)
                            .overlay(Rectangle().strokeBorder(on ? Theme.accent2 : Theme.line, lineWidth: 2))
                            .overlay(alignment: .topTrailing) { if locked { ProBadge().padding(3) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!feasible.contains(s))
                    .opacity(feasible.contains(s) ? 1 : 0.35)
                    .accessibilityLabel(locked ? Text("\(s) times, requires Pro") : Text("\(s) times"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                if options.offersFourK { fourKChip }
            }
        }
    }

    /// 4K (Pro): the long side scaled up to about 3840 px.
    private var fourKChip: some View {
        let on = options.fourK
        let locked = !access.allowsFourK
        let possible = SpriteExporter.fourKFeasible(source, options: options)
        return Button {
            if locked { upgrade = .largeExport } else { options.fourK = true }
        } label: {
            Text(verbatim: "4K")
                .font(AppFont.pixel(15))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(on ? Theme.onAccent2 : Theme.text)
                .background(on ? Theme.accent2 : Theme.surface)
                .overlay(Rectangle().strokeBorder(on ? Theme.accent2 : Theme.line, lineWidth: 2))
                .overlay(alignment: .topTrailing) { if locked { ProBadge().padding(3) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!possible)
        .opacity(possible ? 1 : 0.35)
        .accessibilityLabel(locked ? Text("4K, requires Pro") : Text("4K"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Video: 1080 × 1080, or 4K (2160 × 2160).
    private var videoResolution: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Resolution")
                Spacer()
                Text(verbatim: outputText).font(AppFont.pixel(12)).foregroundStyle(Theme.accent2)
            }
            HStack(spacing: 6) {
                Button { options.fourK = false } label: {
                    Text(verbatim: "1080p")
                        .font(AppFont.pixel(15))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(!options.fourK ? Theme.onAccent2 : Theme.text)
                        .background(!options.fourK ? Theme.accent2 : Theme.surface)
                        .overlay(Rectangle().strokeBorder(!options.fourK ? Theme.accent2 : Theme.line, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(!options.fourK ? .isSelected : [])
                fourKChip
            }
        }
    }

    /// Share-ready video: the shape, the end card and the caption.
    private var videoOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Video for")
            HStack(spacing: 6) {
                ForEach(VideoShape.allCases) { shape in
                    let on = options.videoShape == shape
                    let locked = shape == .timelapse && !access.allowsTimelapseVideo
                    let missing = shape == .timelapse && source.timelapse.isEmpty
                    Button {
                        if locked { upgrade = .timing } else { options.videoShape = shape }
                    } label: {
                        Text(shape.title)
                            .font(AppFont.body(14, .medium, relativeTo: .subheadline))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(alignment: .topTrailing) { if locked { ProBadge().padding(3) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle(active: on, fill: Theme.surface))
                    .disabled(missing)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            optionRow(title: "End card", detail: "Finishes on \"Pixel Deck · Available on the App Store\" for 1.5 s",
                      isOn: $options.endCard)
            optionRow(title: "Caption", detail: "Copies \"Made with #PixelDeck\" and the link, ready to paste when you post",
                      isOn: $shareCaption)
        }
    }

    private func optionRow(title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                Text(detail).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }

    private var captionNotice: some View {
        Text("Caption copied. Paste it when you post.")
            .font(AppFont.pixel(12))
            .foregroundStyle(Theme.onAccent2)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.accent2)
            .padding(.top, 70)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Free exports carry the mark; say so, with the way to remove it.
    private var watermarkNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Free exports include a small \"Made with Pixel Deck\" mark below the art. Pro removes it.")
                .font(AppFont.body(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Button("Remove with Pro") { upgrade = .noWatermark }
                .font(AppFont.body(13, .bold, relativeTo: .footnote))
                .foregroundStyle(Theme.accent)
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Format")
            ForEach(ExportFormat.allCases) { f in
                let on = f == options.format
                Button {
                    options.format = f
                } label: {
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(on ? Theme.accent : .clear)
                            .frame(width: 8, height: 8)
                            .frame(width: 18, height: 18)
                            .overlay(Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                            Text(f.detail).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(verbatim: f.fileExtension).font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 60)
                    .background(Theme.surface)
                    .overlay(Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])

                if on && f == .spriteSheet { sheetOptions }
            }
        }
    }

    private var sheetOptions: some View {
        HStack(spacing: 6) {
            ChoiceRow(options: SpriteSheetLayout.allCases, selection: $options.layout) { Text($0.title) }
            Button { options.includeMetadata.toggle() } label: {
                Text(verbatim: "JSON")
                    .font(AppFont.pixel(12))
                    .frame(width: 72, height: 44)
            }
            .buttonStyle(TileButtonStyle(active: options.includeMetadata, fill: Theme.surface))
            .accessibilityLabel("Include JSON frame data")
            .accessibilityAddTraits(options.includeMetadata ? .isSelected : [])
        }
    }

    @ViewBuilder
    private var actions: some View {
        if options.format == .video {
            // Sharing comes first for video: that's where Reels and TikTok are.
            VStack(spacing: 8) {
                Button(action: share) {
                    ZStack {
                        if working {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            HStack(spacing: 10) {
                                PixelIcon.share.view(size: 20, lineWidth: 2.5)
                                Text("Share to Instagram or TikTok").font(AppFont.pixel(14)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(action: save) {
                    HStack(spacing: 10) {
                        PixelIcon.download.view(size: 18)
                        Text("Save video").font(AppFont.pixel(14))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            }
            .disabled(working)
        } else {
            saveAndShare
        }
    }

    private var saveAndShare: some View {
        HStack(spacing: 8) {
            Button(action: save) {
                ZStack {
                    if working {
                        ProgressView().tint(Theme.onAccent)
                    } else {
                        HStack(spacing: 10) {
                            PixelIcon.download.view(size: 20, lineWidth: 2.5)
                            Text(options.format.action).font(AppFont.pixel(17))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(working || (!options.fourK && feasible.isEmpty))

            Button(action: share) {
                PixelIcon.share.view(size: 20).frame(width: 56, height: 56)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            .disabled(working || (!options.fourK && feasible.isEmpty))
            .accessibilityLabel("Share")
        }
    }

    private var toast: some View {
        Text("Saved to Photos")
            .font(AppFont.pixel(13))
            .foregroundStyle(Theme.onAccent2)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.accent2)
            .padding(.top, 70)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Actions

    private func chooseStartingFormat() {
        clampScale()
    }

    private func clampScale() {
        if options.videoShape == .timelapse && (source.timelapse.isEmpty || !access.allowsTimelapseVideo) {
            options.videoShape = .square
        }
        if options.fourK && (!options.offersFourK || !access.allowsFourK || !SpriteExporter.fourKFeasible(source, options: options)) {
            options.fourK = false
        }
        let usable = feasible.filter { $0 <= access.maxExportScale }
        // A long single-row sheet can be too wide at any scale: wrap it into a grid instead.
        if usable.isEmpty, options.format == .spriteSheet, options.layout == .strip {
            options.layout = .grid
            return
        }
        if !usable.contains(options.scale) { options.scale = usable.last ?? 1 }
    }

    private func makeFiles(_ then: @escaping ([URL]) -> Void) {
        working = true
        let src = source
        var opts = options
        opts.watermark = access.addsWatermark && opts.format != .spriteSheet
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try SpriteExporter.export(src, options: opts) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success(let urls): then(urls)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Dragging the preview into another app drops the file in the selected format and scale,
    /// made when the other app asks for it. (PNG frames drop as a single sprite sheet.)
    private func dragProvider() -> NSItemProvider {
        var opts = options
        if opts.format == .frames { opts.format = .spriteSheet }
        opts.watermark = access.addsWatermark && opts.format != .spriteSheet
        let src = source
        let type: UTType = switch opts.format {
        case .gif: .gif
        case .video: .mpeg4Movie
        case .spriteSheet, .frames: .png
        }
        let provider = NSItemProvider()
        provider.suggestedName = project.name
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { done in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let urls = try SpriteExporter.export(src, options: opts)
                    done(urls.first, false, nil)
                } catch {
                    done(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private func save() {
        makeFiles { urls in
            Task { @MainActor in
                do {
                    try await PhotoSaver.save(urls)
                    withAnimation { savedToast = true }
                    exportSucceeded()
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    withAnimation { savedToast = false }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func share() {
        let caption = options.format == .video && shareCaption
        makeFiles { urls in
            if caption {
                // Instagram and TikTok don't accept a caption from the share sheet, so it waits
                // on the clipboard.
                UIPasteboard.general.string = String(localized: "Made with #PixelDeck \(AppConfig.shareURL.absoluteString)",
                                                     comment: "Caption copied when sharing a video; the placeholder is a web link")
                withAnimation { captionToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { captionToast = false } }
            }
            shareItems = ShareItems(urls: urls)
        }
    }

    /// Ask for a rating only after a few completed exports, at most once per app version. The
    /// system decides whether to show it (and limits it to 3 times a year).
    private func exportSucceeded() {
        completedExports += 1
        guard completedExports >= 3, reviewRequestedForVersion != AppConfig.version else { return }
        reviewRequestedForVersion = AppConfig.version
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { requestReview() }
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
