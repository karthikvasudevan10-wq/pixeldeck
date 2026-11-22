import Foundation

// Layer folders: named groups of layers. A folder's layers sit together in the stack, so the
// folder can be shown as one block, hidden as one, folded away, and moved as one. Folders are
// one level deep (a folder doesn't hold other folders).

/// A row of the layers list: a loose layer, or a folder with the layers in it.
enum LayerEntry: Identifiable, Equatable {
    /// `index` is the layer's place in the sprite's stack (0 is the bottom).
    case layer(id: UUID, index: Int)
    /// `indices`: the folder's layers, top of the stack first.
    case folder(LayerFolder, indices: [Int])

    var id: UUID {
        switch self {
        case .layer(let id, _): id
        case .folder(let folder, _): folder.id
        }
    }
}

extension SpriteProject {
    func folder(id: UUID?) -> LayerFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    /// Where a folder's layers are in the stack (they sit together), or nil if it has none.
    func folderRange(_ id: UUID) -> ClosedRange<Int>? {
        guard let low = layers.firstIndex(where: { $0.folderID == id }),
              let high = layers.lastIndex(where: { $0.folderID == id }) else { return nil }
        return low...high
    }

    /// The layers as they are listed: top of the stack first, each folder as one entry.
    var layerOutline: [LayerEntry] {
        var out: [LayerEntry] = []
        var i = layers.count - 1
        while i >= 0 {
            if let folder = folder(id: layers[i].folderID) {
                var inside: [Int] = []
                while i >= 0, layers[i].folderID == folder.id {
                    inside.append(i)
                    i -= 1
                }
                out.append(.folder(folder, indices: inside))
            } else {
                out.append(.layer(id: layers[i].id, index: i))
                i -= 1
            }
        }
        return out
    }

    /// Keeps folders sound after layers are added, moved or removed (and when a file is opened).
    mutating func tidyFolders() {
        SpriteProject.tidyFolders(layers: &layers, folders: &folders)
    }

    /// - A layer whose folder no longer exists is loose again.
    /// - A loose layer that has ended up between two layers of one folder joins it.
    /// - A folder's layers sit together: any that are apart from the topmost group are loose again.
    /// - A folder with no layers is removed.
    static func tidyFolders(layers: inout [LayerInfo], folders: inout [LayerFolder]) {
        guard !folders.isEmpty || layers.contains(where: { $0.folderID != nil }) else { return }
        let known = Set(folders.map(\.id))
        for i in layers.indices where layers[i].folderID.map({ !known.contains($0) }) ?? false {
            layers[i].folderID = nil
        }
        if layers.count >= 3 {
            for i in 1..<(layers.count - 1) where layers[i].folderID == nil {
                if let below = layers[i - 1].folderID, below == layers[i + 1].folderID { layers[i].folderID = below }
            }
        }
        var seen = Set<UUID>()
        for i in layers.indices.reversed() {
            guard let folder = layers[i].folderID else { continue }
            let continuesGroup = i + 1 < layers.count && layers[i + 1].folderID == folder
            if seen.contains(folder) && !continuesGroup {
                layers[i].folderID = nil
            } else {
                seen.insert(folder)
            }
        }
        let used = Set(layers.compactMap(\.folderID))
        folders.removeAll { !used.contains($0.id) }
    }
}

extension EditorModel {
    var folders: [LayerFolder] { project.folders }

    func folder(ofLayer index: Int) -> LayerFolder? {
        project.layers.indices.contains(index) ? project.folder(id: project.layers[index].folderID) : nil
    }

    /// Makes a folder holding one layer. Returns the folder's id.
    @discardableResult
    func newFolder(containing index: Int, named name: String? = nil) -> UUID? {
        guard project.layers.indices.contains(index) else { return nil }
        commitSelection()
        pushUndo()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let folder = LayerFolder(name: trimmed.isEmpty ? newFolderName(project.folders.count + 1) : trimmed)
        project.folders.append(folder)
        place(layer: index, inFolder: folder.id)
        finishEdit()
        return folder.id
    }

    /// Moves a layer into a folder, or out of its folder (`nil`).
    func moveLayer(_ index: Int, toFolder id: UUID?) {
        guard project.layers.indices.contains(index), project.layers[index].folderID != id,
              id == nil || project.folder(id: id) != nil else { return }
        commitSelection()
        pushUndo()
        place(layer: index, inFolder: id)
        finishEdit()
    }

