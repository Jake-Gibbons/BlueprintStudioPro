import SwiftUI

/// Background grid in model units (meters). One unit per major line.
struct GridView: View {
    var scale: CGFloat        // pixels per model unit
    var offset: CGSize        // screen-space offset
    var size: CGSize          // canvas size
    
    var body: some View {
        Canvas { context, _ in
            let w = size.width
            let h = size.height
            
            // Compute visible model-space bounds
            let minX = (-w/2 - offset.width) / scale
            let maxX = ( w/2 - offset.width) / scale
            let minY = (-h/2 - offset.height) / scale
            let maxY = ( h/2 - offset.height) / scale
            
            let startX = Int(floor(minX))
            let endX = Int(ceil(maxX))
            let startY = Int(floor(minY))
            let endY = Int(ceil(maxY))
            
            var path = Path()
            // Vertical lines
            for x in startX...endX {
                let sx = CGFloat(x) * scale + w/2 + offset.width
                path.move(to: CGPoint(x: sx, y: 0))
                path.addLine(to: CGPoint(x: sx, y: h))
            }
            // Horizontal lines
            for y in startY...endY {
                let sy = CGFloat(y) * scale + h/2 + offset.height
                path.move(to: CGPoint(x: 0, y: sy))
                path.addLine(to: CGPoint(x: w, y: sy))
            }
            
            context.stroke(path, with: .color(Color.gray.opacity(0.15)), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}
