import SwiftUI

/// Home screen: every saved sprite, plus "New canvas".
struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @State private var path: [UUID] = []
    @State private var showingNewCanvas = false
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var deletingID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No sprites yet", systemImage: "square.grid.3x3.fill")
                    } description: {
                        Text("Start with a canvas from 8×8 up to 256×256.")
                    } actions: {
                        Button("New Canvas") { showingNewCanvas = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.projects) { project in
                                NavigationLink(value: project.id) {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { menu(for: project) }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Pixel Deck")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewCanvas = true } label: {
                        Label("New Canvas", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let project = store.project(id: id) {
                    EditorView(project: project)
                }
            }
        }
        .sheet(isPresented: $showingNewCanvas) {
            NewCanvasSheet { size in
                let project = store.create(size: size)
                path = [project.id]
            }
        }
        .alert("Rename sprite", isPresented: Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = renamingID { store.rename(id: id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this sprite?", isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deletingID { store.delete(id: id) }
            }
        } message: {
            Text("All of its frames will be removed. This can't be undone.")
        }
    }

    @ViewBuilder
    private func menu(for project: SpriteProject) -> some View {
        Button {
            renameText = project.name
            renamingID = project.id
        } label: { Label("Rename", systemImage: "pencil") }
        Button { store.duplicate(id: project.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button(role: .destructive) { deletingID = project.id } label: { Label("Delete", systemImage: "trash") }
    }
}

private struct ProjectCard: View {
    let project: SpriteProject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PixelImage(frame: project.frames[0])
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
            Text(project.name)
                .font(.headline)
                .lineLimit(1)
            Text("\(project.size)×\(project.size) · \(project.frames.count) frame\(project.frames.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
