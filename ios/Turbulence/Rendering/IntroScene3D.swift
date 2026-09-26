import SceneKit
import UIKit

/// The flight intro cutscene in real 3D (GDD §8b), built procedurally from the flight's CabinLayout:
/// no model files. Model units carry over: x runs nose → tail, model y becomes SceneKit z, height is y.
/// The camera starts at eye level by the forward door, rises over the safety demo, then swoops to a
/// near-orthographic top-down shot that lines up with the 2D play view before the crossfade.
final class IntroScene3D {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let layout: CabinLayout
    private let passengers: [Passenger]
    /// The live view size and cabin insets (read every frame, so the last shot always matches the 2D view).
    private let frame: () -> (size: CGSize, insets: UIEdgeInsets)
    private let bins = SCNNode()
    /// The 3D cabin (seats, people, walls, galleys) that fades out during the swoop…
    private let solid = SCNNode()
    /// …while this flat copy of the exact 2D art fades in, so the last frame is the game's own picture.
    private let flat = SCNNode()
    private var done: (() -> Void)?
    private var finished = false
    /// The camera waits at the end of the three-quarter shot until the captain has finished (GDD §8b).
    static let holdAt = 7.6
    private var released = false
    private var clock = 0.0
    private var held = 0.0
    private var lastElapsed: CGFloat = 0

    /// Lets the camera move on from the hold: call when the captain has finished speaking.
    func release() { released = true }
    /// Unhurried on purpose: Tap to skip is always there (GDD §8b).
    static let duration = 11.0
    /// The 2D view starts fading in this long before the camera stops, so the two overlap.
    static let handoffLead = 0.8
    private let lights = SCNNode()
    private var ambientLight: SCNLight?, sunLight: SCNLight?, lampLights: [SCNLight] = []

    init(sim: FlightSimulation, frame: @escaping () -> (size: CGSize, insets: UIEdgeInsets)) {
        layout = sim.layout
        passengers = sim.passengers
        self.frame = frame
        scene.background.contents = Art.sky(CGSize(width: 900, height: 420))   // the same night sky as the 2D view
        build()
    }

    // MARK: - Materials

    private var materials: [String: SCNMaterial] = [:]
    private func mat(_ color: UIColor, rough: CGFloat = 0.75, emissive: Bool = false) -> SCNMaterial {
        let key = "\(color.description)-\(rough)-\(emissive)"
        if let m = materials[key] { return m }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = 0
        if emissive { m.emission.contents = color }
        materials[key] = m
        return m
    }

