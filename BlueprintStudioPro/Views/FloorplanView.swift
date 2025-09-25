import SwiftUI

// MARK: - Snapping Helpers
fileprivate let GRID_STEP: CGFloat = 1.0
fileprivate let SNAP_TOLERANCE: CGFloat = 0.2

@inline(__always)
fileprivate func softlySnapValue(_ v: CGFloat, step: CGFloat = GRID_STEP,
                                 tol: CGFloat = SNAP_TOLERANCE) -> CGFloat {
    let target = round(v / step) * step
    return abs(target - v) <= tol ? target : v
}

@inline(__always)
fileprivate func softlySnapPoint(_ p: CGPoint,
                                 step: CGFloat = GRID_STEP,
                                 tol: CGFloat = SNAP_TOLERANCE) -> CGPoint {
    CGPoint(x: softlySnapValue(p.x, step: step, tol: tol),
            y: softlySnapValue(p.y, step: step, tol: tol))
}

@inline(__always)
fileprivate func hardSnapPoint(_ p: CGPoint, step: CGFloat = GRID_STEP) -> CGPoint {
    CGPoint(x: round(p.x / step) * step,
            y: round(p.y / step) * step)
}

// MARK: - FloorPlanView

struct FloorPlanView: View {
    @EnvironmentObject private var floorPlan: Floorplan
    @Binding var currentTool: EditorTool
    @Binding var snapToGrid: Bool
    @Binding var showDimensions: Bool

    @State private var workingVertices: [CGPoint] = []

    // Pan/zoom state
    @State private var panOffset: CGSize = .zero
    @State private var liveTwoFingerPan: CGSize = .zero
    @State private var scale: CGFloat = 60.0
    @GestureState private var gestureScale: CGFloat = 1.0

    // Draw-room rubber-band
    @State private var drawRoomStart: CGPoint? = nil
    @State private var drawRoomCurrent: CGPoint? = nil

    // Opening preview
    struct PreviewOpening { var roomID: UUID; var wallIndex: Int; var offset: CGFloat; var isDoor: Bool }
    @State private var previewOpening: PreviewOpening? = nil

