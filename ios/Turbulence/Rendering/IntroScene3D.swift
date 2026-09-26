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
    private let viewSize: CGSize
    private let insets: UIEdgeInsets
    private let bins = SCNNode()
    private var done: (() -> Void)?
    private var finished = false
    static let duration = 6.4

    init(sim: FlightSimulation, viewSize: CGSize, insets: UIEdgeInsets) {
        layout = sim.layout
        passengers = sim.passengers
        self.viewSize = viewSize
        self.insets = insets
        scene.background.contents = Palette.sky
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
        (parent ?? scene.rootNode).addChildNode(n)
        return n
    }

    private func v(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(Float(x), Float(y), Float(z)) }

    // MARK: - Build the cabin

    private func build() {
        let L = layout
        let W = L.width, H = L.height
        let a0 = L.aisles[0]

        // floor, carpet and the coral runner
        box(CGFloat(W - 40), 2, CGFloat(H - 44), at: v(W / 2, -1, H / 2), Palette.cream)
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
                scene.rootNode.addChildNode(pane)
            }
        }

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
        let reachX = 70 + 80 * 4.0
        let walkerIDs = Set(passengers.indices.filter { passengers[$0].aisle == 0 && passengers[$0].x < reachX && !passengers[$0].vip }
            .shuffled().prefix(4))
        for (i, p) in passengers.enumerated() {
            let node = person(shirt: Palette.shirt(p.archetype), skin: Palette.skins[p.skin], hair: Palette.hairs[p.hair])
            node.position = v(p.x + 1, 0, p.y)
            scene.rootNode.addChildNode(node)
            if walkerIDs.contains(i) { board(node, to: p, delay: 0.15 + 0.55 * Double(walkerIDs.sorted().firstIndex(of: i) ?? 0)) }
        }

        // the attendant runs the safety demo mid-cabin
        let midX = L.rows[L.rows.count / 2].x + 18
        let crew = person(shirt: Palette.teal, skin: UIColor(hex: 0xE9B892), hair: UIColor(hex: 0x3A2A20), standing: true)
        crew.position = v(midX, 0, a0)
        scene.rootNode.addChildNode(crew)
        let belt = box(3, 18, 3, at: v(-12, 64, 0), Palette.calm, parent: crew)
        belt.runAction(.repeatForever(.sequence([.rotateBy(x: 0.35, y: 0, z: 0, duration: 0.35), .rotateBy(x: -0.35, y: 0, z: 0, duration: 0.35)])))
        for side in [-1.0, 1.0] {
            let arm = box(4, 18, 4, at: v(-6, 58, side * 11), Palette.teal, chamfer: 2, parent: crew)
            arm.eulerAngles.x = Float(side * 0.5)
        }

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
        scene.rootNode.addChildNode(bins)

        // a bag goes up into a bin, and the lid snaps shut
        let binRow = L.rows[max(1, L.rows.count / 2 - 2)]
        let bag = box(18, 12, 10, at: v(binRow.x, 40, a0 - 12), UIColor(hex: 0x3D6E8C), chamfer: 2)
        bag.runAction(.sequence([.wait(duration: 1.2), .move(to: v(binRow.x, 104, a0 - 58), duration: 0.6), .fadeOut(duration: 0.15)]))
        let lid = box(36, 2, 24, at: v(binRow.x, 92, a0 - 40), binColor, chamfer: 1, parent: bins)   // fades with the bins
        lid.eulerAngles.x = -1.1
        lid.runAction(.sequence([.wait(duration: 1.9), .rotateTo(x: 0, y: 0, z: 0, duration: 0.15)]))

        // warm cabin light with soft shadows
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient
        ambient.light!.intensity = 520; ambient.light!.color = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional
        sun.light!.intensity = 850; sun.light!.castsShadow = true
        sun.light!.shadowMode = .forward; sun.light!.shadowRadius = 4; sun.light!.shadowSampleCount = 8
        sun.light!.shadowColor = UIColor(white: 0, alpha: 0.35)
        sun.light!.orthographicScale = CGFloat(max(W, H) / 1.6)
        sun.position = v(W / 2, 400, H / 2)
        sun.eulerAngles = SCNVector3(-Float.pi / 2.4, 0.3, 0)
        scene.rootNode.addChildNode(sun)
        for k in 0..<3 {
            let lamp = SCNNode(); lamp.light = SCNLight(); lamp.light!.type = .omni
            lamp.light!.intensity = 260; lamp.light!.color = UIColor(red: 1, green: 0.88, blue: 0.7, alpha: 1)
            lamp.light!.attenuationEndDistance = 420
            lamp.position = v(L.firstRowX + (L.lastRowX - L.firstRowX) * Double(k) / 2, 110, a0)
            scene.rootNode.addChildNode(lamp)
        }

        // camera
        let camera = SCNCamera()
        camera.zNear = 1; camera.zFar = 6000
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
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
        node.position = v(62, 12, lane)
        node.eulerAngles.y = .pi                       // facing aft while walking in
        let walk = SCNAction.move(to: v(p.x + 1, 12, lane), duration: (p.x - 62) / 80)
        let bob = SCNAction.repeat(.sequence([.moveBy(x: 0, y: 2, z: 0, duration: 0.18), .moveBy(x: 0, y: -2, z: 0, duration: 0.18)]),
                                   count: Int((p.x - 62) / 80 / 0.36))
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
            Key(t: 0, pos: v(66, 60, a0 - 4), pitch: -0.05, yaw: -.pi / 2, fov: 64),
            Key(t: 2.4, pos: v(170, 62, a0 + 6), pitch: -0.1, yaw: -.pi / 2 + 0.06, fov: 60),
            Key(t: 4.5, pos: v(midX - 190, 230, a0 + 60), pitch: -0.78, yaw: -.pi / 2 + 0.45, fov: 52),
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

    func play(done: @escaping () -> Void) {
        self.done = done
        let ks = keys()
        pose(at: 0, ks)
        let total = Self.duration
        cameraNode.runAction(.sequence([
            .customAction(duration: total) { [weak self] _, elapsed in self?.pose(at: Double(elapsed), ks) },
            .run { [weak self] _ in DispatchQueue.main.async { self?.finish() } }
        ]), forKey: "intro")
        bins.runAction(.sequence([.wait(duration: 2.5), .fadeOut(duration: 1.0)]))   // clears the view for the 3/4 shot
    }

    func skip() { finish() }

    private func finish() {
        guard !finished else { return }
        finished = true
        cameraNode.removeAllActions()
        let d = done
        done = nil
        d?()
    }
}
