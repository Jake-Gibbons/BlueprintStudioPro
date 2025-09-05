import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var floorPlan: FloorPlan
    @State private var selectedTool: Tool = .select
    @State private var snapToGrid: Bool = true
    @State private var showDimensions: Bool = true
    @State private var projectName: String = "Blueprint Studio Pro"

    enum Category: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case build = "Build"
        case openings = "Openings"
        case view = "View"
        var id: String { rawValue }
    }
    @State private var category: Category = .edit

    @State private var isExporting: Bool = false
    @State private var exportDoc = FloorPlanDocument(data: Data())
    @State private var showShare: Bool = false
    @State private var shareURL: URL?

    @State private var showRenameAlert: Bool = false
    @State private var pendingProjectName: String = ""

    @State private var confirmNewProject: Bool = false

    var body: some View {
        ZStack {
            FloorPlanView(currentTool: $selectedTool,
                          snapToGrid: $snapToGrid,
                          showDimensions: $showDimensions)
                .environmentObject(floorPlan)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                Spacer()

                Picker("Category", selection: $category) {
                    ForEach(Category.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                HStack(spacing: 12) {
                    switch category {
                    case .edit:
                        ToolButton(tool: .select, selectedTool: $selectedTool, systemName: "cursorarrow")
                        ToolButton(tool: .resize, selectedTool: $selectedTool, systemName: "square.and.pencil.circle",
                                   enabled: floorPlan.selectedRoomID != nil)
                        ToolButton(tool: .delete, selectedTool: $selectedTool, systemName: "trash",
                                   enabled: floorPlan.selectedRoomID != nil)
                        Spacer()
                    case .build:
                        ToolButton(tool: .drawRoom, selectedTool: $selectedTool, systemName: "square.dashed")
                        ToolButton(tool: .drawWall, selectedTool: $selectedTool, systemName: "scribble")
                        Spacer()
                    case .openings:
                        let hasAnyRoom = !floorPlan.rooms.isEmpty
                        ToolButton(tool: .addWindow, selectedTool: $selectedTool, systemName: "rectangle.split.2x1", enabled: hasAnyRoom)
                        ToolButton(tool: .addDoor, selectedTool: $selectedTool, systemName: "door.left.hand.open", enabled: hasAnyRoom)
                        Spacer()
                    case .view:
                        HStack(spacing: 10) {
                            ToggleChip(isOn: $snapToGrid,
                                       label: "Snap to Grid",
                                       onIcon: "square.grid.3x3.fill",
                                       offIcon: "square.grid.3x3")
                            ToggleChip(isOn: $showDimensions,
                                       label: "Dimensions",
                                       onIcon: "ruler.fill",
                                       offIcon: "ruler")
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                // Utility bar (full-width, thin)
                HStack(spacing: 10) {
                    IconBarButton(systemName: "arrow.uturn.backward", enabled: true) { floorPlan.undo() }
                    IconBarButton(systemName: "arrow.uturn.forward", enabled: true) { floorPlan.redo() }

                    let hasSelection = (floorPlan.selectedRoomID != nil)
                    IconBarButton(systemName: "trash",
                                  enabled: hasSelection,
                                  isDestructive: true) { floorPlan.deleteSelectedRoom() }

                    IconBarButton(systemName: "square.and.arrow.up", enabled: true) {
                        if let url = makeTemporaryExportFile() {
                            shareURL = url
                            showShare = true
                        }
                    }
                    IconBarButton(systemName: "square.and.arrow.down.on.square", enabled: true) {
                        exportDoc = FloorPlanDocument(data: floorPlan.exportData())
                        isExporting = true
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
            }
        }
        // MARK: - Top overlays
        .overlay(
            // Left: branding pill -> Project menu with chevron
            HStack {
                Menu {
                    Section("Project") {
                        Button {
                            confirmNewProject = true
                        } label: {
                            Label("New Project", systemImage: "doc.badge.plus")
                        }
                        Button {
                            exportDoc = FloorPlanDocument(data: floorPlan.exportData())
                            isExporting = true
                        } label: {
                            Label("Save (Export JSON)", systemImage: "square.and.arrow.down.on.square")
                        }
                        Button {
                            if let url = makeTemporaryExportFile() {
                                shareURL = url
                                showShare = true
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Section {
                        Button {
                            pendingProjectName = projectName
                            showRenameAlert = true
                        } label: {
                            Label("Rename Project", systemImage: "pencil")
                        }
                        Button {
                            // Future Settings
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "house.lodge")
                        Text(projectName)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down")
                            .font(.footnote)
                    }
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
            }
            .padding([.top, .leading], 16),
            alignment: .topLeading
        )
        .overlay(
            // Right: Floor menu pill — just the floor label
            HStack {
                Spacer()
                Menu {
                    Section("Floors") {
                        ForEach(floorPlan.floors) { floor in
                            Button {
                                if selectedTool == .resize { selectedTool = .select }
                                floorPlan.switchToFloor(floor.id)
                            } label: {
                                if floorPlan.floors[floorPlan.currentFloorIndex].id == floor.id {
                                    Label(floor.name, systemImage: "checkmark")
                                } else {
                                    Text(floor.name)
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            if selectedTool == .resize { selectedTool = .select }
                            floorPlan.addFloor()
                        } label: {
                            Label("Add Floor", systemImage: "plus")
                        }
                        Button(role: .destructive) {
                            if selectedTool == .resize { selectedTool = .select }
                            floorPlan.deleteCurrentFloor()
                        } label: {
                            Label("Delete Current Floor", systemImage: "trash")
                        }
                        .disabled(floorPlan.floors.count <= 1)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.3.layers.3d.down.right")
                        Text(floorPlan.floors[floorPlan.currentFloorIndex].name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down")
                            .font(.footnote)
                    }
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding([.top, .trailing], 16),
            alignment: .topTrailing
        )
        // MARK: - Export / Share / Alerts
        .fileExporter(isPresented: $isExporting, document: exportDoc, contentType: .json, defaultFilename: "floorplan.json") { _ in }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(activityItems: [url]).ignoresSafeArea()
            }
        }
        .alert("Rename Project", isPresented: $showRenameAlert) {
            TextField("Project name", text: $pendingProjectName)
            Button("Cancel", role: .cancel) { }
            Button("Save") { projectName = pendingProjectName }
        } message: {
            Text("Enter a name for this project.")
        }
        .confirmationDialog("Start a new project? The current plan will be cleared.",
                            isPresented: $confirmNewProject,
                            titleVisibility: .visible) {
            Button("Start New Project", role: .destructive) {
                floorPlan.resetProject()               // ✅ Now defined on the model
                projectName = "Untitled Project"
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func makeTemporaryExportFile() -> URL? {
        let data = floorPlan.exportData()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floorplan-\(UUID().uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}

private struct ToolButton: View {
    let tool: Tool
    @Binding var selectedTool: Tool
    let systemName: String
    var enabled: Bool = true

    var body: some View {
        Button {
            if enabled { selectedTool = tool }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName).imageScale(.large)
                Text(tool.rawValue).font(.system(size: 11, weight: .semibold))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(minWidth: 58)
            .background(selectedTool == tool ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selectedTool == tool ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(enabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct IconBarButton: View {
    let systemName: String
    let enabled: Bool
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .imageScale(.large)
                .foregroundStyle(isDestructive ? (enabled ? .red : .gray) : .white.opacity(enabled ? 1 : 0.6))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDestructive && enabled ? Color.red.opacity(0.12) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
        .accessibilityHidden(!enabled)
    }
}

private struct ToggleChip: View {
    @Binding var isOn: Bool
    var label: String
    var onIcon: String
    var offIcon: String

    var body: some View {
        Button { isOn.toggle() } label: {
            Label(label, systemImage: isOn ? onIcon : offIcon)
                .font(.system(size: 14, weight: .semibold))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView().environmentObject(FloorPlan())
}
