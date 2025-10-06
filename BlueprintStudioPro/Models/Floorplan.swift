import SwiftUI
import Combine

// MARK: - Core Models

/// Represents a single floor within a floorplan. Each floor has a name and a collection
/// of rooms. This struct conforms to `Codable` and `Equatable` so that it can be
/// serialized/deserialized and compared.
struct Floor: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var rooms: [Room]
    
    init(id: UUID = UUID(), name: String, rooms: [Room] = []) {
        self.id = id
        self.name = name
        self.rooms = rooms
    }
}

/// Protocol for items that attach to a room's wall (doors and windows).  It records
/// the wall index, an offset along that wall (0 to 1), and a length in meters.
protocol WallAttachment: Codable {
    var wallIndex: Int { get set }
    var offset: CGFloat { get set }
    var length: CGFloat { get set }
}

/// A door attached to a wall of a room.  Doors can be single, double or have a sidelight.
struct Door: Identifiable, WallAttachment {
    /// Default id so callers don't have to pass it
    let id: UUID = UUID()
    var wallIndex: Int
    var offset: CGFloat
    var length: CGFloat
    var type: DoorType = .single
}

/// A window attached to a wall of a room.  Windows can be single, double, triple or picture style.
struct Window: Identifiable, WallAttachment {
    /// Default id so callers don't have to pass it
    let id: UUID = UUID()
    var wallIndex: Int
    var offset: CGFloat
    var length: CGFloat
    var type: WindowType = .single
}

/// Enum describing the type of door for rendering and export.
enum DoorType: String, Codable {
    case single
    case double
    case sideLight
}

/// Enum describing window styles for drawing.
enum WindowType: String, Codable {
    case single
    case double
    case triple
    case picture
}

/// NOTE: 'internal' is a Swift access-control keyword, so we use 'internalWall' instead.
enum WallType: String, Codable {
    case internalWall
    case externalWall
}

/// A polygonal room defined by its vertices. Rooms can contain doors, windows and
/// staircases. The `Codable` conformance allows rooms to be persisted along with
/// their contents.
struct Room: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var vertices: [CGPoint]     // model space, meters
    var wallTypes: [WallType]   // per-edge, same count as vertices
    var windows: [Window] = []
    var doors: [Door] = []
    /// Staircases contained within the room. Each stairs instance
    /// references its geometry and orientation relative to this room.
    var stairs: [Stairs] = []

    // Store HSBA directly so we can round-trip without UIKit.
    private var _h: Double
    private var _s: Double
    private var _b: Double
    private var _a: Double
    
    /// Computed SwiftUI color (opacity is baked into `_a`)
    var fillColor: Color {
        Color(hue: _h, saturation: _s, brightness: _b).opacity(_a)
    }
    
    /// Designated initializer. If `hsba` is nil, a random pastel is chosen.
    init(
        id: UUID = UUID(),
        name: String = "",
        vertices: [CGPoint],
        wallTypes: [WallType]? = nil,
        hsba: (h: Double, s: Double, b: Double, a: Double)? = nil
    ) {
        self.id = id
        self.name = name
        self.vertices = vertices
        self.wallTypes = wallTypes ?? Array(repeating: .externalWall, count: max(vertices.count, 0))
        
        if let hsba {
            self._h = hsba.h
            self._s = hsba.s
            self._b = hsba.b
            self._a = hsba.a
        } else {
            let pastel = Room.randomPastelHSBA()
            self._h = pastel.h
            self._s = pastel.s
            self._b = pastel.b
            self._a = pastel.a
        }
    }
    
    /// Simple point-in-polygon test using the even–odd rule.
    func contains(point: CGPoint) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        for i in vertices.indices {
            let j = (i + vertices.count - 1) % vertices.count
            let xi = vertices[i].x, yi = vertices[i].y
            let xj = vertices[j].x, yj = vertices[j].y
            let denom = (yj - yi)
            let safeDenom: CGFloat = denom == 0 ? .leastNonzeroMagnitude : denom
            let intersect = ((yi > point.y) != (yj > point.y)) &&
            (point.x < (xj - xi) * (point.y - yi) / safeDenom + xi)
            if intersect { inside.toggle() }
        }
        return inside
    }
    
    /// Returns the index of the wall nearest a given point if within a threshold distance.
    func indexOfWall(near p: CGPoint, threshold: CGFloat) -> Int? {
        guard vertices.count >= 2 else { return nil }
        var best: (idx: Int, d: CGFloat)? = nil
        for i in vertices.indices {
            let a = vertices[i]
            let b = vertices[(i + 1) % vertices.count]
            let d = distancePointToSegment(p, a, b)
            if d <= threshold, (best == nil || d < best!.d) {
                best = (i, d)
            }
        }
        return best?.idx
    }
    
    /// Builds a SwiftUI `Path` from this room's vertices using a provided transform.
    func path(using transform: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        guard let first = vertices.first else { return path }
        path.move(to: transform(first))
        for v in vertices.dropFirst() { path.addLine(to: transform(v)) }
        path.closeSubpath()
        return path
    }
    
    // MARK: - Color helpers (UIKit-free)
    
    /// Random soft/pastel HSBA with low opacity for pleasant room fills.
    static func randomPastelHSBA() -> (h: Double, s: Double, b: Double, a: Double) {
        let h = Double.random(in: 0...1)
        let s = Double.random(in: 0.35...0.55)
        let b = Double.random(in: 0.92...1.0)
        let a = 0.10
        return (h, s, b, a)
    }
    
    // Hashable/Equatable by id
    static func == (lhs: Room, rhs: Room) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Geometry utility

