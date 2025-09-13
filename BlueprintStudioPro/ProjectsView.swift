import SwiftUI

struct ProjectsView: View {
    @ObservedObject var store: ProjectStore
    @EnvironmentObject var floorPlan: Floorplan
    @Environment(\.dismiss) private var dismiss

    @State private var selection: ProjectStore.Project? = nil
    @State private var newName: String = ""
    @State private var showNewAlert = false
    @State private var showSaveAsAlert = false
    @State private var renameTarget: ProjectStore.Project? = nil
    @State private var renameText: String = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(store.projects) { p in
                        Button {
                            selection = p
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.name).font(.headline)
                                    Text(p.modified.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .contextMenu {
                            Button("Rename") {
                                renameTarget = p
                                renameText = p.name
                            }
                            Button("Delete", role: .destructive) {
                                store.delete(project: p)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("New") { showNewAlert = true }
                    Button("Save") {
                        if let sel = selection {
                            store.save(project: sel, from: floorPlan)
                        } else {
                            store.newProject(named: "Untitled", from: floorPlan)
                        }
                    }
                    Button("Save As") { showSaveAsAlert = true }
                }
            }
            .alert("New Project", isPresented: $showNewAlert) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    store.newProject(named: newName.isEmpty ? "Untitled" : newName, from: floorPlan)
                    newName = ""
                }
            } message: { Text("Create a new project from the current canvas.") }
            .alert("Save As", isPresented: $showSaveAsAlert) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    store.saveAs(name: newName.isEmpty ? "Untitled" : newName, from: floorPlan)
                    newName = ""
                }
            } message: { Text("Save a copy of the current project.") }
            .alert("Rename Project", isPresented: .constant(renameTarget != nil)) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") {
                    if let target = renameTarget {
                        store.rename(project: target, to: renameText)
                    }
                    renameTarget = nil
                }
            } message: { Text("Rename the selected project.") }
            .onChange(of: selection) { p in
                guard let p else { return }
                try? store.load(project: p, into: floorPlan)
            }
        }
    }
}
