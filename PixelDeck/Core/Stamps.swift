import Foundation
import Observation

/// A reusable piece of art (an eye, a tree, a cloud) you can drop into any canvas.
struct Stamp: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var grid: PixelGrid

    static let maxSide = 64
    static let maxNameLength = 24
}

/// The stamps every library starts with (art in StarterStamps.swift).
enum StarterStamps {
    static var stamps: [Stamp] {
        art.map { Stamp(id: UUID(stableName: "pixeldeck.stamp.\($0.name)"), name: $0.name, grid: $0.grid) }
    }
}

/// The user's saved stamps, kept as one JSON file beside the sprites (in iCloud when sync is on).
@Observable
final class StampLibrary {
    private(set) var stamps: [Stamp] = []
    let url: URL
    /// The app swaps in a coordinated (iCloud-safe) write.
    @ObservationIgnored var writeFile: (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }

    static let maxStamps = 200

    init(url: URL) {
        self.url = url
        load()
    }

    var isFull: Bool { stamps.count >= StampLibrary.maxStamps }

    func load() {
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Stamp].self, from: data) else { return }
        stamps = saved
    }

    /// Saves a new stamp (trimmed to its pixels). Nil if it's empty, too big, or the library is full.
    @discardableResult
    func add(name: String, grid: PixelGrid) -> Stamp? {
        guard !isFull, let box = grid.opaqueBounds, box.width <= Stamp.maxSide, box.height <= Stamp.maxSide else { return nil }
        let patch = grid.patch(in: box)
        var trimmed = PixelGrid(width: box.width, height: box.height)
        trimmed.stamp(patch, at: .zero)
        let stamp = Stamp(name: tidy(name), grid: trimmed)
        stamps.insert(stamp, at: 0)
        save()
        return stamp
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = stamps.firstIndex(where: { $0.id == id }) else { return }
        stamps[i].name = tidy(name)
        save()
    }

    func delete(_ id: UUID) {
        stamps.removeAll { $0.id == id }
        save()
    }

    private func tidy(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Stamp" : String(t.prefix(Stamp.maxNameLength))
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(stamps) { try? writeFile(data, url) }
    }
}

extension EditorModel {
    /// The selected pixels as a stamp-sized picture (or everything on the active layer of this
    /// frame, with no selection). Nil if there's nothing there.
    func stampSource() -> PixelGrid? {
        let cel = currentLayerGrid
        var out = PixelGrid(width: cel.width, height: cel.height)
        if let mask = selectedMask {
            for p in mask.points {
                let l = p - bounds.origin
                out[l] = cel[l]
            }
        } else {
            out = cel
        }
        guard let box = out.opaqueBounds else { return nil }
        var trimmed = PixelGrid(width: box.width, height: box.height)
        trimmed.stamp(out.patch(in: box), at: .zero)
        return trimmed
    }

    /// Drops `art` onto the active layer as a selection you can move, turn and resize, centred on
    /// `center` (world pixels; the middle of your art by default). Returns false if it won't fit.
    @discardableResult
    func placeStamp(_ art: PixelGrid, at center: PixelPoint? = nil) -> Bool {
        isPlaying = false
        commitSelection()
        let c = center ?? contentBounds.map { PixelPoint(x: $0.x + $0.width / 2, y: $0.y + $0.height / 2) } ?? .zero
        let rect = PixelRect(x: c.x - art.width / 2, y: c.y - art.height / 2, width: art.width, height: art.height)
        promptedThisGesture = false
        guard ensureCovers(rect) else { return false }
        revealActiveLayer()
        pushUndo()
        if tool != .select { tool = .select }
        let floatingStamp = FloatingSelection(pasting: art.patch(in: art.rect), at: rect.origin, onto: currentLayerGrid, bounds: bounds)
        floating = floatingStamp
        floatingIsMasked = true
        mutateCurrent { $0 = floatingStamp.composited() }
        contentKnown = false
        return true
    }
}
