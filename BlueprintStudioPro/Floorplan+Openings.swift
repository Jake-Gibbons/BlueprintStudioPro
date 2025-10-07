import Foundation

// This extension adds helpers for inserting door and window attachments with
// explicit types.  It computes reasonable default lengths based on the
// selected type and uses the existing active room and selected wall context
// maintained by the Floorplan.  Adding an attachment saves to the undo
// history and updates the model in place.  These helpers are used by the
// modified FloorPlanView to support interactive placement of openings.

extension Floorplan {

    /// Add a door to the currently active room on the selected wall at a
    /// relative offset.  The `type` parameter controls the visual style and
    /// physical length of the door.
    /// - Parameters:
    ///   - offset: Relative position along the wall in the range 0...1.
    ///   - type: Style of the door (single, double or sideLight).
    func addDoor(at offset: CGFloat, type: DoorType) {
        // Ensure we have an active room and a selected wall index.
        guard let rid = activeRoomID,
              let wIndex = selectedWallIndex,
              let idx = rooms.firstIndex(where: { $0.id == rid }) else { return }
        saveToHistory()
        var room = rooms[idx]
        // Compute a default physical length based on the type.  These values
        // approximate common door sizes: single ≈ 0.9 m, double ≈ 1.8 m and
        // sideLight (a single door with an adjacent side window) ≈ 1.4 m.
        let length: CGFloat
        switch type {
        case .double:
            length = 1.8
        case .sideLight:
            length = 1.4
        default:
            length = 0.9
        }
        // Create a door with the computed length and assign the type.  The
        // default initialiser assigns a new UUID automatically.
        var door = Door(wallIndex: wIndex, offset: offset, length: length)
        door.type = type
        room.doors.append(door)
        rooms[idx] = room
    }

    /// Add a window to the currently active room on the selected wall at a
    /// relative offset.  The `type` parameter controls the style and default
    /// length of the window.  Single windows are 1 m, double and picture
    /// windows are 2 m and triple windows are 3 m.
    /// - Parameters:
    ///   - offset: Relative position along the wall in the range 0...1.
    ///   - type: Style of the window (single, double, triple or picture).
    func addWindow(at offset: CGFloat, type: WindowType) {
        guard let rid = activeRoomID,
              let wIndex = selectedWallIndex,
              let idx = rooms.firstIndex(where: { $0.id == rid }) else { return }
        saveToHistory()
        var room = rooms[idx]
        let length: CGFloat
        switch type {
        case .double, .picture:
            length = 2.0
        case .triple:
            length = 3.0
        default:
            length = 1.0
        }
        var window = Window(wallIndex: wIndex, offset: offset, length: length)
        window.type = type
        room.windows.append(window)
        rooms[idx] = room
    }
}