fileprivate func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ax = b.x - a.x, ay = b.y - a.y
    let denom = ax*ax + ay*ay
    if denom == 0 { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * ax + (p.y - a.y) * ay) / denom))
    let proj = CGPoint(x: a.x + t * ax, y: a.y + t * ay)
    return hypot(p.x - proj.x, p.y - proj.y)
}

// MARK: - Editor Tools

enum EditorTool: String, CaseIterable, Identifiable {
    case select  = "Select"
    case delete  = "Delete"
    case drawWall = "Draw Wall"
    case drawRoom = "Draw Room"
    case addWindow = "Window"
    case addDoor  = "Door"
    case addStairs = "Stairs"
    case resize   = "Resize"
    case duplicate = "Duplicate"
    case rotate    = "Rotate"
    var id: String { rawValue }
}

// MARK: - Floorplan (ObservableObject)

/// The root model holding all floors and rooms for a project.  This class also manages
/// selection state, undo/redo stacks and helper methods for modifying rooms.
final class Floorplan: ObservableObject {
    
    // Floors
    @Published var floors: [Floor] = [Floor(name: "Ground Floor")]
    @Published var currentFloorIndex: Int = 0
    
    // Convenience for current floor rooms
    var rooms: [Room] {
        get { floors[currentFloorIndex].rooms }
        set { objectWillChange.send(); floors[currentFloorIndex].rooms = newValue }
    }
    
    // Selection (legacy + multi)
    @Published var selectedRoomID: UUID? = nil
    @Published var selectedWallIndex: Int? = nil
    @Published var selectedRoomIDs: Set<UUID> = []
    
    /// The room ID to use for single-target actions (wall ops, etc.)
    var activeRoomID: UUID? { selectedRoomID ?? selectedRoomIDs.first }
    
    func selectOnly(_ id: UUID?) {
        selectedRoomID = id
        selectedRoomIDs = id.map { [$0] } ?? []
        selectedWallIndex = nil
    }
    
    func toggleSelect(_ id: UUID) {
        if selectedRoomIDs.contains(id) {
            selectedRoomIDs.remove(id)
        } else {
            selectedRoomIDs.insert(id)
        }
        selectedRoomID = nil
        selectedWallIndex = nil
    }
    
    func clearSelection() {
        selectedRoomID = nil
        selectedRoomIDs.removeAll()
        selectedWallIndex = nil
    }
    
    /// Delete all selected rooms (multi and legacy single)
    func deleteSelectedRooms() {
        let ids = selectedRoomIDs.union(selectedRoomID.map { Set([$0]) } ?? [])
        guard !ids.isEmpty else { return }
        saveToHistory()
        rooms.removeAll { ids.contains($0.id) }
        clearSelection()
    }
    
    // History
    private var undoStack: [[Floor]] = []
    private var redoStack: [[Floor]] = []
    
    // MARK: - Floor management
    func addFloor() {
        saveToHistory()
        floors.append(Floor(name: "New Floor"))
        currentFloorIndex = floors.count - 1
        clearSelection()
    }
    
    func deleteCurrentFloor() {
        guard floors.count > 1 else { return }
        saveToHistory()
        floors.remove(at: currentFloorIndex)
        currentFloorIndex = max(0, currentFloorIndex - 1)
        clearSelection()
    }
    