    var body: some View {
        GeometryReader { geometry in
            let effectiveScale = scale * gestureScale
            let effectiveOffset = CGSize(width: panOffset.width + liveTwoFingerPan.width,
                                         height: panOffset.height + liveTwoFingerPan.height)

            ZStack {
                // 1) Grid
                GridView(scale: effectiveScale, offset: effectiveOffset, size: geometry.size)

                // 2) Rooms & overlays
                ForEach(floorPlan.rooms) { room in
                    let isSelected = (room.id == floorPlan.selectedRoomID) || floorPlan.selectedRoomIDs.contains(room.id)
                    let isResizeMode = (currentTool == .resize && ((floorPlan.activeRoomID == room.id) || isSelected))

                    // Room shape + watermark + variable-width edges
                    RoomRender(
                        room: room,
                        isSelected: isSelected,
                        isResizeMode: isResizeMode,
                        transform: { modelToScreen($0, size: geometry.size, scale: effectiveScale, offset: effectiveOffset) }
                    )
                    // Taps on the shape (for non-select tools) → single select
                    .highPriorityGesture(
                        TapGesture().onEnded { handleTapOnRoom(room: room) }
                    )
                    .zIndex(1)

                    // Openings drawn above but non-interactive
                    openings(for: room, size: geometry.size, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
                        .allowsHitTesting(false)
                        .zIndex(1)

                    // Movement & tap capture limited to the room polygon — only in Select tool
                    RoomMoveCapture(
                        room: room,
                        isActive: (currentTool == .select),
                        effectiveScale: effectiveScale,
                        size: geometry.size,
                        effectiveOffset: effectiveOffset,
                        getBinding: { bindingForRoom(id: $0) },
                        snapToGrid: snapToGrid,
                        onHistory: { floorPlan.saveToHistory() },
                        onTap: { tapModelPoint in
                            // Toggle selection of the tapped room
                            floorPlan.toggleSelect(room.id)

                            // If now it’s the only selected room, try to pick a wall near the tap
                            if floorPlan.selectedRoomIDs.count == 1,
                               floorPlan.selectedRoomIDs.contains(room.id) {
                                if let wall = room.indexOfWall(near: tapModelPoint, threshold: 0.3) {
                                    floorPlan.selectedWallIndex = wall
                                } else {
                                    floorPlan.selectedWallIndex = nil
                                }
                            } else {
                                // Multiple rooms selected: clear wall focus
                                floorPlan.selectedWallIndex = nil
                            }
                        }
                    )
                    .zIndex(2)

                    // Resizing overlays (rails/handles) – topmost
                    if isResizeMode {
                        resizeOverlays(for: room, size: geometry.size, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
                            .zIndex(3)
                    } else if let selectedID = floorPlan.activeRoomID,
                              selectedID == room.id,
                              let wallIndex = floorPlan.selectedWallIndex,
                              room.vertices.indices.contains(wallIndex) {
                        singleWallOverlay(room: room, wall: wallIndex, size: geometry.size, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
                            .zIndex(3)
                    }

                    // Dimensional annotations
                    if showDimensions {
                        drawDimensions(for: room, size: geometry.size, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
                            .allowsHitTesting(false)
                            .zIndex(4)
                    }
                }

                // Opening preview (ghost)
                openingPreviewLayer(size: geometry.size, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)

                // Draw-wall preview
                if currentTool == .drawWall && !workingVertices.isEmpty {
                    Path { path in
                        let pts = workingVertices.map {
                            modelToScreen($0, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                        }
                        path.move(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }

                // Draw-room rubber-band preview
                if let a = drawRoomStart, let b = drawRoomCurrent, currentTool == .drawRoom {
                    let rect = normalizedRect(from: a, to: b)
                    let sRect = modelRectToScreen(rect, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                    Rectangle().path(in: sRect)
                        .stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.05))
                                .frame(width: sRect.width, height: sRect.height)
                                .position(x: sRect.midX, y: sRect.midY)
                        )
                }

                // Two-finger pan
                TwoFingerPanGestureView(
                    onChanged: { translation in liveTwoFingerPan = translation },
                    onEnded: { translation in
                        panOffset.width += translation.width
                        panOffset.height += translation.height
                        liveTwoFingerPan = .zero
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(true)
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: "canvas")
            .simultaneousGesture(magnificationGesture())
            .simultaneousGesture(mainGesture(size: geometry.size))
            // Background clear-selection tap (runs if no room handled the tap)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        // Ignore if it was a drag
                        if abs(value.translation.width) > 3 || abs(value.translation.height) > 3 { return }

                        let effectiveScale = scale * gestureScale
                        let effectiveOffset = CGSize(width: panOffset.width + liveTwoFingerPan.width,
                                                     height: panOffset.height + liveTwoFingerPan.height)
                        let modelPoint = screenToModel(value.location,
                                                       size: geometry.size,
                                                       scale: effectiveScale,
                                                       offset: effectiveOffset)
                        let hitAny = floorPlan.rooms.contains { $0.contains(point: modelPoint) }
                        if !hitAny {
                            floorPlan.clearSelection()
                        }
                    }
            )
        }
    }

    // MARK: - Bindings
    private func bindingForRoom(id: UUID) -> Binding<Room>? {
        guard let idx = floorPlan.rooms.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { floorPlan.rooms[idx] },
            set: { newValue in
                floorPlan.rooms[idx] = newValue
                // poke to trigger @Published on parent
                floorPlan.floors = floorPlan.floors
            }
        )
    }

    // MARK: - Transforms
    private func modelToScreen(_ p: CGPoint, size: CGSize, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: p.x * scale + size.width / 2 + offset.width,
                y: p.y * scale + size.height / 2 + offset.height)
    }
    private func screenToModel(_ p: CGPoint, size: CGSize, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: (p.x - size.width / 2 - offset.width) / scale,
                y: (p.y - size.height / 2 - offset.height) / scale)
    }
    private func modelRectToScreen(_ r: CGRect, size: CGSize, scale: CGFloat, offset: CGSize) -> CGRect {
        let origin = modelToScreen(r.origin, size: size, scale: scale, offset: offset)
        return CGRect(x: origin.x, y: origin.y, width: r.width * scale, height: r.height * scale)
    }

    // MARK: - Gestures
    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in state = value }
            .onEnded { value in scale = max(10, min(scale * value, 300)) }
    }

    private func mainGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let effectiveScale = scale * gestureScale
                let offset = CGSize(width: panOffset.width + liveTwoFingerPan.width,
                                    height: panOffset.height + liveTwoFingerPan.height)
                let modelPoint = screenToModel(value.location, size: size, scale: effectiveScale, offset: offset)

