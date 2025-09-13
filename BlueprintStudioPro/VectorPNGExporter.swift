import SwiftUI
import CoreGraphics
import UIKit   // used for fonts, images, bezier paths in export

/// Renders the current floors/rooms to a PNG by drawing directly with CoreGraphics.
/// - No view snapshotting (so no privacy watermark / yellow matte).
/// - White background, opaque image.
/// - Auto-fit to image with padding.
enum VectorPNGExporter {

    struct Options {
        var showGrid: Bool = false
        var showDimensions: Bool = true
        var background: CGColor = CGColor(gray: 1.0, alpha: 1.0) // white
        var externalWallWidth: CGFloat = 5
        var internalWallWidth: CGFloat = 2.5
        var margin: CGFloat = 32
        var gridStepMeters: CGFloat = 1.0
        var imageScale: CGFloat = 2.0
    }

    static func makePNG(
        floors: [Floor],
        targetSize logicalSize: CGSize,
        opts: Options = Options()
    ) -> Data? {

        // 1) Bounds in model space
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        var hasAny = false

        for f in floors {
            for r in f.rooms where !r.vertices.isEmpty {
                hasAny = true
                for v in r.vertices {
                    minX = min(minX, v.x); maxX = max(maxX, v.x)
                    minY = min(minY, v.y); maxY = max(maxY, v.y)
                }
            }
        }

        if !hasAny {
            return blankPNG(size: logicalSize, background: opts.background, scale: opts.imageScale)
        }
        if minX == maxX { maxX += 1 }
        if minY == maxY { maxY += 1 }

        let contentWidthM  = maxX - minX
        let contentHeightM = maxY - minY

        // 2) Fit transform
        let pixelSize = CGSize(width: logicalSize.width * opts.imageScale,
                               height: logicalSize.height * opts.imageScale)
        let drawRect = CGRect(x: opts.margin, y: opts.margin,
                              width: pixelSize.width  - opts.margin * 2,
                              height: pixelSize.height - opts.margin * 2)

        let sx = drawRect.width  / contentWidthM
        let sy = drawRect.height / contentHeightM
        let scale = min(sx, sy)

        func modelToScreen(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: (p.x - minX) * scale + drawRect.minX,
                y: (p.y - minY) * scale + drawRect.minY
            )
        }

        // 3) Context (✅ correct bitmapInfo)
        let cs = CGColorSpaceCreateDeviceRGB()
        let alphaInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | alphaInfo

        guard let ctx = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Background
        ctx.setFillColor(opts.background)
        ctx.fill(CGRect(origin: .zero, size: pixelSize))

