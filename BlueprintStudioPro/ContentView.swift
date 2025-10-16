import SwiftUI
import UniformTypeIdentifiers
import Combine

/// The main entry point for Blueprint Studio Pro's user interface. This
/// view coordinates the underlying `Floorplan` model with editing tools,
/// categories, export operations and contextual overlays like the project
/// and floor selectors. It uses environment objects to share the model
/// across subviews and maintains local state for UI affordances such as
/// which editor tool is currently active, whether dimensions are shown
/// and whether snap‑to‑grid is enabled. The view is split into logical
/// sections via private computed properties to keep the `body` relatively
/// concise.
struct ContentView: View {
    @EnvironmentObject var floorPlan: Floorplan
    @State private var selectedTool: EditorTool = .select
    @State private var snapToGrid: Bool = true
    @State private var projectName: String = "Blueprint Studio Pro"
    
    @StateObject private var settings = AppSettings()   // <-- ADD
    @State private var showSettings: Bool = false       // <-- ADD
    
    /// Categories used to drive the tools tray. Each category corresponds
    /// to a row of tools appropriate for editing, building, openings or view
    /// settings.
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
    
    // Track the selected opening types from the tools menus. These strings
    // map to the `DoorType` and `WindowType` enums and are passed down to
    // `FloorPlanView` so that taps can insert the appropriate attachment.
    @State private var selectedDoorType: String = ""
    @State private var selectedWindowType: String = ""
    
    // Room inspector
    @State private var showRoomInspector: Bool = false
    
    // Visual height target for the tool row
    private let toolsRowHeight: CGFloat = 74
    
