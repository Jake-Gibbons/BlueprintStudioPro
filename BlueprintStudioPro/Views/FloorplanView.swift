import SwiftUI

// MARK: - File-scope snapping helpers
fileprivate let GRID_STEP: CGFloat = 1.0
fileprivate let SNAP_TOLERANCE: CGFloat = 0.2

@inline(__always)
fileprivate func softlySnapValue(_ v: CGFloat,
                                 step: CGFloat = GRID_STEP,
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

/// Primary canvas for editing floor plans.
struct FloorPlanView: View {
    @EnvironmentObject private var floorPlan: FloorPlan
    @Binding var currentTool: Tool
    @Binding var snapToGrid: Bool
    @Binding var showDimensions: Bool

    // Working polygon (Draw Wall tool)
    @State private var workingVertices: [CGPoint] = []

    // Pan/zoom state
    @State private var panOffset: CGSize = .zero
    @State private var liveTwoFingerPan: CGSize = .zero
    @State private var scale: CGFloat = 60.0
    @GestureState private var gestureScale: CGFloat = 1.0

    // Move room
    @State private var roomDragTranslation: CGSize = .zero
    @State private var isDraggingRoom: Bool = false

    // Draw-room rubber-band
    @State private var drawRoomStart: CGPoint? = nil
    @State private var drawRoomCurrent: CGPoint? = nil

    // Live opening preview
    struct PreviewOpening { var roomID: UUID; var wallIndex: Int; var offset: CGFloat; var isDoor: Bool }
    @State private var previewOpening: PreviewOpening? = nil

    // Editable dimension tag
    @State private var editingDimension: (roomID: UUID, wallIndex: Int)? = nil
    @State private var editingText: String = ""

    private let unitLabel = "m"

    var body: some View {
        GeometryReader { geometry in
            let effectiveScale = scale * gestureScale
            let effectiveOffset = CGSize(width: panOffset.width + liveTwoFingerPan.width,
                                         height: panOffset.height + liveTwoFingerPan.height)

            ZStack {
                // Grid
                GridView(scale: effectiveScale, offset: effectiveOffset, size: geometry.size)

                // Rooms
                ForEach(floorPlan.rooms) { room in
                    let isSelected = room.id == floorPlan.selectedRoomID
                    let isResizeMode = (currentTool == .resize && isSelected)

                    // Render
                    RoomRender(
                        room: room,
                        isSelected: isSelected,
                        isResizeMode: isResizeMode,
                        transform: { modelToScreen($0, size: geometry.size, scale: effectiveScale, offset: effectiveOffset) }
                    )
                    .gesture(
                        TapGesture().onEnded { handleTapOnRoom(room: room) }
                    )

                    // --- MOVE CAPTURE LAYER (fixes movement reliability) ---
                    // Transparent fill of the room shape that owns the move drag.
                    RoomMoveCapture(
                        room: room,
                        isActive: currentTool == .select && isSelected,
                        effectiveScale: effectiveScale,
                        getBinding: { bindingForRoom(id: $0) },
                        snapToGrid: snapToGrid,
                        onHistory: { floorPlan.saveToHistory() }
                    )

                    // WINDOWS
                    ForEach(room.windows) { window in
                        let sidx = window.wallIndex % room.vertices.count
                        let eidx = (window.wallIndex + 1) % room.vertices.count
                        let start = room.vertices[sidx], end = room.vertices[eidx]
                        let (p1, p2) = openingPoints(start: start, end: end, attachment: window)
                        let s1 = modelToScreen(p1, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                        let s2 = modelToScreen(p2, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)

                        Path { $0.move(to: s1); $0.addLine(to: s2) }
                            .stroke(Color.teal.opacity(0.7), lineWidth: 3)
                            .overlay(
                                Path { $0.move(to: s1); $0.addLine(to: s2) }
                                    .stroke(Color.clear, lineWidth: 28)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                let mt = CGPoint(x: value.translation.width / effectiveScale, y: value.translation.height / effectiveScale)
                                                let wdx = end.x - start.x, wdy = end.y - start.y
                                                let wallLen = hypot(wdx, wdy); guard wallLen > 0 else { return }
                                                let unit = CGPoint(x: wdx / wallLen, y: wdy / wallLen)
                                                let delta = mt.x * unit.x + mt.y * unit.y
                                                if let rIdx = floorPlan.rooms.firstIndex(where: { $0.id == room.id }),
                                                   let wIdx = floorPlan.rooms[rIdx].windows.firstIndex(where: { $0.id == window.id }) {
                                                    var r = floorPlan.rooms[rIdx]
                                                    var w = r.windows[wIdx]
                                                    w.offset = min(max(w.offset + (delta / wallLen), 0), 1)
                                                    r.windows[wIdx] = w
                                                    floorPlan.rooms[rIdx] = r
                                                }
                                            }
                                            .onEnded { _ in floorPlan.saveToHistory() }
                                    )
                            )
                    }

                    // DOORS
                    ForEach(room.doors) { door in
                        let sidx = door.wallIndex % room.vertices.count
                        let eidx = (door.wallIndex + 1) % room.vertices.count
                        let start = room.vertices[sidx], end = room.vertices[eidx]
                        let (p1, p2) = openingPoints(start: start, end: end, attachment: door)
                        let s1 = modelToScreen(p1, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                        let s2 = modelToScreen(p2, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)

                        Path { $0.move(to: s1); $0.addLine(to: s2) }
                            .stroke(Color.brown.opacity(0.7), lineWidth: 5)
                            .overlay(
                                Path { $0.move(to: s1); $0.addLine(to: s2) }
                                    .stroke(Color.clear, lineWidth: 36)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                let mt = CGPoint(x: value.translation.width / effectiveScale, y: value.translation.height / effectiveScale)
                                                let wdx = end.x - start.x, wdy = end.y - start.y
                                                let wallLen = hypot(wdx, wdy); guard wallLen > 0 else { return }
                                                let unit = CGPoint(x: wdx / wallLen, y: wdy / wallLen)
                                                let delta = mt.x * unit.x + mt.y * unit.y
                                                if let rIdx = floorPlan.rooms.firstIndex(where: { $0.id == room.id }),
                                                   let dIdx = floorPlan.rooms[rIdx].doors.firstIndex(where: { $0.id == door.id }) {
                                                    var r = floorPlan.rooms[rIdx]
                                                    var d = r.doors[dIdx]
                                                    d.offset = min(max(d.offset + (delta / wallLen), 0), 1)
                                                    r.doors[dIdx] = d
                                                    floorPlan.rooms[rIdx] = r
                                                }
                                            }
                                            .onEnded { _ in floorPlan.saveToHistory() }
                                    )
                            )
                    }

                    // === RESIZE MODE visuals (all walls + handles) ===
                    if isResizeMode {
                        let count = room.vertices.count
                        ForEach(0..<count, id: \.self) { wall in
                            let v1 = room.vertices[wall]
                            let v2 = room.vertices[(wall + 1) % count]

                            Path { path in
                                let sStart = modelToScreen(v1, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                                let sEnd = modelToScreen(v2, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                                path.move(to: sStart); path.addLine(to: sEnd)
                            }
                            .stroke(Color.orange.opacity(0.9), lineWidth: 4)

                            WallHitRail(
                                roomID: room.id,
                                wallIndex: wall,
                                v1: v1, v2: v2,
                                effectiveScale: effectiveScale,
                                snapToGrid: snapToGrid,
                                getRoom: { bindingForRoom(id: $0) },
                                onCommit: { floorPlan.saveToHistory() }
                            )
                            .allowsHitTesting(true)

                            let dx = v2.x - v1.x, dy = v2.y - v1.y
                            let len = hypot(dx, dy)
                            if len > 0 {
                                let mid = CGPoint(x: (v1.x + v2.x)/2, y: (v1.y + v2.y)/2)
                                let unitNormal = CGPoint(x: -dy / len, y: dx / len)
                                let offsetModel = 16.0 / effectiveScale
                                let handleModelPos = CGPoint(x: mid.x + unitNormal.x * offsetModel, y: mid.y + unitNormal.y * offsetModel)
                                let handleScreen = modelToScreen(handleModelPos, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)

                                WallHandle(
                                    roomID: room.id,
                                    wallIndex: wall,
                                    v1: v1, v2: v2,
                                    centerScreen: handleScreen,
                                    effectiveScale: effectiveScale,
                                    snapToGrid: snapToGrid,
                                    getRoom: { bindingForRoom(id: $0) },
                                    onCommit: { floorPlan.saveToHistory() }
                                )
                                .allowsHitTesting(true)
                            }
                        }
                    }
                    // === Single-wall selection visuals (bring back the handle) ===
                    else if let selectedID = floorPlan.selectedRoomID,
                            selectedID == room.id,
                            let wall = floorPlan.selectedWallIndex,
                            room.vertices.indices.contains(wall) {

                        let v1 = room.vertices[wall], v2 = room.vertices[(wall + 1) % room.vertices.count]

                        Path { path in
                            let sStart = modelToScreen(v1, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                            let sEnd = modelToScreen(v2, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                            path.move(to: sStart); path.addLine(to: sEnd)
                        }
                        .stroke(Color.orange.opacity(0.9), lineWidth: 4)

                        WallHitRail(
                            roomID: room.id,
                            wallIndex: wall,
                            v1: v1, v2: v2,
                            effectiveScale: effectiveScale,
                            snapToGrid: snapToGrid,
                            getRoom: { bindingForRoom(id: $0) },
                            onCommit: { floorPlan.saveToHistory() }
                        )
                        .allowsHitTesting(true)

                        // Visible handle (it had disappeared; restored here)
                        let dx = v2.x - v1.x, dy = v2.y - v1.y
                        let len = hypot(dx, dy)
                        if len > 0 {
                            let mid = CGPoint(x: (v1.x + v2.x)/2, y: (v1.y + v2.y)/2)
                            let unitNormal = CGPoint(x: -dy / len, y: dx / len)
                            let offsetModel = 16.0 / effectiveScale
                            let handleModelPos = CGPoint(x: mid.x + unitNormal.x * offsetModel, y: mid.y + unitNormal.y * offsetModel)
                            let handleScreen = modelToScreen(handleModelPos, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)

                            WallHandle(
                                roomID: room.id,
                                wallIndex: wall,
                                v1: v1, v2: v2,
                                centerScreen: handleScreen,
                                effectiveScale: effectiveScale,
                                snapToGrid: snapToGrid,
                                getRoom: { bindingForRoom(id: $0) },
                                onCommit: { floorPlan.saveToHistory() }
                            )
                            .allowsHitTesting(true)
                        }
                    }

                    // Dimensions
                    if showDimensions {
                        drawDimensions(for: room, size: geometry.size, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
                            .allowsHitTesting(false)
                    }
                }

                // Live opening preview
                if let preview = previewOpening,
                   let room = floorPlan.rooms.first(where: { $0.id == preview.roomID }) {
                    let start = room.vertices[preview.wallIndex]
                    let end = room.vertices[(preview.wallIndex + 1) % room.vertices.count]
                    let ghost = Window(wallIndex: preview.wallIndex, offset: preview.offset, length: preview.isDoor ? 0.9 : 1.0)
                    let (p1, p2) = openingPoints(start: start, end: end, attachment: ghost)
                    let s1 = modelToScreen(p1, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                    let s2 = modelToScreen(p2, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                    Path { $0.move(to: s1); $0.addLine(to: s2) }
                        .stroke(preview.isDoor ? Color.brown.opacity(0.6) : Color.teal.opacity(0.6),
                                style: StrokeStyle(lineWidth: preview.isDoor ? 5 : 3, dash: [6, 4]))
                }

                // Temp polyline when drawing custom polygon
                if currentTool == .drawWall && !workingVertices.isEmpty {
                    Path { path in
                        let pts = workingVertices.map { modelToScreen($0, size: geometry.size, scale: effectiveScale, offset: effectiveOffset) }
                        path.move(to: pts[0]); for p in pts.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }

                // Draw-room rubber band preview
                if let a = drawRoomStart, let b = drawRoomCurrent, currentTool == .drawRoom {
                    let rect = normalizedRect(from: a, to: b)
                    let sRect = modelRectToScreen(rect, size: geometry.size, scale: effectiveScale, offset: effectiveOffset)
                    Rectangle()
                        .path(in: sRect)
                        .stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Rectangle().fill(Color.accentColor.opacity(0.05)).frame(width: sRect.width, height: sRect.height).position(x: sRect.midX, y: sRect.midY))
                }

                // Two-finger pan overlay (works; does not block single-finger)
                TwoFingerPanGestureView(
                    onChanged: { translation in
                        guard !isDraggingRoom else { return }
                        liveTwoFingerPan = translation
                    },
                    onEnded: { translation in
                        guard !isDraggingRoom else { return }
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
        }
    }

    // MARK: - Bindings
    private func bindingForRoom(id: UUID) -> Binding<Room>? {
        guard let idx = floorPlan.rooms.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { floorPlan.rooms[idx] },
                       set: { floorPlan.rooms[idx] = $0 })
    }

    // MARK: - Transforms
    private func modelToScreen(_ p: CGPoint, size: CGSize, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: p.x * scale + size.width/2 + offset.width,
                y: p.y * scale + size.height/2 + offset.height)
    }
    private func screenToModel(_ p: CGPoint, size: CGSize, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: (p.x - size.width/2 - offset.width) / scale,
                y: (p.y - size.height/2 - offset.height) / scale)
    }
    private func modelRectToScreen(_ r: CGRect, size: CGSize, scale: CGFloat, offset: CGSize) -> CGRect {
        let origin = modelToScreen(r.origin, size: size, scale: scale, offset: offset)
        return CGRect(x: origin.x, y: origin.y, width: r.width * scale, height: r.height * scale)
    }

    // MARK: - Gestures
    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in state = value }
            .onEnded { value in
                scale = max(10, min(scale * value, 300))
            }
    }

    private func mainGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let effectiveScale = scale * gestureScale
                let offset = CGSize(width: panOffset.width + liveTwoFingerPan.width,
                                    height: panOffset.height + liveTwoFingerPan.height)
                let modelPoint = screenToModel(value.location, size: size, scale: effectiveScale, offset: offset)

                switch currentTool {
                case .select:
                    break // move handled by RoomMoveCapture; tap handled onEnded
                case .delete:
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
                    if let selID = floorPlan.selectedRoomID,
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
                    floorPlan.selectedRoomID = room.id
                    floorPlan.selectedWallIndex = wallIndex
                case .resize:
                    break
                }
            }
            .onEnded { value in
                let effectiveScale = scale * gestureScale
                let offset = CGSize(width: panOffset.width + liveTwoFingerPan.width,
                                    height: panOffset.height + liveTwoFingerPan.height)
                let modelPoint = screenToModel(value.location, size: size, scale: effectiveScale, offset: offset)

                switch currentTool {
                case .select:
                    // Tap empty clears selection
                    let hitAny = floorPlan.rooms.contains { $0.contains(point: modelPoint) }
                    if !hitAny {
                        floorPlan.selectedRoomID = nil
                        floorPlan.selectedWallIndex = nil
                    } else {
                        floorPlan.selectRoom(containing: modelPoint)
                        if floorPlan.selectedRoomID != nil {
                            floorPlan.selectWall(near: modelPoint, threshold: 0.3)
                        }
                    }
                case .delete:
                    floorPlan.selectRoom(containing: modelPoint)
                    floorPlan.deleteSelectedRoom()
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
                        floorPlan.selectedRoomID = preview.roomID
                        floorPlan.selectedWallIndex = preview.wallIndex
                        if preview.isDoor { floorPlan.addDoor(at: preview.offset) }
                        else { floorPlan.addWindow(at: preview.offset) }
                    }
                    previewOpening = nil
                case .resize:
                    break
                }
            }
    }

    // MARK: - Utilities
    private func addRectRoom(_ rect: CGRect) {
        let v1 = rect.origin
        let v2 = CGPoint(x: rect.maxX, y: rect.minY)
        let v3 = CGPoint(x: rect.maxX, y: rect.maxY)
        let v4 = CGPoint(x: rect.minX, y: rect.maxY)
        floorPlan.addRoom(vertices: [v1, v2, v3, v4])
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x),
               y: min(a.y, b.y),
               width: abs(b.x - a.x),
               height: abs(b.y - a.y))
    }

    private func handleTapOnRoom(room: Room) {
        switch currentTool {
        case .select, .addWindow, .addDoor, .resize:
            floorPlan.selectedRoomID = room.id
        default: break
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

    private func snappedDeltaForRoomMove(dx: CGFloat, dy: CGFloat, currentVertices: [CGPoint]) -> (CGFloat, CGFloat) {
        var bestDx = dx, bestDy = dy
        var bestAbsX: CGFloat = .infinity
        for v in currentVertices {
            let xAfter = v.x + dx
            let targetX = round(xAfter / GRID_STEP) * GRID_STEP
            let corr = targetX - xAfter
            if abs(corr) <= SNAP_TOLERANCE, abs(corr) < bestAbsX {
                bestAbsX = abs(corr); bestDx = dx + corr
            }
        }
        var bestAbsY: CGFloat = .infinity
        for v in currentVertices {
            let yAfter = v.y + dy
            let targetY = round(yAfter / GRID_STEP) * GRID_STEP
            let corr = targetY - yAfter
            if abs(corr) <= SNAP_TOLERANCE, abs(corr) < bestAbsY {
                bestAbsY = abs(corr); bestDy = dy + corr
            }
        }
        return (bestDx, bestDy)
    }

    // MARK: - Dimensions (subtle) + editable labels
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
                    let unitNormal = CGPoint(x: -dy / len, y: dx / len)
                    let offsetScreen: CGFloat = 18
                    let offsetModel = offsetScreen / effectiveScale

                    let aOff = CGPoint(x: a.x + unitNormal.x * offsetModel, y: a.y + unitNormal.y * offsetModel)
                    let bOff = CGPoint(x: b.x + unitNormal.x * offsetModel, y: b.y + unitNormal.y * offsetModel)

                    let sa = modelToScreen(aOff, size: size, scale: effectiveScale, offset: effectiveOffset)
                    let sb = modelToScreen(bOff, size: size, scale: effectiveScale, offset: effectiveOffset)

                    let tickHalf: CGFloat = 5
                    let unitDir = CGPoint(x: dx / len, y: dy / len)
                    let tickNormal = CGPoint(x: -unitDir.y, y: unitDir.x)
                    let t1a = CGPoint(x: sa.x - tickNormal.x * tickHalf, y: sa.y - tickNormal.y * tickHalf)
                    let t1b = CGPoint(x: sa.x + tickNormal.x * tickHalf, y: sa.y + tickNormal.y * tickHalf)
                    let t2a = CGPoint(x: sb.x - tickNormal.x * tickHalf, y: sb.y - tickNormal.y * tickHalf)
                    let t2b = CGPoint(x: sb.x + tickNormal.x * tickHalf, y: sb.y + tickNormal.y * tickHalf)

                    let midScreen = CGPoint(x: (sa.x + sb.x)/2, y: (sa.y + sb.y)/2)
                    let angle = atan2(sb.y - sa.y, sb.x - sa.x)
                    let labelAngle = angle > .pi/2 || angle < -.pi/2 ? angle + .pi : angle

                    Path { p in
                        p.move(to: sa); p.addLine(to: sb)
                        p.move(to: t1a); p.addLine(to: t1b)
                        p.move(to: t2a); p.addLine(to: t2b)
                    }
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)

                    let formatted = formattedLength(lengthModel)
                    let isEditing = editingDimension?.roomID == room.id && editingDimension?.wallIndex == i

                    if isEditing {
                        EditableDimensionField(
                            text: $editingText,
                            onCommit: { commitDimensionEdit(roomID: room.id, wallIndex: i, text: editingText) },
                            onCancel: { editingDimension = nil }
                        )
                        .frame(width: 80)
                        .rotationEffect(Angle(radians: Double(labelAngle)))
                        .position(midScreen)
                        .allowsHitTesting(true)
                    } else {
                        Text(formatted)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.1).opacity(0.25), in: Capsule())
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .rotationEffect(Angle(radians: Double(labelAngle)))
                            .position(midScreen)
                            .onTapGesture {
                                editingDimension = (roomID: room.id, wallIndex: i)
                                editingText = String(format: "%.2f", Double(lengthModel))
                            }
                            .allowsHitTesting(true)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }

    private func commitDimensionEdit(roomID: UUID, wallIndex: Int, text: String) {
        defer { editingDimension = nil }
        let sanitized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(sanitized), value > 0 else { return }
        let newLen = CGFloat(value)

        guard let binding = bindingForRoom(id: roomID) else { return }
        var room = binding.wrappedValue
        guard room.vertices.indices.contains(wallIndex) else { return }

        let i1 = wallIndex
        let i2 = (wallIndex + 1) % room.vertices.count
        let s = room.vertices[i1], e = room.vertices[i2]
        let dx = e.x - s.x, dy = e.y - s.y
        let len = hypot(dx, dy); guard len > 0 else { return }

        let mid = CGPoint(x: (s.x + e.x)/2, y: (s.y + e.y)/2)
        let unitDir = CGPoint(x: dx / len, y: dy / len)
        let half = newLen / 2
        room.vertices[i1] = CGPoint(x: mid.x - unitDir.x * half, y: mid.y - unitDir.y * half)
        room.vertices[i2] = CGPoint(x: mid.x + unitDir.x * half, y: mid.y + unitDir.y * half)

        if snapToGrid {
            room.vertices[i1] = hardSnapPoint(room.vertices[i1])
            room.vertices[i2] = hardSnapPoint(room.vertices[i2])
        }

        floorPlan.saveToHistory()
        binding.wrappedValue = room
    }

    private func formattedLength(_ meters: CGFloat) -> String {
        let v = Double(meters)
        return v >= 10 ? String(format: "%.1f %@", v, unitLabel)
                       : String(format: "%.2f %@", v, unitLabel)
    }
}

