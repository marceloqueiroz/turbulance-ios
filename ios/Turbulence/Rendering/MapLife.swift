import SpriteKit
import UIKit

/// City life on the route map (Route Map Plan, City life): a few ferries, sailboats, whales and gulls along short
/// authored paths, plus chimney smoke, lighthouse beams and parked planes. People, cars and buses were taken out on
/// 2026-10-04 to keep the towns calm; the walk and road kinds still work if they come back.
///
/// Calm on purpose: one actor per back-and-forth path (only loops carry more, all moving the same way at the same speed,
/// so nobody collides), and quiet airports stay quiet. Paths are checked against the art by ios/tools/check_life.py.
///
/// The animals and boats are cut-out puppets (ios/tools/puppet_parts.py slices them; parts share one canvas and turn
/// around their joints): the whale's tail beats and its flipper paddles, the sailboat's sails billow, the gull flaps and
/// glides. Boats leave wakes, the ferry puffs smoke. Only actors on screen move, and nothing moves with Reduce Motion.
final class MapLifeLayer: SKNode {
    private struct Actor {
        let node: SKSpriteNode
        let width: CGFloat
        let kind: MapLayout.Life.Kind
        let points: [CGPoint]
        let lengths: [CGFloat]          // cumulative length at each point
        let loop: Bool
        let speed: CGFloat
        let rolls: Bool                 // a plain sprite rocks on the swell; puppets rock their own parts
        let wake: Bool
        var distance: CGFloat
        var direction: CGFloat = 1
        var phase: Double
        var pause: Double = 0           // seconds left standing still
        var wakeClock: Double = 0

        var total: CGFloat { lengths.last ?? 0 }

