import Foundation
import Observation

/// Keeps every sprite as a JSON file in the app's Documents/Sprites folder.
@Observable
final class ProjectStore {
    private(set) var projects: [SpriteProject] = []
    /// Set when a save fails (for example, the device is full), so the app can warn the user
    /// instead of silently losing work. Atomic writes leave the previous version intact.
    private(set) var saveFailed = false

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let io = DispatchQueue(label: "PixelDeck.ProjectStore", qos: .utility)
    /// Latest unsaved version of each project. Only touched on `io`.
    @ObservationIgnored private var pendingWrites: [UUID: SpriteProject] = [:]
    @ObservationIgnored private var writeScheduled = false
    /// Edits arriving within this window are written to disk once.
    private let writeDelay: TimeInterval = 0.6

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sprites", isDirectory: true)
        self.directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        projects = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SpriteProject.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
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
                try encoder.encode(project).write(to: fileURL(for: id), options: .atomic)
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
    func add(_ newProjects: [SpriteProject]) {
        for (i, var p) in newProjects.enumerated() {
            p.modifiedAt = Date(timeIntervalSinceNow: -Double(newProjects.count - i))
            save(p)
        }
        projects.sort { $0.modifiedAt > $1.modifiedAt }
    }

    func duplicate(id: UUID, name: (String) -> String = { "\($0) copy" }) {
        guard let p = project(id: id) else { return }
        save(p.duplicated(name: name(p.name)))
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
            try? FileManager.default.removeItem(at: url)
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
