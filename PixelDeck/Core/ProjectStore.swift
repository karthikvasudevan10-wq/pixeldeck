import Foundation
import Observation

/// Keeps every sprite as a JSON file in a folder: Documents/Sprites on the device, or a Sprites
/// folder in the app's iCloud container when iCloud sync is on (the app's `CloudSync` moves it
/// there and tells it when other devices change files). With several devices, the newest
/// version of a sprite (by `modifiedAt`) wins.
@Observable
final class ProjectStore {
    /// Documents/Sprites on this device.
    static var localDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sprites", isDirectory: true)
    }

    private(set) var projects: [SpriteProject] = []
    /// Set when a save fails (for example, the device is full), so the app can warn the user
    /// instead of silently losing work. Atomic writes leave the previous version intact.
    private(set) var saveFailed = false

    @ObservationIgnored private(set) var directory: URL
    /// How files are written and removed. The app swaps in coordinated versions (NSFileCoordinator)
    /// so iCloud sees every change. Called on the store's background queue.
    @ObservationIgnored var writeFile: (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }
    @ObservationIgnored var removeFile: (URL) -> Void = { url in try? FileManager.default.removeItem(at: url) }
    @ObservationIgnored private let io = DispatchQueue(label: "PixelDeck.ProjectStore", qos: .utility)
    /// Latest unsaved version of each project. Only touched on `io`.
    @ObservationIgnored private var pendingWrites: [UUID: SpriteProject] = [:]
    @ObservationIgnored private var writeScheduled = false
    /// Modification date of each sprite file when it was last read or written here, so
    /// `mergeFromDisk` only reads files another device changed. Only touched on `io`.
    @ObservationIgnored private var fileDates: [String: Date] = [:]
    /// Edits arriving within this window are written to disk once.
    private let writeDelay: TimeInterval = 0.6

    init(directory: URL? = nil) {
        let dir = directory ?? ProjectStore.localDirectory
        self.directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        var loaded: [UUID: SpriteProject] = [:]
        io.sync {
            fileDates = [:]
            loaded = scan(directory, skipUnchanged: false).changed
        }
        projects = loaded.values.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Reads the sprite files in `dir` (only those changed since last seen, with `skipUnchanged`)
    /// and lists the ids of every sprite file present. Runs on `io`.
    private func scan(_ dir: URL, skipUnchanged: Bool) -> (changed: [UUID: SpriteProject], present: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let decoder = JSONDecoder()
        var changed: [UUID: SpriteProject] = [:]
        var present = Set<UUID>()
        for url in files {
            // ".<id>.json.icloud": in iCloud but not downloaded (or evicted to save space). The
            // sprite still exists; it's read once iCloud brings the file back.
            if url.pathExtension == "icloud" {
                let name = url.deletingPathExtension().lastPathComponent        // ".<id>.json"
                if name.hasPrefix("."), name.hasSuffix(".json"),
                   let id = UUID(uuidString: String(name.dropFirst().dropLast(5))) { present.insert(id) }
                continue
            }
            guard url.pathExtension == "json",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            present.insert(id)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if skipUnchanged, let date, fileDates[url.lastPathComponent] == date { continue }
            guard let data = try? Data(contentsOf: url), let p = try? decoder.decode(SpriteProject.self, from: data) else { continue }
            fileDates[url.lastPathComponent] = date
            changed[p.id] = p
        }
        return (changed, present)
    }

    /// Notes a file this store just wrote, so it isn't read back as a change. Runs on `io`.
    private func noteWritten(_ url: URL) {
        fileDates[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Every readable sprite in a folder. Files iCloud hasn't downloaded yet are skipped.
    private static func read(_ dir: URL) -> [UUID: SpriteProject] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        var out: [UUID: SpriteProject] = [:]
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let p = try? decoder.decode(SpriteProject.self, from: data) else { continue }
            // Two files for one sprite (shouldn't happen): keep the newer.
            if let o = out[p.id], o.modifiedAt >= p.modifiedAt { continue }
            out[p.id] = p
        }
        return out
    }

    /// Moves the store to another folder (on or off iCloud), merging: a sprite in both places keeps
    /// its newer version. `removingOld` deletes the old folder's sprite files once copied (used when
    /// moving local work into iCloud, so a stale local copy can't come back later).
    func relocate(to newDirectory: URL, removingOld: Bool) {
        guard newDirectory.standardizedFileURL != directory.standardizedFileURL else { return }
        flush()
        try? FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        let old = directory
        var merged = Self.read(newDirectory)
        var toWrite: [SpriteProject] = []
        for p in projects where (merged[p.id]?.modifiedAt ?? .distantPast) < p.modifiedAt {
            merged[p.id] = p
            toWrite.append(p)
        }
        directory = newDirectory
        projects = merged.values.sorted { $0.modifiedAt > $1.modifiedAt }
        let encoder = JSONEncoder()
        io.sync {
            var failed = false
            for p in toWrite {
                do { try writeFile(encoder.encode(p), fileURL(for: p.id)) } catch { failed = true }
            }
            fileDates = [:]
            _ = scan(newDirectory, skipUnchanged: false)       // remember the new folder's dates
            if removingOld && !failed {
                let files = (try? FileManager.default.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? []
                for url in files where url.pathExtension == "json" { removeFile(url) }
            }
            if failed { DispatchQueue.main.async { [self] in saveFailed = true } }
        }
    }

    /// Picks up changes made on other devices: newer versions replace older ones, new sprites
    /// appear, and sprites whose files were deleted elsewhere go. Edits not yet written here are
    /// kept (they're newer).
    func mergeFromDisk() {
        var changed: [UUID: SpriteProject] = [:]
        var present = Set<UUID>()
        var pending = Set<UUID>()
        io.sync {
            (changed, present) = scan(directory, skipUnchanged: true)
            pending = Set(pendingWrites.keys)
        }
        var next: [SpriteProject] = []
        var seen = Set<UUID>()
        for p in projects {
            seen.insert(p.id)
            if let d = changed[p.id], d.modifiedAt > p.modifiedAt, !pending.contains(p.id) {
                next.append(d)                       // newer from another device
            } else if present.contains(p.id) || pending.contains(p.id) {
                next.append(p)                       // unchanged, or created here and not written yet
            }                                        // otherwise deleted on another device
        }
        for (id, d) in changed where !seen.contains(id) { next.append(d) }
        next.sort { $0.modifiedAt > $1.modifiedAt }
        if next.map(\.id) != projects.map(\.id) || zip(next, projects).contains(where: { $0.modifiedAt != $1.modifiedAt }) {
            projects = next
        }
    }

    func project(id: UUID) -> SpriteProject? {
        projects.first { $0.id == id }
    }

    /// `baseName` is localised by the app, e.g. "Sprite" → "Sprite 3".
    @discardableResult
    func create(baseName: String = "Sprite") -> SpriteProject {
        let p = SpriteProject(name: nextName(base: baseName))
        save(p)
        return p
    }

    func save(_ p: SpriteProject) {
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            // An older copy (e.g. an editor closing after another device saved a newer version)
            // never replaces a newer one.
            guard projects[i].modifiedAt <= p.modifiedAt else { return }
            projects[i] = p
        } else {
            projects.insert(p, at: 0)
        }
        io.async { [self] in
            pendingWrites[p.id] = p
            guard !writeScheduled else { return }
            writeScheduled = true
            io.asyncAfter(deadline: .now() + writeDelay) { [self] in writePending() }
        }
    }

    /// Runs on `io`.
    private func writePending() {
        writeScheduled = false
        let batch = pendingWrites
        pendingWrites = [:]
        let encoder = JSONEncoder()
        var failed = false
        for (id, project) in batch {
            do {
                try writeFile(encoder.encode(project), fileURL(for: id))
                noteWritten(fileURL(for: id))
            } catch {
                failed = true
            }
        }
        if failed {
            DispatchQueue.main.async { [self] in saveFailed = true }
        }
    }

    func acknowledgeSaveFailure() {
        saveFailed = false
    }

    /// `name` builds the copy's name from the original's (localised by the app).
    /// Adds ready-made sprites (the starter examples), oldest first so they sort after new work.
    /// `before`: their dates, counting back from it (fixed dates let the same starter added on two
    /// devices merge into one, with any edit winning).
    func add(_ newProjects: [SpriteProject], before date: Date = Date()) {
        for (i, var p) in newProjects.enumerated() {
            p.modifiedAt = date.addingTimeInterval(-Double(newProjects.count - i))
            p.createdAt = p.modifiedAt
            save(p)
        }
        projects.sort { $0.modifiedAt > $1.modifiedAt }
    }

    /// Returns the copy, so the app can copy files kept beside the sprite (e.g. its tracing picture).
    @discardableResult
    func duplicate(id: UUID, name: (String) -> String = { "\($0) copy" }) -> SpriteProject? {
        guard let p = project(id: id) else { return nil }
        let copy = p.duplicated(name: name(p.name))
        save(copy)
        return copy
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var p = project(id: id), !trimmed.isEmpty else { return }
        p.name = trimmed
        save(p)
    }

    func delete(id: UUID) {
        projects.removeAll { $0.id == id }
        let url = fileURL(for: id)
        io.async { [self] in
            pendingWrites[id] = nil
            removeFile(url)
        }
    }

    /// Blocks until pending writes are on disk. Used by tests and when the app goes to the background.
    func flush() {
        io.sync { writePending() }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func nextName(base: String) -> String {
        let names = Set(projects.map(\.name))
        var n = projects.count + 1
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
