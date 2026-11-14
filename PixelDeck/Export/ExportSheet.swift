import SwiftUI
import UIKit
import StoreKit

/// Choose a format and size, then hand the files to the share sheet
/// (Save to Files, Photos, AirDrop, Messages…).
struct ExportSheet: View {
    let project: SpriteProject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(PurchaseManager.self) private var purchases
    @AppStorage("completedExports") private var completedExports = 0
    @AppStorage("reviewRequestedForVersion") private var reviewRequestedForVersion = ""
    @State private var upgrade: ProFeature?
    @State private var options = ExportOptions()
    @State private var shareItems: ShareItems?
    @State private var errorMessage: String?
    @State private var working = false

    private var scales: [Int] { SpriteExporter.allowedScales(for: project, options: options) }

    /// Whole sentences with placeholders, so translators can reorder them.
    private var outputDescription: Text {
        let s = options.scale
        let side = project.size * s
        switch options.format {
        case .spriteSheet:
            let size = SpriteSheet.pixelSize(canvas: project.size, frameCount: project.frames.count, scale: s, layout: options.layout)
            return options.includeMetadata
                ? Text("One \(size.width) × \(size.height) PNG plus JSON frame data")
                : Text("One \(size.width) × \(size.height) PNG")
        case .gif:
            return Text("Looping \(side) × \(side) GIF at \(project.fps) fps")
        case .frames:
            return Text("\(project.frames.count) PNG files, each \(side) × \(side)", comment: "Export summary (plural on the first number)")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: formatBinding) {
                        ForEach(ExportFormat.allCases) { format in
                            Group {
                                if format == .gif && !purchases.access.allowsGIF {
                                    Text("\(Text(format.title)) · Pro", comment: "A locked option; the placeholder is the option name")
                                } else {
                                    Text(format.title)
                                }
                            }
                            .tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if options.format == .spriteSheet {
                    Section("Sheet") {
                        Picker("Layout", selection: $options.layout) {
                            ForEach(SpriteSheetLayout.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Include JSON frame data", isOn: $options.includeMetadata)
                    }
                }

                Section {
                    Picker("Scale", selection: scaleBinding) {
                        ForEach(scales, id: \.self) { s in
                            Group {
                                if s > purchases.access.maxExportScale {
                                    Text("\(s)× · Pro", comment: "Export scale that needs Pro")
                                } else {
                                    Text("\(s)×", comment: "Export scale, e.g. 4×")
                                }
                            }
                            .tag(s)
                        }
                    }
                } header: {
                    Text("Size")
                } footer: {
                    outputDescription
                }

                Section {
                    Button {
                        export()
                    } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Label("Export", systemImage: "square.and.arrow.up") }
                            Spacer()
                        }
                    }
                    .disabled(working)
                }
            }
            .navigationTitle("Export Sprites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onChange(of: options.format) { _, _ in clampScale() }
            .onChange(of: options.layout) { _, _ in clampScale() }
            .sheet(item: $shareItems) { items in
                ActivityView(items: items.urls) { completed in
                    if completed { exportSucceeded() }
                }
                .ignoresSafeArea()
            }
            .proUpgradeSheet($upgrade)
            .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// Locked choices open the paywall instead of being selected.
    private var formatBinding: Binding<ExportFormat> {
        Binding(get: { options.format }, set: { f in
            if f == .gif && !purchases.access.allowsGIF { upgrade = .gifExport } else { options.format = f }
        })
    }

    private var scaleBinding: Binding<Int> {
        Binding(get: { options.scale }, set: { s in
            if s > purchases.access.maxExportScale { upgrade = .largeExport } else { options.scale = s }
        })
    }

    /// Ask for a rating only after a few exports the user actually completed, and at most once
    /// per app version. The system decides whether to show it (and limits it to 3 times a year).
    private func exportSucceeded() {
        completedExports += 1
        guard completedExports >= 3, reviewRequestedForVersion != AppConfig.version else { return }
        reviewRequestedForVersion = AppConfig.version
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { requestReview() }
    }

    private func clampScale() {
        let usable = scales.filter { $0 <= purchases.access.maxExportScale }
        if !usable.contains(options.scale) { options.scale = usable.last ?? 1 }
    }

    private func export() {
        working = true
        let project = project, options = options
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try SpriteExporter.export(project, options: options) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success(let urls): shareItems = ShareItems(urls: urls)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
        }
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