                switch currentTool {
                case .select, .delete, .resize, .duplicate, .rotate:
                    break
                case .drawRoom:
                    if drawRoomStart == nil {
                        drawRoomStart = snapToGrid ? hardSnapPoint(modelPoint) : modelPoint
                        drawRoomCurrent = drawRoomStart
                    } else {
                        drawRoomCurrent = snapToGrid ? softlySnapPoint(modelPoint) : modelPoint
                    }
                case .drawWall:
                    break
                case .addWindow, .addDoor:
                    var targetRoom: Room?
                    if let selID = floorPlan.activeRoomID,
                       let sr = floorPlan.rooms.first(where: { $0.id == selID }),
                       sr.contains(point: modelPoint) {
                        targetRoom = sr
                    } else {
                        targetRoom = floorPlan.rooms.first(where: { $0.contains(point: modelPoint) })
                    }
                    guard let room = targetRoom,
                          let wallIndex = room.indexOfWall(near: modelPoint, threshold: 0.6) else {
                        previewOpening = nil
                        return
                    }
                    let start = room.vertices[wallIndex]
                    let end = room.vertices[(wallIndex + 1) % room.vertices.count]
                    let t = projectionFactor(point: modelPoint, start: start, end: end)
                    let clamped = max(0, min(1, t))
                    previewOpening = PreviewOpening(roomID: room.id, wallIndex: wallIndex, offset: clamped, isDoor: currentTool == .addDoor)
                    floorPlan.selectOnly(room.id) // focus for single-target actions
                    floorPlan.selectedWallIndex = wallIndex
                }
            }
            .onEnded { value in
                let effectiveScale = scale * gestureScale
                let offset = CGSize(width: panOffset.width + liveTwoFingerPan.width,
                                    height: panOffset.height + liveTwoFingerPan.height)
                let modelPoint = screenToModel(value.location, size: size, scale: effectiveScale, offset: offset)

                switch currentTool {
                case .select:
                    // selection handled by RoomMoveCapture tap; nothing to do here
                    break
                case .delete:
                    floorPlan.selectRoom(containing: modelPoint)
                    floorPlan.deleteSelectedRooms()
                case .drawRoom:
                    if let a = drawRoomStart {
                        if let b = drawRoomCurrent, hypot(b.x - a.x, b.y - a.y) > 0.05 {
                            let rect = normalizedRect(from: a, to: b)
                            addRectRoom(rect)
                        } else {
                            let w: CGFloat = 4.0, h: CGFloat = 3.0
                            let origin = CGPoint(x: modelPoint.x - w/2, y: modelPoint.y - h/2)
                            addRectRoom(CGRect(x: snapToGrid ? softlySnapValue(origin.x) : origin.x,
                                               y: snapToGrid ? softlySnapValue(origin.y) : origin.y,
                                               width: w, height: h))
                        }
                    }
                    drawRoomStart = nil
                    drawRoomCurrent = nil
                    floorPlan.saveToHistory()
                case .drawWall:
                    if let first = workingVertices.first {
                        let firstScreen = CGPoint(x: first.x * effectiveScale + size.width/2 + offset.width,
                                                  y: first.y * effectiveScale + size.height/2 + offset.height)
                        let distPx = hypot(firstScreen.x - value.location.x, firstScreen.y - value.location.y)
                        if distPx < 10, workingVertices.count >= 3 {
                            floorPlan.addRoom(vertices: workingVertices)
                            workingVertices.removeAll()
                            return
                        }
                    }
                    let pt = snapToGrid ? softlySnapPoint(modelPoint) : modelPoint
                    workingVertices.append(pt)
                case .addWindow, .addDoor:
                    if let preview = previewOpening {
                        floorPlan.selectOnly(preview.roomID)
                        floorPlan.selectedWallIndex = preview.wallIndex
                        if preview.isDoor { floorPlan.addDoor(at: preview.offset) }
                        else { floorPlan.addWindow(at: preview.offset) }
                    }
                    previewOpening = nil
                case .duplicate:
                    floorPlan.selectRoom(containing: modelPoint)
                    floorPlan.duplicateSelectedRoom()
                    currentTool = .select
                case .rotate:
                    floorPlan.selectRoom(containing: modelPoint)
                    floorPlan.rotateSelectedRoom()
                    currentTool = .select
                case .resize:
                    break
                }
            }
    }

    // MARK: - Utility Methods
    private func addRectRoom(_ rect: CGRect) {
        let v1 = rect.origin
        let v2 = CGPoint(x: rect.maxX, y: rect.minY)
        let v3 = CGPoint(x: rect.maxX, y: rect.maxY)
        let v4 = CGPoint(x: rect.minX, y: rect.maxY)
        floorPlan.addRoom(vertices: [v1, v2, v3, v4])
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func handleTapOnRoom(room: Room) {
        switch currentTool {
        case .select:
            // Select tool taps handled in RoomMoveCapture for polygon-accurate hit test
            break
        default:
            // For other tools, a tap on the shape selects just this room
            floorPlan.selectOnly(room.id)
        }
    }

    private func openings(for room: Room, size: CGSize, effectiveScale: CGFloat, effectiveOffset: CGSize) -> some View {
        ZStack {
            // Windows
            ForEach(room.windows) { window in
                let sidx = window.wallIndex % room.vertices.count
                let eidx = (window.wallIndex + 1) % room.vertices.count
                let start = room.vertices[sidx], end = room.vertices[eidx]
                let (p1, p2) = openingPoints(start: start, end: end, attachment: window)
                let s1 = modelToScreen(p1, size: size, scale: effectiveScale, offset: effectiveOffset)
                let s2 = modelToScreen(p2, size: size, scale: effectiveScale, offset: effectiveOffset)
                Path { $0.move(to: s1); $0.addLine(to: s2) }
                    .stroke(Color.teal.opacity(0.7), lineWidth: 3)
            }
            // Doors
            ForEach(room.doors) { door in
                let sidx = door.wallIndex % room.vertices.count
                let eidx = (door.wallIndex + 1) % room.vertices.count
                let start = room.vertices[sidx], end = room.vertices[eidx]
                let (p1, p2) = openingPoints(start: start, end: end, attachment: door)
                let s1 = modelToScreen(p1, size: size, scale: effectiveScale, offset: effectiveOffset)
                let s2 = modelToScreen(p2, size: size, scale: effectiveScale, offset: effectiveOffset)
                Path { $0.move(to: s1); $0.addLine(to: s2) }
                    .stroke(Color.brown.opacity(0.7), lineWidth: 5)
            }
        }
    }

    private func openingPreviewLayer(size: CGSize, effectiveScale: CGFloat, effectiveOffset: CGSize) -> some View {
        Group {
            if let preview = previewOpening,
               let room = floorPlan.rooms.first(where: { $0.id == preview.roomID }) {
                let start = room.vertices[preview.wallIndex]
                let end = room.vertices[(preview.wallIndex + 1) % room.vertices.count]
                let ghost = Window(wallIndex: preview.wallIndex, offset: preview.offset, length: preview.isDoor ? 0.9 : 1.0)
                let (p1, p2) = openingPoints(start: start, end: end, attachment: ghost)
                let s1 = modelToScreen(p1, size: size, scale: effectiveScale, offset: effectiveOffset)
                let s2 = modelToScreen(p2, size: size, scale: effectiveScale, offset: effectiveOffset)
                Path { $0.move(to: s1); $0.addLine(to: s2) }
                    .stroke(preview.isDoor ? Color.brown.opacity(0.6) : Color.teal.opacity(0.6),
                            style: StrokeStyle(lineWidth: preview.isDoor ? 5 : 3, dash: [6, 4]))
            }
        }
    }

    private func openingPoints(start: CGPoint, end: CGPoint, attachment: any WallAttachment) -> (CGPoint, CGPoint) {
        let dir = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let len = hypot(dir.x, dir.y); guard len > 0 else { return (start, start) }
        let unit = CGPoint(x: dir.x / len, y: dir.y / len)
        let centre = CGPoint(x: start.x + unit.x * len * attachment.offset,
                             y: start.y + unit.y * len * attachment.offset)
        let half = attachment.length / 2
        let p1 = CGPoint(x: centre.x - unit.x * half, y: centre.y - unit.y * half)
        let p2 = CGPoint(x: centre.x + unit.x * half, y: centre.y + unit.y * half)
        return (p1, p2)
    }

    private func projectionFactor(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let denom = dx*dx + dy*dy; guard denom > 0 else { return 0 }
        let px = point.x - start.x, py = point.y - start.y
        return (px*dx + py*dy) / denom
    }

    // MARK: - Resize helpers (rails/handles with parallel movement)

    private func resizeOverlays(for room: Room, size: CGSize, effectiveScale: CGFloat, effectiveOffset: CGSize) -> some View {
        let count = room.vertices.count
        return ZStack {
            ForEach(0..<count, id: \.self) { wall in
                let v1 = room.vertices[wall]
                let v2 = room.vertices[(wall + 1) % count]
                // Draw the rail as an orange line (visible only if selected)
                Path { path in
                    let sStart = modelToScreen(v1, size: size, scale: effectiveScale, offset: effectiveOffset)
                    let sEnd = modelToScreen(v2, size: size, scale: effectiveScale, offset: effectiveOffset)
                    path.move(to: sStart); path.addLine(to: sEnd)
                }
                .stroke(Color.orange.opacity(0.9), lineWidth: 4)
                // Dragging along this rail moves the wall perpendicular only
                WallHitRail(
                    roomID: room.id,
                    wallIndex: wall,
                    v1: v1, v2: v2,
                    effectiveScale: effectiveScale,
                    effectiveOffset: effectiveOffset,
                    snapToGrid: snapToGrid,
                    getRoom: { bindingForRoom(id: $0) },
                    onHistoryOnce: { floorPlan.saveToHistory() }
                )
                .allowsHitTesting(true)
                // Handle to drag more easily on mobile
                let dx = v2.x - v1.x, dy = v2.y - v1.y
                let len = hypot(dx, dy)
                if len > 0 {
                    let mid = CGPoint(x: (v1.x + v2.x)/2, y: (v1.y + v2.y)/2)
                    let unitNormal = CGPoint(x: -dy/len, y: dx/len)
                    let offsetModel = 16.0 / effectiveScale
                    let handleModelPos = CGPoint(x: mid.x + unitNormal.x * offsetModel, y: mid.y + unitNormal.y * offsetModel)
                    let handleScreen = modelToScreen(handleModelPos, size: size, scale: effectiveScale, offset: effectiveOffset)
                    WallHandle(
                        roomID: room.id,
                        wallIndex: wall,
                        v1: v1, v2: v2,
                        centerScreen: handleScreen,
                        effectiveScale: effectiveScale,
                        snapToGrid: snapToGrid,
                        getRoom: { bindingForRoom(id: $0) },
                        onHistoryOnce: { floorPlan.saveToHistory() }
                    )
                    .allowsHitTesting(true)
                }
            }
        }
    }

    private func singleWallOverlay(room: Room, wall: Int, size: CGSize, effectiveScale: CGFloat, effectiveOffset: CGSize) -> some View {
        let v1 = room.vertices[wall], v2 = room.vertices[(wall + 1) % room.vertices.count]
        return ZStack {
            Path { path in
                let sStart = modelToScreen(v1, size: size, scale: effectiveScale, offset: effectiveOffset)
                let sEnd = modelToScreen(v2, size: size, scale: effectiveScale, offset: effectiveOffset)
                path.move(to: sStart); path.addLine(to: sEnd)
            }
            .stroke(Color.orange.opacity(0.9), lineWidth: 4)
            WallHitRail(
                roomID: room.id,
                wallIndex: wall,
                v1: v1, v2: v2,
                effectiveScale: effectiveScale,
                effectiveOffset: effectiveOffset,
                snapToGrid: snapToGrid,
                getRoom: { bindingForRoom(id: $0) },
                onHistoryOnce: { floorPlan.saveToHistory() }
            )
            .allowsHitTesting(true)
            let dx = v2.x - v1.x, dy = v2.y - v1.y
            let len = hypot(dx, dy)
            if len > 0 {
                let mid = CGPoint(x: (v1.x + v2.x)/2, y: (v1.y + v2.y)/2)
                let unitNormal = CGPoint(x: -dy/len, y: dx/len)
                let offsetModel = 16.0 / effectiveScale
                let handleModelPos = CGPoint(x: mid.x + unitNormal.x * offsetModel, y: mid.y + unitNormal.y * offsetModel)
                let handleScreen = modelToScreen(handleModelPos, size: size, scale: effectiveScale, offset: effectiveOffset)
                WallHandle(
                    roomID: room.id,
                    wallIndex: wall,
                    v1: v1, v2: v2,
                    centerScreen: handleScreen,
                    effectiveScale: effectiveScale,
                    snapToGrid: snapToGrid,
                    getRoom: { bindingForRoom(id: $0) },
                    onHistoryOnce: { floorPlan.saveToHistory() }
                )
                .allowsHitTesting(true)
            }
        }
    }

    // MARK: - Dimension overlay
    private func drawDimensions(for room: Room, size: CGSize, effectiveScale: CGFloat, effectiveOffset: CGSize) -> some View {
        let count = room.vertices.count
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let a = room.vertices[i]
                let b = room.vertices[(i + 1) % count]
                let dx = b.x - a.x, dy = b.y - a.y
                let lengthModel = hypot(dx, dy)
                if lengthModel > 0 {
                    let len = lengthModel
                    let unitNormal = CGPoint(x: -dy/len, y: dx/len)
                    let offsetScreen: CGFloat = 18
                    let offsetModel = offsetScreen / effectiveScale
                    let aOff = CGPoint(x: a.x + unitNormal.x * offsetModel, y: a.y + unitNormal.y * offsetModel)
                    let bOff = CGPoint(x: b.x + unitNormal.x * offsetModel, y: b.y + unitNormal.y * offsetModel)
                    let sa = modelToScreen(aOff, size: size, scale: effectiveScale, offset: effectiveOffset)
                    let sb = modelToScreen(bOff, size: size, scale: effectiveScale, offset: effectiveOffset)
                    let tickHalf: CGFloat = 5
                    let unitDir = CGPoint(x: dx/len, y: dy/len)
                    let tickNormal = CGPoint(x: -unitDir.y, y: unitDir.x)
                    let t1a = CGPoint(x: sa.x - tickNormal.x * tickHalf, y: sa.y - tickNormal.y * tickHalf)
                    let t1b = CGPoint(x: sa.x + tickNormal.x * tickHalf, y: sa.y + tickNormal.y * tickHalf)
                    let t2a = CGPoint(x: sb.x - tickNormal.x * tickHalf, y: sb.y - tickNormal.y * tickHalf)
                    let t2b = CGPoint(x: sb.x + tickNormal.x * tickHalf, y: sb.y + tickNormal.y * tickHalf)
                    let midScreen = CGPoint(x: (sa.x + sb.x)/2, y: (sa.y + sb.y)/2)
                    Path { p in
                        p.move(to: sa); p.addLine(to: sb)
                        p.move(to: t1a); p.addLine(to: t1b)
                        p.move(to: t2a); p.addLine(to: t2b)
                    }.stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                    Text(formattedLength(lengthModel))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.1).opacity(0.25), in: Capsule())
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .position(midScreen)
                }
            }
        }
    }

    private func formattedLength(_ meters: CGFloat) -> String {
        let v = Double(meters)
        return v >= 10 ? String(format: "%.1f m", v) : String(format: "%.2f m", v)
    }
}