    var body: some View {
        ZStack {
            // Canvas
            FloorPlanView(
                currentTool: $selectedTool,
                snapToGrid: $snapToGrid,
                showDimensions: $settings.showDimensions,
                selectedDoorType: $selectedDoorType,
                selectedWindowType: $selectedWindowType
            )
            .environmentObject(floorPlan)
            .environmentObject(settings)
            .ignoresSafeArea()
        }
        // Pills at the top corners
        .overlay(
            // Present the project pill.  Wrap it in a content shape and
            // compositing group so that the `Menu` receives taps reliably,
            // mirroring the floor pill.
            projectPill
                .scaleEffect(0.9, anchor: .topLeading)
                .contentShape(Rectangle())
                .compositingGroup(),
            alignment: .topLeading
        )
        .overlay(floorPill.scaleEffect(0.9, anchor: .topTrailing)
            .contentShape(Rectangle())
            .compositingGroup(),
                 alignment: .topTrailing)
        // Room Info pill (shows only when exactly one room selected)
        .overlay(roomInfoPill, alignment: .topTrailing)
        
        // Bottom stack: Category (top), Tools (middle), Utilities (bottom)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                categorySelector
                toolsTray
                utilityBar
                    .scaleEffect(0.9, anchor: .bottom)
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                    .compositingGroup()
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
        .sheet(isPresented: $showRoomInspector) {
            if let rid = singleSelectedRoomID,
               let room = $floorPlan.room(withID: rid) {
                RoomInspectorView(room: room)
                    .environmentObject(floorPlan)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            } else {
                Text("No room selected.")
                    .font(.headline)
                    .padding()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(floorPlan)
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
    
    // Single selected room helper
    private var singleSelectedRoomID: UUID? {
        if let active = floorPlan.activeRoomID { return active }
        if floorPlan.selectedRoomIDs.count == 1 { return floorPlan.selectedRoomIDs.first }
        if let single = floorPlan.selectedRoomID { return single }
        return nil
    }
    
    // MARK: - Top-right Room Info pill (under floor pill)
    private var roomInfoPill: some View {
        Group {
            if singleSelectedRoomID != nil {
                HStack {
                    Spacer()
                    Button {
                        showRoomInspector = true
                    } label: {
                        Label("Room Info", systemImage: "info.circle")
                            .font(.system(.subheadline, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                // push under the floor pill
                .padding(.trailing, 16)
                .padding(.top, 64) // ~48 pill + spacing
            }
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
                floorPlan.activeRoomID != nil
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
        Menu {
            // Primary project section containing settings and export options
            Section("Project") {
                // Settings button
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                
                // Secondary section for new project and export commands
                Section {
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
            }
            // Rename project section
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
            showDimensions: settings.showDimensions,
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
        ToolButton(
            tool: .addStairs,
            selectedTool: $selectedTool,
            systemName: "stair.circle"
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
            ToggleChip(isOn: $settings.showDimensions,
                       label: "Dimensions",
                       onIcon: "ruler.fill",
                       offIcon: "ruler")
        }
    }
    
    // MARK: - Previews
    #Preview {
        ContentView().environmentObject(Floorplan())
    }
    
    // MARK: - Room Inspector Sheet
    private struct RoomInspectorView: View {
        @EnvironmentObject var floorPlan: Floorplan
        @Environment(\.dismiss) private var dismiss
        let room: Room
        
        @State private var floorName: String = ""
        @State private var wallTexts: [String] = []
        
        var body: some View {
            NavigationView {
                List {
                    Section("Floor") {
                        TextField("Floor name", text: $floorName)
                            .onSubmit {
                                floorPlan.renameCurrentFloor(to: floorName)
                            }
                    }
                    
                    Section("Walls (meters)") {
                        // Loop through each wall index using its own index as the identifier. This
                        // closure has been formatted on a single line to avoid accidental line
                        // breaks that can corrupt the `id` parameter syntax.
                        ForEach(wallIndices, id: \.self) { i in
                            HStack {
                                Text("Wall \(i + 1)")
                                Spacer()
                                TextField("\(wallLength(i), specifier: "%.2f")",
                                          text: $wallTexts[i],
                                          onCommit: { applyWallChange(i) })
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 100)
                            }
                        }
                    }
                }
                .navigationTitle(room.name.isEmpty ? "Room" : room.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            // Apply pending floor rename if edited
                            floorPlan.renameCurrentFloor(to: floorName)
                            // Dismiss the sheet
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                floorName = floorPlan.floors[floorPlan.currentFloorIndex].name
                wallTexts = wallIndices.map { String(format: "%.2f", wallLength($0)) }
            }
        }
        
        private var wallIndices: [Int] { Array(0..<room.vertices.count) }
        
        private func wallLength(_ i: Int) -> CGFloat {
            guard room.vertices.count >= 2 else { return 0 }
            let a = room.vertices[i]
            let b = room.vertices[(i + 1) % room.vertices.count]
            return hypot(b.x - a.x, b.y - a.y)
        }
        
        private func applyWallChange(_ i: Int) {
            let raw = wallTexts[i].replacingOccurrences(of: ",", with: ".")
            guard let newLen = Double(raw), newLen > 0 else {
                wallTexts[i] = String(format: "%.2f", wallLength(i))
                return
            }
            $floorPlan.setWallLength(roomID: room.id, wallIndex: i, newLength: CGFloat(newLen))
            // refresh displayed lengths from model
            if let updated = $floorPlan.room(withID: room.id) {
                let lens = (0..<updated.vertices.count).map { idx -> String in
                    let a = updated.vertices[idx]
                    let b = updated.vertices[(idx + 1) % updated.vertices.count]
                    let m = hypot(b.x - a.x, b.y - a.y)
                    return String(format: "%.2f", m)
                }
                wallTexts = lens
            }
        }
    }
    
    // MARK: - Convenience operations on Floorplan used by the inspector
    extension Floorplan {
        /// Returns a copy of the room with the given id.
        func room(withID id: UUID) -> Room? {
            rooms.first(where: { $0.id == id })
        }
        
        /// Sets a wall's length by moving one endpoint along its current direction.
        /// - Parameters:
        ///   - roomID: room identifier
        ///   - wallIndex: index of the wall (edge from vertex i to i+1)
        ///   - newLength: new length in model meters (> 0)
        ///   - anchorAtStart: if `true`, keeps vertex i fixed and moves i+1. If `false`, keeps i+1 fixed and moves i.
        func setWallLength(roomID: UUID, wallIndex: Int, newLength: CGFloat, anchorAtStart: Bool = true) {
            guard newLength > 0,
                  let rIndex = rooms.firstIndex(where: { $0.id == roomID }) else { return }
            var room = rooms[rIndex]
            guard room.vertices.count >= 2 else { return }
            
            let i1 = wallIndex
            let i2 = (wallIndex + 1) % room.vertices.count
            let a = room.vertices[i1]
            let b = room.vertices[i2]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            guard len > 0 else { return }
            let ux = dx / len, uy = dy / len
            
            saveToHistory()
            if anchorAtStart {
                room.vertices[i2] = CGPoint(x: a.x + ux * newLength, y: a.y + uy * newLength)
            } else {
                room.vertices[i1] = CGPoint(x: b.x - ux * newLength, y: b.y - uy * newLength)
            }
            rooms[rIndex] = room
            objectWillChange.send()
        }
    }
}