    func switchToFloor(_ id: UUID) {
        if let idx = floors.firstIndex(where: { $0.id == id }) {
            currentFloorIndex = idx
            clearSelection()
        }
    }
    
    func resetProject() {
        saveToHistory()
        floors = [Floor(name: "Ground Floor")]
        currentFloorIndex = 0
        clearSelection()
        redoStack.removeAll()
    }
    
    /// Rename the current floor to the provided name.
    func renameCurrentFloor(to newName: String) {
        guard floors.indices.contains(currentFloorIndex) else { return }
        saveToHistory()
        floors[currentFloorIndex].name = newName
    }
    
    // MARK: - Room ops
    func addRoom(vertices: [CGPoint]) {
        saveToHistory()
        rooms.append(Room(vertices: vertices))
    }

    /// Adds a rectangular room at the given centre point.  A default room is
    /// 4 m wide and 4 m deep, but you can supply a custom size.  The room is
    /// axis aligned in model space.
    ///
    /// - Parameters:
    ///   - center: The centre of the new room in model metres.
    ///   - size: The dimensions of the room in metres (width and height).  Default
    ///     is 4×4.
    func addRoom(at center: CGPoint, size: CGSize = CGSize(width: 4.0, height: 4.0)) {
        let halfW = size.width / 2.0
        let halfH = size.height / 2.0
        let vertices = [
            CGPoint(x: center.x - halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y + halfH),
            CGPoint(x: center.x - halfW, y: center.y + halfH)
        ]
        addRoom(vertices: vertices)
    }
    
    func addNamedRoom(_ name: String, vertices: [CGPoint]) {
        saveToHistory()
        var r = Room(vertices: vertices)
        r.name = name
        rooms.append(r)
    }
    
    func selectRoom(containing point: CGPoint) {
        for r in rooms.reversed() {
            if r.contains(point: point) { selectOnly(r.id); return }
        }
        clearSelection()
    }
    
    func selectWall(near point: CGPoint, threshold: CGFloat) {
        guard let id = activeRoomID,
              let idx = rooms.firstIndex(where: { $0.id == id }) else {
            selectedWallIndex = nil; return
        }
        selectedWallIndex = rooms[idx].indexOfWall(near: point, threshold: threshold)
    }
    
    func deleteSelectedRoom() {
        guard let id = selectedRoomID, let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        saveToHistory()
        rooms.remove(at: idx)
        clearSelection()
    }
    
    func renameSelectedRoom(to newName: String) {
        guard let id = activeRoomID,
              let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        saveToHistory()
        rooms[idx].name = newName
    }
    
    func setSelectedWallType(_ type: WallType) {
        guard let rid = activeRoomID,
              let wIndex = selectedWallIndex,
              let idx = rooms.firstIndex(where: { $0.id == rid }),
              rooms[idx].vertices.indices.contains(wIndex) else { return }
        saveToHistory()
        if rooms[idx].wallTypes.count != rooms[idx].vertices.count {
            rooms[idx].wallTypes = Array(repeating: .externalWall, count: rooms[idx].vertices.count)
        }
        rooms[idx].wallTypes[wIndex] = type
    }
    
    func addWindow(at offset: CGFloat) {
        guard let rid = activeRoomID,
              let wIndex = selectedWallIndex,
              let idx = rooms.firstIndex(where: { $0.id == rid }) else { return }
        saveToHistory()
        var r = rooms[idx]
        r.windows.append(Window(wallIndex: wIndex, offset: offset, length: 1.0))
        rooms[idx] = r
    }
    
    func addDoor(at offset: CGFloat) {
        guard let rid = activeRoomID,
              let wIndex = selectedWallIndex,
              let idx = rooms.firstIndex(where: { $0.id == rid }) else { return }
        saveToHistory()
        var r = rooms[idx]
        r.doors.append(Door(wallIndex: wIndex, offset: offset, length: 0.9))
        rooms[idx] = r
    }
    