// MARK: - Room Rendering with watermark + per-edge widths

private struct RoomRender: View {
    let room: Room
    let isSelected: Bool
    let isResizeMode: Bool
    let transform: (CGPoint) -> CGPoint

    // Wall widths (screen points)
    private let externalWidth: CGFloat = 5
    private let internalWidth: CGFloat = 2.5

    var body: some View {
        let path = room.path(using: transform)

        ZStack {
            // Fill
            path.fill(room.fillColor)

            // Watermark
            if !room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let rect = path.boundingRect
                let insetRect = rect.insetBy(dx: 16, dy: 28)
                if insetRect.width > 10, insetRect.height > 10 {
                    let base = min(insetRect.width, insetRect.height)
                    let fontSize = max(12, min(base * 0.28, 42))
                    Text(room.name)
                        .font(.system(size: fontSize, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary.opacity(0.045))
                        .frame(width: insetRect.width)
                        .position(x: insetRect.midX, y: insetRect.midY)
                        .allowsHitTesting(false)
                }
            }

            // Per-edge strokes
            if room.vertices.count >= 2 {
                let count = room.vertices.count
                ForEach(0..<count, id: \.self) { i in
                    let a = room.vertices[i]
                    let b = room.vertices[(i + 1) % count]
                    let sa = transform(a)
                    let sb = transform(b)
                    Path { p in p.move(to: sa); p.addLine(to: sb) }
                        .stroke(
                            isResizeMode ? Color.orange.opacity(0.9)
                            : (isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.7)),
                            lineWidth: (room.wallTypes.indices.contains(i) ? (room.wallTypes[i] == .externalWall ? externalWidth : internalWidth) : externalWidth)
                        )
                }
            }
        }
    }
}