// MARK: - Render subview
private struct RoomRender: View {
    let room: Room
    let isSelected: Bool
    let isResizeMode: Bool
    let transform: (CGPoint) -> CGPoint

    var body: some View {
        let path = room.path(using: transform)

        ZStack {
            path.fill(room.fillColor)

            if isResizeMode {
                path.fill(Color.orange.opacity(0.08))
            }

            path.stroke(
                isResizeMode
                    ? Color.orange.opacity(0.9)
                    : (isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.7)),
                lineWidth: isResizeMode ? 3 : (isSelected ? 2 : 1)
            )
            .shadow(color: (isSelected || isResizeMode) ? Color.accentColor.opacity(0.18) : .clear, radius: 6)
        }
    }
}

// MARK: - Move capture layer
/// Transparent hit layer that uses the actual room shape as the drag area,
/// so room movement in Select mode is reliable.
private struct RoomMoveCapture: View {
    let room: Room
    let isActive: Bool
    let effectiveScale: CGFloat
    let getBinding: (UUID) -> Binding<Room>?
    let snapToGrid: Bool
    let onHistory: () -> Void

    @State private var roomDragTranslation: CGSize = .zero
    @State private var isDraggingRoom: Bool = false

    var body: some View {
        let path = room.path(using: { p in
            // We don't know container size/offset here, but SwiftUI only needs the shape for hit-testing.
            // Use a unit transform; attach gesture without drawing.
            CGPoint(x: p.x * effectiveScale, y: p.y * effectiveScale)
        })

        path
            .fill(Color.clear)
            .contentShape(path)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        guard isActive, let binding = getBinding(room.id) else { return }
                        if !isDraggingRoom { isDraggingRoom = true }

                        var dx = (value.translation.width - roomDragTranslation.width) / effectiveScale
                        var dy = (value.translation.height - roomDragTranslation.height) / effectiveScale

                        if snapToGrid {
                            (dx, dy) = snappedDeltaForRoomMove(dx: dx, dy: dy, currentVertices: binding.wrappedValue.vertices)
                        }

                        var updated = binding.wrappedValue
                        for i in updated.vertices.indices {
                            updated.vertices[i].x += dx
                            updated.vertices[i].y += dy
                        }
                        binding.wrappedValue = updated

                        roomDragTranslation.width += dx * effectiveScale
                        roomDragTranslation.height += dy * effectiveScale
                    }
                    .onEnded { _ in
                        guard isActive, let binding = getBinding(room.id) else { return }
                        if snapToGrid {
                            var updated = binding.wrappedValue
                            for i in updated.vertices.indices {
                                updated.vertices[i] = softlySnapPoint(updated.vertices[i])
                            }
                            binding.wrappedValue = updated
                        }
                        roomDragTranslation = .zero
                        isDraggingRoom = false
                        onHistory()
                    }
            )
            .allowsHitTesting(isActive)
    }
}