    // MARK: - History
    func saveToHistory() { undoStack.append(floors); redoStack.removeAll() }
    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(floors); floors = last
        clearSelection()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(floors); floors = next
        clearSelection()
    }
    
    // MARK: - Extra tools
    func duplicateSelectedRoom() {
        guard let id = activeRoomID,
              let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        saveToHistory()
        let original = rooms[idx]
        var newRoom = Room(
            id: UUID(),
            name: original.name.isEmpty ? "" : "\(original.name) Copy",
            vertices: original.vertices.map { CGPoint(x: $0.x + 2, y: $0.y + 2) },
            wallTypes: original.wallTypes
        )
        newRoom.windows = original.windows
        newRoom.doors = original.doors
        newRoom.stairs = original.stairs
        rooms.append(newRoom)
        selectOnly(newRoom.id)
    }
    
    func rotateSelectedRoom() {
        guard let id = activeRoomID,
              let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        saveToHistory()
        var room = rooms[idx]
        let cx = room.vertices.map(\.x).reduce(0, +) / CGFloat(room.vertices.count)
        let cy = room.vertices.map(\.y).reduce(0, +) / CGFloat(room.vertices.count)
        room.vertices = room.vertices.map { pt in
            let x = pt.x - cx, y = pt.y - cy
            return CGPoint(x: cx + y, y: cy - x)
        }
        rooms[idx] = room
    }
    
    // MARK: - Export (simple JSON for "Export JSON" menu)
    func exportData() -> Data {
        struct EncodedFloor: Codable { var id: UUID; var name: String; var rooms: [[CGPoint]] }
        let payload = floors.map { EncodedFloor(id: $0.id, name: $0.name, rooms: $0.rooms.map { $0.vertices }) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }
    
    // MARK: - Full Project Save/Load (used by Projects)
    func projectData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return (try? encoder.encode(floors)) ?? Data()
    }
    
    func loadProject(from data: Data) throws {
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([Floor].self, from: data)
        floors = decoded
        currentFloorIndex = min(currentFloorIndex, max(0, floors.count - 1))
        clearSelection()
        undoStack.removeAll(); redoStack.removeAll()
    }
    
    // MARK: - Auto internal/external classification
    func updateWallTypes() {
        for floorIndex in floors.indices {
            for roomIndex in floors[floorIndex].rooms.indices {
                var room = floors[floorIndex].rooms[roomIndex]
                let n = room.vertices.count
                var newTypes: [WallType] = []
                for i in 0..<n {
                    let a = room.vertices[i]
                    let b = room.vertices[(i + 1) % n]
                    // midpoint
                    let mid = CGPoint(x: (a.x + b.x)/2, y: (a.y + b.y)/2)
                    // normal vector
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let len = hypot(dx, dy)
                    guard len > 0 else { newTypes.append(.externalWall); continue }
                    let normal = CGPoint(x: -dy/len, y: dx/len)
                    // pick samples on both sides
                    let sampleDist: CGFloat = 0.1
                    let s1 = CGPoint(x: mid.x + normal.x * sampleDist, y: mid.y + normal.y * sampleDist)
                    let s2 = CGPoint(x: mid.x - normal.x * sampleDist, y: mid.y - normal.y * sampleDist)
                    // interior vs exterior
                    let interior = room.contains(point: s1) ? s1 : s2
                    let exterior = room.contains(point: s1) ? s2 : s1
                    // test if any other room covers exterior sample
                    var isExternal = true
                    for (fi, floor) in floors.enumerated() {
                        for (ri, other) in floor.rooms.enumerated() {
                            if fi == floorIndex && ri == roomIndex { continue }
                            if other.contains(point: exterior) {
                                isExternal = false
                                break
                            }
                        }
                        if !isExternal { break }
                    }
                    newTypes.append(isExternal ? .externalWall : .internalWall)
                }
                room.wallTypes = newTypes
                floors[floorIndex].rooms[roomIndex] = room
            }
        }
    }
    
    // MARK: - Vector drawing helpers (for exporters, unchanged)
    func drawDoor(
        ctx: CGContext,
        start: CGPoint,
        end: CGPoint,
        interiorNormal: CGPoint,
        type: DoorType,
        scale: CGFloat
    ) {
        let length = hypot(end.x - start.x, end.y - start.y)
        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        switch type {
        case .single:
            // hinge at start
            let radius = length
            ctx.move(to: start)
            ctx.addLine(to: end) // door leaf
            ctx.strokePath()
            // swing path (dotted arc)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.addArc(
                center: start,
                radius: radius,
                startAngle: atan2(direction.y, direction.x),
                endAngle: atan2(direction.y + interiorNormal.y, direction.x + interiorNormal.x),
                clockwise: false
            )
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        case .double:
            // split in two
            let mid = CGPoint(x: (start.x + end.x)/2, y: (start.y + end.y)/2)
            drawDoor(ctx: ctx, start: start, end: mid, interiorNormal: interiorNormal, type: .single, scale: scale)
            drawDoor(ctx: ctx, start: end, end: mid, interiorNormal: interiorNormal, type: .single, scale: scale)
        case .sideLight:
            // door occupies ~70%, window is ~30%
            let doorLen = length * 0.7
            let doorEnd = CGPoint(x: start.x + direction.x * doorLen, y: start.y + direction.y * doorLen)
            drawDoor(ctx: ctx, start: start, end: doorEnd, interiorNormal: interiorNormal, type: .single, scale: scale)
            // adjacent window could be drawn using drawWindow(...)
        }
    }
    
    func drawWindow(
        ctx: CGContext,
        start: CGPoint,
        end: CGPoint,
        type: WindowType
    ) {
        let nPanels: Int
        switch type {
        case .single: nPanels = 1
        case .double: nPanels = 2
        case .triple: nPanels = 3
        case .picture: nPanels = 1
        }
        // Draw the frame
        ctx.move(to: start); ctx.addLine(to: end); ctx.strokePath()
        // Subdivide
        let dx = (end.x - start.x) / CGFloat(nPanels)
        let dy = (end.y - start.y) / CGFloat(nPanels)
        for i in 1..<nPanels {
            let p = CGPoint(x: start.x + dx * CGFloat(i), y: start.y + dy * CGFloat(i))
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x - dy, y: p.y + dx)) // orthogonal direction for thickness
            ctx.strokePath()
        }
    }
    
    /// Append a new staircase to the specified room.  A default staircase has a length
    /// of 3 m and 12 steps.
    func addStairs(in roomID: UUID, at center: CGPoint) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        saveToHistory()
        var r = rooms[idx]
        r.stairs.append(Stairs(center: center))
        rooms[idx] = r
    }

    /// Updates an existing staircase's position, rotation and/or scale.  Pass only the
    /// parameters you wish to modify.  The update is applied relative to the current
    /// values.  For example, a `delta` of `(1,0)` moves the stairs one meter to the
    /// right, a `rotation` of `.pi/4` rotates the stairs by 45° and a `scale` of
    /// `1.2` increases both the length and width by 20 percent.
    ///
    /// - Parameters:
    ///   - roomID: Identifier of the room containing the stairs.
    ///   - id: Identifier of the stairs to update.
    ///   - delta: Optional translation in model‑space meters.
    ///   - rotation: Optional rotation to add (in radians).
    ///   - scale: Optional uniform scale factor to multiply the length and width.
    func updateStairs(in roomID: UUID, id: UUID,
                      delta: CGPoint? = nil,
                      rotation: CGFloat? = nil,
                      scale: CGFloat? = nil) {
        guard let rIndex = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        var room = rooms[rIndex]
        guard let sIndex = room.stairs.firstIndex(where: { $0.id == id }) else { return }
        var stairs = room.stairs[sIndex]
        // Apply pending updates
        if let d = delta {
            stairs.center.x += d.x
            stairs.center.y += d.y
        }
        if let rot = rotation {
            stairs.rotation += rot
        }
        if let sc = scale {
            let factor = max(sc, 0.01)
            stairs.length *= factor
            stairs.width  *= factor
        }
        // Persist
        saveToHistory()
        room.stairs[sIndex] = stairs
        rooms[rIndex] = room
    }

    // Close the Floorplan class before defining Stairs outside of it
}

/// A simple model describing a staircase within a room.  This is declared
/// outside of ``Floorplan`` so that it can be encoded/decoded independently
/// and referenced from ``Room``.
struct Stairs: Identifiable, Codable, Hashable {
    let id: UUID
    var center: CGPoint          // model-space center
    var length: CGFloat          // meters along run
    var width: CGFloat           // meters across stairs
    var steps: Int               // number of treads (visual)
    var up: Bool                 // direction (for later arrows)
    var rotation: CGFloat        // radians, 0 = +x

    init(
        id: UUID = UUID(),
        center: CGPoint,
        length: CGFloat = 3.0,
        width: CGFloat = 1.0,
        steps: Int = 12,
        up: Bool = true,
        rotation: CGFloat = 0
    ) {
        self.id = id
        self.center = center
        self.length = length
        self.width = width
        self.steps = steps
        self.up = up
        self.rotation = rotation
    }
}