        // Grid (optional)
        if opts.showGrid {
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.06))
            ctx.setLineWidth(1)
            let stepPx = opts.gridStepMeters * scale
            if stepPx >= 6 {
                var x = drawRect.minX.rounded(.down)
                while x <= drawRect.maxX {
                    ctx.move(to: CGPoint(x: x, y: drawRect.minY))
                    ctx.addLine(to: CGPoint(x: x, y: drawRect.maxY))
                    x += stepPx
                }
                var y = drawRect.minY.rounded(.down)
                while y <= drawRect.maxY {
                    ctx.move(to: CGPoint(x: drawRect.minX, y: y))
                    ctx.addLine(to: CGPoint(x: drawRect.maxX, y: y))
                    y += stepPx
                }
                ctx.strokePath()
            }
            ctx.restoreGState()
        }

        // Rooms
        for floor in floors {
            for room in floor.rooms where room.vertices.count >= 3 {

                // Fill
                let cgFill = UIColor(room.fillColor).cgColor.copy(alpha: 0.10) ?? CGColor(gray: 0, alpha: 0.08)
                ctx.setFillColor(cgFill)

                let path = CGMutablePath()
                var first = true
                for v in room.vertices {
                    let s = modelToScreen(v)
                    first ? path.move(to: s) : path.addLine(to: s)
                    first = false
                }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()

                // Per-edge strokes
                let count = room.vertices.count
                for i in 0..<count {
                    let a = room.vertices[i]
                    let b = room.vertices[(i + 1) % count]
                    let sa = modelToScreen(a)
                    let sb = modelToScreen(b)

                    let isExternal = room.wallTypes.indices.contains(i) ? (room.wallTypes[i] == .externalWall) : true
                    let w = isExternal ? opts.externalWallWidth : opts.internalWallWidth
                    ctx.setLineWidth(w)
                    ctx.setStrokeColor(isExternal ? CGColor(gray: 0, alpha: 0.85)
                                                  : CGColor(gray: 0, alpha: 0.7))
                    ctx.beginPath()
                    ctx.move(to: sa); ctx.addLine(to: sb)
                    ctx.strokePath()
                }

                // Watermark name
                let name = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let b = path.boundingBox
                    let inset = b.insetBy(dx: 16, dy: 28)
                    if inset.width > 10, inset.height > 10 {
                        let base = min(inset.width, inset.height)
                        let fontSize = max(12, min(base * 0.28, 42))
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: fontSize, weight: .black),
                            .foregroundColor: UIColor.black.withAlphaComponent(0.045)
                        ]
                        let att = NSAttributedString(string: name, attributes: attrs)
                        let textSize = att.size()
                        let textRect = CGRect(
                            x: inset.midX - textSize.width/2,
                            y: inset.midY - textSize.height/2,
                            width: textSize.width,
                            height: textSize.height
                        )
                        UIGraphicsPushContext(ctx)
                        att.draw(in: textRect.integral)
                        UIGraphicsPopContext()
                    }
                }

                // Dimensions (optional)
                if opts.showDimensions {
                    let count = room.vertices.count
                    for i in 0..<count {
                        let a = room.vertices[i]
                        let b = room.vertices[(i + 1) % count]
                        let dx = b.x - a.x, dy = b.y - a.y
                        let lengthModel = hypot(dx, dy)
                        guard lengthModel > 0 else { continue }

                        let len = lengthModel
                        let unitNormal = CGPoint(x: -dy / len, y: dx / len)
                        let offsetScreen: CGFloat = 18
                        let offsetModel = offsetScreen / scale

                        let aOff = CGPoint(x: a.x + unitNormal.x * offsetModel, y: a.y + unitNormal.y * offsetModel)
                        let bOff = CGPoint(x: b.x + unitNormal.x * offsetModel, y: b.y + unitNormal.y * offsetModel)

                        let sa = modelToScreen(aOff)
                        let sb = modelToScreen(bOff)

                        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.45))
                        ctx.setLineWidth(1)

                        // dimension line + ticks
                        ctx.move(to: sa); ctx.addLine(to: sb)
                        let unitDir = CGPoint(x: dx / len, y: dy / len)
                        let tickNormal = CGPoint(x: -unitDir.y, y: unitDir.x)
                        let tickHalf: CGFloat = 5
                        func tick(_ p: CGPoint) {
                            ctx.move(to: CGPoint(x: p.x - tickNormal.x * tickHalf, y: p.y - tickNormal.y * tickHalf))
                            ctx.addLine(to: CGPoint(x: p.x + tickNormal.x * tickHalf, y: p.y + tickNormal.y * tickHalf))
                        }
                        tick(sa); tick(sb)
                        ctx.strokePath()

                        // text badge
                        let text = (len >= 10) ? String(format: "%.1f m", len) : String(format: "%.2f m", len)
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                            .foregroundColor: UIColor(white: 0.1, alpha: 0.85)
                        ]
                        let att = NSAttributedString(string: text, attributes: attrs)
                        let textSize = att.size()
                        let mid = CGPoint(x: (sa.x + sb.x)/2, y: (sa.y + sb.y)/2)
                        let badgeRect = CGRect(
                            x: mid.x - textSize.width/2 - 6,
                            y: mid.y - textSize.height/2 - 2,
                            width: textSize.width + 12,
                            height: textSize.height + 4
                        ).integral
                        // rounded bg
                        ctx.setFillColor(CGColor(gray: 0.1, alpha: 0.25))
                        let bgPath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeRect.height/2)
                        ctx.addPath(bgPath.cgPath); ctx.fillPath()
                        // text
                        UIGraphicsPushContext(ctx)
                        att.draw(in: badgeRect.insetBy(dx: 6, dy: 2))
                        UIGraphicsPopContext()
                    }
                }
            }
        }

        // 4) PNG
        guard let cg = ctx.makeImage() else { return nil }
        let ui = UIImage(cgImage: cg, scale: opts.imageScale, orientation: .up)
        return ui.pngData()
    }

    // plain white PNG
    private static func blankPNG(size: CGSize, background: CGColor, scale: CGFloat) -> Data? {
        let pixel = CGSize(width: size.width * scale, height: size.height * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        let alphaInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | alphaInfo
        guard let ctx = CGContext(data: nil, width: Int(pixel.width), height: Int(pixel.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: bitmapInfo) else { return nil }
        ctx.setFillColor(background)
        ctx.fill(CGRect(origin: .zero, size: pixel))
        guard let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up).pngData()
    }
}