// MARK: - Hit rails & handles
private struct WallHitRail: View {
    let roomID: UUID
    let wallIndex: Int
    let v1: CGPoint
    let v2: CGPoint
    let effectiveScale: CGFloat
    let snapToGrid: Bool
    let getRoom: (UUID) -> Binding<Room>?
    let onCommit: () -> Void

    @State private var startLocation: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            let sStart = modelToScreen(v1, geo: geo)
            let sEnd   = modelToScreen(v2, geo: geo)

            Path { p in p.move(to: sStart); p.addLine(to: sEnd) }
                .stroke(Color.clear, lineWidth: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if startLocation == nil { startLocation = value.startLocation }
                            guard let binding = getRoom(roomID) else { return }
                            var updated = binding.wrappedValue

                            let i1 = wallIndex
                            let i2 = (wallIndex + 1) % updated.vertices.count
                            let s = updated.vertices[i1], e = updated.vertices[i2]

                            let dx = e.x - s.x, dy = e.y - s.y
                            let len = hypot(dx, dy); guard len > 0 else { return }

                            let unitNormal = CGPoint(x: -dy / len, y: dx / len)

                            let absDx = (value.location.x - (startLocation?.x ?? value.startLocation.x)) / effectiveScale
                            let absDy = (value.location.y - (startLocation?.y ?? value.startLocation.y)) / effectiveScale
                            var deltaNormal = absDx * unitNormal.x + absDy * unitNormal.y

                            if snapToGrid {
                                let movedS = CGPoint(x: s.x + unitNormal.x * deltaNormal, y: s.y + unitNormal.y * deltaNormal)
                                let movedE = CGPoint(x: e.x + unitNormal.x * deltaNormal, y: e.y + unitNormal.y * deltaNormal)
                                let snappedS = softlySnapPoint(movedS), snappedE = softlySnapPoint(movedE)
                                if movedS != snappedS || movedE != snappedE {
                                    let corrS = ((snappedS.x - movedS.x) * unitNormal.x + (snappedS.y - movedS.y) * unitNormal.y)
                                    let corrE = ((snappedE.x - movedE.x) * unitNormal.x + (snappedE.y - movedE.y) * unitNormal.y)
                                    deltaNormal += (corrS + corrE) / 2
                                }
                            }

                            let deltaVec = CGPoint(x: unitNormal.x * deltaNormal, y: unitNormal.y * deltaNormal)
                            updated.vertices[i1].x = s.x + deltaVec.x
                            updated.vertices[i1].y = s.y + deltaVec.y
                            updated.vertices[i2].x = e.x + deltaVec.x
                            updated.vertices[i2].y = e.y + deltaVec.y

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
                            startLocation = nil
                            onCommit()
                        }
                )
        }
        .allowsHitTesting(true)
    }

    private func modelToScreen(_ p: CGPoint, geo: GeometryProxy) -> CGPoint {
        CGPoint(x: p.x * effectiveScale + geo.size.width/2, y: p.y * effectiveScale + geo.size.height/2)
    }
}

