import SwiftUI
import UIKit

/// Choose a format and size, then hand the files to the share sheet
/// (Save to Files, Photos, AirDrop, Messages…).
struct ExportSheet: View {
    let project: SpriteProject
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()
    @State private var shareItems: ShareItems?
    @State private var errorMessage: String?
    @State private var working = false

    private var scales: [Int] { SpriteExporter.allowedScales(for: project, options: options) }

    private var outputDescription: String {
        let s = options.scale
        switch options.format {
        case .spriteSheet:
            let size = SpriteSheet.pixelSize(canvas: project.size, frameCount: project.frames.count, scale: s, layout: options.layout)
            return "One \(size.width) × \(size.height) PNG" + (options.includeMetadata ? " + JSON frame data" : "")
        case .gif:
            return "Looping \(project.size * s) × \(project.size * s) GIF at \(project.fps) fps"
        case .frames:
            return "\(project.frames.count) PNG file\(project.frames.count == 1 ? "" : "s"), \(project.size * s) × \(project.size * s)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $options.format) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
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
                    Picker("Scale", selection: $options.scale) {
                        ForEach(scales, id: \.self) { Text("\($0)×").tag($0) }
                    }
                } header: {
                    Text("Size")
                } footer: {
                    Text(outputDescription)
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
                ActivityView(items: items.urls)
                    .ignoresSafeArea()
            }
            .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func clampScale() {
        if !scales.contains(options.scale) { options.scale = scales.last ?? 1 }
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

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
