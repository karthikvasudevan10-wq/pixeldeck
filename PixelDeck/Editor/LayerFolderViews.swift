import SwiftUI

// The pieces of the layers list that deal with folders, shared by the layers sheet (iPhone, and
// the Layers button) and the desk's panel (Mac and iPad).

/// "Folder" in a layer's menu: move the layer into a folder, into a new one, or out.
struct LayerFolderMenu: View {
    let model: EditorModel
    let index: Int

    var body: some View {
        let current = model.layers.indices.contains(index) ? model.layers[index].folderID : nil
        Menu {
            ForEach(model.folders) { folder in
                Button { model.moveLayer(index, toFolder: folder.id) } label: {
                    Label { Text(verbatim: folder.name) } icon: { Image(systemName: current == folder.id ? "checkmark" : "folder") }
                }
                .disabled(current == folder.id)
            }
            if !model.folders.isEmpty { Divider() }
            Button { model.newFolder(containing: index) } label: { Label("New folder", systemImage: "folder.badge.plus") }
            if current != nil {
                Button { model.moveLayer(index, toFolder: nil) } label: { Label("Out of the folder", systemImage: "arrow.up.forward.square") }
            }
        } label: {
            Label("Folder", systemImage: "folder")
        }
    }
}

/// A folder's row in the layers list: fold it away, show or hide all its layers, and more.
struct LayerFolderRow: View {
    let model: EditorModel
    let folder: LayerFolder
    /// How many layers are in it.
    let count: Int
    /// The desk's narrow panel uses smaller controls.
    var compact = false
    var onRename: (LayerFolder) -> Void

    var body: some View {
        let side: CGFloat = compact ? 36 : 44
        HStack(spacing: compact ? 6 : 10) {
            Button { model.setFolderCollapsed(folder.id, !folder.isCollapsed) } label: {
                HStack(spacing: compact ? 6 : 10) {
                    Image(systemName: folder.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 14)
                    Image(systemName: folder.isVisible ? "folder.fill" : "folder")
                        .font(.system(size: compact ? 15 : 17))
                        .foregroundStyle(folder.isVisible ? Theme.accent2 : Theme.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: folder.name)
                            .font(AppFont.body(compact ? 15 : 15, .bold, relativeTo: .body))
                            .foregroundStyle(folder.isVisible ? Theme.cream : Theme.muted)
                            .lineLimit(1)
                        Text("\(count) layers", comment: "Under a folder's name in the layers list; plural")
                            .font(AppFont.pixel(9)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: side)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Folder \(folder.name), \(count) layers"))
            .accessibilityHint(folder.isCollapsed ? Text("Opens the folder") : Text("Folds the folder away"))
            .help("Folder: click to fold its layers away or open it again")

            Button { model.setFolderVisible(folder.id, !folder.isVisible) } label: {
                (folder.isVisible ? PixelIcon.eye : .eyeOff).view(size: compact ? 18 : 20)
                    .foregroundStyle(folder.isVisible ? Theme.text : Theme.muted)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(folder.isVisible ? Text("Hide folder") : Text("Show folder"))
            .help("Show or hide every layer in this folder")

            Menu {
                menuItems
            } label: {
                PixelIcon.more.view(size: compact ? 18 : 20)
                    .foregroundStyle(Theme.muted)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("More for folder \(folder.name)"))
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 2 : 4)
        .background(Theme.tool.opacity(compact ? 0.6 : 1))
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: compact ? 1 : 2))
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button { onRename(folder) } label: { Label("Rename folder", systemImage: "pencil") }
        Button { model.moveFolder(folder.id, by: 1) } label: { Label("Move folder up", systemImage: "arrow.up") }
            .disabled(!model.canMoveFolder(folder.id, by: 1))
        Button { model.moveFolder(folder.id, by: -1) } label: { Label("Move folder down", systemImage: "arrow.down") }
            .disabled(!model.canMoveFolder(folder.id, by: -1))
        Button { model.ungroupFolder(folder.id) } label: { Label("Remove the folder, keep its layers", systemImage: "folder.badge.minus") }
        Divider()
        Button(role: .destructive) { model.deleteFolder(folder.id) } label: { Label("Delete the folder and its layers", systemImage: "trash") }
            .disabled(!model.canDeleteFolder(folder.id))
    }
}

/// Asks for a folder's new name.
struct FolderRenameAlert: ViewModifier {
    let model: EditorModel
    @Binding var renaming: LayerFolder?
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: renaming) { _, folder in if let folder { text = folder.name } }
            .alert("Rename folder", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $text)
                Button("Save") {
                    if let folder = renaming { model.renameFolder(folder.id, to: text) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
    }
}
