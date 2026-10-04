import SpriteKit
import UIKit

/// City life on the route map (Route Map Plan, City life): a few ferries, sailboats, whales and gulls gliding and bobbing
/// along short authored paths, plus chimney smoke, lighthouse lamps and parked planes. People, cars and buses were taken
/// out on 2026-10-04 to keep the towns calm; the walk and road kinds still work if they come back. It is kept
/// calm on purpose: one actor per back-and-forth path (only loops carry more, all moving the same way at the same speed,
/// so nobody collides), people and cars pause, and quiet airports stay quiet. Paths are checked against the art by
/// ios/tools/check_life.py. Pieces are static cut-outs; all motion is code. Only actors on screen move, and nothing
/// moves with Reduce Motion.
final class MapLifeLayer: SKNode {
    private struct Actor {
        let node: SKSpriteNode
        let width: CGFloat
        let kind: MapLayout.Life.Kind
        let points: [CGPoint]
        let lengths: [CGFloat]          // cumulative length at each point
        let loop: Bool
        let speed: CGFloat
        var distance: CGFloat
        var direction: CGFloat = 1
        var phase: Double
        var pause: Double = 0           // seconds left standing still

        var total: CGFloat { lengths.last ?? 0 }

        /// Position along the polyline and which way it is heading horizontally.
        func sample(_ d: CGFloat) -> (CGPoint, CGFloat) {
            guard points.count > 1, total > 0 else { return (points.first ?? .zero, 1) }
            var i = 1
            while i < lengths.count - 1 && lengths[i] < d { i += 1 }
            let a = points[i - 1], b = points[i]
            let seg = max(lengths[i] - lengths[i - 1], 0.001)
            let t = min(1, max(0, (d - lengths[i - 1]) / seg))
            return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), b.x - a.x)
        }
    }

    private var actors: [Actor] = []
    private var time: Double = 0
    private var stillLife = false

    /// Width in world units for each piece (buildings are about 40 wide).
    static let widths: [String: CGFloat] = [
        "CarCoral": 26, "CarTeal": 26, "Van": 28, "Bus": 36, "BaggageTractor": 36, "FuelTruck": 32, "PushbackTug": 24,
        "PersonCoral": 11, "PersonTeal": 11, "PersonSuitcase": 12, "Attendant": 11, "Gull": 20,
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
        actors.removeAll()
        whaleTail.removeAll()
        stillLife = reduceMotion
        var seed = 0
        for region in life {
            for entry in region.entries {
                let pts = entry.points.map { region.toScene(CGPoint(x: $0[0], y: $0[1])) }
                let names = entry.actors ?? Self.defaults[entry.kind] ?? []
                switch entry.kind {
                case .smoke: pts.forEach { addSmoke(at: $0, still: reduceMotion) }
                case .glow: pts.forEach { addGlow(at: $0, still: reduceMotion) }
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
        for a in airports { addAirportLife(a.at, style: a.style, busy: a.isNext, still: reduceMotion, seed: &seed) }
        if reduceMotion { update(dt: 0, visible: .infinite, reduceMotion: true) }
    }

    private func sprite(_ name: String) -> (SKSpriteNode, CGFloat) {
        let node = SKSpriteNode(imageNamed: "Map/\(name)")
        let w = Self.widths[name] ?? 24
        node.size = CGSize(width: w, height: w * node.size.height / max(node.size.width, 1))
        return (node, w)
    }

    private func addActor(_ name: String, kind: MapLayout.Life.Kind, path: [CGPoint], loop: Bool, offset: CGFloat, seed: inout Int) {
        var (node, w) = sprite(name)
        if name == "Whale" {                            // a puppet in a holder, so it can dive and blow while it travels
            let (puppet, width) = whalePuppet()
            w = width
            node = SKSpriteNode(color: .clear, size: .zero)
            node.addChild(puppet)
            if !stillLife { runWhaleCycle(puppet, in: node, width: w) }
        }
        var lengths: [CGFloat] = [0]
        let pts = loop && path.count > 2 ? path + [path[0]] : path
        for i in 1..<max(1, pts.count) { lengths.append(lengths[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        seed += 1
        let actor = Actor(node: node, width: w, kind: kind, points: pts, lengths: lengths, loop: loop,
                          speed: (Self.speeds[kind] ?? 10) * (0.85 + 0.3 * CGFloat(seed % 5) / 4),
                          distance: (lengths.last ?? 0) * offset, phase: Double(seed) * 1.7)
        node.zPosition = kind == .air ? 3 : 1
        node.position = pts.first ?? .zero
        addChild(node)
        actors.append(actor)
    }

    // MARK: Whale

    private var whaleTail: [ObjectIdentifier: SKSpriteNode] = [:]

    /// The whale as a cut-out puppet: body, tail and flipper share one 512 × 420 canvas (branding/map/cut/piece-whale-*),
    /// and each part turns around its own joint. The tail beats, the flipper paddles and the body rocks.
    private func whalePuppet() -> (SKSpriteNode, CGFloat) {
        let w = Self.widths["Whale"] ?? 66
        let canvas = CGSize(width: 512, height: 420)
        let size = CGSize(width: w, height: w * canvas.height / canvas.width)
        let puppet = SKSpriteNode(color: .clear, size: size)
        func part(_ name: String, pivot: CGPoint?, z: CGFloat) -> SKSpriteNode {
            let n = SKSpriteNode(imageNamed: "Map/\(name)")
            n.size = size
            if let pivot {                              // turn around the joint: anchor there, then put the joint back in place
                n.anchorPoint = CGPoint(x: pivot.x / canvas.width, y: 1 - pivot.y / canvas.height)
                n.position = CGPoint(x: (n.anchorPoint.x - 0.5) * size.width, y: (n.anchorPoint.y - 0.5) * size.height)
            }
            n.zPosition = z
            puppet.addChild(n)
            return n
        }
        let body = part("WhaleBody", pivot: nil, z: 0)
        let flipper = part("WhaleFlipper", pivot: CGPoint(x: 300, y: 305), z: 1)
        let tail = part("WhaleTail", pivot: CGPoint(x: 368, y: 147), z: 1)
        whaleTail[ObjectIdentifier(puppet)] = tail
        guard !stillLife else { return (puppet, w) }
        let beat = SKAction.sequence([.rotate(toAngle: 0.16, duration: 0.75), .rotate(toAngle: -0.12, duration: 0.75)])
        beat.timingMode = .easeInEaseOut
        tail.run(.repeatForever(beat), withKey: "beat")
        let paddle = SKAction.sequence([.rotate(toAngle: -0.2, duration: 0.9), .rotate(toAngle: 0.12, duration: 0.9)])
        paddle.timingMode = .easeInEaseOut
        flipper.run(.repeatForever(paddle))
        let rock = SKAction.sequence([.group([.rotate(toAngle: 0.03, duration: 1.5), .scaleY(to: 1.025, duration: 1.5)]),
                                      .group([.rotate(toAngle: -0.03, duration: 1.5), .scaleY(to: 1, duration: 1.5)])])
        rock.timingMode = .easeInEaseOut
        body.run(.repeatForever(rock))
        return (puppet, w)
    }

    /// The tail's own move for a dive (fluke up, held) and for surfacing (back to its beat).
    private func tailDive(_ puppet: SKNode) -> SKAction {
        .run { [weak self] in
            guard let tail = self?.whaleTail[ObjectIdentifier(puppet)] else { return }
            tail.removeAction(forKey: "beat")
            tail.run(.rotate(toAngle: 0.34, duration: 0.6, shortestUnitArc: true))
        }
    }

    private func tailResume(_ puppet: SKNode) -> SKAction {
        .run { [weak self] in
            guard let tail = self?.whaleTail[ObjectIdentifier(puppet)] else { return }
            let beat = SKAction.sequence([.rotate(toAngle: 0.16, duration: 0.75), .rotate(toAngle: -0.12, duration: 0.75)])
            beat.timingMode = .easeInEaseOut
            tail.run(.sequence([.rotate(toAngle: 0, duration: 0.4), .repeatForever(beat)]), withKey: "beat")
        }
    }

    /// Swims at the surface, blows, dives with a splash, glides under water as a faint shadow, then surfaces again.
    private func runWhaleCycle(_ whale: SKSpriteNode, in holder: SKNode, width w: CGFloat) {
        // the fluke rises as the body tips nose-down; dive tilt is kept moderate so the tail joint never opens
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
            .run { [weak self] in self?.splash(at: CGPoint(x: 0, y: -h * 0.2), in: holder, width: w) },
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
            .run { [weak self] in self?.splash(at: CGPoint(x: 0, y: -h * 0.2), in: holder, width: w)
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

    /// Two widening rings of foam where the whale breaks the surface.
    private func splash(at p: CGPoint, in parent: SKNode, width w: CGFloat) {
        for (i, delay) in [0.0, 0.25].enumerated() {
            let ring = SKShapeNode(ellipseOf: CGSize(width: w * 0.55, height: w * 0.18))
            ring.strokeColor = UIColor.white.withAlphaComponent(0.85); ring.lineWidth = i == 0 ? 2 : 1.4; ring.fillColor = .clear
            ring.position = p; ring.zPosition = -0.5; ring.alpha = 0
            parent.addChild(ring)
            ring.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.05),
                                .group([.scale(to: 2.1, duration: 1.1), .fadeOut(withDuration: 1.1)]), .removeFromParent()]))
        }
    }

    private func addSmoke(at p: CGPoint, still: Bool) {
        guard !still else { return }
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

    private func addGlow(at p: CGPoint, still: Bool) {
        let glow = SKShapeNode(circleOfRadius: 9)
        glow.fillColor = Palette.calm.withAlphaComponent(0.55)
        glow.strokeColor = .clear
        glow.glowWidth = 6
        glow.position = p
        glow.zPosition = 2
        addChild(glow)
        if !still { glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.15, duration: 0.9), .fadeAlpha(to: 1, duration: 0.9)]))) }
    }

    /// Town and city airports keep a parked plane; the next departure's plane also blinks.
    private func addAirportLife(_ at: CGPoint, style: MapLayout.Airport.Style, busy: Bool, still: Bool, seed: inout Int) {
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
            if !still { light.run(.repeatForever(.sequence([.fadeOut(withDuration: 0.4), .fadeIn(withDuration: 0.4)]))) }
        }
    }

    /// Moves the actors that are on screen. Boats bob, people hop, gulls flap; everyone faces the way they travel.
    func update(dt: Double, visible: CGRect, reduceMotion: Bool) {
        time += dt
        for i in actors.indices {
            var a = actors[i]
            guard reduceMotion || visible.contains(a.node.position) else { continue }
            if a.pause > 0 {
                a.pause -= dt
            } else if !reduceMotion, a.points.count > 1, a.total > 0 {
                a.distance += a.speed * CGFloat(dt) * a.direction
                if a.loop {
                    a.distance = a.distance.truncatingRemainder(dividingBy: a.total)
                    if a.distance < 0 { a.distance += a.total }
                } else if a.distance >= a.total || a.distance <= 0 {
                    a.distance = min(a.total, max(0, a.distance)); a.direction = a.distance <= 0 ? 1 : -1
                    a.pause = Double.random(in: Self.endPause[a.kind] ?? 0...0)
                }
                // now and then a walker stops to look around
                if a.kind == .walk, Double.random(in: 0..<1) < dt * 0.06 { a.pause = Double.random(in: 1...2.5) }
            }
            let (p, heading) = a.sample(a.distance)
            let travel = heading * (a.loop ? 1 : a.direction)
            let facing: CGFloat = travel > 0.01 ? -1 : (travel < -0.01 ? 1 : (a.node.xScale < 0 ? -1 : 1))   // pieces face left
            let t = reduceMotion ? 0 : time + a.phase
            var pos = p
            switch a.kind {
            case .walk: if a.pause <= 0 { pos.y += abs(sin(t * 6)) * 2 }      // a little hop while walking, still when standing
            case .moored, .water:
                pos.y += sin(t * 1.6) * 1.2
                if a.node.children.isEmpty { a.node.zRotation = CGFloat(sin(t * 1.3) * 0.05) }   // the whale rolls on its own
            case .air: a.node.yScale = 0.8 + 0.2 * abs(sin(t * 6))
            default: break
            }
            a.node.position = pos
            a.node.xScale = facing
            actors[i] = a
        }
    }
}