    /// Sets a layer's folder and moves it next to that folder's other layers (on top of them),
    /// or, leaving a folder, just above it. Folders' layers stay together either way.
    private func place(layer index: Int, inFolder id: UUID?) {
        let old = project.layers[index].folderID
        var order = Array(project.layers.indices)
        order.remove(at: index)
        // Above the folder it is joining; or, with nothing to join, above the one it is leaving.
        let beside = [id, old].compactMap { $0 }.first { f in order.contains { project.layers[$0].folderID == f } }
        var position = index
        if let beside, let top = order.lastIndex(where: { project.layers[$0].folderID == beside }) {
            position = top + 1
        }
        project.layers[index].folderID = id
        order.insert(index, at: min(position, order.count))
        reorderLayers(order)
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = project.folders.firstIndex(where: { $0.id == id }) else { return }
        project.folders[i].name = String(trimmed.prefix(32))
        finishEdit()
    }

    /// Shows or hides every layer in a folder at once.
    func setFolderVisible(_ id: UUID, _ visible: Bool) {
        guard let i = project.folders.firstIndex(where: { $0.id == id }), project.folders[i].isVisible != visible else { return }
        commitSelection()
        pushUndo()
        project.folders[i].isVisible = visible
        reflattenAll()
        finishEdit()
    }

    /// Folds a folder away in the layers list, or opens it. Nothing on the canvas changes.
    func setFolderCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard let i = project.folders.firstIndex(where: { $0.id == id }), project.folders[i].isCollapsed != collapsed else { return }
        project.folders[i].isCollapsed = collapsed
        finishEdit()
    }

    /// Whether a folder can move up (+1) or down (-1) in the stack.
    func canMoveFolder(_ id: UUID, by delta: Int) -> Bool {
        guard let block = project.folderRange(id) else { return false }
        return delta > 0 ? block.upperBound + 1 < project.layers.count : block.lowerBound > 0
    }

    /// Moves a folder, with its layers, over the layer (or whole folder) above or below it.
    func moveFolder(_ id: UUID, by delta: Int) {
        guard canMoveFolder(id, by: delta), let block = project.folderRange(id) else { return }
        let n = project.layers.count
        func group(at index: Int) -> ClosedRange<Int> {
            project.layers[index].folderID.flatMap { project.folderRange($0) } ?? index...index
        }
        let order: [Int]
        if delta > 0 {
            let over = group(at: block.upperBound + 1)
            order = Array(0..<block.lowerBound) + Array(over) + Array(block) + Array((over.upperBound + 1)..<n)
        } else {
            let over = group(at: block.lowerBound - 1)
            order = Array(0..<over.lowerBound) + Array(block) + Array(over) + Array((block.upperBound + 1)..<n)
        }
        commitSelection()
        pushUndo()
        reorderLayers(order)
        finishEdit()
    }

    /// Takes the layers out of a folder and removes it. The layers stay where they are.
    func ungroupFolder(_ id: UUID) {
        guard project.folders.contains(where: { $0.id == id }) else { return }
        commitSelection()
        pushUndo()
        let wasHidden = !(project.folder(id: id)?.isVisible ?? true)
        for i in project.layers.indices where project.layers[i].folderID == id { project.layers[i].folderID = nil }
        project.folders.removeAll { $0.id == id }
        if wasHidden { reflattenAll() }
        finishEdit()
    }

    /// Whether a folder can be deleted with its layers (a sprite keeps at least one layer).
    func canDeleteFolder(_ id: UUID) -> Bool {
        let inside = project.layers.filter { $0.folderID == id }.count
        return inside > 0 && inside < project.layers.count
    }

    /// Deletes a folder and every layer in it, from every frame.
    func deleteFolder(_ id: UUID) {
        guard canDeleteFolder(id) else { return }
        commitSelection()
        pushUndo()
        let keep = project.layers.indices.filter { project.layers[$0].folderID != id }
        // The layer being drawn on, or the nearest one left below it.
        let active = keep.lastIndex(where: { $0 <= activeLayer }) ?? 0
        project.layers = keep.map { project.layers[$0] }
        project.folders.removeAll { $0.id == id }
        project.tidyFolders()
        let visible = project.layerVisibility
        for i in project.frames.indices {
            let cels = project.frames[i].layers
            project.frames[i].setLayers(keep.map { cels[$0] }, visible: visible)
        }
        activeLayer = min(active, project.layers.count - 1)
        contentKnown = false
        finishEdit()
    }
}
