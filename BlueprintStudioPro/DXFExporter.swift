import Foundation
import CoreGraphics

enum DXFExporter {
    static func makeDXF(floors: [Floor]) -> Data {
        var s = ""
        // HEADER
        s += "0\nSECTION\n2\nENTITIES\n"
        for floor in floors {
            for room in floor.rooms {
                guard room.vertices.count >= 3 else { continue }
                // LWPOLYLINE
                s += "0\nLWPOLYLINE\n"
                s += "8\n\(floor.name)\n"     // layer name = floor
                s += "90\n\(room.vertices.count)\n"
                s += "70\n1\n"                // closed poly
                for v in room.vertices {
                    s += "10\n\(v.x)\n20\n\(v.y)\n"
                }
            }
        }
        // FOOTER
        s += "0\nENDSEC\n0\nEOF\n"
        return s.data(using: .utf8) ?? Data()
    }
}