        /// Position along the polyline and the direction of travel there.
        func sample(_ d: CGFloat) -> (CGPoint, CGVector) {
            guard points.count > 1, total > 0 else { return (points.first ?? .zero, CGVector(dx: 1, dy: 0)) }
            var i = 1
            while i < lengths.count - 1 && lengths[i] < d { i += 1 }
            let a = points[i - 1], b = points[i]
            let seg = max(lengths[i] - lengths[i - 1], 0.001)
            let t = min(1, max(0, (d - lengths[i - 1]) / seg))
            return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), CGVector(dx: b.x - a.x, dy: b.y - a.y))
        }
    }

    private var actors: [Actor] = []
    private var time: Double = 0
    private var stillLife = false

    /// Width in world units for each piece (buildings are about 40 wide).
    static let widths: [String: CGFloat] = [
        "CarCoral": 26, "CarTeal": 26, "Van": 28, "Bus": 36, "BaggageTractor": 36, "FuelTruck": 32, "PushbackTug": 24,
        "PersonCoral": 11, "PersonTeal": 11, "PersonSuitcase": 12, "Attendant": 11, "Gull": 22,
        "Rowboat": 26, "Sailboat": 30, "FishingBoat": 36, "Speedboat": 30, "Ferry": 56, "Whale": 66, "Dolphin": 30, "Buoy": 14,
        "ToyPlane": 40,
    ]

    private static let defaults: [MapLayout.Life.Kind: [String]] = [
        .road: ["CarCoral", "CarTeal", "Van"], .walk: ["PersonCoral", "PersonTeal", "PersonSuitcase"],
        .water: ["Sailboat"], .moored: ["Rowboat"], .air: ["Gull"],
    ]

    private static let speeds: [MapLayout.Life.Kind: CGFloat] = [.road: 20, .walk: 5.5, .water: 8, .air: 24]

    /// How long each kind stands still at the end of a back-and-forth path.
    private static let endPause: [MapLayout.Life.Kind: ClosedRange<Double>] = [.walk: 1.5...4, .road: 2...3.5, .water: 3...5]

    /// Builds everything for the open regions. `toScene` turns 0…1 region-image points into scene points.
    func build(life: [(entries: [MapLayout.Life], toScene: (CGPoint) -> CGPoint)],
               airports: [(at: CGPoint, style: MapLayout.Airport.Style, isNext: Bool)], reduceMotion: Bool) {
        removeAllChildren()
        removeAllActions()
        actors.removeAll()
        whaleTails.removeAll()
        stillLife = reduceMotion
        var seed = 0
        for region in life {
            for entry in region.entries {
                let pts = entry.points.map { region.toScene(CGPoint(x: $0[0], y: $0[1])) }
                let names = entry.actors ?? Self.defaults[entry.kind] ?? []
                switch entry.kind {
                case .smoke: pts.forEach { addSmoke(at: $0) }
                case .glow: pts.forEach { addLighthouse(at: $0) }
                case .moored:
                    for (i, p) in pts.enumerated() where !names.isEmpty {
                        addActor(names[i % names.count], kind: .moored, path: [p], loop: false, offset: 0, seed: &seed)
                    }
                default:
                    // back-and-forth paths carry one actor so nobody meets head-on; loops may carry a few, evenly spaced
                    let count = (entry.loop ?? false) ? max(1, entry.count ?? 1) : 1
                    for i in 0..<count where !names.isEmpty {
                        addActor(names[i % names.count], kind: entry.kind, path: pts, loop: entry.loop ?? false,
                                 offset: CGFloat(i) / CGFloat(count), seed: &seed)
                    }
                }
            }
        }
        for a in airports { addAirportLife(a.at, style: a.style, busy: a.isNext) }
        if reduceMotion { update(dt: 0, visible: .infinite, reduceMotion: true) }
    }

    private func sprite(_ name: String) -> (SKSpriteNode, CGFloat) {
        let node = SKSpriteNode(imageNamed: "Map/\(name)")
        let w = Self.widths[name] ?? 24
        node.size = CGSize(width: w, height: w * node.size.height / max(node.size.width, 1))
        return (node, w)
    }

    private func addActor(_ name: String, kind: MapLayout.Life.Kind, path: [CGPoint], loop: Bool, offset: CGFloat, seed: inout Int) {
        let w = Self.widths[name] ?? 24
        let node: SKSpriteNode                          // the holder that travels; it flips to face the way it goes
        var rolls = false
        switch name {
        case "Whale":
            node = holder(whale(width: w))
        case "Sailboat":
            node = holder(sailboat(width: w))
        case "Gull":
            node = holder(gull(width: w))
        case "Ferry":
            let (ferry, _) = sprite(name)
            node = holder(ferry)
            if !stillLife { funnelSmoke(on: ferry, at: CGPoint(x: (230.0 / 484 - 0.5) * w, y: (0.5 - 15.0 / 420) * ferry.size.height)) }
            rolls = true
        default:
            node = sprite(name).0
            rolls = true
        }
        var lengths: [CGFloat] = [0]
        let pts = loop && path.count > 2 ? path + [path[0]] : path
        for i in 1..<max(1, pts.count) { lengths.append(lengths[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        seed += 1
        let actor = Actor(node: node, width: w, kind: kind, points: pts, lengths: lengths, loop: loop,
                          speed: (Self.speeds[kind] ?? 10) * (0.85 + 0.3 * CGFloat(seed % 5) / 4),
                          rolls: rolls, wake: kind == .water && name != "Whale",
                          distance: (lengths.last ?? 0) * offset, phase: Double(seed) * 1.7)
        node.zPosition = kind == .air ? 3 : 1
        node.position = pts.first ?? .zero
        addChild(node)
        actors.append(actor)
    }

    private func holder(_ child: SKNode) -> SKSpriteNode {
        let h = SKSpriteNode(color: .clear, size: .zero)
        h.addChild(child)
        return h
    }

    // MARK: Puppets

    /// Parts that share one source canvas; each turns around its own joint (pivot in source pixels, nil = fixed).
    private func puppet(canvas: CGSize, width w: CGFloat, parts: [(image: String, pivot: CGPoint?, z: CGFloat)]) -> (SKSpriteNode, [SKSpriteNode]) {
        let size = CGSize(width: w, height: w * canvas.height / canvas.width)
        let root = SKSpriteNode(color: .clear, size: size)
        let nodes = parts.map { p -> SKSpriteNode in
            let n = SKSpriteNode(imageNamed: "Map/\(p.image)")
            n.size = size
            if let pivot = p.pivot {                    // anchor at the joint, then put the joint back where it belongs
                n.anchorPoint = CGPoint(x: pivot.x / canvas.width, y: 1 - pivot.y / canvas.height)
                n.position = CGPoint(x: (n.anchorPoint.x - 0.5) * size.width, y: (n.anchorPoint.y - 0.5) * size.height)
            }
            n.zPosition = p.z
            root.addChild(n)
            return n
        }
        return (root, nodes)
    }

    private func loop(_ a: SKAction, _ b: SKAction) -> SKAction {
        let s = SKAction.sequence([a, b]); s.timingMode = .easeInEaseOut
        return .repeatForever(s)
    }

    // MARK: Sailboat

    /// The sails billow across the mast (they fill and slacken, with a slight sway), and the boat heels in the gusts.
    private func sailboat(width w: CGFloat) -> SKSpriteNode {
        let (root, parts) = puppet(canvas: CGSize(width: 396, height: 472), width: w, parts: [
            ("SailboatHull", nil, 0), ("SailboatSails", CGPoint(x: 185, y: 300), 1)])
        guard !stillLife else { return root }
        let sails = parts[1]
        sails.run(loop(.group([.scaleX(to: 1.07, duration: 1.3), .rotate(toAngle: 0.025, duration: 1.3)]),
                       .group([.scaleX(to: 0.9, duration: 1.6), .rotate(toAngle: -0.02, duration: 1.6)])))
        root.run(.sequence([.wait(forDuration: Double.random(in: 0...2)),
                            loop(.rotate(toAngle: 0.07, duration: 2.1), .rotate(toAngle: -0.03, duration: 2.6))]))
        return root
    }

    // MARK: Gull

    /// A few wing beats, then a long glide; its shadow glides on the water below.
    private func gull(width w: CGFloat) -> SKSpriteNode {
        let (root, parts) = puppet(canvas: CGSize(width: 456, height: 276), width: w, parts: [
            ("GullBody", nil, 0), ("GullWingLeft", CGPoint(x: 236, y: 100), 1), ("GullWingRight", CGPoint(x: 304, y: 126), 1)])
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.7, height: w * 0.18))
        shadow.fillColor = Palette.navy.withAlphaComponent(0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -w * 1.1); shadow.zPosition = -1
        root.addChild(shadow)
        guard !stillLife else { return root }
        let left = parts[1], right = parts[2]
        func beat(_ wing: SKSpriteNode, angle: CGFloat) -> SKAction {
            let down = SKAction.group([.scaleY(to: 0.55, duration: 0.16), .rotate(toAngle: angle, duration: 0.16)])
            let up = SKAction.group([.scaleY(to: 1, duration: 0.2), .rotate(toAngle: 0, duration: 0.2)])
            down.timingMode = .easeIn; up.timingMode = .easeOut
            return .sequence([down, up])
        }
        let glide = SKAction.sequence([.rotate(toAngle: 0.05, duration: 0.8), .rotate(toAngle: 0, duration: 0.8)])
        func cycle(_ wing: SKSpriteNode, angle: CGFloat) -> SKAction {
            .repeatForever(.sequence([.repeat(beat(wing, angle: angle), count: 3), glide, .wait(forDuration: Double.random(in: 0.4...1.2))]))
        }
        let start = Double.random(in: 0...1.5)
        left.run(.sequence([.wait(forDuration: start), cycle(left, angle: -0.14)]))
        right.run(.sequence([.wait(forDuration: start), cycle(right, angle: 0.14)]))
        return root
    }

    // MARK: Whale

    private var whaleTails: [ObjectIdentifier: SKSpriteNode] = [:]

    /// The whale's tail beats, its flipper paddles and its body rocks; it swims, blows, dives and surfaces in a cycle.
    private func whale(width w: CGFloat) -> SKSpriteNode {
        let (root, parts) = puppet(canvas: CGSize(width: 512, height: 420), width: w, parts: [
            ("WhaleBody", nil, 0), ("WhaleFlipper", CGPoint(x: 300, y: 305), 1), ("WhaleTail", CGPoint(x: 368, y: 147), 1)])
        let body = parts[0], flipper = parts[1], tail = parts[2]
        whaleTails[ObjectIdentifier(root)] = tail
        guard !stillLife else { return root }
        tail.run(loop(.rotate(toAngle: 0.16, duration: 0.75), .rotate(toAngle: -0.12, duration: 0.75)), withKey: "beat")
        flipper.run(loop(.rotate(toAngle: -0.2, duration: 0.9), .rotate(toAngle: 0.12, duration: 0.9)))
        body.run(loop(.group([.rotate(toAngle: 0.03, duration: 1.5), .scaleY(to: 1.025, duration: 1.5)]),
                      .group([.rotate(toAngle: -0.03, duration: 1.5), .scaleY(to: 1, duration: 1.5)])))
        DispatchQueue.main.async { [weak self, weak root] in        // once the root has its holder, start the dive cycle
            guard let self, let root, let holder = root.parent else { return }
            self.runWhaleCycle(root, in: holder, width: w)
        }
        return root
    }

    private func tailDive(_ whale: SKNode) -> SKAction {
        .run { [weak self] in
            guard let tail = self?.whaleTails[ObjectIdentifier(whale)] else { return }
            tail.removeAction(forKey: "beat")
            tail.run(.rotate(toAngle: 0.34, duration: 0.6, shortestUnitArc: true))     // fluke up as the body tips down
        }
    }

    private func tailResume(_ whale: SKNode) -> SKAction {
        .run { [weak self] in
            guard let self, let tail = self.whaleTails[ObjectIdentifier(whale)] else { return }
            tail.run(.sequence([.rotate(toAngle: 0, duration: 0.4),
                                self.loop(.rotate(toAngle: 0.16, duration: 0.75), .rotate(toAngle: -0.12, duration: 0.75))]), withKey: "beat")
        }
    }

    /// Swims at the surface, blows, dives with a splash, glides under water as a faint shadow, then surfaces again.
    private func runWhaleCycle(_ whale: SKSpriteNode, in holder: SKNode, width w: CGFloat) {
        let h = whale.size.height
        let blowhole = CGPoint(x: -0.2 * w, y: 0.2 * h)          // the piece faces left; the holder flips with the travel
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.8, height: h * 0.3))
        shadow.fillColor = Palette.navy.withAlphaComponent(0.28); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -h * 0.18); shadow.alpha = 0; shadow.zPosition = -1
        holder.addChild(shadow)

        let blow = SKAction.run { [weak self] in self?.spout(from: blowhole, in: holder) }
        let surfaceSwim = SKAction.sequence([.wait(forDuration: 1.6), blow, .wait(forDuration: 0.9), blow, .wait(forDuration: 3.2)])
        let dive = SKAction.group([
            tailDive(whale),
            .run { [weak self] in self?.ring(at: CGPoint(x: 0, y: -h * 0.2), in: holder, width: w * 0.55, twice: true) },
            .rotate(toAngle: 0.38, duration: 1.1, shortestUnitArc: true),
            .moveTo(y: -h * 0.25, duration: 1.1),
            .scale(to: 0.85, duration: 1.1),
            .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.75)]),
        ])
        let underwater = SKAction.sequence([
            .run { shadow.run(.fadeAlpha(to: 1, duration: 0.6)) },
            .wait(forDuration: Double.random(in: 4.5...7)),
            .run { shadow.run(.fadeOut(withDuration: 0.4)) },
        ])
        let surface = SKAction.group([
            tailResume(whale),
            .run { [weak self] in self?.ring(at: CGPoint(x: 0, y: -h * 0.2), in: holder, width: w * 0.55, twice: true)
                                  self?.spout(from: blowhole, in: holder, small: true) },
            .sequence([.rotate(toAngle: -0.25, duration: 0), .rotate(toAngle: 0, duration: 1.0, shortestUnitArc: true)]),
            .moveTo(y: 0, duration: 0.9),
            .scale(to: 1, duration: 0.9),
            .fadeIn(withDuration: 0.5),
        ])
        whale.run(.sequence([.wait(forDuration: Double.random(in: 0...3)), .repeatForever(.sequence([surfaceSwim, dive, underwater, surface]))]))
    }

    /// A puff of droplets from the blowhole: they burst up, fan out, fall back and fade, with a little mist.
    private func spout(from p: CGPoint, in parent: SKNode, small: Bool = false) {
        let count = small ? 6 : 14
        for i in 0..<count {
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.8...3.4))
            drop.fillColor = UIColor.white.withAlphaComponent(0.95); drop.strokeColor = .clear
            drop.position = p; drop.zPosition = 2; drop.setScale(0.6)
            parent.addChild(drop)
            let rise = CGFloat.random(in: small ? 10...16 : 24...38), spread = CGFloat.random(in: -11...11)
            let up = SKAction.moveBy(x: spread * 0.4, y: rise, duration: 0.42); up.timingMode = .easeOut
            let down = SKAction.moveBy(x: spread, y: -rise * 0.7, duration: 0.5); down.timingMode = .easeIn
            drop.run(.sequence([.wait(forDuration: Double(i) * 0.025), .group([.sequence([up, down]), .scale(to: 1.4, duration: 0.92),
                                .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.42)])]), .removeFromParent()]))
        }
        guard !small else { return }
        let mist = SKSpriteNode(imageNamed: "Map/Cloud5")
        mist.size = CGSize(width: 16, height: 10); mist.alpha = 0.6; mist.zPosition = 2
        mist.color = .white; mist.colorBlendFactor = 0.7                // spray is white, not cloud-shaded grey
        mist.position = CGPoint(x: p.x, y: p.y + 22)
        parent.addChild(mist)
        mist.run(.sequence([.group([.scale(to: 2.2, duration: 1.2), .moveBy(x: 0, y: 8, duration: 1.2), .fadeOut(withDuration: 1.2)]), .removeFromParent()]))
    }

    // MARK: Water and smoke

    /// Widening rings of foam (a splash, or a boat's wake).
    private func ring(at p: CGPoint, in parent: SKNode, width: CGFloat, twice: Bool = false, alpha: CGFloat = 0.85) {
        for (i, delay) in (twice ? [0.0, 0.25] : [0.0]).enumerated() {
            let r = SKShapeNode(ellipseOf: CGSize(width: width, height: width * 0.33))
            r.strokeColor = UIColor.white.withAlphaComponent(alpha); r.lineWidth = i == 0 ? 2 : 1.4; r.fillColor = .clear
            r.position = p; r.zPosition = 0.5; r.alpha = 0
            parent.addChild(r)
            r.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.05),
                             .group([.scale(to: 2.1, duration: 1.2), .fadeOut(withDuration: 1.2)]), .removeFromParent()]))
        }
    }

    /// The ferry's funnel puffs little clouds that drift back and up.
    private func funnelSmoke(on ferry: SKNode, at p: CGPoint) {
        let puff = SKAction.run { [weak ferry] in
            guard let ferry else { return }
            let s = SKSpriteNode(imageNamed: "Map/Cloud3")
            s.size = CGSize(width: 8, height: 5); s.alpha = 0.9; s.zPosition = 2
            s.color = .white; s.colorBlendFactor = 0.4
            s.position = p
            ferry.addChild(s)
            s.run(.sequence([.group([.moveBy(x: 10, y: 16, duration: 1.8), .scale(to: 2.4, duration: 1.8), .fadeOut(withDuration: 1.8)]),
                             .removeFromParent()]))
        }
        ferry.run(.repeatForever(.sequence([puff, .wait(forDuration: 0.9, withRange: 0.4)])))
    }

    private func addSmoke(at p: CGPoint) {
        guard !stillLife else { return }
        let spawn = SKAction.run { [weak self] in
            let puff = SKSpriteNode(imageNamed: "Map/Cloud3")
            puff.size = CGSize(width: 9, height: 6)
            puff.position = p
            puff.alpha = 0.85
            puff.zPosition = 2
            self?.addChild(puff)
            puff.run(.sequence([.group([.moveBy(x: 6, y: 26, duration: 2.6), .scale(to: 2.2, duration: 2.6), .fadeOut(withDuration: 2.6)]),
                                .removeFromParent()]))
        }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 2.2, withRange: 0.8)])))
    }

    /// A lamp that glows and a beam that sweeps round, squashed to sit flat in the map's tilted view.
    private func addLighthouse(at p: CGPoint) {
        let glow = SKShapeNode(circleOfRadius: 7)
        glow.fillColor = Palette.calm.withAlphaComponent(0.7); glow.strokeColor = .clear; glow.glowWidth = 5
        glow.position = p; glow.zPosition = 2.6
        addChild(glow)
        let flat = SKNode()                                      // perspective: the sweep is a flattened circle
        flat.position = p; flat.yScale = 0.42; flat.zPosition = 2.5
        addChild(flat)
        let spin = SKNode()
        flat.addChild(spin)
        for angle in [0, CGFloat.pi] {
            let beam = CGMutablePath()
            beam.move(to: .zero)
            beam.addLine(to: CGPoint(x: 75 * cos(angle - 0.22), y: 75 * sin(angle - 0.22)))
            beam.addLine(to: CGPoint(x: 75 * cos(angle + 0.22), y: 75 * sin(angle + 0.22)))
            beam.closeSubpath()
            let shape = SKShapeNode(path: beam)
            // warm light laid over the sea (additive blending would turn it cyan on the blue)
            shape.fillColor = UIColor(red: 1, green: 0.86, blue: 0.45, alpha: 0.3); shape.strokeColor = .clear
            spin.addChild(shape)
        }
        guard !stillLife else { return }
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 1), .fadeAlpha(to: 1, duration: 1)])))
        spin.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 5)))
    }

    /// Town and city airports keep a parked plane; the next departure's plane also blinks.
    private func addAirportLife(_ at: CGPoint, style: MapLayout.Airport.Style, busy: Bool) {
        guard busy || style != .airstrip else { return }
        let (plane, _) = sprite("ToyPlane")
        plane.position = CGPoint(x: at.x + 22, y: at.y - 6)
        plane.zPosition = 1
        addChild(plane)
        if busy {
            let light = SKShapeNode(circleOfRadius: 2.5)
            light.fillColor = Palette.critical; light.strokeColor = .clear; light.glowWidth = 3
            light.position = CGPoint(x: plane.position.x - 4, y: plane.position.y + 9)
            light.zPosition = 2
            addChild(light)
            if !stillLife { light.run(.repeatForever(.sequence([.fadeOut(withDuration: 0.4), .fadeIn(withDuration: 0.4)]))) }
        }
    }

    // MARK: Per frame

    /// Moves the actors that are on screen: everyone faces the way they travel, boats bob and leave wakes, gulls bank
    /// into their turns, walkers hop. Puppets animate their own parts through actions.
    func update(dt: Double, visible: CGRect, reduceMotion: Bool) {
        time += dt
        for i in actors.indices {
            var a = actors[i]
            guard reduceMotion || visible.contains(a.node.position) else { continue }
            var moving = false
            if a.pause > 0 {
                a.pause -= dt
            } else if !reduceMotion, a.points.count > 1, a.total > 0 {
                moving = true
                a.distance += a.speed * CGFloat(dt) * a.direction
                if a.loop {
                    a.distance = a.distance.truncatingRemainder(dividingBy: a.total)
                    if a.distance < 0 { a.distance += a.total }
                } else if a.distance >= a.total || a.distance <= 0 {
                    a.distance = min(a.total, max(0, a.distance)); a.direction = a.distance <= 0 ? 1 : -1
                    a.pause = Double.random(in: Self.endPause[a.kind] ?? 0...0)
                }
                if a.kind == .walk, Double.random(in: 0..<1) < dt * 0.06 { a.pause = Double.random(in: 1...2.5) }
            }
            let (p, heading) = a.sample(a.distance)
            let sign: CGFloat = a.loop ? 1 : a.direction
            let travel = CGVector(dx: heading.dx * sign, dy: heading.dy * sign)
            let facing: CGFloat = travel.dx > 0.01 ? -1 : (travel.dx < -0.01 ? 1 : (a.node.xScale < 0 ? -1 : 1))   // pieces face left
            let t = reduceMotion ? 0 : time + a.phase
            var pos = p
            switch a.kind {
            case .walk: if a.pause <= 0 { pos.y += abs(sin(t * 6)) * 2 }
            case .moored, .water:
                pos.y += sin(t * 1.6) * 1.2
                if a.rolls { a.node.zRotation = CGFloat(sin(t * 1.3) * 0.05) }
            case .air:
                // bank into the turn: lean with the climb or dive of the path, plus a slow sway
                let len = max(0.001, hypot(travel.dx, travel.dy))
                a.node.zRotation = (travel.dy / len) * 0.3 * -facing + CGFloat(sin(t * 0.7) * 0.04)
            default: break
            }
            a.node.position = pos
            a.node.xScale = facing
            if a.wake, moving {                         // a little ring of foam left behind every half second
                a.wakeClock += dt
                if a.wakeClock > 0.5 {
                    a.wakeClock = 0
                    let len = max(0.001, hypot(travel.dx, travel.dy))
                    let behind = CGPoint(x: p.x - travel.dx / len * a.width * 0.45, y: p.y - travel.dy / len * a.width * 0.45 - a.width * 0.12)
                    ring(at: behind, in: self, width: a.width * 0.32, alpha: 0.55)
                }
            }
            actors[i] = a
        }
    }
}
