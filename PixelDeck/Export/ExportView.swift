import SwiftUI
import UIKit
import StoreKit

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
                    formatSection
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .screenBackground()
        .overlay(alignment: .top) { if savedToast { toast } }
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
            TweenPreview(frames: source.grids, fps: project.fps)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation preview")
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
                    let on = s == options.scale
                    let locked = s > access.maxExportScale
                    Button {
                        if locked { upgrade = .largeExport } else { options.scale = s }
                    } label: {
                        Text(verbatim: "\(s)×")
                            .font(AppFont.pixel(15))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(on ? Theme.onAccent : Theme.text)
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
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Format")
            ForEach(ExportFormat.allCases) { f in
                let on = f == options.format
                Button {
                    if f.needsPro && !access.allowsAnimatedExport { upgrade = .gifExport } else { options.format = f }
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
                        if f.needsPro && !access.allowsAnimatedExport { ProBadge() }
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

    private var actions: some View {
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
            .disabled(working || feasible.isEmpty)

            Button(action: share) {
                PixelIcon.share.view(size: 20).frame(width: 56, height: 56)
            }
            .buttonStyle(TileButtonStyle(fill: Theme.surface))
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            .disabled(working || feasible.isEmpty)
            .accessibilityLabel("Share")
        }
    }

    private var toast: some View {
        Text("Saved to Photos")
            .font(AppFont.pixel(13))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.accent2)
            .padding(.top, 70)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Actions

    private func chooseStartingFormat() {
        // GIF is the design's default, but it's part of Pro.
        if purchases.entitlementsLoaded, options.format.needsPro, !access.allowsAnimatedExport { options.format = .spriteSheet }
        clampScale()
    }

    private func clampScale() {
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
        let src = source, opts = options
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
        makeFiles { shareItems = ShareItems(urls: $0) }
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
