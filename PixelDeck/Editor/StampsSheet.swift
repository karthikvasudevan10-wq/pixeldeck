import SwiftUI

extension StampLibrary {
    /// Saved stamps live beside the sprites (in iCloud when sync is on).
    @MainActor static func forApp() -> StampLibrary {
        let base = ImageStore.root
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let library = StampLibrary(url: base.appendingPathComponent("Stamps", isDirectory: true).appendingPathComponent("stamps.json"))
        library.writeFile = CloudFiles.write
        return library
    }
}

/// Stamps: reusable pieces (eyes, trees, clouds). Tap one and it lands on the canvas as a
/// selection to move into place; save any selection as a stamp of your own.
struct StampsSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var library = StampLibrary.forApp()
    @State private var tab: StampTab = .mine
    @State private var naming = false
    @State private var nameText = ""
    @State private var deleting: Stamp?
    @State private var message: String?

    private enum StampTab: String, CaseIterable, Identifiable {
        case mine, starter
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .mine ? "Mine" : "Starter" }
    }

    private var shown: [Stamp] { tab == .mine ? library.stamps : StarterStamps.stamps }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Stamps", onClose: { dismiss() })
            ChoiceRow(options: StampTab.allCases, selection: $tab) { Text($0.title) }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap one and it lands on your canvas. Drag it into place, then tap Done.")
                        .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    if shown.isEmpty {
                        Text("No stamps of your own yet. Select part of your drawing, then save it here.")
                            .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .multilineTextAlignment(.center)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 8)], spacing: 8) {
                        ForEach(shown) { stamp in
                            Button { place(stamp) } label: {
                                VStack(spacing: 4) {
                                    PixelImage(grid: stamp.grid, checker: false)
                                        .padding(8)
                                        .frame(height: 76)
                                        .frame(maxWidth: .infinity)
                                        .background(Theme.ink)
                                    Text(verbatim: stamp.name.capitalized).font(AppFont.pixel(9)).foregroundStyle(Theme.text).lineLimit(1)
                                }
                                .padding(4)
                                .background(Theme.surface)
                                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if tab == .mine {
                                    Button(role: .destructive) { deleting = stamp } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                            .accessibilityLabel(Text("Stamp: \(stamp.name)"))
                        }
                    }
                    if let message {
                        Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                    }
                }
                .padding(16)
            }
            Button {
                nameText = ""
                naming = true
            } label: {
                PrimaryActionLabel(title: model.hasSelection ? "Save the selection as a stamp" : "Save this layer as a stamp", icon: .plus, height: 52)
            }
            .buttonStyle(PrimaryButtonStyle(depth: 4))
            .disabled(model.stampSource() == nil || library.isFull)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .alert("Name your stamp", isPresented: $naming) {
            TextField("Name", text: $nameText)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this stamp?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let d = deleting { library.delete(d.id) } }
        }
    }

    private func place(_ stamp: Stamp) {
        if model.placeStamp(stamp.grid) {
            dismiss()
        } else {
            message = String(localized: "That stamp doesn't fit: the art would be too big.")
        }
    }

    private func save() {
        guard let source = model.stampSource() else { return }
        if library.add(name: nameText, grid: source) != nil {
            tab = .mine
            message = String(localized: "Saved to your stamps.")
        } else {
            message = String(localized: "Stamps can be up to \(Stamp.maxSide) × \(Stamp.maxSide) pixels. Select a smaller piece.")
        }
    }
}