// MARK: - Move capture overlay (polygon hit region, tap selects)

private struct RoomMoveCapture: View {
    let room: Room
    let isActive: Bool
    let effectiveScale: CGFloat
    let size: CGSize
    let effectiveOffset: CGSize
    let getBinding: (UUID) -> Binding<Room>?
    let snapToGrid: Bool
    let onHistory: () -> Void
    let onTap: (CGPoint) -> Void     // model-space tap point

    @State private var startVertices: [CGPoint] = []
    @State private var startLocation: CGPoint? = nil
    @State private var historySaved: Bool = false
    @State private var moved: Bool = false

    // Build the room path in SCREEN space for precise hit testing
    private func roomScreenPath() -> Path {
        var path = Path()
        guard let first = room.vertices.first else { return path }
        let sFirst = CGPoint(
            x: first.x * effectiveScale + size.width/2 + effectiveOffset.width,
            y: first.y * effectiveScale + size.height/2 + effectiveOffset.height
        )
        path.move(to: sFirst)
        for v in room.vertices.dropFirst() {
            let sv = CGPoint(
                x: v.x * effectiveScale + size.width/2 + effectiveOffset.width,
                y: v.y * effectiveScale + size.height/2 + effectiveOffset.height
            )
            path.addLine(to: sv)
        }
        path.closeSubpath()
        return path
    }

