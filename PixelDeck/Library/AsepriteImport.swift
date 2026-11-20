import SwiftUI
import UniformTypeIdentifiers

/// Aseprite files: opening them (with their layers, frames, timing and tags) and saving sprites
/// back, so work can move to and from the desktop.
enum AsepriteFiles {
    static var contentTypes: [UTType] {
        var types: [UTType] = [.data]
        for ext in Aseprite.fileExtensions { if let t = UTType(filenameExtension: ext) { types.insert(t, at: 0) } }
        return types
    }

    static func isAseprite(_ url: URL) -> Bool { Aseprite.fileExtensions.contains(url.pathExtension.lowercased()) }

    /// Reads a picked or dropped file. Returns the file, or a message saying why not.
    static func read(_ url: URL) -> Result<AsepriteFile, AsepriteReadError> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        do { return .success(try Aseprite.parse(data)) } catch let e as AsepriteError {
            return .failure(e == .tooBig ? .tooBig : e == .notAseprite ? .notAseprite : .damaged)
        } catch { return .failure(.damaged) }
    }

    /// Writes the sprite as an .aseprite file, ready to share.
    static func export(_ project: SpriteProject) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = String(project.name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" })
        let url = dir.appendingPathComponent(safe.isEmpty ? "Sprite" : safe).appendingPathExtension("aseprite")
        do { try Aseprite.encode(project).write(to: url) } catch { return nil }
        return url
    }
}

enum AsepriteReadError: Error {
    case unreadable, notAseprite, tooBig, damaged

    var message: String {
        switch self {
        case .unreadable: String(localized: "Couldn't open that file.")
        case .notAseprite: String(localized: "That isn't an Aseprite file.")
        case .tooBig: String(localized: "That sprite is bigger than Pixel Deck's canvas (\(Aseprite.maxSide) × \(Aseprite.maxSide)).")
        case .damaged: String(localized: "That Aseprite file couldn't be read. It may use features Pixel Deck doesn't know.")
        }
    }
}

/// A file being imported (for `.sheet(item:)`).
struct AsepriteImport: Identifiable {
    let id = UUID()
    let name: String
    let file: AsepriteFile
}

/// "Open an Aseprite file": what's inside, and how to bring it in.
struct AsepriteImportSheet: View {
    let item: AsepriteImport
    /// Called with the sprites to add to the gallery.
    var onImport: ([SpriteProject]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @State private var splitTags = true
    @State private var keepLayers = true
    @State private var upgrade: ProFeature?

    private var file: AsepriteFile { item.file }
    private var sprites: [SpriteProject] { Aseprite.projects(from: file, name: item.name, splitTags: splitTags, keepLayers: keepLayers) }
    private var tooManyLayers: Bool { file.layerNames.count > SpriteProject.maxLayers }

    var body: some View {
        let result = sprites
        return VStack(spacing: 0) {
            SheetHeader(title: "Open an Aseprite file", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        if let first = result.first?.frames.first {
                            PixelImage(frame: first, checker: true).frame(width: 72, height: 72).background(Theme.ink)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: item.name).font(AppFont.body(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream).lineLimit(1)
                            Text("\(file.width) × \(file.height) · \(file.layerNames.count) layers · \(file.frames.count) frames",
                                 comment: "Aseprite file summary: size, layer count (plural), frame count (plural)")
                                .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        if !purchases.access.allowsAseprite { ProBadge() }
                    }
                    if !file.tags.isEmpty {
                        toggle("Tags become animations", detail: Text(verbatim: file.tags.map { "\($0.name) · \($0.frameCount)" }.joined(separator: "   ")), isOn: $splitTags)
                    }
                    toggle("Keep layers", detail: tooManyLayers
                           ? Text("Pixel Deck sprites have up to \(SpriteProject.maxLayers) layers, so these are joined into one.")
                           : Text(verbatim: file.layerNames.joined(separator: ", ")), isOn: $keepLayers)
                        .disabled(tooManyLayers)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frame timing").font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                        Text("Per-frame durations are kept, as holds. Pixels that are partly see-through become solid or clear.")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
            Button {
                guard purchases.access.allowsAseprite else { upgrade = .aseprite; return }
                onImport(result)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    PixelIcon.download.view(size: 18, lineWidth: 2.5)
                    Text("Import \(result.count) sprites", comment: "Button; plural").font(AppFont.pixel(17))
                    if !purchases.access.allowsAseprite { ProBadge() }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .presentationDetents([.large])
        .proUpgradeSheet($upgrade)
    }

    private func toggle(_ title: LocalizedStringKey, detail: Text, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                detail.font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.accent)
    }
}
