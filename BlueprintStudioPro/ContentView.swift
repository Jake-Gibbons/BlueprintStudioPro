import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @EnvironmentObject var floorPlan: Floorplan
    @State private var selectedTool: EditorTool = .select
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
    
    // Exporters
    @State private var isExportingJSON: Bool = false
    @State private var exportJSONDoc = FloorPlanDocument(data: Data())
    
    @State private var showShare: Bool = false
    @State private var shareURL: URL?
    
    // Projects
    @StateObject private var projectStore = ProjectStore()
    @State private var showProjectsSheet = false
    
    // Rename project
    @State private var showRenameAlert: Bool = false
    @State private var pendingProjectName: String = ""
    
    // Rename room
    @State private var showRenameRoomAlert: Bool = false
    @State private var pendingRoomName: String = ""
    
    // Confirm new
    @State private var confirmNewProject: Bool = false
    
    @State private var lastExportURL: URL? = nil
    @State private var showDocLauncher = false
    
    @State private var selectedDoorType: String = ""
    @State private var selectedWindowType: String = ""
    
    // Visual height target for the tool row
    private let toolsRowHeight: CGFloat = 74
    
    var body: some View {
        ZStack {
            // Canvas
            FloorPlanView(
                currentTool: $selectedTool,
                snapToGrid: $snapToGrid,
                showDimensions: $showDimensions
            )
            .environmentObject(floorPlan)
            .ignoresSafeArea()
        }
        // Pills at the top corners
        .overlay(projectPill
                    .scaleEffect(0.9, anchor: .topLeading)
                    .contentShape(Rectangle())
                    .compositingGroup(),
                 alignment: .topLeading)

        .overlay(floorPill
                    .scaleEffect(0.9, anchor: .topTrailing)
                    .contentShape(Rectangle())
                    .compositingGroup(),
                 alignment: .topTrailing)
        
        
        // Bottom stack: Category (top), Tools (middle), Utilities (bottom)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                categorySelector
                toolsTray
                utilityBar
                    .scaleEffect(0.9, anchor: .bottom)
                    .contentShape(Rectangle())        // keeps a big tappable area
                    .padding(.vertical, 2)            // tiny buffer so it’s not “too low”
                    .compositingGroup()               // cleaner blur with materials when scaled

            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        
        // Sheets / alerts
        .fileExporter(
            isPresented: $isExportingJSON,
            document: exportJSONDoc,
            contentType: .json,
            defaultFilename: "floorplan.json"
        ) {
            _ in
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(activityItems: [url]).ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showProjectsSheet) {
            ProjectsView(store: projectStore).environmentObject(floorPlan)
        }
        .sheet(isPresented: $showDocLauncher) {
            if let url = lastExportURL {
                DocumentLauncher(url: url).ignoresSafeArea()
            }
        }
        .alert("Rename Project", isPresented: $showRenameAlert) {
            TextField("Project name", text: $pendingProjectName)
            Button("Cancel", role: .cancel) { }
            Button("Save") { projectName = pendingProjectName }
        } message: { Text("Enter a name for this project.") }
            .alert("Rename Room", isPresented: $showRenameRoomAlert) {
                TextField("Room name", text: $pendingRoomName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    floorPlan
                        .renameSelectedRoom(
                            to: pendingRoomName
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                }
            } message: { Text("Give this room a name.") }
            .confirmationDialog(
                "Start a new project? The current plan will be cleared.",
                isPresented: $confirmNewProject,
                titleVisibility: .visible
            ) {
                Button("Start New Project", role: .destructive) {
                    floorPlan.resetProject()
                    projectName = "Untitled Project"
                }
                Button("Cancel", role: .cancel) { }
            }
    }
    
    // MARK: - Bottom components (ordered via safeAreaInset)
    
    private var categorySelector: some View {
        Picker("Category", selection: $category) {
            ForEach(Category.allCases) { cat in
                Text(cat.rawValue).tag(cat)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
    }
    
    private var toolsTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                switch category {
                case .edit:
                    editToolsRow
                case .build:
                    buildToolsRow
                case .openings:
                    openingsToolsRow
                case .view:
                    viewToolsRow
                }
            }
            .frame(minHeight: toolsRowHeight, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        )
    }
    
    private var utilityBar: some View {
        HStack(spacing: 10) {
            IconBarButton(systemName: "arrow.uturn.backward", enabled: true) {
                floorPlan.undo()
            }
            IconBarButton(systemName: "arrow.uturn.forward", enabled: true) {
                floorPlan.redo()
            }
            
            let hasSelection = (
                floorPlan.selectedRoomID != nil
            ) || !floorPlan.selectedRoomIDs.isEmpty
            IconBarButton(
                systemName: "trash",
                enabled: hasSelection,
                isDestructive: true
            ) {
                floorPlan.deleteSelectedRooms()
            }
            
            // Rename selected room (single-active target)
            IconBarButton(
                systemName: "text.cursor",
                enabled: floorPlan.activeRoomID != nil
            ) {
                if let rid = floorPlan.activeRoomID,
                   let room = floorPlan.rooms.first(where: { $0.id == rid }) {
                    pendingRoomName = room.name
                } else { pendingRoomName = "" }
                showRenameRoomAlert = true
            }
            
            // === EXPORTS ===
            IconBarButton(systemName: "curlybraces.square", enabled: true) {
                if let url = makeTemporaryExportFileJSON() {
                    shareURL = url
                    lastExportURL = url
                    showShare = true
                }
            }
            IconBarButton(
                systemName: "photo.on.rectangle.angled",
                enabled: true
            ) {
                if let url = makeTemporaryExportPNG() {
                    shareURL = url
                    lastExportURL = url
                    showShare = true
                }
            }
            IconBarButton(systemName: "square.grid.3x3.square", enabled: true) {
                if let url = makeTemporaryExportDXF() {
                    shareURL = url
                    lastExportURL = url
                    showShare = true
                }
            }
            
            // Quick open last export
            IconBarButton(
                systemName: "square.and.arrow.up.on.square",
                enabled: lastExportURL != nil
            ) {
                showDocLauncher = (lastExportURL != nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
    }
    
    // MARK: - Pills
    private var projectPill: some View {
        HStack {
            Menu {
                Section("Project") {
                    Button {
                        confirmNewProject = true
                    } label: {
                        Label("New Project", systemImage: "doc.badge.plus")
                    }
                    
                    Button {
                        exportJSONDoc = FloorPlanDocument(
                            data: floorPlan.projectData()
                        )
                        isExportingJSON = true
                    } label: {
                        Label(
                            "Save (Full JSON)",
                            systemImage: "square.and.arrow.down.on.square"
                        )
                    }
                    
                    Button {
                        showProjectsSheet = true
                    } label: {
                        Label("Open / Manage Projects", systemImage: "folder")
                    }
                    
                    Button {
                        if let url = makeTemporaryExportFileJSON() {
                            shareURL = url; showShare = true
                        }
                    } label: {
                        Label(
                            "Export JSON (Vertices Only)",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    
                    Button {
                        if let url = makeTemporaryExportPNG() {
                            shareURL = url; showShare = true
                        }
                    } label: {
                        Label(
                            "Export PNG",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    
                    Button {
                        if let url = makeTemporaryExportDXF() {
                            shareURL = url; showShare = true
                        }
                    } label: {
                        Label(
                            "Export DXF",
                            systemImage: "square.grid.3x3.square"
                        )
                    }
                }
                Section {
                    Button {
                        pendingProjectName = projectName
                        showRenameAlert = true
                    } label: { Label("Rename Project", systemImage: "pencil") }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "house.lodge")
                    Text(projectName)
                        .fontWeight(.semibold)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.footnote)
                }
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
        }
        .padding([.top, .leading], 16)
    }
    
    private var floorPill: some View {
        HStack {
            Spacer()
            Menu {
                Section("Floors") {
                    ForEach(floorPlan.floors) { floor in
                        Button {
                            if selectedTool == .resize {
                                selectedTool = .select
                            }
                            floorPlan.switchToFloor(floor.id)
                        } label: {
                            if floorPlan
                                .floors[floorPlan.currentFloorIndex].id == floor.id {
                                Label(floor.name, systemImage: "checkmark")
                            } else { Text(floor.name) }
                        }
                    }
                }
                Section {
                    Button {
                        if selectedTool == .resize { selectedTool = .select }
                        floorPlan.addFloor()
                    } label: { Label("Add Floor", systemImage: "plus") }
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
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.footnote)
                }
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding([.top, .trailing], 16)
    }
    
    // MARK: - Export helpers
    private func makeTemporaryExportFileJSON() -> URL? {
        let data = floorPlan.exportData()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "floorplan-\(UUID().uuidString).json"
        )
        do { try data.write(to: url, options: .atomic); return url } catch {
            return nil
        }
    }
    
    private func makeTemporaryExportPNG() -> URL? {
        let logicalSize = CGSize(width: UIScreen.main.bounds.width,
                                 height: UIScreen.main.bounds.height)
        let opts = VectorPNGExporter.Options(
            showGrid: false,
            showDimensions: showDimensions,
            background: CGColor(gray: 1.0, alpha: 1.0),
            externalWallWidth: 5,
            internalWallWidth: 2.5,
            margin: 32,
            gridStepMeters: 1.0,
            imageScale: 2.0
        )
        guard let data = VectorPNGExporter.makePNG(
            floors: floorPlan.floors,
            targetSize: logicalSize,
            opts: opts
        ) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floorplan-\(UUID().uuidString).png")
        try? data.write(to: url)
        return url
    }
    
    private func makeTemporaryExportDXF() -> URL? {
        let data = DXFExporter.makeDXF(floors: floorPlan.floors)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "floorplan-\(UUID().uuidString).dxf"
        )
        do { try data.write(to: url, options: .atomic); return url } catch {
            return nil
        }
    }
    
    // MARK: - Small UI bits
    private struct WallTypeChip: View {
        let title: String
        let isActive: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        isActive ? Color.accentColor.opacity(0.18) : Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isActive ? Color.accentColor
                                    .opacity(0.6) : Color.gray
                                    .opacity(0.25),
                                lineWidth: 1
                            )
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
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
                    .background(
                        isOn ? Color.accentColor
                            .opacity(0.20) : Color.gray
                            .opacity(0.15),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(isOn ? "On" : "Off"))
        }
    }

    
    private struct ToolButton: View {
        let tool: EditorTool
        @Binding var selectedTool: EditorTool
        let systemName: String
        var enabled: Bool = true
        
        var body: some View {
            Button {
                if enabled { selectedTool = tool }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: systemName).imageScale(.large)
                    Text(tool.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(minWidth: 58)
                .background(
                    selectedTool == tool ? Color.accentColor
                        .opacity(0.18) : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            selectedTool == tool ? Color.accentColor
                                .opacity(0.6) : Color.gray
                                .opacity(0.25),
                            lineWidth: 1
                        )
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
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
                    .foregroundStyle(
                        isDestructive ? (enabled ? .red : .gray) : .primary
                            .opacity(enabled ? 1 : 0.6)
                    )
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .disabled(!enabled)
            .buttonStyle(.plain)
            .accessibilityHidden(!enabled)
        }
    }
    
    // MARK: - Tool Rows
    @ViewBuilder
    private var editToolsRow: some View {
        ToolButton(
            tool: .select,
            selectedTool: $selectedTool,
            systemName: "cursorarrow"
        )
        ToolButton(tool: .resize, selectedTool: $selectedTool, systemName: "square.and.pencil.circle",
                   enabled: floorPlan.activeRoomID != nil)
        ToolButton(tool: .duplicate, selectedTool: $selectedTool, systemName: "doc.on.doc",
                   enabled: floorPlan.activeRoomID != nil)
        ToolButton(tool: .rotate, selectedTool: $selectedTool, systemName: "rotate.right",
                   enabled: floorPlan.activeRoomID != nil)
        ToolButton(
tool: .delete,
selectedTool: $selectedTool,
systemName: "trash",
enabled: (
    floorPlan.activeRoomID != nil
) || !floorPlan.selectedRoomIDs.isEmpty
        )
        
        if let rid = floorPlan.activeRoomID,
           let w = floorPlan.selectedWallIndex,
           let room = floorPlan.rooms.first(where: { $0.id == rid }),
           room.vertices.indices.contains(w) {
            Divider().frame(height: 24)
            Text("Wall:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .fixedSize()
            WallTypeChip(
                title: "Internal",
                isActive: room.wallTypes.indices
                    .contains(w) ? (room.wallTypes[w] == .internalWall) : false,
                action: { floorPlan.setSelectedWallType(.internalWall) }
            )
            WallTypeChip(
                title: "External",
                isActive: room.wallTypes.indices
                    .contains(w) ? (room.wallTypes[w] == .externalWall) : true,
                action: { floorPlan.setSelectedWallType(.externalWall) }
            ).fixedSize()
        }
    }
    
    @ViewBuilder
    private var buildToolsRow: some View {
        ToolButton(
            tool: .drawRoom,
            selectedTool: $selectedTool,
            systemName: "square.dashed"
        )
        ToolButton(
            tool: .drawWall,
            selectedTool: $selectedTool,
            systemName: "scribble"
        )
    }
    
    @ViewBuilder
    private var openingsToolsRow: some View {
        // Doors
        Menu {
            Button("Single Door") {
                selectedTool = .addDoor; selectedDoorType = "single"
            }
            Button("Double Door") {
                selectedTool = .addDoor; selectedDoorType = "double"
            }
            Button("Door with Side Window") {
                selectedTool = .addDoor; selectedDoorType = "sideLight"
            }
        } label: {
            ToolButton(
                tool: .addDoor,
                selectedTool: $selectedTool,
                systemName: "door.left.hand.open"
            )
        }
        // Windows
        Menu {
            Button("Single Window") {
                selectedTool = .addWindow; selectedWindowType = "single"
            }
            Button("Double Window") {
                selectedTool = .addWindow; selectedWindowType = "double"
            }
            Button("Triple Window") {
                selectedTool = .addWindow; selectedWindowType = "triple"
            }
            Button("Picture Window") {
                selectedTool = .addWindow; selectedWindowType = "picture"
            }
        } label: {
            ToolButton(
                tool: .addWindow,
                selectedTool: $selectedTool,
                systemName: "rectangle.split.2x1"
            )
        }
    }
    
    @ViewBuilder
    private var viewToolsRow: some View {
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
    }
}

#Preview {
    ContentView().environmentObject(Floorplan())
}
