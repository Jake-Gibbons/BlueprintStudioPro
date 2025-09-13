import Foundation
import Combine   // ✅ needed for ObservableObject

final class ProjectStore: ObservableObject {
    struct Project: Identifiable, Codable, Equatable {
        var id: UUID
        var name: String
        var filename: String // file on disk
        var modified: Date
    }

    @Published private(set) var projects: [Project] = []

    private let fm = FileManager.default
    private let dirURL: URL
    private let indexURL: URL

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        dirURL = docs.appendingPathComponent("Projects", isDirectory: true)
        indexURL = dirURL.appendingPathComponent("index.json")
        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        loadIndex()
    }

    // MARK: - Index I/O
    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { projects = []; return }
        let decoder = JSONDecoder()
        projects = (try? decoder.decode([Project].self, from: data)) ?? []
    }

    private func saveIndex() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? enc.encode(projects)) ?? Data()
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Public API
    func newProject(named name: String, from floorplan: Floorplan) {
        let id = UUID()
        let file = "project-\(id.uuidString).json"
        let url = dirURL.appendingPathComponent(file)
        try? floorplan.projectData().write(to: url, options: .atomic)
        let p = Project(id: id, name: name, filename: file, modified: Date())
        projects.append(p)
        saveIndex()
    }

    func save(project: Project, from floorplan: Floorplan) {
        let url = dirURL.appendingPathComponent(project.filename)
        try? floorplan.projectData().write(to: url, options: .atomic)
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i].modified = Date()
            saveIndex()
        }
    }

    func saveAs(name: String, from floorplan: Floorplan) {
        newProject(named: name, from: floorplan)
    }

    func load(project: Project, into floorplan: Floorplan) throws {
        let url = dirURL.appendingPathComponent(project.filename)
        let data = try Data(contentsOf: url)
        try floorplan.loadProject(from: data)
    }

    func delete(project: Project) {
        let url = dirURL.appendingPathComponent(project.filename)
        try? fm.removeItem(at: url)
        projects.removeAll { $0.id == project.id }
        saveIndex()
    }

    /// Rename a project and persist the index.
    func rename(project: Project, to newName: String) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i].name = newName.isEmpty ? projects[i].name : newName
        projects[i].modified = Date()
        saveIndex()
    }
}