    var body: some View {
        let shape = roomScreenPath()

        shape
            .fill(Color.white.opacity(0.001))   // tiny alpha so it's hittable
            .contentShape(shape)                 // hit area = polygon, not fullscreen
            .allowsHitTesting(isActive)          // disabled when not in Select tool
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isActive, let binding = getBinding(room.id) else { return }

                        if startLocation == nil {
                            // start only if finger began inside the polygon
                            if !shape.contains(value.startLocation, eoFill: false) { return }
                            startLocation = value.startLocation
                            startVertices = binding.wrappedValue.vertices
                            historySaved = false
                            moved = false
                        }

                        guard let startLoc = startLocation else { return }

                        // Detect movement
                        let dxs = value.location.x - startLoc.x
                        let dys = value.location.y - startLoc.y
                        if !moved, (abs(dxs) > 2 || abs(dys) > 2) { moved = true }

                        // Save undo on first movement
                        if moved && !historySaved { onHistory(); historySaved = true }
                        guard moved else { return }

                        // Move by finger delta (screen → model)
                        let dxModel = dxs / effectiveScale
                        let dyModel = dys / effectiveScale
                        var updated = binding.wrappedValue
                        for i in updated.vertices.indices {
                            updated.vertices[i].x = startVertices[i].x + dxModel
                            updated.vertices[i].y = startVertices[i].y + dyModel
                        }
                        binding.wrappedValue = updated
                    }
                    .onEnded { value in
                        guard isActive else { cleanup(); return }

                        if !moved {
                            // Treat as a tap: report model-space point for wall pick
                            let tapModel = CGPoint(
                                x: (value.location.x - size.width / 2 - effectiveOffset.width) / effectiveScale,
                                y: (value.location.y - size.height / 2 - effectiveOffset.height) / effectiveScale
                            )
                            onTap(tapModel)
                            cleanup()
                            return
                        }

                        if let binding = getBinding(room.id), snapToGrid {
                            var updated = binding.wrappedValue
                            for i in updated.vertices.indices {
                                updated.vertices[i] = softlySnapPoint(updated.vertices[i])
                            }
                            binding.wrappedValue = updated
                        }
                        cleanup()
                    }
            )
    }

    private func cleanup() {
        startLocation = nil
        startVertices = []
        historySaved = false
        moved = false
    }
}

