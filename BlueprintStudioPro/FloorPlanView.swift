import SwiftUI

/// A simplified view for editing and displaying a floor plan. It renders
/// rooms as polygons and supports adding and manipulating staircases as well
/// as doors and windows. Stairs can be placed by tapping inside a room when
/// the stairs tool is active. Doors and windows can be inserted by tapping
/// near a wall when the corresponding tool is active; the type of opening
/// (single, double, etc.) is provided via bindings from the parent view.
/// Once placed, stairs can be moved, rotated and resized via drag,
/// rotation and pinch gestures when the resize tool is selected. This
/// implementation focuses on correcting the issues reported around stairs
/// placement and project‑pill interactivity, while extending support for
/// opening insertion and optional dimension overlays.
struct FloorPlanView: View {
    @EnvironmentObject var floorPlan: Floorplan
    @EnvironmentObject var settings: AppSettings

    /// The currently selected editing tool (inherited from the parent ContentView).
    @Binding var currentTool: EditorTool
    @Binding var snapToGrid: Bool
    @Binding var showDimensions: Bool
    /// Bindings indicating the selected opening styles from the toolbar. These
    /// strings map to the `DoorType` and `WindowType` enums. When the user
    /// taps with the add‑door or add‑window tool active, the view will insert
    /// an attachment of the corresponding type on the nearest wall.
    @Binding var selectedDoorType: String
    @Binding var selectedWindowType: String

    // Viewport transform state for panning and zooming. The `viewportScale`
    // multiplies the points‑per‑metre setting to zoom the entire canvas. The
    // `viewportOffset` shifts the origin, enabling the user to pan around the
    // drawing. `lastScale` and `lastOffset` track the previous values at
    // the start of a gesture.
    @State private var viewportScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var viewportOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let scale = settings.pointsPerMeter

            // Precompute unique edges and their desired stroke widths. Edges shared
            // between two rooms are drawn once with the internal wall width. Other
            // edges (i.e. exterior walls) use the external wall width. We sort
            // endpoints to create a consistent key regardless of order.
            let edgeInfos: [(CGPoint, CGPoint, CGFloat)] = {
                struct EdgeKey: Hashable {
                    let a: CGPoint
                    let b: CGPoint
                    init(_ p: CGPoint, _ q: CGPoint) {
                        // Normalise orientation by sorting endpoints lexicographically
                        if p.x < q.x || (p.x == q.x && p.y <= q.y) {
                            self.a = p; self.b = q
                        } else {
                            self.a = q; self.b = p
                        }
                    }
                }
                var counts: [EdgeKey: Int] = [:]
                var originals: [EdgeKey: (CGPoint, CGPoint)] = [:]
                for room in floorPlan.rooms {
                    let verts = room.vertices
                    guard verts.count >= 2 else { continue }
                    for i in 0..<verts.count {
                        let a = verts[i]
                        let b = verts[(i + 1) % verts.count]
                        let key = EdgeKey(a, b)
                        counts[key, default: 0] += 1
                        if originals[key] == nil { originals[key] = (a, b) }
                    }
                }
                var result: [(CGPoint, CGPoint, CGFloat)] = []
                for (key, count) in counts {
                    guard let (a, b) = originals[key] else { continue }
                    let width = (count > 1) ? settings.internalWallWidthPt : settings.externalWallWidthPt
                    result.append((a, b, width))
                }
                return result
            }()

            ZStack {
                // Background fill
                settings.backgroundColor
                    .ignoresSafeArea()

                // Optional grid overlay
                if settings.showGrid {
                    Path { path in
                        // Vertical and horizontal grid lines. The step scales with
                        // the current viewport zoom.
                        let step = settings.gridStepMeters * settings.pointsPerMeter * viewportScale
                        guard step > 0 else { return }

                        // Start drawing lines from the centre adjusted by the current pan.
                        // We draw in both directions from 0 to cover the entire view.
                        var x = fmod((geo.size.width / 2 + viewportOffset.width), step)
                        if x < 0 { x += step }
                        while x <= geo.size.width {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                            x += step
                        }
                        var y = fmod((geo.size.height / 2 + viewportOffset.height), step)
                        if y < 0 { y += step }
                        while y <= geo.size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            y += step
                        }
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                }

                // Draw all rooms on the current floor
                ForEach(floorPlan.rooms) { room in
                    // Convert vertices to view space
                    let pts = room.vertices.map { modelToView($0, scale: scale, in: geo.size) }

                    Path { path in
                        guard let first = pts.first else { return }
                        path.move(to: first)
                        for p in pts.dropFirst() { path.addLine(to: p) }
                        path.closeSubpath()
                    }
                    // Use the room's own random pastel with its built‑in alpha.
                    .fill(room.fillColor)
                    .overlay(
                        Path { path in
                            guard let first = pts.first else { return }
                            path.move(to: first)
                            for p in pts.dropFirst() { path.addLine(to: p) }
                            path.closeSubpath()
                        }
                        .stroke(Color.primary, lineWidth: settings.externalWallWidthPt)
                    )

                    // Draw staircases for this room
                    ForEach(room.stairs) { stairs in
                        let viewCenter = modelToView(stairs.center, scale: scale, in: geo.size)

                        // Size of the stairs in view coordinates scaled by both points‑per‑metre and viewport zoom
                        let viewWidth  = stairs.length * settings.pointsPerMeter * viewportScale
                        let viewHeight = stairs.width  * settings.pointsPerMeter * viewportScale

                        StairsShape(steps: stairs.steps)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: viewWidth, height: viewHeight)
                            .position(viewCenter)
                            .rotationEffect(Angle(radians: stairs.rotation))
                            // When in resize mode allow the user to manipulate the stairs
                            .gesture(stairsGesture(for: stairs, in: room))
                    }
                }

