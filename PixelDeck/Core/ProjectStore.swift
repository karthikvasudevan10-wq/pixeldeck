import Foundation
import Observation

/// Keeps every sprite as a JSON file in the app's Documents/Sprites folder.
@Observable
final class ProjectStore {
    private(set) var projects: [SpriteProject] = []

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let io = DispatchQueue(label: "PixelDeck.ProjectStore", qos: .utility)

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

    @discardableResult
    func create(size: Int) -> SpriteProject {
        let p = SpriteProject(name: nextName(), size: size)
        save(p)
        return p
    }

    func save(_ p: SpriteProject) {
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            projects[i] = p
        } else {
            projects.insert(p, at: 0)
        }
        let url = fileURL(for: p.id)
        io.async {
            guard let data = try? JSONEncoder().encode(p) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func duplicate(id: UUID) {
        guard let p = project(id: id) else { return }
        save(p.duplicated(name: p.name + " copy"))
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
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Blocks until pending writes are on disk. Used by tests and when the app goes to the background.
    func flush() {
        io.sync {}
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func nextName() -> String {
        let names = Set(projects.map(\.name))
        var n = projects.count + 1
        while names.contains("Sprite \(n)") { n += 1 }
        return "Sprite \(n)"
    }
}
