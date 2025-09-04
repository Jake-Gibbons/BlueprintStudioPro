import Foundation

/// Tools available in the editor.
enum Tool: String, CaseIterable, Identifiable {
    case select = "Select"
    case drawRoom = "Draw Room"
    case drawWall = "Draw Wall"
    case addWindow = "Add Window"
    case addDoor = "Add Door"
    case delete = "Delete"
    case resize = "Resize"      // NEW: global wall-resize mode for the selected room
    
    var id: String { rawValue }
}
