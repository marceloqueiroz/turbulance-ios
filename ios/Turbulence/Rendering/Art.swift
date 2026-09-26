import UIKit

/// Procedural artwork drawn with Core Graphics (y-down, like the web canvas), baked into textures.
/// No external assets: everything the renderer shows comes from here or from SKShapeNodes.
enum Art {
    static let scale: CGFloat = 3

    static func image(_ w: CGFloat, _ h: CGFloat, scale: CGFloat = Art.scale, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { draw($0.cgContext) }
    }

    // MARK: - Primitives

    static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// Rounded rect with per-corner radii (tl, tr, br, bl), quadratic corners like the web version.
    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: [CGFloat]) -> CGPath {
        let (tl, tr, br, bl) = (r[0], r[1], r[2], r[3])
        let p = CGMutablePath()
        p.move(to: P(x + tl, y))
        p.addLine(to: P(x + w - tr, y)); p.addQuadCurve(to: P(x + w, y + tr), control: P(x + w, y))
        p.addLine(to: P(x + w, y + h - br)); p.addQuadCurve(to: P(x + w - br, y + h), control: P(x + w, y + h))
        p.addLine(to: P(x + bl, y + h)); p.addQuadCurve(to: P(x, y + h - bl), control: P(x, y + h))
        p.addLine(to: P(x, y + tl)); p.addQuadCurve(to: P(x + tl, y), control: P(x, y))
        p.closeSubpath()
        return p
    }
    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath { rr(x, y, w, h, [r, r, r, r]) }

    static func fill(_ c: CGContext, _ path: CGPath, _ color: UIColor) {
        c.setFillColor(color.cgColor); c.addPath(path); c.fillPath()
    }
    static func stroke(_ c: CGContext, _ path: CGPath, _ color: UIColor, _ width: CGFloat) {
        c.setStrokeColor(color.cgColor); c.setLineWidth(width); c.addPath(path); c.strokePath()
    }
    static func ellipse(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: UIColor) {
        c.setFillColor(color.cgColor); c.fillEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }
    static func dot(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: UIColor) { ellipse(c, x, y, r, r, color) }

    static func linear(_ c: CGContext, _ path: CGPath, _ colors: [UIColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: locs) else { return }
        c.saveGState(); c.addPath(path); c.clip()
        c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
    static func radial(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r0: CGFloat, _ r1: CGFloat, _ inner: UIColor, _ outer: UIColor) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [inner.cgColor, outer.cgColor] as CFArray, locations: [0, 1]) else { return }
        c.drawRadialGradient(g, startCenter: P(x, y), startRadius: r0, endCenter: P(x, y), endRadius: r1, options: [])
    }
    static func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: UIFont.Weight = .heavy, color: UIColor) {
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: d, size: size) }
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let sz = str.size()
        str.draw(at: P(x - sz.width / 2, y - sz.height / 2))
    }
    static func shadow(_ c: CGContext, _ color: UIColor, blur: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) {
        c.setShadow(offset: CGSize(width: dx, height: dy), blur: blur, color: color.cgColor)
    }
    static func white(_ a: CGFloat) -> UIColor { UIColor(white: 1, alpha: a) }
    static func navy(_ a: CGFloat) -> UIColor { UIColor(red: 27 / 255, green: 42 / 255, blue: 74 / 255, alpha: a) }
    static func ink(_ a: CGFloat) -> UIColor { UIColor(red: 17 / 255, green: 28 / 255, blue: 51 / 255, alpha: a) }

    // MARK: - Items (flat fill + 2px navy outline, GDD §8a)

    static func drawItem(_ c: CGContext, _ item: Item, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        c.saveGState()
        c.translateBy(x: x, y: y); c.scaleBy(x: s, y: s)
        c.setLineWidth(2); c.setStrokeColor(Palette.navy.cgColor); c.setLineJoin(.round)
        func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
            let p = CGMutablePath(); p.addLines(between: pts.map { P($0.0, $0.1) }); p.closeSubpath(); return p
        }
        func fillStroke(_ p: CGPath, _ color: UIColor) {
            c.setFillColor(color.cgColor); c.addPath(p); c.drawPath(using: .fillStroke)
        }
        switch item {
        case .towel:
            fillStroke(CGPath(rect: CGRect(x: -10, y: -8, width: 20, height: 16), transform: nil), UIColor(hex: 0x6FB1D8))
            c.setFillColor(UIColor.white.cgColor); c.fill(CGRect(x: -9, y: 2, width: 18, height: 3))
            c.move(to: P(-10, -2)); c.addLine(to: P(10, -2)); c.strokePath()
        case .water, .juice:
            let cup = poly([(-8, -10), (8, -10), (6, 11), (-6, 11)])
            fill(c, cup, .white)
            fill(c, poly([(-7, -2), (7, -2), (6, 11), (-6, 11)]), item == .water ? UIColor(hex: 0x5FA8D9) : UIColor(hex: 0xF29B30))
            if item == .juice { dot(c, 4, -6, 3, UIColor(hex: 0xF5B942)); c.addEllipse(in: CGRect(x: 1, y: -9, width: 6, height: 6)); c.strokePath() }
            c.addPath(cup); c.strokePath()
        case .snack:
            // a pretzel bag
            fillStroke(poly([(-8, -11), (8, -11), (9, 11), (-9, 11)]), UIColor(hex: 0xE8543E))
            c.setFillColor(UIColor(hex: 0xF5B942).cgColor); c.fill(CGRect(x: -6, y: -3, width: 12, height: 8))
            c.setStrokeColor(UIColor(hex: 0x8A4B22).cgColor); c.setLineWidth(1.6)
            c.addEllipse(in: CGRect(x: -4, y: -2, width: 4, height: 5)); c.addEllipse(in: CGRect(x: 0, y: -2, width: 4, height: 5)); c.strokePath()
        case .coffee:
            let mug = CGPath(roundedRect: CGRect(x: -8, y: -5, width: 14, height: 15), cornerWidth: 3, cornerHeight: 3, transform: nil)
            fillStroke(mug, .white)
            c.setFillColor(UIColor(hex: 0x6B3E26).cgColor); c.fill(CGRect(x: -6.5, y: -3.5, width: 11, height: 3))
            c.addEllipse(in: CGRect(x: 5, y: -1, width: 6, height: 7)); c.strokePath()
            c.setStrokeColor(Palette.navy.withAlphaComponent(0.6).cgColor); c.setLineWidth(1.5)
            c.move(to: P(-3, -8)); c.addQuadCurve(to: P(-3, -13), control: P(-6, -10)); c.move(to: P(2, -8)); c.addQuadCurve(to: P(2, -13), control: P(-1, -10)); c.strokePath()
        case .meal:
            // a covered hot meal on a tray
            fillStroke(CGPath(roundedRect: CGRect(x: -11, y: 4, width: 22, height: 6), cornerWidth: 2, cornerHeight: 2, transform: nil), UIColor(hex: 0xC9CDD3))
            let dome = CGMutablePath(); dome.move(to: P(-9, 4)); dome.addQuadCurve(to: P(9, 4), control: P(0, -14)); dome.closeSubpath()
            fillStroke(dome, UIColor(hex: 0xE3E6EA))
            dot(c, 0, -5, 2, Palette.navy)
        case .toy:
            // a teddy bear
            let bear = UIColor(hex: 0xC98A55)
            dot(c, -6, -8, 4, bear); dot(c, 6, -8, 4, bear)
            c.addEllipse(in: CGRect(x: -10, y: -12, width: 8, height: 8)); c.addEllipse(in: CGRect(x: 2, y: -12, width: 8, height: 8)); c.strokePath()
            fillStroke(CGPath(ellipseIn: CGRect(x: -9, y: -8, width: 18, height: 18), transform: nil), bear)
            dot(c, -3, -1, 1.4, Palette.navy); dot(c, 3, -1, 1.4, Palette.navy); dot(c, 0, 3, 2, UIColor(hex: 0x6B3E26))
        case .plunger:
            c.setStrokeColor(UIColor(hex: 0x8A5A3C).cgColor); c.setLineWidth(3.5)
            c.move(to: P(0, -12)); c.addLine(to: P(0, 3)); c.strokePath()
            c.setStrokeColor(Palette.navy.cgColor); c.setLineWidth(2)
            let cup = CGMutablePath(); cup.move(to: P(-9, 11)); cup.addQuadCurve(to: P(9, 11), control: P(0, -4)); cup.closeSubpath()
            fillStroke(cup, UIColor(hex: 0xD62828))
        case .tool:
            // a toolkit: steel box, coral latch, carry handle
            c.move(to: P(-5, -6)); c.addLine(to: P(-5, -10)); c.addLine(to: P(5, -10)); c.addLine(to: P(5, -6)); c.strokePath()
            fillStroke(CGPath(roundedRect: CGRect(x: -11, y: -6, width: 22, height: 16), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil), UIColor(hex: 0x7E8693))
            c.move(to: P(-11, 0)); c.addLine(to: P(11, 0)); c.strokePath()
            c.setFillColor(Palette.coral.cgColor); c.fill(CGRect(x: -2.5, y: -2, width: 5, height: 5))
        case .usedBag:
            // a crumpled, tied-off sick bag
            fillStroke(poly([(-8, -4), (8, -4), (9, 11), (-9, 11)]), UIColor(hex: 0xC9D6A0))
            fillStroke(poly([(-3, -4), (-5, -11), (5, -11), (3, -4)]), UIColor(hex: 0xB4C487))
            c.move(to: P(-5, 3)); c.addLine(to: P(-1, 6)); c.addLine(to: P(4, 2)); c.strokePath()
        }
        c.restoreGState()
    }

    static func itemImage(_ item: Item, size: CGFloat = 28) -> UIImage {
        image(size, size) { c in drawItem(c, item, size / 2, size / 2, size / 28) }
    }

    // MARK: - Static cabin (hull, floor, seats, galleys, lavs), drawn from a CabinLayout

    static func cabin(_ L: CabinLayout) -> UIImage {
        let W = CGFloat(L.width), H = CGFloat(L.height)
        let aisles = L.aisles.map { CGFloat($0) }
        let top = aisles.first!, bottom = aisles.last!
        let aftX = CGFloat(L.aftX)
        return image(W, H, scale: 2.5) { c in
            // hull: cylinder shading + drop shadow
            let hull = rr(12, 12, W - 19, H - 24, [80, 32, 32, 80])
            c.saveGState()
            shadow(c, UIColor(white: 0, alpha: 0.5), blur: 24, dy: 10)
            fill(c, hull, UIColor(hex: 0xD3D8DE))
            c.restoreGState()
            linear(c, hull, [UIColor(hex: 0x8F98A6), UIColor(hex: 0xD3D8DE), UIColor(hex: 0xEEF0F2), UIColor(hex: 0xD3D8DE), UIColor(hex: 0x8F98A6)],
                   [0, 0.07, 0.5, 0.93, 1], from: P(0, 12), to: P(0, H - 12))
            c.setFillColor(Palette.coral.cgColor); c.fill(CGRect(x: 150, y: 13, width: W - 168, height: 5)); c.fill(CGRect(x: 150, y: H - 18, width: W - 168, height: 5))
            c.setFillColor(Palette.navy.cgColor); c.fill(CGRect(x: 150, y: 18, width: W - 168, height: 1.5)); c.fill(CGRect(x: 150, y: H - 19.5, width: W - 168, height: 1.5))

            c.saveGState()
            c.addPath(rr(22, 22, W - 39, H - 44, [70, 24, 24, 70])); c.clip()

            // floor
            linear(c, CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil),
                   [UIColor(hex: 0xD6CEC1), Palette.cream, Palette.cream, UIColor(hex: 0xD6CEC1)], [0, 0.1, 0.9, 1], from: P(0, 22), to: P(0, H - 22))

            // aisle carpet with woven diamonds, one per aisle
            for a in aisles {
                c.setFillColor(Palette.carpet.cgColor); c.fill(CGRect(x: 172, y: a - 38, width: aftX - 174, height: 76))
                c.setFillColor(navy(0.08).cgColor)
                var dy = a - 38
                while dy < a + 38 {
                    var dx: CGFloat = 172
                    while dx < aftX - 2 {
                        c.move(to: P(dx + 6, dy + 2)); c.addLine(to: P(dx + 10, dy + 6)); c.addLine(to: P(dx + 6, dy + 10)); c.addLine(to: P(dx + 2, dy + 6)); c.closePath()
                        dx += 12
                    }
                    dy += 12
                }
                c.fillPath()
                c.setFillColor(navy(0.14).cgColor); c.fill(CGRect(x: 172, y: a - 38, width: aftX - 174, height: 1.5)); c.fill(CGRect(x: 172, y: a + 36.5, width: aftX - 174, height: 1.5))
            }

            // galley floors: tiles spanning every aisle (crew can cross here)
            for range in L.galleyFloors {
                let x0 = CGFloat(range.lowerBound), x1 = CGFloat(range.upperBound)
                let y0 = top - 54, y1 = bottom + 56
                if x0 > 100 { c.setFillColor(Palette.cream.cgColor); c.fill(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) }
                var i = 0
                var tx = x0
                while tx < x1 {
                    var j = 0
                    var ty = y0
                    while ty < y1 {
                        c.setFillColor(((i + j) % 2 == 1 ? navy(0.07) : white(0.25)).cgColor)
                        c.fill(CGRect(x: tx, y: ty, width: min(11, x1 - tx), height: min(11, y1 - ty)))
                        ty += 11; j += 1
                    }
                    tx += 11; i += 1
                }
            }

            // coral runner down each aisle (GDD §8a)
            for a in aisles {
                c.setFillColor(UIColor(hex: 0xC9432F).cgColor); c.fill(CGRect(x: 56, y: a - 5, width: aftX - 58, height: 10))
                c.setFillColor(Palette.coral.cgColor); c.fill(CGRect(x: 56, y: a - 4, width: aftX - 58, height: 8))
                c.setFillColor(white(0.35).cgColor)
                var sx: CGFloat = 60
                while sx < aftX - 4 { c.fill(CGRect(x: sx, y: a - 2.6, width: 4, height: 1)); sx += 8 }
                // emergency floor-path lighting
                var lx: CGFloat = 180
                while lx < aftX - 6 {
                    for ly in [a - 35, a + 35] {
                        dot(c, lx, ly, 3, UIColor(red: 1, green: 214 / 255, blue: 140 / 255, alpha: 0.35))
                        dot(c, lx, ly, 1.2, UIColor(hex: 0xFFE3A8))
                    }
                    lx += 18
                }
            }

            // wall shadows
            linear(c, CGPath(rect: CGRect(x: 0, y: 22, width: W, height: 22), transform: nil), [navy(0.22), navy(0)], [0, 1], from: P(0, 22), to: P(0, 44))
            linear(c, CGPath(rect: CGRect(x: 0, y: H - 44, width: W, height: 22), transform: nil), [navy(0.22), navy(0)], [0, 1], from: P(0, H - 22), to: P(0, H - 44))

            // windows, a few shades pulled
            for (r, row) in L.rows.enumerated() {
                for wy in [CGFloat(24), H - 31] {
                    let x = CGFloat(row.x)
                    let win = rr(x - 6, wy, 12, 7, 3)
                    linear(c, win, [UIColor(hex: 0xB7D4EA), UIColor(hex: 0x6E9BC0)], [0, 1], from: P(0, wy), to: P(0, wy + 7))
                    if (r * 7 + Int(wy)) % 5 == 0 { fill(c, rr(x - 6, wy, 12, 4, [3, 3, 0, 0]), UIColor(hex: 0xE3DCCF)) }
                    stroke(c, win, UIColor(hex: 0x9AA2AE), 1)
                    c.setFillColor(white(0.7).cgColor); c.fill(CGRect(x: x - 3, y: wy + 1.5, width: 3, height: 1))
                }
            }

            // flight deck door with keypad
            let mid = (top + bottom) / 2
            let door = rr(28, mid - 34, 26, 68, 5)
            linear(c, door, [UIColor(hex: 0xA7AEB9), Palette.steel], [0, 1], from: P(28, 0), to: P(54, 0))
            stroke(c, door, UIColor(hex: 0x8A919C), 1.5)
            fill(c, rr(44, mid - 10, 6, 9, 1.5), Palette.navy)
            dot(c, 47, mid - 13, 1.2, UIColor(hex: 0x6FD08C))
            fill(c, rr(33, mid + 8, 4, 14, 2), UIColor(hex: 0x56606F))

            // fixtures: galley counters, lavatories, closets
            for b in L.blocks {
                let x = CGFloat(b.x), y = CGFloat(b.y), w = CGFloat(b.w), h = CGFloat(b.h)
                let box = rr(x, y, w, h, 8)
                let above = y + h < top           // sits above the top aisle, so it faces down
                if b.kind == .counter {
                    c.saveGState(); shadow(c, navy(0.3), blur: 6, dy: 3); fill(c, box, UIColor(hex: 0xC8CDD4)); c.restoreGState()
                }
                linear(c, box, [UIColor(hex: 0xE1E4E8), UIColor(hex: 0xB8BEC7)], [0, 1], from: P(0, y), to: P(0, y + h))
                stroke(c, box, UIColor(hex: 0x9AA2AE), 1)
                switch b.kind {
                case .counter:
                    let facesAisle = above || y > bottom
                    if facesAisle {
                        let bayY = above ? y + h - 24 : y + 4
                        for i in 0..<Int((w - 6) / 27) {
                            let bx = x + 6 + CGFloat(i) * 27
                            fill(c, rr(bx, bayY, 23, 18, 2), UIColor(hex: 0xA5ACB6))
                            c.setFillColor(UIColor(hex: 0x7E8693).cgColor)
                            c.fill(CGRect(x: bx + 6, y: bayY + (above ? 14 : 2), width: 11, height: 2))
                        }
                    }
                    if !b.label.isEmpty { text(b.label, x + w / 2, y + h + 12, size: 8, color: navy(0.5)) }
                case .lavatory:
                    let doorY = above ? y + h - 40 : y + 2
                    let lavDoor = rr(x + 2, doorY, 32, 38, 4)
                    fill(c, lavDoor, UIColor(hex: 0xD5D9DE)); stroke(c, lavDoor, UIColor(hex: 0x9AA2AE), 1)
                    let py = above ? y + 22 : y + h - 44
                    dot(c, x + 33, py, 4, Palette.navy); fill(c, rr(x + 28, py + 5, 10, 13, 3), Palette.navy)
                    fill(c, rr(x + 20, py + 24, 26, 6, 3), UIColor(hex: 0x6FD08C))
                    text("VACANT", x + 33, py + 27, size: 5.5, color: Palette.navy)
                case .closet:
                    if !b.label.isEmpty { text(b.label, x + w / 2, y + 12, size: 8, color: navy(0.5)) }
                }
            }

            // premium curtain: a bulkhead across the seats and a drawn curtain across each aisle
            if let cx = L.curtainX.map({ CGFloat($0) }) {
                var edges: [(CGFloat, CGFloat)] = [(24, top - 38)]
                for i in 0..<(aisles.count - 1) { edges.append((aisles[i] + 38, aisles[i + 1] - 38)) }
                edges.append((bottom + 38, H - 24))
                for (y0, y1) in edges { fill(c, rr(cx - 3, y0, 6, y1 - y0, 2), UIColor(hex: 0xB8BEC7)) }
                for a in aisles {
                    fill(c, rr(cx - 5, a - 38, 10, 76, 2), UIColor(hex: 0x7B2E3A))
                    c.setFillColor(white(0.18).cgColor)
                    var fy = a - 36
                    while fy < a + 36 { c.fill(CGRect(x: cx - 5, y: fy, width: 10, height: 2)); fy += 7 }
                    c.setFillColor(Palette.navy.cgColor); c.fill(CGRect(x: cx - 6, y: a - 39, width: 12, height: 2))
                }
                text("PREMIUM", cx - 30, 32, size: 7, color: navy(0.45))
            }

            // galley stations: bins, machines (coffee, oven) and trash (GDD §6a)
            for b in L.bins {
                let bx = CGFloat(b.x), by = CGFloat(b.y)
                let box = rr(bx - 17, by - 22, 34, 36, 7)
                switch b.kind {
                case .bin(let item):
                    c.saveGState(); shadow(c, navy(0.35), blur: 4, dy: 2); fill(c, box, .white); c.restoreGState()
                    stroke(c, box, Palette.navy, 2)
                    drawItem(c, item, bx, by - 4, 0.95)
                case .machine(let item, _):
                    c.saveGState(); shadow(c, navy(0.35), blur: 4, dy: 2); fill(c, box, UIColor(hex: 0x3D4452)); c.restoreGState()
                    stroke(c, box, Palette.navy, 2)
                    fill(c, rr(bx - 12, by - 18, 24, 7, 2), UIColor(hex: 0x5B6475))
                    dot(c, bx + 8, by - 14.5, 1.6, UIColor(hex: 0x6FD08C))
                    fill(c, rr(bx - 11, by - 8, 22, 18, 3), UIColor(hex: 0xE3E6EA))
                    drawItem(c, item, bx, by + 1, 0.7)
                case .trash:
                    c.saveGState(); shadow(c, navy(0.35), blur: 4, dy: 2); fill(c, box, UIColor(hex: 0x9AA2AE)); c.restoreGState()
                    stroke(c, box, Palette.navy, 2)
                    drawTrash(c, bx, by - 4, 0.9)
                }
                text(b.label.uppercased(), bx, by + 22, size: 6.5, color: Palette.navy)
            }

            // warm light pools from the overhead panels
            for a in aisles {
                for r in stride(from: 0, to: L.rows.count, by: 2) {
                    let x = CGFloat(L.rows[r].x + 18)
                    radial(c, x, a, 4, 70, UIColor(red: 1, green: 238 / 255, blue: 200 / 255, alpha: 0.22), UIColor(red: 1, green: 238 / 255, blue: 200 / 255, alpha: 0))
                }
            }

            // seats: cushion, seatback, headrest cover, armrests (premium: wider, plum)
            for row in L.rows {
                let x = CGFloat(row.x)
                for spot in row.seats {
                    let y = CGFloat(spot.y)
                    if row.premium {
                        let cushion = rr(x - 18, y - 21, 34, 42, 9)
                        c.saveGState(); shadow(c, ink(0.35), blur: 5, dx: 2, dy: 3); fill(c, cushion, UIColor(hex: 0x3B3566)); c.restoreGState()
                        linear(c, cushion, [UIColor(hex: 0x57508A), UIColor(hex: 0x3B3566)], [0, 1], from: P(x - 18, y - 21), to: P(x + 16, y + 21))
                        fill(c, rr(x + 12, y - 22, 10, 44, 3), Palette.navyDeep)
                        fill(c, rr(x + 13, y - 9, 8, 18, 2), UIColor(hex: 0xF3EEE6))
                        c.setFillColor(Palette.calm.cgColor); c.fill(CGRect(x: x + 13, y: y - 1, width: 8, height: 2))
                    } else {
                        let cushion = rr(x - 14, y - 17, 27, 34, 6)
                        c.saveGState(); shadow(c, ink(0.35), blur: 5, dx: 2, dy: 3); fill(c, cushion, Palette.navy); c.restoreGState()
                        linear(c, cushion, [UIColor(hex: 0x30446E), Palette.navy], [0, 1], from: P(x - 14, y - 17), to: P(x + 13, y + 17))
                        fill(c, rr(x + 8, y - 18, 9, 36, 3), Palette.navyDeep)
                        fill(c, rr(x + 9, y - 8, 7, 16, 2), UIColor(hex: 0xF3EEE6))
                        c.setFillColor(Palette.coral.cgColor); c.fill(CGRect(x: x + 9, y: y - 1, width: 7, height: 2))
                        fill(c, rr(x - 12, y - 20, 21, 3, 1.5), UIColor(hex: 0x8C93A0))
                        fill(c, rr(x - 12, y + 17, 21, 3, 1.5), UIColor(hex: 0x8C93A0))
                    }
                }
                for a in aisles { text(String(row.number), x, a - 29, size: 8, color: navy(0.45)) }
            }
            c.restoreGState()
        }
    }

    // MARK: - Obstacles: the service cart and an open overhead bin

    static func cart(stuck: Bool) -> UIImage {
        image(48, 30) { c in
            ellipse(c, 26, 18, 22, 11, ink(0.25))
            let body = rr(4, 4, 40, 22, 4)
            linear(c, body, [UIColor(hex: 0xE3E6EA), UIColor(hex: 0xAEB5BF)], [0, 1], from: P(0, 4), to: P(0, 26))
            stroke(c, body, Palette.navy, 2)
            c.setFillColor(Palette.navy.cgColor); c.fill(CGRect(x: 2, y: 8, width: 3, height: 14)); c.fill(CGRect(x: 43, y: 8, width: 3, height: 14))
            // cups and bottles on top
            for (i, col) in [0x5FA8D9, 0xFFFFFF, 0xE8543E, 0xFFFFFF, 0x6FB1D8].enumerated() {
                dot(c, 12 + CGFloat(i) * 6, 11, 2.2, UIColor(hex: UInt32(col)))
            }
            c.setFillColor(Palette.coral.cgColor); c.fill(CGRect(x: 8, y: 19, width: 32, height: 3))
            if stuck {
                c.setStrokeColor(Palette.critical.cgColor); c.setLineWidth(2)
                c.move(to: P(10, 27)); c.addLine(to: P(16, 29)); c.move(to: P(32, 29)); c.addLine(to: P(38, 27)); c.strokePath()
            }
        }
    }

    static func binJam() -> UIImage {
        image(48, 48) { c in
            ellipse(c, 25, 30, 16, 8, ink(0.22))
            // lid swung open over the aisle
            let lid = rr(6, 4, 36, 11, 3)
            fill(c, lid, UIColor(hex: 0x9AA2AE)); stroke(c, lid, Palette.navy, 2)
            c.setFillColor(Palette.navy.cgColor); c.fill(CGRect(x: 21, y: 7, width: 6, height: 3))
            // a suitcase sticking out
            let bag = rr(13, 17, 22, 16, 3)
            fill(c, bag, UIColor(hex: 0x8A5A3C)); stroke(c, bag, Palette.navy, 1.8)
            c.setStrokeColor(Palette.navy.cgColor); c.setLineWidth(1.6)
            c.move(to: P(20, 17)); c.addLine(to: P(20, 14)); c.addLine(to: P(28, 14)); c.addLine(to: P(28, 17)); c.strokePath()
            c.setFillColor(Palette.calm.cgColor); c.fill(CGRect(x: 13, y: 24, width: 22, height: 2))
            // a coat half-fallen out
            fill(c, rr(30, 30, 10, 12, 3), UIColor(hex: 0x6F8AA6))
        }
    }

    static func drawTrash(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        c.saveGState(); c.translateBy(x: x, y: y); c.scaleBy(x: s, y: s)
        c.setStrokeColor(Palette.navy.cgColor); c.setLineWidth(2); c.setLineJoin(.round)
        let can = CGMutablePath(); can.addLines(between: [P(-8, -6), P(8, -6), P(6, 11), P(-6, 11)]); can.closeSubpath()
        c.setFillColor(UIColor(hex: 0x5B6475).cgColor); c.addPath(can); c.drawPath(using: .fillStroke)
        c.setFillColor(UIColor(hex: 0x7E8693).cgColor)
        c.addPath(CGPath(roundedRect: CGRect(x: -10, y: -10, width: 20, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)); c.drawPath(using: .fillStroke)
        c.move(to: P(-2, -10)); c.addLine(to: P(-2, -12)); c.addLine(to: P(2, -12)); c.addLine(to: P(2, -10)); c.strokePath()
        c.setStrokeColor(white(0.5).cgColor); c.setLineWidth(1.4)
        for lx in [-3.0, 0.0, 3.0] { c.move(to: P(CGFloat(lx), -2)); c.addLine(to: P(CGFloat(lx), 8)); }
        c.strokePath()
        c.restoreGState()
    }

    static func bell(size: CGFloat = 28) -> UIImage {
        image(size, size) { c in
            c.translateBy(x: size / 2, y: size / 2); c.scaleBy(x: size / 28, y: size / 28)
            c.setStrokeColor(Palette.navy.cgColor); c.setLineWidth(2); c.setLineJoin(.round)
            let b = CGMutablePath()
            b.move(to: P(-9, 6)); b.addQuadCurve(to: P(0, -10), control: P(-9, -10)); b.addQuadCurve(to: P(9, 6), control: P(9, -10)); b.closeSubpath()
            c.setFillColor(UIColor(hex: 0xF5B942).cgColor); c.addPath(b); c.drawPath(using: .fillStroke)
            c.move(to: P(-11, 6)); c.addLine(to: P(11, 6)); c.strokePath()
            dot(c, 0, 9, 2.6, Palette.navy); dot(c, 0, -11, 1.8, Palette.navy)
        }
    }

    static func trashImage(size: CGFloat = 28) -> UIImage { image(size, size) { c in drawTrash(c, size / 2, size / 2, size / 28) } }

    /// Two items side by side, for combo orders.
    static func comboImage(_ items: [Item], size: CGFloat = 28) -> UIImage {
        image(size, size) { c in
            for (i, item) in items.prefix(2).enumerated() {
                drawItem(c, item, size / 2 + (i == 0 ? -size * 0.2 : size * 0.2), size / 2 + (i == 0 ? -size * 0.08 : size * 0.1), size / 28 * 0.68)
            }
        }
    }

    static func suitcase() -> UIImage {
        image(40, 36) { c in
            ellipse(c, 21, 26, 15, 7, ink(0.22))
            let bag = rr(6, 10, 28, 20, 4)
            fill(c, bag, UIColor(hex: 0x3D6E8C)); stroke(c, bag, Palette.navy, 2)
            c.setStrokeColor(Palette.navy.cgColor); c.setLineWidth(2)
            c.move(to: P(15, 10)); c.addLine(to: P(15, 5)); c.addLine(to: P(25, 5)); c.addLine(to: P(25, 10)); c.strokePath()
            c.setFillColor(Palette.calm.cgColor); c.fill(CGRect(x: 6, y: 18, width: 28, height: 3))
            fill(c, rr(24, 13, 7, 4, 1), .white)
        }
    }

    static func crown() -> UIImage {
        image(18, 12) { c in
            let p = CGMutablePath()
            p.addLines(between: [P(2, 10), P(2, 3), P(6, 7), P(9, 1), P(12, 7), P(16, 3), P(16, 10)]); p.closeSubpath()
            fill(c, p, UIColor(hex: 0xF5B942)); stroke(c, p, Palette.navy, 1.4)
            dot(c, 9, 7.5, 1.3, Palette.coral)
        }
    }

    /// Glyph for a step: an item, a combo, the trash, or an open hand for "needs a free hand".
    static func stepImage(_ step: Step, size: CGFloat = 28) -> UIImage {
        switch step {
        case .item(let item): return itemImage(item, size: size)
        case .combo(let items): return comboImage(items, size: size)
        case .trash: return trashImage(size: size)
        case .hands:
            return image(size, size) { c in
                c.translateBy(x: size / 2, y: size / 2); c.scaleBy(x: size / 28, y: size / 28)
                c.setStrokeColor(Palette.navy.cgColor); c.setLineWidth(2); c.setLineJoin(.round)
                let skin = UIColor(hex: 0xF1C9A5)
                for (i, fx) in [-7.0, -2.5, 2.0, 6.5].enumerated() {
                    let len: CGFloat = i == 0 || i == 3 ? 8 : 10
                    let f = rr(CGFloat(fx) - 2, -3 - len, 4, len + 4, 2)
                    fill(c, f, skin); stroke(c, f, Palette.navy, 1.6)
                }
                let thumb = rr(-13, 0, 8, 4, 2)
                fill(c, thumb, skin); stroke(c, thumb, Palette.navy, 1.6)
                let palm = rr(-9, -4, 18, 15, 6)
                fill(c, palm, skin); stroke(c, palm, Palette.navy, 2)
            }
        }
    }

    // MARK: - Passengers (archetypes read from silhouette props, GDD §7/§8a)

    static let passengerSize = CGSize(width: 48, height: 64)

    /// Drawn around the image centre = the passenger's seat position.
    static func passenger(_ p: Passenger, sick: Bool) -> UIImage {
        image(passengerSize.width, passengerSize.height) { c in
            let x = passengerSize.width / 2, y = passengerSize.height / 2
            let shirt = Palette.shirt(p.archetype)
            let skin = Palette.skins[p.skin], hair = Palette.hairs[p.hair]
            ellipse(c, x + 3, y + 3, 9, 14, ink(0.22))
            ellipse(c, x + 2, y, 8, 13, shirt)
            ellipse(c, x, y - 4, 4.5, 6, white(0.14))
            if p.archetype == .sleeper {
                fill(c, rr(x - 9, y - 13, 16, 26, 6), UIColor(hex: 0x9DB9D6))
                c.setFillColor(white(0.5).cgColor)
                c.fill(CGRect(x: x - 5, y: y - 13, width: 1.5, height: 26)); c.fill(CGRect(x: x + 1, y: y - 13, width: 1.5, height: 26))
            } else {
                ellipse(c, x - 4, y - 10, 6, 3.2, shirt); ellipse(c, x - 4, y + 10, 6, 3.2, shirt)
                if p.archetype == .business {
                    fill(c, rr(x - 18, y - 7, 8, 14, 1.5), UIColor(hex: 0x3D4452))
                    c.setFillColor(UIColor(hex: 0x9FD3F0).cgColor); c.fill(CGRect(x: x - 18, y: y - 6, width: 2, height: 12))
                }
                dot(c, x - 10, y - 10, 2.6, skin); dot(c, x - 10, y + 10, 2.6, skin)
            }
            dot(c, x - 2, y, 7.5, sick ? UIColor(hex: 0xA9C97A) : skin)
            c.setFillColor(hair.cgColor)
            c.addArc(center: P(x - 1, y), radius: 7.5, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false); c.fillPath()
            if p.hairStyle == 1 { dot(c, x + 6.5, y, 3.2, hair) }
            if p.hairStyle == 2 { ellipse(c, x + 1, y - 3, 3, 1.5, white(0.18)) }
            if p.hasKid {
                ellipse(c, x - 9, y, 4, 6, UIColor(hex: 0xE47C6A))
                dot(c, x - 11, y, 4.2, skin)
                c.setFillColor(hair.cgColor)
                c.addArc(center: P(x - 10.5, y), radius: 4.2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false); c.fillPath()
            }
            if p.archetype == .sleeper && !sick { fill(c, rr(x - 10.5, y - 5, 4, 10, 2), UIColor(hex: 0x2C3E66)) }
        }
    }

    static func grumpyCloud() -> UIImage {
        image(20, 18) { c in
            let g = UIColor(hex: 0x6B7282)
            dot(c, 5, 6, 4, g); dot(c, 10, 4.5, 5, g); dot(c, 15, 6, 4, g)
            c.setStrokeColor(Palette.critical.cgColor); c.setLineWidth(1.6)
            c.move(to: P(10, 8)); c.addLine(to: P(8, 12)); c.addLine(to: P(11, 12)); c.addLine(to: P(9, 16)); c.strokePath()
        }
    }

    static func chatBubble() -> UIImage {
        image(18, 11) { c in
            fill(c, rr(1, 1, 16, 9, 4.5), .white)
            for i in 0..<3 { dot(c, 5 + CGFloat(i) * 4, 5.5, 1.1, Palette.navy) }
        }
    }

    static func heart() -> UIImage {
        image(16, 14) { c in
            c.setFillColor(Palette.coral.cgColor)
            c.addArc(center: P(5, 5), radius: 3.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            c.addArc(center: P(11, 5), radius: 3.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            c.fillPath()
            c.move(to: P(1.5, 6)); c.addLine(to: P(8, 13)); c.addLine(to: P(14.5, 6)); c.closePath(); c.fillPath()
        }
    }

    // MARK: - Spill

    static func spill(seed: Double, failed: Bool) -> UIImage {
        image(64, 56) { c in
            let s = CGFloat(seed)
            c.translateBy(x: 30, y: 30)
            let color = failed ? UIColor(hex: 0x5E4330, alpha: 0.88) : UIColor(hex: 0x8A4B22, alpha: 0.88)
            c.setFillColor(color.cgColor)
            c.saveGState(); c.rotate(by: s); c.fillEllipse(in: CGRect(x: -18, y: -8, width: 36, height: 24)); c.restoreGState()
            c.fillEllipse(in: CGRect(x: 9 * cos(s) - 10, y: -13, width: 20, height: 14))
            c.fillEllipse(in: CGRect(x: -18, y: 14 * sin(s) * 0.6 - 5, width: 14, height: 10))
            dot(c, 20, 8, 2.2, color); dot(c, -18, -8, 1.8, color); dot(c, 14, -14, 1.5, color)
            c.saveGState(); c.translateBy(x: -5, y: -2); c.rotate(by: -0.3); ellipse(c, 0, 0, 7, 2.6, white(0.3)); c.restoreGState()
            // the tipped-over cup
            c.saveGState(); c.translateBy(x: 17, y: -13); c.rotate(by: s)
            let cup = CGMutablePath(); cup.addLines(between: [P(-5, -4), P(5, -3), P(5, 3), P(-5, 4)]); cup.closeSubpath()
            c.setFillColor(UIColor.white.cgColor); c.setStrokeColor(Palette.navy.cgColor); c.setLineWidth(1.2)
            c.addPath(cup); c.drawPath(using: .fillStroke)
            c.restoreGState()
        }
    }

    // MARK: - Effects & ambience

    static func softDot() -> UIImage { image(16, 16) { c in dot(c, 8, 8, 8, .white) } }

    static func sparkle() -> UIImage {
        image(20, 20) { c in
            let x: CGFloat = 10, y: CGFloat = 10, r: CGFloat = 5
            c.setFillColor(UIColor.white.cgColor)
            c.move(to: P(x, y - r * 2))
            c.addQuadCurve(to: P(x + r * 2, y), control: P(x, y))
            c.addQuadCurve(to: P(x, y + r * 2), control: P(x, y))
            c.addQuadCurve(to: P(x - r * 2, y), control: P(x, y))
            c.addQuadCurve(to: P(x, y - r * 2), control: P(x, y))
            c.fillPath()
        }
    }

    static func glow() -> UIImage {
        image(64, 64, scale: 2) { c in
            radial(c, 32, 32, 8, 32, UIColor(hex: 0xD62828, alpha: 0.5), UIColor(hex: 0xD62828, alpha: 0))
        }
    }

    static func cloud() -> UIImage {
        image(256, 128, scale: 1) { c in
            for (x, y, r) in [(70.0, 74.0, 48.0), (120, 60, 58), (176, 76, 46), (128, 88, 50), (90, 90, 36), (200, 90, 30)] as [(CGFloat, CGFloat, CGFloat)] {
                radial(c, x, y, 0, r, white(0.9), white(0))
            }
        }
    }

    static func sky(_ size: CGSize) -> UIImage {
        image(max(size.width, 1), max(size.height, 1), scale: 1) { c in
            linear(c, CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
                   [UIColor(hex: 0x0A1226), UIColor(hex: 0x1C2C54)], [0, 1], from: .zero, to: P(0, size.height))
        }
    }

    static func vignette(_ size: CGSize) -> UIImage {
        image(max(size.width, 1), max(size.height, 1), scale: 1) { c in
            let dark = UIColor(red: 5 / 255, green: 10 / 255, blue: 25 / 255, alpha: 0.5)
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [dark.withAlphaComponent(0).cgColor, dark.cgColor] as CFArray, locations: [0, 1]) else { return }
            let center = P(size.width / 2, size.height / 2)
            c.drawRadialGradient(g, startCenter: center, startRadius: min(size.width, size.height) * 0.45,
                                 endCenter: center, endRadius: max(size.width, size.height) * 0.75, options: [.drawsAfterEndLocation])
        }
    }
}
