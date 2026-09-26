// Renders the Zelda Labs studio logo.
// Usage: swift ios/tools/make-studio-logo.swift <out.png> [--transparent]
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let cream = rgb(0xF3EEE6), navy = rgb(0x1B2A4A), coral = rgb(0xE8543E), teal = rgb(0x1F8A8C), sky = rgb(0x0E1830)

/// The flask mark in a 200 × 200 box, y down. Shared geometry with ZeldaLabsMark in the app.
enum Mark {
    static func flask() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 80, y: 30)); p.addLine(to: CGPoint(x: 80, y: 82))
        p.addLine(to: CGPoint(x: 36, y: 158))
        p.addQuadCurve(to: CGPoint(x: 52, y: 176), control: CGPoint(x: 28, y: 176))
        p.addLine(to: CGPoint(x: 148, y: 176))
        p.addQuadCurve(to: CGPoint(x: 164, y: 158), control: CGPoint(x: 172, y: 176))
        p.addLine(to: CGPoint(x: 120, y: 82)); p.addLine(to: CGPoint(x: 120, y: 30))
        return p
    }
    static func z() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 76, y: 122)); p.addLine(to: CGPoint(x: 124, y: 122))
        p.addLine(to: CGPoint(x: 76, y: 160)); p.addLine(to: CGPoint(x: 124, y: 160))
        return p
    }
    static func draw(_ ctx: CGContext) {
        let body = flask()
        // liquid: everything in the flask below the waterline
        ctx.saveGState()
        let closed = CGMutablePath(); closed.addPath(body); closed.closeSubpath()
        ctx.addPath(closed); ctx.clip()
        ctx.setFillColor(coral); ctx.fill(CGRect(x: 0, y: 106, width: 200, height: 100))
        ctx.setFillColor(rgb(0xFFFFFF, 0.25)); ctx.fill(CGRect(x: 0, y: 106, width: 200, height: 5))
        ctx.restoreGState()
        // the Z, set into the liquid
        ctx.addPath(z()); ctx.setStrokeColor(navy); ctx.setLineWidth(11)
        ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
        // glass
        ctx.addPath(body); ctx.setStrokeColor(cream); ctx.setLineWidth(9); ctx.strokePath()
        ctx.move(to: CGPoint(x: 68, y: 30)); ctx.addLine(to: CGPoint(x: 132, y: 30)); ctx.strokePath()
        // bubbles rising up the neck
        ctx.setFillColor(teal)
        for (x, y, r) in [(108.0, 70.0, 7.0), (92.0, 50.0, 5.0), (104.0, 14.0, 4.0)] {
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }
}

let transparent = CommandLine.arguments.contains("--transparent")
let W = 1024, H = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
if !transparent { ctx.setFillColor(sky); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }

// mark, centred in the upper part (flip to y-down for the shared geometry)
ctx.saveGState()
ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
ctx.translateBy(x: 512 - 2.4 * 100, y: 225); ctx.scaleBy(x: 2.4, y: 2.4)
Mark.draw(ctx)
ctx.restoreGState()

// wordmark
func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}
func drawText(_ s: String, font: NSFont, color: CGColor, kern: CGFloat, centerY: CGFloat) {
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: kern])
    let line = CTLineCreateWithAttributedString(attr)
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: (CGFloat(W) - CGFloat(w) + kern) / 2, y: centerY)
    CTLineDraw(line, ctx)
}
drawText("ZELDA", font: rounded(150, .heavy), color: cream, kern: 14, centerY: 150)
drawText("LABS", font: rounded(64, .bold), color: rgb(0x2FB3B5), kern: 40, centerY: 70)

let img = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote", out.path)