private struct WallHandle: View {
    let roomID: UUID
    let wallIndex: Int
    let v1: CGPoint
    let v2: CGPoint
    let centerScreen: CGPoint
    let effectiveScale: CGFloat
    let snapToGrid: Bool
    let getRoom: (UUID) -> Binding<Room>?
    let onCommit: () -> Void

    @State private var startLocation: CGPoint? = nil

    var body: some View {
        Circle()
            .fill(Color.orange)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .position(centerScreen)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startLocation == nil { startLocation = value.startLocation }
                        guard let binding = getRoom(roomID) else { return }
                        var updated = binding.wrappedValue

                        let i1 = wallIndex
                        let i2 = (wallIndex + 1) % updated.vertices.count
                        let s = updated.vertices[i1], e = updated.vertices[i2]

                        let dx = e.x - s.x, dy = e.y - s.y
                        let len = hypot(dx, dy); guard len > 0 else { return }

                        let unitNormal = CGPoint(x: -dy / len, y: dx / len)

                        let absDx = (value.location.x - (startLocation?.x ?? value.startLocation.x)) / effectiveScale
                        let absDy = (value.location.y - (startLocation?.y ?? value.startLocation.y)) / effectiveScale
                        var deltaNormal = absDx * unitNormal.x + absDy * unitNormal.y

                        if snapToGrid {
                            let movedS = CGPoint(x: s.x + unitNormal.x * deltaNormal, y: s.y + unitNormal.y * deltaNormal)
                            let movedE = CGPoint(x: e.x + unitNormal.x * deltaNormal, y: e.y + unitNormal.y * deltaNormal)
                            let snappedS = softlySnapPoint(movedS), snappedE = softlySnapPoint(movedE)
                            if movedS != snappedS || movedE != snappedE {
                                let corrS = ((snappedS.x - movedS.x) * unitNormal.x + (snappedS.y - movedS.y) * unitNormal.y)
                                let corrE = ((snappedE.x - movedE.x) * unitNormal.x + (snappedE.y - movedE.y) * unitNormal.y)
                                deltaNormal += (corrS + corrE) / 2
                            }
                        }

                        let deltaVec = CGPoint(x: unitNormal.x * deltaNormal, y: unitNormal.y * deltaNormal)
                        updated.vertices[i1].x = s.x + deltaVec.x
                        updated.vertices[i1].y = s.y + deltaVec.y
                        updated.vertices[i2].x = e.x + deltaVec.x
                        updated.vertices[i2].y = e.y + deltaVec.y

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
                        startLocation = nil
                        onCommit()
                    }
            )
    }
}

// MARK: - Dimensions editor
private struct EditableDimensionField: View {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, onCommit: onCommit)
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.1).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .focused($focused)
            .onAppear { focused = true }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { onCommit() }
                    Button("Cancel") { onCancel() }
                }
            }
    }
}