// MARK: - Rails (parallel wall move via normal projection)

private struct WallHitRail: View {
    let roomID: UUID
    let wallIndex: Int
    let v1: CGPoint
    let v2: CGPoint
    let effectiveScale: CGFloat
    let effectiveOffset: CGSize
    let snapToGrid: Bool
    let getRoom: (UUID) -> Binding<Room>?
    let onHistoryOnce: () -> Void   // called once when the first movement occurs

    @State private var startLocation: CGPoint?
    @State private var startVertices: [CGPoint] = []
    @State private var unitNormal: CGPoint = .zero
    @State private var historySaved: Bool = false

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let sStart = CGPoint(x: v1.x * effectiveScale + geo.size.width/2 + effectiveOffset.width,
                                     y: v1.y * effectiveScale + geo.size.height/2 + effectiveOffset.height)
                let sEnd = CGPoint(x: v2.x * effectiveScale + geo.size.width/2 + effectiveOffset.width,
                                   y: v2.y * effectiveScale + geo.size.height/2 + effectiveOffset.height)
                p.move(to: sStart)
                p.addLine(to: sEnd)
            }
            .stroke(Color.clear, lineWidth: 36) // fat, invisible hit rail
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let binding = getRoom(roomID) else { return }

                        if startLocation == nil {
                            startLocation = value.startLocation
                            startVertices = binding.wrappedValue.vertices
                            historySaved = false

                            // Compute the wall's unit normal from starting geometry
                            let s = startVertices[wallIndex]
                            let e = startVertices[(wallIndex + 1) % startVertices.count]
                            let dx = e.x - s.x, dy = e.y - s.y
                            let len = hypot(dx, dy)
                            unitNormal = len > 0 ? CGPoint(x: -dy/len, y: dx/len) : .zero
                        }

                        guard let startLoc = startLocation, unitNormal != .zero else { return }

                        // Save one snapshot at first motion
                        if !historySaved { onHistoryOnce(); historySaved = true }

                        // Convert drag delta (screen → model)
                        let deltaModel = CGPoint(
                            x: (value.location.x - startLoc.x) / effectiveScale,
                            y: (value.location.y - startLoc.y) / effectiveScale
                        )
                        // Project onto wall normal (parallel move)
                        let d = deltaModel.x * unitNormal.x + deltaModel.y * unitNormal.y
                        let offset = CGPoint(x: unitNormal.x * d, y: unitNormal.y * d)

                        var updated = binding.wrappedValue
                        let i1 = wallIndex
                        let i2 = (wallIndex + 1) % updated.vertices.count
                        updated.vertices[i1].x = startVertices[i1].x + offset.x
                        updated.vertices[i1].y = startVertices[i1].y + offset.y
                        updated.vertices[i2].x = startVertices[i2].x + offset.x
                        updated.vertices[i2].y = startVertices[i2].y + offset.y
                        binding.wrappedValue = updated
                    }
                    .onEnded { _ in
                        if snapToGrid, let binding = getRoom(roomID) {
                            var updated = binding.wrappedValue
                            let i1 = wallIndex
                            let i2 = (wallIndex + 1) % updated.vertices.count
                            updated.vertices[i1] = hardSnapPoint(updated.vertices[i1])
                            updated.vertices[i2] = hardSnapPoint(updated.vertices[i2])
                            binding.wrappedValue = updated
                        }
                        reset()
                    }
            )
        }
        .allowsHitTesting(true)
    }

    private func reset() {
        startLocation = nil
        startVertices = []
        unitNormal = .zero
        historySaved = false
    }
}

