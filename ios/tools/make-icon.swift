import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let cream = rgb(0xE8E2D8), navy = rgb(0x1B2A4A), coral = rgb(0xE8543E), teal = rgb(0x1F8A8C)
let red = rgb(0xD62828), yellow = rgb(0xF5B942), steel = rgb(0xC9CDD3)

let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(S)); ctx.scaleBy(x: 1, y: -1)   // top-left origin

// Night-sky background
let bgGrad = CGGradient(colorsSpace: cs, colors: [rgb(0x2A4478), rgb(0x16254A), rgb(0x0B1428)] as CFArray,
                        locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])

// Soft clouds
func puff(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat) {
    let g = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, a), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y),
                           endRadius: r, options: [])
}
for (x, y, r) in [(120.0, 900.0, 220.0), (300, 980, 200), (900, 860, 240), (80, 160, 180), (980, 120, 160)] {
    puff(x, y, r, 0.10)
}

// Turbulence swirls
ctx.setLineCap(.round)
for (i, y0) in [250.0, 560.0, 860.0].enumerated() {
    let p = CGMutablePath()
    for x in stride(from: -40.0, through: 1064.0, by: 8.0) {
        let y = y0 + 34 * sin((x + Double(i) * 90) / 58)
        if x == -40 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    ctx.addPath(p); ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(22); ctx.strokePath()
}

// ---- Airplane, drawn nose-up around the origin, then rotated ----
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath(); p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
    for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
    p.closeSubpath(); return p
}
func fillStroke(_ path: CGPath, _ fill: CGColor, _ lw: CGFloat = 16) {
    ctx.addPath(path); ctx.setFillColor(fill); ctx.fillPath()
    ctx.addPath(path); ctx.setStrokeColor(navy); ctx.setLineWidth(lw); ctx.setLineJoin(.round); ctx.strokePath()
}

ctx.saveGState()
ctx.translateBy(x: 452, y: 590)
ctx.rotate(by: 35 * .pi / 180)
ctx.scaleBy(x: 0.9, y: 0.9)

// drop shadow for the whole plane
ctx.setShadow(offset: CGSize(width: 18, height: 28), blur: 40, color: rgb(0x000000, 0.45))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

for m: CGFloat in [-1, 1] {
    // wing
    fillStroke(poly([(m * 50, -40), (m * 370, 120), (m * 370, 172), (m * 50, 78)]), steel)
    // wingtip livery
    fillStroke(poly([(m * 330, 100), (m * 370, 120), (m * 370, 172), (m * 330, 158)]), coral, 12)
    // engine
    fillStroke(rrect(m * 180 - 30, -2, 60, 118, 30), rgb(0x5B6475), 14)
    ctx.setFillColor(rgb(0x1B2230)); ctx.fillEllipse(in: CGRect(x: m * 180 - 20, y: -2, width: 40, height: 18))
    // tailplane
    fillStroke(poly([(m * 40, 262), (m * 178, 352), (m * 178, 392), (m * 40, 336)]), steel, 14)
}

// fuselage (cabin cutaway)
let body = rrect(-66, -392, 132, 784, 66)
ctx.addPath(body); ctx.setFillColor(cream); ctx.fillPath()
ctx.saveGState(); ctx.addPath(body); ctx.clip()
ctx.setFillColor(coral); ctx.fill(CGRect(x: -10, y: -300, width: 20, height: 640))          // aisle runner
for i in 0..<9 {
    let y = CGFloat(-236 + i * 62)
    for x: CGFloat in [-56, -33, 13, 36] {
        ctx.addPath(rrect(x, y, 20, 42, 6)); ctx.setFillColor(navy); ctx.fillPath()
    }
}
ctx.setFillColor(navy)                                                                      // cockpit windows
ctx.addPath(rrect(-40, -350, 32, 20, 8)); ctx.fillPath()
ctx.addPath(rrect(8, -350, 32, 20, 8)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(body); ctx.setStrokeColor(navy); ctx.setLineWidth(18); ctx.strokePath()

// flight attendant in the aisle
ctx.setFillColor(teal); ctx.fillEllipse(in: CGRect(x: -38, y: -86, width: 76, height: 96))
ctx.setStrokeColor(navy); ctx.setLineWidth(10); ctx.strokeEllipse(in: CGRect(x: -38, y: -86, width: 76, height: 96))
ctx.setFillColor(coral); ctx.fill(CGRect(x: -12, y: -84, width: 24, height: 12))
ctx.setFillColor(rgb(0xE9B892)); ctx.fillEllipse(in: CGRect(x: -24, y: -62, width: 48, height: 48))
ctx.strokeEllipse(in: CGRect(x: -24, y: -62, width: 48, height: 48))
ctx.setFillColor(rgb(0x3A2A20)); ctx.addArc(center: CGPoint(x: 0, y: -38), radius: 24, startAngle: 0, endAngle: .pi, clockwise: false); ctx.fillPath()
ctx.fillEllipse(in: CGRect(x: -12, y: -18, width: 24, height: 20))

ctx.endTransparencyLayer()
ctx.restoreGState()

// ---- Occurrence badges (traffic-light ramp) ----
func badge(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: CGColor, ring: CGFloat?) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 10, height: 16), blur: 26, color: rgb(0x000000, 0.45))
    ctx.setFillColor(rgb(0x000000, 0.001)); ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()
    if let frac = ring {
        let rr = r + r * 0.28
        ctx.setLineWidth(r * 0.2)
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.9)); ctx.strokeEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: 2 * rr, height: 2 * rr))
        ctx.setStrokeColor(navy)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rr, startAngle: -.pi / 2,
                   endAngle: -.pi / 2 + frac * 2 * .pi, clockwise: false)
        ctx.strokePath()
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 8, height: 14), blur: 22, color: rgb(0x000000, 0.4))
    ctx.setFillColor(color); ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.45)); ctx.setLineWidth(r * 0.1)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r * 0.74, startAngle: .pi * 1.05, endAngle: .pi * 1.5, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(navy); ctx.setLineWidth(r * 0.12)
    ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
}

badge(800, 222, 112, red, ring: 0.28)
// exclamation mark
ctx.setFillColor(cream)
ctx.addPath(rrect(800 - 18, 222 - 68, 36, 90, 18)); ctx.fillPath()
ctx.fillEllipse(in: CGRect(x: 800 - 20, y: 222 + 36, width: 40, height: 40))

badge(196, 250, 60, yellow, ring: nil)

// write PNG
let img = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote", out.path)
