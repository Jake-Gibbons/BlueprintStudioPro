import SwiftUI
import Combine

// MARK: - Floor / Room Models (abbreviated to the essentials used here)
// NOTE: Keep your existing properties & methods; this file shows the full type with the new resetProject().

struct Floor: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rooms: [Room]

    init(id: UUID = UUID(), name: String, rooms: [Room] = []) {
        self.id = id
        self.name = name
        self.rooms = rooms
    }
}

struct Window: Identifiable {
    let id = UUID()
    var wallIndex: Int
    var offset: CGFloat    // 0...1 along the wall
    var length: CGFloat    // in model units (m)
}

struct Door: Identifiable {
    let id = UUID()
    var wallIndex: Int
    var offset: CGFloat
    var length: CGFloat
}

protocol WallAttachment {
    var wallIndex: Int { get set }
    var offset: CGFloat { get set }
    var length: CGFloat { get set }
}
extension Window: WallAttachment {}
extension Door: WallAttachment {}

struct Room: Identifiable, Hashable {
    let id: UUID
    var vertices: [CGPoint]
    var windows: [Window] = []
    var doors: [Door] = []
    var fillColor: Color = Color.blue.opacity(0.06)

    init(id: UUID = UUID(), vertices: [CGPoint]) {
        self.id = id
        self.vertices = vertices
    }

    // Simple point-in-polygon hit
    func contains(point: CGPoint) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        for i in vertices.indices {
            let j = (i + vertices.count - 1) % vertices.count
            let xi = vertices[i].x, yi = vertices[i].y
            let xj = vertices[j].x, yj = vertices[j].y
            let intersect = ((yi > point.y) != (yj > point.y)) &&
            (point.x < (xj - xi) * (point.y - yi) / ((yj - yi) == 0 ? 1 : (yj - yi)) + xi)
            if intersect { inside.toggle() }
        }
        return inside
    }

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

    func path(using transform: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        guard let first = vertices.first else { return path }
        path.move(to: transform(first))
        for v in vertices.dropFirst() { path.addLine(to: transform(v)) }
        path.closeSubpath()
        return path
    }
}

// Utility
fileprivate func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ax = b.x - a.x, ay = b.y - a.y
    let denom = ax*ax + ay*ay
    if denom == 0 { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * ax + (p.y - a.y) * ay) / denom))
    let proj = CGPoint(x: a.x + t * ax, y: a.y + t * ay)
    return hypot(p.x - proj.x, p.y - proj.y)
}

// MARK: - FloorPlan

final class FloorPlan: ObservableObject {

    // Floors
    @Published var floors: [Floor] = [Floor(name: "Ground Floor")]
    @Published var currentFloorIndex: Int = 0

    // Convenience for current floor rooms
    var rooms: [Room] {
        get { floors[currentFloorIndex].rooms }
        set { floors[currentFloorIndex].rooms = newValue }
    }

    // Selection
    @Published var selectedRoomID: UUID? = nil
    @Published var selectedWallIndex: Int? = nil

    // History (very lightweight)
    private var undoStack: [[Floor]] = []
    private var redoStack: [[Floor]] = []

    // MARK: - Floor management
    func addFloor() {
        saveToHistory()
        floors.append(Floor(name: "New Floor"))
        currentFloorIndex = floors.count - 1
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    func deleteCurrentFloor() {
        guard floors.count > 1 else { return }
        saveToHistory()
        floors.remove(at: currentFloorIndex)
        currentFloorIndex = max(0, currentFloorIndex - 1)
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    func switchToFloor(_ id: UUID) {
        if let idx = floors.firstIndex(where: { $0.id == id }) {
            currentFloorIndex = idx
            selectedRoomID = nil
            selectedWallIndex = nil
        }
    }

    // ✅ New: reset project (clears extra floors and rooms on current floor)
    func resetProject() {
        saveToHistory()
        floors = [Floor(name: "Ground Floor")]
        currentFloorIndex = 0
        selectedRoomID = nil
        selectedWallIndex = nil
        redoStack.removeAll()
    }

    // MARK: - Room ops
    func addRoom(vertices: [CGPoint]) {
        saveToHistory()
        rooms.append(Room(vertices: vertices))
    }

    func selectRoom(containing point: CGPoint) {
        for r in rooms.reversed() { // prefer top-most
            if r.contains(point: point) {
                selectedRoomID = r.id
                return
            }
        }
        selectedRoomID = nil
    }

    func selectWall(near point: CGPoint, threshold: CGFloat) {
        guard let id = selectedRoomID, let idx = rooms.firstIndex(where: { $0.id == id }) else {
            selectedWallIndex = nil; return
        }
        selectedWallIndex = rooms[idx].indexOfWall(near: point, threshold: threshold)
    }

    func deleteSelectedRoom() {
        guard let id = selectedRoomID, let idx = rooms.firstIndex(where: { $0.id == id }) else { return }
        saveToHistory()
        rooms.remove(at: idx)
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    func addWindow(at offset: CGFloat) {
        guard let rid = selectedRoomID,
              let wIndex = selectedWallIndex,
              let idx = rooms.firstIndex(where: { $0.id == rid }) else { return }
        saveToHistory()
        var r = rooms[idx]
        r.windows.append(Window(wallIndex: wIndex, offset: offset, length: 1.0))
        rooms[idx] = r
    }

    func addDoor(at offset: CGFloat) {
        guard let rid = selectedRoomID,
              let wIndex = selectedWallIndex,
              let idx = rooms.firstIndex(where: { $0.id == rid }) else { return }
        saveToHistory()
        var r = rooms[idx]
        r.doors.append(Door(wallIndex: wIndex, offset: offset, length: 0.9))
        rooms[idx] = r
    }

    // MARK: - History
    func saveToHistory() {
        undoStack.append(floors)
        redoStack.removeAll()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(floors)
        floors = last
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(floors)
        floors = next
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    // MARK: - Export
    func exportData() -> Data {
        // Simple JSON of vertices (replace with your real encoder if you have one)
        struct EncodedFloor: Codable { var id: UUID; var name: String; var rooms: [[CGPoint]] }
        let payload = floors.map { EncodedFloor(id: $0.id, name: $0.name, rooms: $0.rooms.map { $0.vertices }) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }
}
