import SwiftUI
import CoreGraphics

// Protocol for things that attach to a wall segment
protocol WallAttachment: Identifiable {
    var id: UUID { get }
    var wallIndex: Int { get set }  // index of the start vertex of the wall
    var offset: CGFloat { get set } // 0..1 along the wall
    var length: CGFloat { get set } // model units (meters)
}

struct Window: WallAttachment, Identifiable {
    let id: UUID
    var wallIndex: Int
    var offset: CGFloat
    var length: CGFloat
    
    init(id: UUID = UUID(), wallIndex: Int, offset: CGFloat, length: CGFloat = 1.0) {
        self.id = id
        self.wallIndex = wallIndex
        self.offset = offset
        self.length = length
    }
}

struct Door: WallAttachment, Identifiable {
    let id: UUID
    var wallIndex: Int
    var offset: CGFloat
    var length: CGFloat
    
    init(id: UUID = UUID(), wallIndex: Int, offset: CGFloat, length: CGFloat = 0.9) {
        self.id = id
        self.wallIndex = wallIndex
        self.offset = offset
        self.length = length
    }
}

/// A polygonal room with windows and doors.
struct Room: Identifiable {
    let id: UUID
    var vertices: [CGPoint]               // model coordinates (meters)
    var windows: [Window]
    var doors: [Door]
    var fillColor: Color = Color.blue.opacity(0.12)
    
    init(id: UUID = UUID(), vertices: [CGPoint], windows: [Window] = [], doors: [Door] = []) {
        self.id = id
        self.vertices = vertices
        self.windows = windows
        self.doors = doors
    }
    
    // MARK: - Geometry helpers
    
    /// Point-in-polygon test in model coordinatesX
    func contains(point: CGPoint) -> Bool {
        guard vertices.count >= 3 else { return false }
        var result = false
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            let pi = vertices[i], pj = vertices[j]
            let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
                             (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) == 0 ? 0.000001 : (pj.y - pi.y)) + pi.x)
            if intersects { result.toggle() }
            j = i
        }
        return result
    }
    
    /// Index of the wall (edge) nearest to `point` within `threshold` (model units).
    func indexOfWall(near point: CGPoint, threshold: CGFloat) -> Int? {
        guard vertices.count >= 2 else { return nil }
        var bestIndex: Int? = nil
        var bestDistance = CGFloat.greatestFiniteMagnitude
        
        for i in 0..<vertices.count {
            let a = vertices[i]
            let b = vertices[(i + 1) % vertices.count]
            let (dist, t) = distanceToSegment(point, a, b)
            if dist < bestDistance, dist <= threshold, t >= 0, t <= 1 {
                bestDistance = dist
                bestIndex = i
            }
        }
        return bestIndex
    }
    
    /// Build a Path in screen coordinates using a transform closure.
    func path(using transform: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        guard let first = vertices.first else { return path }
        path.move(to: transform(first))
        // FIX: use dropFirst() instead of drop(1)
        for v in vertices.dropFirst() {
            path.addLine(to: transform(v))
        }
        path.closeSubpath()
        return path
    }
    
    // MARK: - Private math
    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (CGFloat, CGFloat) {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
        let denom = ab.x * ab.x + ab.y * ab.y
        if denom == 0 { return (hypot(ap.x, ap.y), 0) }
        var t = (ap.x * ab.x + ap.y * ab.y) / denom
        t = max(0, min(1, t))
        let closest = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        return (hypot(p.x - closest.x, p.y - closest.y), t)
    }
}