    @discardableResult
    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, at p: SCNVector3, _ color: UIColor, chamfer: CGFloat = 0,
                     parent: SCNNode? = nil) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        g.firstMaterial = mat(color)
        let n = SCNNode(geometry: g)
        n.position = p
        (parent ?? solid).addChildNode(n)
        return n
    }

    private func v(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(Float(x), Float(y), Float(z)) }

    // MARK: - Build the cabin

    private func build() {
        let L = layout
        let W = L.width, H = L.height
        let a0 = L.aisles[0]

        // hull, livery, wings and tail in the same place as the 2D art, so the last frame matches it
        /// An extruded flat shape; `flatShaded` ones are unlit so their colour matches the 2D art exactly.
        func slab(_ path: CGPath, depth: CGFloat, y: Double, _ color: UIColor, flatShaded: Bool = false) {
            let shape = SCNShape(path: UIBezierPath(cgPath: path), extrusionDepth: depth)
            if flatShaded {
                let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color
                shape.firstMaterial = m
            } else {
                shape.firstMaterial = mat(color)
            }
            let n = SCNNode(geometry: shape)
            n.eulerAngles.x = .pi / 2                  // shape y → model y (SceneKit z)
            n.position = v(0, y, 0)
            (flatShaded ? scene.rootNode : solid).addChildNode(n)
        }
        slab(Art.rr(12, 12, CGFloat(W - 19), CGFloat(H - 24), [80, 32, 32, 80]), depth: 20, y: -12, UIColor(hex: 0xC9CED5))
        slab(Art.rr(22, 22, CGFloat(W - 39), CGFloat(H - 44), [70, 24, 24, 70]), depth: 2, y: -1, Palette.cream)
        box(CGFloat(W - 168), 1, 5, at: v(150 + (W - 168) / 2, -1.5, 15.5), Palette.coral)
        box(CGFloat(W - 168), 1, 5, at: v(150 + (W - 168) / 2, -1.5, H - 15.5), Palette.coral)
        let dx = (W - 1000) * 0.45, tx = W - 1000
        for m in [1.0, -1.0] {
            let Y: (Double) -> CGFloat = { CGFloat(m == 1 ? $0 : H - $0) }
            func poly(_ pts: [(Double, Double)]) -> CGPath {
                let p = CGMutablePath(); p.addLines(between: pts.map { CGPoint(x: $0.0, y: Double(Y($0.1))) }); p.closeSubpath(); return p
            }
            slab(poly([(430 + dx, 24), (620 + dx, -380), (690 + dx, -380), (610 + dx, 24)]), depth: 6, y: -26, UIColor(hex: 0xA3AAB6), flatShaded: true)
            slab(poly([(620 + dx, -380), (690 + dx, -380), (686 + dx, -362), (628 + dx, -362)]), depth: 6, y: -25, Palette.coral, flatShaded: true)
            slab(poly([(898 + tx, 24), (972 + tx, -100), (1004 + tx, -100), (985 + tx, 40)]), depth: 6, y: -26, UIColor(hex: 0xA3AAB6), flatShaded: true)
            let ey = Double(Y(-90))
            slab(Art.rr(CGFloat(450 + dx), CGFloat(ey - 13), 98, 26, 13), depth: 4, y: -21, UIColor(hex: 0x5B6475), flatShaded: true)
            slab(CGPath(rect: CGRect(x: 470 + dx, y: ey - 13, width: 3, height: 26), transform: nil), depth: 4, y: -20, Palette.coral, flatShaded: true)
            let engine = SCNNode(geometry: SCNCapsule(capRadius: 13, height: 98))
            engine.geometry?.firstMaterial = mat(UIColor(hex: 0x5B6475))
            engine.eulerAngles.z = .pi / 2
            engine.position = v(499 + dx, -40, ey)
            solid.addChildNode(engine)
        }

        // carpet and the coral runner
        for a in L.aisles {
            box(CGFloat(L.aftX - 172), 0.6, 76, at: v((172 + L.aftX) / 2, 0.3, a), Palette.carpet)
            box(CGFloat(L.aftX - 56), 0.8, 8, at: v((56 + L.aftX) / 2, 0.7, a), Palette.coral)
        }

        // side walls with glowing windows, nose and tail bulkheads
        let wall = UIColor(hex: 0xE6E1D8)
        box(CGFloat(W - 60), 120, 8, at: v(W / 2, 60, 22), wall)
        box(CGFloat(W - 60), 120, 8, at: v(W / 2, 60, H - 22), wall)
        box(10, 120, CGFloat(H - 40), at: v(34, 60, H / 2), UIColor(hex: 0xC9CDD3))
        box(10, 120, CGFloat(H - 40), at: v(W - 26, 60, H / 2), UIColor(hex: 0xC9CDD3))
        let glass = mat(UIColor(hex: 0x9CC8EA), rough: 0.2, emissive: true)
        for row in L.rows {
            for (z, turn) in [(26.5, 0.0), (H - 26.5, Double.pi)] {
                let pane = SCNNode(geometry: SCNPlane(width: 13, height: 18))
                pane.geometry?.firstMaterial = glass
                pane.position = v(row.x, 72, z)
                pane.eulerAngles.y = Float(turn)
                solid.addChildNode(pane)
            }
        }

        // jump seats at the edge of each aisle
        for j in L.jumpSeats { box(22, 10, 12, at: v(j.x, 22, L.aisles[j.aisle] - 30), UIColor(hex: 0x4E6A7A), chamfer: 2) }

        // galleys, lavatories, closets
        for b in L.blocks {
            let h: Double = b.kind == .counter ? 46 : b.kind == .lavatory ? 112 : 84
            let color = b.kind == .counter ? UIColor(hex: 0xC8CDD4) : UIColor(hex: 0xDADDE2)
            box(CGFloat(b.w), CGFloat(h), CGFloat(b.h), at: v(b.x + b.w / 2, h / 2, b.y + b.h / 2), color, chamfer: 3)
        }
        for s in L.bins {
            let color: UIColor
            switch s.kind {
            case .trash: color = UIColor(hex: 0x5B6475)
            case .machine: color = UIColor(hex: 0x3D4452)
            case .bin: color = .white
            }
            box(28, 14, 28, at: v(s.x, 53, s.y - 4), color, chamfer: 3)
        }

        // premium curtain
        if let cx = L.curtainX {
            for a in L.aisles { box(6, 104, 76, at: v(cx, 52, a), UIColor(hex: 0x7B2E3A)) }
        }

        // seats
        let navy = Palette.navy, navyDeep = Palette.navyDeep, plum = UIColor(hex: 0x3B3566)
        for row in L.rows {
            for spot in row.seats {
                let wide: CGFloat = row.premium ? 34 : 26
                box(wide, 9, wide + 4, at: v(row.x - 1, 16, spot.y), row.premium ? plum : navy, chamfer: 3)
                box(8, 40, wide + 6, at: v(row.x + 12, 32, spot.y), navyDeep, chamfer: 3)
                box(8.5, 12, 16, at: v(row.x + 12, 47, spot.y), UIColor(hex: 0xF3EEE6), chamfer: 2)
                box(18, 3, 3, at: v(row.x - 2, 26, spot.y - Double(wide) / 2 - 2), UIColor(hex: 0x8C93A0))
            }
        }

        // passengers (the walkers start at the door and board during the cutscene)
        let reachX = 70 + 60 * 5.0
        let walkerIDs = Set(passengers.indices.filter { passengers[$0].aisle == 0 && passengers[$0].x > 260 && passengers[$0].x < reachX && !passengers[$0].vip }
            .shuffled().prefix(4))
        for (i, p) in passengers.enumerated() {
            let node = person(shirt: Palette.shirt(p.archetype), skin: Palette.skins[p.skin], hair: Palette.hairs[p.hair])
            node.position = v(p.x + 1, 0, p.y)
            solid.addChildNode(node)
            if walkerIDs.contains(i) { board(node, to: p, delay: 0.3 + 0.9 * Double(walkerIDs.sorted().firstIndex(of: i) ?? 0)) }
        }

        // the attendant runs the safety demo mid-cabin
        let midX = L.rows[L.rows.count / 2].x + 18
        let crew = person(shirt: Palette.teal, skin: UIColor(hex: 0xE9B892), hair: UIColor(hex: 0x3A2A20), standing: true)
        crew.position = v(midX, 0, a0)
        solid.addChildNode(crew)
        let belt = box(3, 18, 3, at: v(-12, 64, 0), Palette.calm, parent: crew)
        belt.runAction(.repeatForever(.sequence([.rotateBy(x: 0.35, y: 0, z: 0, duration: 0.35), .rotateBy(x: -0.35, y: 0, z: 0, duration: 0.35)])))
        for side in [-1.0, 1.0] {
            let arm = box(4, 18, 4, at: v(-6, 58, side * 11), Palette.teal, chamfer: 2, parent: crew)
            arm.eulerAngles.x = Float(side * 0.5)
        }
        // after the demo the attendant walks forward and buckles into the jump seat they start from
        let seat = L.jumpSeats.first { $0.aisle == 0 } ?? JumpSeat(x: 72, aisle: 0)
        let walkTime = (midX - seat.x) / 110
        crew.runAction(.sequence([
            .wait(duration: 7.0),
            .run { _ in belt.removeAllActions(); belt.isHidden = true },
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: true),
            .move(to: v(seat.x, 0, a0), duration: walkTime),
            .rotateTo(x: 0, y: .pi, z: 0, duration: 0.25, usesShortestUnitArc: true),
            .move(to: v(seat.x, -8, a0 - 8), duration: 0.35)
        ]))

        // overhead bins over every seat block: they frame the eye-level shots, then fade for the top-down view
        let binColor = UIColor(hex: 0xECE7DE)
        let x0 = L.firstRowX - 20, x1 = L.lastRowX + 20
        var edges: [(Double, Double)] = [(30, L.aisles[0] - 40)]
        for k in 0..<(L.aisles.count - 1) { edges.append((L.aisles[k] + 40, L.aisles[k + 1] - 40)) }
        edges.append((L.aisles.last! + 40, H - 30))
        for (z0, z1) in edges {
            box(CGFloat(x1 - x0), 26, CGFloat(z1 - z0), at: v((x0 + x1) / 2, 104, (z0 + z1) / 2), binColor, chamfer: 3, parent: bins)
            box(CGFloat(x1 - x0), 3, 3, at: v((x0 + x1) / 2, 92, z0 < a0 ? z1 : z0), UIColor(hex: 0xB8BEC7), parent: bins)
        }
        // a ceiling over the aisles for the eye-level shots; it fades out with the bins
        box(CGFloat(W - 80), 3, CGFloat(H - 60), at: v(W / 2, 132, H / 2), UIColor(hex: 0xF1ECE3), parent: bins)
        solid.addChildNode(bins)
        scene.rootNode.addChildNode(solid)
        buildFlat()

        // a bag goes up into a bin, and the lid snaps shut
        let binRow = L.rows[max(1, L.rows.count / 2 - 2)]
        let bag = box(18, 12, 10, at: v(binRow.x, 40, a0 - 12), UIColor(hex: 0x3D6E8C), chamfer: 2)
        bag.runAction(.sequence([.wait(duration: 2.2), .move(to: v(binRow.x, 104, a0 - 58), duration: 0.7), .fadeOut(duration: 0.15)]))
        let lid = box(36, 2, 24, at: v(binRow.x, 92, a0 - 40), binColor, chamfer: 1, parent: bins)   // fades with the bins
        lid.eulerAngles.x = -1.1
        lid.runAction(.sequence([.wait(duration: 3.0), .rotateTo(x: 0, y: 0, z: 0, duration: 0.15)]))

        // warm cabin light with soft shadows
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient
        ambient.light!.intensity = 520; ambient.light!.color = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
        scene.rootNode.addChildNode(ambient); ambientLight = ambient.light
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional
        sun.light!.intensity = 850; sun.light!.castsShadow = true
        sun.light!.shadowMode = .forward; sun.light!.shadowRadius = 4; sun.light!.shadowSampleCount = 8
        sun.light!.shadowColor = UIColor(white: 0, alpha: 0.35)
        sun.light!.orthographicScale = CGFloat(max(W, H) / 1.6)
        sun.position = v(W / 2, 400, H / 2)
        sun.eulerAngles = SCNVector3(-Float.pi / 2.4, 0.3, 0)
        scene.rootNode.addChildNode(sun); sunLight = sun.light
        for k in 0..<3 {
            let lamp = SCNNode(); lamp.light = SCNLight(); lamp.light!.type = .omni
            lamp.light!.intensity = 260; lamp.light!.color = UIColor(red: 1, green: 0.88, blue: 0.7, alpha: 1)
            lamp.light!.attenuationEndDistance = 420
            lamp.position = v(L.firstRowX + (L.lastRowX - L.firstRowX) * Double(k) / 2, 110, a0)
            scene.rootNode.addChildNode(lamp); lampLights.append(lamp.light!)
        }

        // camera
        let camera = SCNCamera()
        camera.zNear = 1; camera.zFar = 6000
        camera.projectionDirection = .vertical     // the field of view is measured on the height (framing maths)
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    /// The game's own art laid flat on the floor: the 2D cabin image and every passenger's 2D sprite, unlit.
    private func buildFlat() {
        func lay(_ image: UIImage, w: Double, h: Double, x: Double, z: Double, y: Double) {
            let plane = SCNPlane(width: CGFloat(w), height: CGFloat(h))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = image
            plane.firstMaterial = m
            let n = SCNNode(geometry: plane)
            n.eulerAngles.x = -.pi / 2                 // lie flat, image top toward the nose side of the screen
            n.position = v(x, y, z)
            flat.addChildNode(n)
        }
        lay(Art.cabin(layout), w: layout.width, h: layout.height, x: layout.width / 2, z: layout.height / 2, y: 0.5)
        for p in passengers {
            lay(Art.passenger(p, sick: false), w: Double(Art.passengerSize.width), h: Double(Art.passengerSize.height), x: p.x, z: p.y, y: 1)
        }
        flat.opacity = 0
        scene.rootNode.addChildNode(flat)
    }

    /// A rounded 3D person: body, head and hair on the back of the head (they face the nose, −x).
    private func person(shirt: UIColor, skin: UIColor, hair: UIColor, standing: Bool = false) -> SCNNode {
        let n = SCNNode()
        let lift: Double = standing ? 22 : 0
        let body = SCNNode(geometry: SCNCapsule(capRadius: 9, height: standing ? 50 : 32))
        body.geometry?.firstMaterial = mat(shirt)
        body.position = v(0, standing ? 25 : 30, 0)
        n.addChildNode(body)
        let head = SCNNode(geometry: SCNSphere(radius: 7.5))
        head.geometry?.firstMaterial = mat(skin, rough: 0.6)
        head.position = v(-1, 50 + lift, 0)
        n.addChildNode(head)
        let hairNode = SCNNode(geometry: SCNSphere(radius: 7.9))
        hairNode.geometry?.firstMaterial = mat(hair, rough: 0.9)
        hairNode.position = v(1.8, 51.5 + lift, 0)
        hairNode.scale = SCNVector3(0.85, 0.95, 1)
        n.addChildNode(hairNode)
        return n
    }

    /// Walk in from the forward door, down the aisle, then turn and sit.
    private func board(_ node: SCNNode, to p: Passenger, delay: Double) {
        let a0 = layout.aisles[0]
        let lane = a0 + (p.y < a0 ? -9 : 9)
        node.position = v(170, 12, lane)              // a few rows in, walking away from the lens
        node.eulerAngles.y = .pi                       // facing aft while walking in
        let walkTime = max(0.4, (p.x - 170) / 60)
        let walk = SCNAction.move(to: v(p.x + 1, 12, lane), duration: walkTime)
        let bob = SCNAction.repeat(.sequence([.moveBy(x: 0, y: 2, z: 0, duration: 0.2), .moveBy(x: 0, y: -2, z: 0, duration: 0.2)]),
                                   count: Int(walkTime / 0.4))
        let turn = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.25, usesShortestUnitArc: true)
        let sit = SCNAction.move(to: v(p.x + 1, 0, p.y), duration: 0.45)
        sit.timingMode = .easeOut
        node.runAction(.sequence([.wait(duration: delay), .group([walk, bob]), turn, sit]))
    }

    // MARK: - Camera path

    private struct Key { let t: Double; let pos: SCNVector3; let pitch: Float; let yaw: Float; let fov: CGFloat }

    /// The final shot: straight down, a long lens, framed like the 2D play view.
    private func topDown() -> Key {
        let fov: CGFloat = 12
        let (viewSize, insets) = frame()
        let availW = Double(viewSize.width - insets.left - insets.right)
        let availH = Double(viewSize.height - insets.top - insets.bottom)
        let s = min(availW / layout.width, availH / layout.height)
        let visibleH = Double(viewSize.height) / s
        let d = visibleH / (2 * tan(Double(fov) * .pi / 360))
        // the 2D world is centred in the inset rect; shift the camera to match
        let dx = Double(insets.right - insets.left) / 2 / s
        let dz = Double(insets.bottom - insets.top) / 2 / s
        return Key(t: Self.duration, pos: v(layout.width / 2 + dx, d, layout.height / 2 + dz), pitch: -.pi / 2, yaw: 0, fov: fov)
    }

    private func keys() -> [Key] {
        let a0 = layout.aisles[0]
        let midX = layout.rows[layout.rows.count / 2].x
        return [
            Key(t: 0, pos: v(66, 86, a0 - 4), pitch: -0.2, yaw: -.pi / 2, fov: 62),        // over the heads, down the aisle
            Key(t: 4.2, pos: v(200, 88, a0 + 6), pitch: -0.22, yaw: -.pi / 2 + 0.06, fov: 58),
            Key(t: 7.6, pos: v(midX - 190, 230, a0 + 60), pitch: -0.78, yaw: -.pi / 2 + 0.45, fov: 52),
            topDown()
        ]
    }

    private func pose(at t: Double, _ ks: [Key]) {
        guard let camera = cameraNode.camera else { return }
        var i = 0
        while i < ks.count - 2 && t > ks[i + 1].t { i += 1 }
        let a = ks[i], b = ks[i + 1]
        let u = max(0, min(1, (t - a.t) / (b.t - a.t)))
        let k = Float(u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2)     // ease in-out (cubic)
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * k }
        camera.fieldOfView = a.fov + (b.fov - a.fov) * CGFloat(k)   // the lens narrows as it rises: near-orthographic at the end
        cameraNode.position = SCNVector3(mix(a.pos.x, b.pos.x), mix(a.pos.y, b.pos.y), mix(a.pos.z, b.pos.z))
        cameraNode.eulerAngles = SCNVector3(mix(a.pitch, b.pitch), mix(a.yaw, b.yaw), 0)
    }

    /// Light for time t: warm with shadows early, flattening during the swoop to match the flat 2D art.
    private func setLights(at t: Double) {
        let k = CGFloat(max(0, min(1, (t - 7.6) / (Self.duration - 7.6))))
        ambientLight?.intensity = 520 + (1150 - 520) * k
        sunLight?.intensity = 850 + (90 - 850) * k
        lampLights.forEach { $0.intensity = 260 * (1 - k) }
    }

    /// Debug: hold the cutscene at time t (launch with `-introAt 9.5`) to check framing and the 2D match.
    func freeze(at t: Double) {
        cameraNode.runAction(.repeatForever(.customAction(duration: 0.1) { [weak self] _, _ in self?.apply(at: t) }))
    }

    /// Everything that follows the cutscene clock: camera, light, the bins fading, and the 3D → flat 2D blend.
    private func apply(at t: Double) {
        pose(at: t, keys())
        setLights(at: t)                                            // flattens during the swoop
        bins.opacity = t < 4.4 ? 1 : max(0, 1 - CGFloat((t - 4.4) / 1.4))
        func smooth(_ x: Double) -> CGFloat { let c = max(0, min(1, x)); return CGFloat(c * c * (3 - 2 * c)) }
        flat.opacity = smooth((t - 8.2) / 1.4)                      // the game's own art fades in…
        solid.opacity = 1 - smooth((t - 8.6) / 1.5)                 // …as the 3D cabin fades out
    }

    func play(done: @escaping () -> Void) {
        self.done = done
        let size = frame().size
        if size.width > 1 { scene.background.contents = Art.sky(size) }   // exactly the 2D sky at this screen size
        let ks = keys()
        pose(at: 0, ks)
        let total = Self.duration
        _ = ks
        // our own clock, so the camera can hold at the end of shot 2 until the captain is done
        cameraNode.runAction(.customAction(duration: 3600) { [weak self] _, elapsed in
            guard let self else { return }
            let dt = Double(elapsed - self.lastElapsed)
            self.lastElapsed = elapsed
            if self.clock < Self.holdAt || self.released {
                self.clock = min(total, self.clock + dt)
            } else {
                self.held += dt
                if self.held > 12 { self.released = true }          // never wait forever on the voice
            }
            let t = self.clock
            self.apply(at: t)
            // hand over to 2D a little before the camera stops, so the crossfade overlaps the end of the move
            if t >= total - Self.handoffLead { DispatchQueue.main.async { self.finish() } }
        }, forKey: "intro")
        scene.rootNode.addChildNode(lights)
    }

    func skip() {
        cameraNode.removeAllActions()
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let d = done
        done = nil
        d?()
    }
}