// MARK: - Handle (same parallel wall move; easier grab target)

private struct WallHandle: View {
    let roomID: UUID
    let wallIndex: Int
    let v1: CGPoint
    let v2: CGPoint
    let centerScreen: CGPoint
    let effectiveScale: CGFloat
    let snapToGrid: Bool
    let getRoom: (UUID) -> Binding<Room>?
    let onHistoryOnce: () -> Void

    @State private var startLocation: CGPoint?
    @State private var startVertices: [CGPoint] = []
    @State private var unitNormal: CGPoint = .zero
    @State private var historySaved: Bool = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .position(centerScreen)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let binding = getRoom(roomID) else { return }

                        if startLocation == nil {
                            startLocation = value.startLocation
                            startVertices = binding.wrappedValue.vertices
                            historySaved = false

                            // Compute wall normal from start geometry
                            let s = startVertices[wallIndex]
                            let e = startVertices[(wallIndex + 1) % startVertices.count]
                            let dx = e.x - s.x, dy = e.y - s.y
                            let len = hypot(dx, dy)
                            unitNormal = len > 0 ? CGPoint(x: -dy/len, y: dx/len) : .zero
                        }

                        guard let startLoc = startLocation, unitNormal != .zero else { return }

                        if !historySaved { onHistoryOnce(); historySaved = true }

                        let deltaModel = CGPoint(
                            x: (value.location.x - startLoc.x) / effectiveScale,
                            y: (value.location.y - startLoc.y) / effectiveScale
                        )
                        let d = deltaModel.x * unitNormal.x + deltaModel.y * unitNormal.y
                        let offset = CGPoint(x: unitNormal.x * d, y: unitNormal.y * d)

                        var updated = binding.wrappedValue
                        let i1 = wallIndex
                        let i2 = (wallIndex + 1) % updated.vertices.count
                        updated.vertices[i1].x = startVertices[i1].x + offset.x
                        updated.vertices[i1].y = startVertices[i1].y + offset.y
                        updated.vertices[i2].x = startVertices[i2].x + offset.x
                        updated.vertices[i2].y = startVertices[i2].y + offset.y
                        binding.wrappedValue = updated
                    }
                    .onEnded { _ in
                        if snapToGrid, let binding = getRoom(roomID) {
                            var updated = binding.wrappedValue
                            let i1 = wallIndex, i2 = (wallIndex + 1) % updated.vertices.count
                            updated.vertices[i1] = hardSnapPoint(updated.vertices[i1])
                            updated.vertices[i2] = hardSnapPoint(updated.vertices[i2])
                            binding.wrappedValue = updated
                        }
                        reset()
                    }
            )
    }

    private func reset() {
        startLocation = nil
        startVertices = []
        unitNormal = .zero
        historySaved = false
    }
}