                // Draw each unique wall segment once with the appropriate thickness.
                // Shared walls between rooms are internal and use the internal wall width;
                // exterior walls use the external wall width.
                ForEach(Array(edgeInfos.enumerated()), id: \.offset) { pair in
                    let info = pair.element
                    let a = modelToView(info.0, scale: scale, in: geo.size)
                    let b = modelToView(info.1, scale: scale, in: geo.size)
                    Path { path in
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                    .stroke(Color.primary, lineWidth: info.2)
                }

                // Overlay dimension labels if requested. For each wall of each room,
                // compute the midpoint and display the length in metres. Offsetting
                // the text slightly upward avoids overlapping the stroke. This
                // overlay appears on top of walls but under interactive elements.
                if showDimensions {
                    ForEach(floorPlan.rooms) { room in
                        let verts = room.vertices
                        ForEach(0..<verts.count, id: \.self) { i in
                            let a = verts[i]
                            let b = verts[(i + 1) % verts.count]
                            let length = hypot(b.x - a.x, b.y - a.y)
                            let mid = CGPoint(x: (a.x + b.x) / 2.0, y: (a.y + b.y) / 2.0)
                            let viewPt = modelToView(mid, scale: scale, in: geo.size)
                            Text(String(format: "%.2f", length))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .background(Color.white.opacity(0.5))
                                .position(x: viewPt.x, y: viewPt.y - 10)
                        }
                    }
                }
            }
            // Gestures: Combine pan and zoom gestures. Tap gestures respond to
            // the current tool to perform actions such as selection, drawing,
            // placing stairs and openings. Taps convert the location to model
            // coordinates and call handleTap on release.
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 1)
                    .onEnded { value in
                        // Convert tap location to model coordinates and handle accordingly.
                        let point = value.location
                        let model = viewToModel(point, scale: scale, in: geo.size)
                        handleTap(at: model)
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard currentTool == .select else { return }
                        let dx = value.translation.width - lastOffset.width
                        let dy = value.translation.height - lastOffset.height
                        viewportOffset.width += dx
                        viewportOffset.height += dy
                        lastOffset = value.translation
                    }
                    .onEnded { _ in
                        lastOffset = .zero
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        guard currentTool == .select else { return }
                        let delta = value / lastScale
                        viewportScale *= delta
                        lastScale = value
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                    }
            )
        }
    }

    // MARK: - Coordinate conversion
    /// Converts a model point (metres) to a view point (screen points) by scaling
    /// and centring the coordinate system. The y axis is flipped so that
    /// increasing y in model space maps to downwards on screen.
    private func modelToView(_ p: CGPoint, scale: CGFloat, in size: CGSize) -> CGPoint {
        // Apply model scaling (points per metre), viewport zoom and pan. The
        // origin is centred in the view and then shifted by `viewportOffset`.
        let s = scale * viewportScale
        return CGPoint(
            x: p.x * s + size.width / 2 + viewportOffset.width,
            y: -p.y * s + size.height / 2 + viewportOffset.height
        )
    }

    /// Converts a view point (screen points) back into model coordinates (metres).
    private func viewToModel(_ p: CGPoint, scale: CGFloat, in size: CGSize) -> CGPoint {
        let s = scale * viewportScale
        return CGPoint(
            x: (p.x - size.width / 2 - viewportOffset.width) / s,
            y: -(p.y - size.height / 2 - viewportOffset.height) / s
        )
    }

    /// Finds the identifier of the first room whose polygon contains the given
    /// model point. Returns `nil` if no room contains the point.
    private func roomContaining(point: CGPoint) -> UUID? {
        for room in floorPlan.rooms {
            if polygonContains(point: point, polygon: room.vertices) {
                return room.id
            }
        }
        return nil
    }

    /// Ray casting algorithm to test whether a point lies inside a polygon.
    private func polygonContains(point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            let intersect = ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + 0.0001) + pi.x)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    // MARK: - Tap handling
    /// Responds to a tap in model coordinates by performing the appropriate action for
    /// the current tool. For stairs, the tap must be inside a room. For rooms,
    /// a new rectangular room is created at the tap location. Otherwise the
    /// room under the tap (if any) becomes selected. When adding doors or
    /// windows, the tap inserts an opening on the nearest wall of the selected or
    /// tapped room.
    private func handleTap(at modelPoint: CGPoint) {
        switch currentTool {
        case .addStairs:
            if let roomID = roomContaining(point: modelPoint) {
                floorPlan.addStairs(in: roomID, at: modelPoint)
            }
        case .drawRoom:
            floorPlan.addRoom(at: modelPoint)
        case .addDoor:
            // Determine which room to modify: prefer the active room if one is selected,
            // otherwise use the room containing the tap.
            let targetRoomID = floorPlan.activeRoomID ?? roomContaining(point: modelPoint)
            guard let rid = targetRoomID,
                  let rIndex = floorPlan.rooms.firstIndex(where: { $0.id == rid }) else {
                return
            }
            let room = floorPlan.rooms[rIndex]
            if let (wallIdx, offset) = nearestWall(in: room, to: modelPoint) {
                // Select the room and wall then insert a door of the chosen type.
                floorPlan.selectOnly(rid)
                floorPlan.selectedWallIndex = wallIdx
                let doorType: DoorType
                switch selectedDoorType {
                case "double": doorType = .double
                case "sideLight": doorType = .sideLight
                default: doorType = .single
                }
                floorPlan.addDoor(at: offset, type: doorType)
            }
        case .addWindow:
            let targetRoomID = floorPlan.activeRoomID ?? roomContaining(point: modelPoint)
            guard let rid = targetRoomID,
                  let rIndex = floorPlan.rooms.firstIndex(where: { $0.id == rid }) else {
                return
            }
            let room = floorPlan.rooms[rIndex]
            if let (wallIdx, offset) = nearestWall(in: room, to: modelPoint) {
                floorPlan.selectOnly(rid)
                floorPlan.selectedWallIndex = wallIdx
                let winType: WindowType
                switch selectedWindowType {
                case "double": winType = .double
                case "triple": winType = .triple
                case "picture": winType = .picture
                default: winType = .single
                }
                floorPlan.addWindow(at: offset, type: winType)
            }
        case .select:
            floorPlan.selectRoom(containing: modelPoint)
        default:
            // Other tools treat taps as selection for now
            floorPlan.selectRoom(containing: modelPoint)
        }
    }

    /// Compute the nearest wall of a room to a given model coordinate and return
    /// both the wall index and the relative offset (0...1) of the projection along
    /// that wall. This is used when placing doors and windows so that the
    /// attachment snaps to the closest segment.
    private func nearestWall(in room: Room, to point: CGPoint) -> (Int, CGFloat)? {
        guard room.vertices.count >= 2 else { return nil }
        var bestDist: CGFloat = .infinity
        var bestIdx: Int = 0
        var bestOffset: CGFloat = 0
        for i in 0..<room.vertices.count {
            let a = room.vertices[i]
            let b = room.vertices[(i + 1) % room.vertices.count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let denom = dx * dx + dy * dy
            if denom == 0 { continue }
            let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / denom
            let tClamped = max(0, min(1, t))
            let projX = a.x + tClamped * dx
            let projY = a.y + tClamped * dy
            let dist = hypot(point.x - projX, point.y - projY)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
                bestOffset = tClamped
            }
        }
        return (bestIdx, bestOffset)
    }

    /// A basic stairs shape drawn as a set of parallel treads. The shape's
    /// orientation is handled externally via `rotationEffect`.
    private struct StairsShape: Shape {
        /// The number of steps to draw. Must be at least 1.
        var steps: Int = 12

        func path(in rect: CGRect) -> Path {
            var path = Path()
            // Draw outer rectangle
            path.addRect(rect)

            // Draw individual treads perpendicular to the run direction. We align
            // the treads along the rectangle's width (x‑axis) and run along its
            // height (y‑axis).
            let count = max(steps, 1)
            let stepSize = rect.width / CGFloat(count)
            for i in 1..<count {
                let x = rect.minX + CGFloat(i) * stepSize
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            return path
        }
    }

    // MARK: - Stairs interaction gesture helpers
    /// Create a simultaneous drag, rotation and pinch gesture for manipulating
    /// a stair component. This is identical to the original implementation and
    /// remains unchanged. It tracks per‑gesture state to update the model
    /// accordingly.
    private func stairsGesture(for stairs: Stairs, in room: Room) -> some Gesture {
        // Drag: move stairs centre relative to its current position
        let drag = DragGesture()
            .onChanged { value in
                guard currentTool == .resize else { return }
                floorPlan.updateStairs(in: room.id, id: stairs.id, translation: value.translation)
            }
        // Rotation: adjust the stairs orientation around its centre
        let rotate = RotationGesture()
            .onChanged { value in
                guard currentTool == .resize else { return }
                floorPlan.updateStairs(in: room.id, id: stairs.id, rotation: value)
            }
        // Pinch (magnification): adjust the stairs length and width
        let pinch = MagnificationGesture()
            .onChanged { value in
                guard currentTool == .resize else { return }
                floorPlan.updateStairs(in: room.id, id: stairs.id, scale: value)
            }
        // Combine gestures simultaneously
        return drag.simultaneously(with: rotate).simultaneously(with: pinch)
    }
}