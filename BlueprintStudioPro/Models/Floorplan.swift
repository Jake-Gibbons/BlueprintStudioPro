import Foundation
import CoreGraphics
import Combine
import SwiftUI

// MARK: - Floor

struct Floor: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rooms: [Room]

    init(id: UUID = UUID(), name: String, rooms: [Room] = []) {
        self.id = id
        self.name = name
        self.rooms = rooms
    }

    // Make Equatable without requiring Room to be Equatable
    static func == (lhs: Floor, rhs: Floor) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - FloorPlan

/// Top-level model storing floors, rooms on the active floor, selection state, history, and export.
final class FloorPlan: ObservableObject {
    // Floors
    @Published var floors: [Floor] = [Floor(name: "Ground Floor")]
    @Published var currentFloorIndex: Int = 0

    // Selection (per-floor semantics: these refer to the active floor)
    @Published var selectedRoomID: UUID? = nil
    @Published var selectedWallIndex: Int? = nil

    // History per floor
    private var historyByFloor: [UUID: [[Room]]] = [:]     // floorID -> undo stack
    private var redoByFloor: [UUID: [[Room]]] = [:]        // floorID -> redo stack

    // Convenience: current floor ID
    private var currentFloorID: UUID { floors[currentFloorIndex].id }

    // MARK: - Rooms accessor for active floor
    var rooms: [Room] {
        get { floors[currentFloorIndex].rooms }
        set {
            var f = floors[currentFloorIndex]
            f.rooms = newValue
            floors[currentFloorIndex] = f
        }
    }

    // MARK: - History management
    func saveToHistory() {
        let fid = currentFloorID
        historyByFloor[fid, default: []].append(rooms)
        redoByFloor[fid] = [] // reset redo on new change
    }

    func undo() {
        let fid = currentFloorID
        guard var stack = historyByFloor[fid], let last = stack.popLast() else { return }
        historyByFloor[fid] = stack
        redoByFloor[fid, default: []].append(rooms)
        rooms = last
    }

    func redo() {
        let fid = currentFloorID
        guard var stack = redoByFloor[fid], let next = stack.popLast() else { return }
        redoByFloor[fid] = stack
        historyByFloor[fid, default: []].append(rooms)
        rooms = next
    }

    // MARK: - Floor management
    func addFloor() {
        saveToHistory() // snapshot current before switching
        let new = Floor(name: "Floor \(floors.count + 1)")
        floors.append(new)
        currentFloorIndex = floors.count - 1
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    func deleteCurrentFloor() {
        guard floors.count > 1 else { return }
        let deletedID = currentFloorID
        historyByFloor[deletedID] = nil
        redoByFloor[deletedID] = nil

        floors.remove(at: currentFloorIndex)
        if currentFloorIndex >= floors.count {
            currentFloorIndex = max(0, floors.count - 1)
        }
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    func switchToFloor(_ floorID: UUID) {
        if let idx = floors.firstIndex(where: { $0.id == floorID }) {
            currentFloorIndex = idx
            selectedRoomID = nil
            selectedWallIndex = nil
        }
    }

    // MARK: - Room management
    func addRoom(vertices: [CGPoint]) {
        guard vertices.count >= 3 else { return }
        saveToHistory()
        var newRoom = Room(vertices: vertices)
        newRoom.fillColor = .blue.opacity(0.15)
        rooms.append(newRoom)
        selectedRoomID = newRoom.id
        selectedWallIndex = nil
    }

    func addSquareRoom(center: CGPoint, sideLength: CGFloat = 4.0) {
        let half = sideLength / 2
        let vertices = [
            CGPoint(x: center.x - half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y + half),
            CGPoint(x: center.x - half, y: center.y + half)
        ]
        addRoom(vertices: vertices)
    }

    func deleteSelectedRoom() {
        guard let id = selectedRoomID else { return }
        saveToHistory()
        rooms.removeAll { $0.id == id }
        selectedRoomID = nil
        selectedWallIndex = nil
    }

    // MARK: - Selection helpers
    func selectRoom(containing point: CGPoint) {
        if let room = rooms.first(where: { $0.contains(point: point) }) {
            selectedRoomID = room.id
            selectedWallIndex = nil
        } else {
            selectedRoomID = nil
            selectedWallIndex = nil
        }
    }

    func selectWall(near point: CGPoint, threshold: CGFloat) {
        guard let id = selectedRoomID,
              let idx = rooms.firstIndex(where: { $0.id == id }),
              let wallIdx = rooms[idx].indexOfWall(near: point, threshold: threshold) else { return }
        selectedWallIndex = wallIdx
    }

    // MARK: - Openings
    func addWindow(at offset: CGFloat) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == selectedRoomID }),
              let wallIdx = selectedWallIndex else { return }
        saveToHistory()
        var room = rooms[roomIdx]
        room.windows.append(Window(wallIndex: wallIdx, offset: max(0, min(1, offset))))
        rooms[roomIdx] = room
    }

    func addDoor(at offset: CGFloat) {
        guard let roomIdx = rooms.firstIndex(where: { $0.id == selectedRoomID }),
              let wallIdx = selectedWallIndex else { return }
        saveToHistory()
        var room = rooms[roomIdx]
        room.doors.append(Door(wallIndex: wallIdx, offset: max(0, min(1, offset))))
        rooms[roomIdx] = room
    }

    // MARK: - Export
    func exportData(pretty: Bool = true) -> Data {
        struct ExportPoint: Codable { let x: Double; let y: Double }
        struct ExportAttachment: Codable { let wallIndex: Int; let offset: Double; let length: Double }
        struct ExportRoom: Codable {
            let id: UUID
            let vertices: [ExportPoint]
            let windows: [ExportAttachment]
            let doors: [ExportAttachment]
        }
        struct ExportFloor: Codable {
            let id: UUID
            let name: String
            let rooms: [ExportRoom]
        }
        struct ExportPlan: Codable {
            let floors: [ExportFloor]
            let currentFloorIndex: Int
        }

        let dtoFloors: [ExportFloor] = floors.map { f in
            let dtoRooms: [ExportRoom] = f.rooms.map { r in
                ExportRoom(
                    id: r.id,
                    vertices: r.vertices.map { ExportPoint(x: Double($0.x), y: Double($0.y)) },
                    windows: r.windows.map { ExportAttachment(wallIndex: $0.wallIndex, offset: Double($0.offset), length: Double($0.length)) },
                    doors: r.doors.map { ExportAttachment(wallIndex: $0.wallIndex, offset: Double($0.offset), length: Double($0.length)) }
                )
            }
            return ExportFloor(id: f.id, name: f.name, rooms: dtoRooms)
        }

        let plan = ExportPlan(floors: dtoFloors, currentFloorIndex: currentFloorIndex)
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return (try? encoder.encode(plan)) ?? Data()
    }
}
