import SpriteKit
import UIKit

/// City life on the route map (Route Map Plan, City life): a few toy cars, people, boats and gulls sliding, hopping and
/// bobbing along short authored paths, plus chimney smoke, lighthouse lamps and the next departure's airport. It is kept
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

    /// Width in world units for each piece (buildings are about 40 wide).
    static let widths: [String: CGFloat] = [
        "CarCoral": 26, "CarTeal": 26, "Van": 28, "Bus": 36, "BaggageTractor": 36, "FuelTruck": 32, "PushbackTug": 24,
        "PersonCoral": 11, "PersonTeal": 11, "PersonSuitcase": 12, "Attendant": 11, "Gull": 20,
        "Rowboat": 26, "Sailboat": 30, "FishingBoat": 36, "Speedboat": 30, "Ferry": 56, "Whale": 60, "Dolphin": 30, "Buoy": 14,
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
        let (node, w) = sprite(name)
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

    /// Quiet airports stay quiet: town and city airports keep a parked plane, and only the next departure is busy, with
    /// a blinking plane, two passengers walking out to it and (at bigger airports) a baggage tractor.
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
            // two passengers on separate short walks to the plane, so they never bump into each other
            addActor("PersonSuitcase", kind: .walk, path: [CGPoint(x: at.x - 20, y: at.y - 18), CGPoint(x: at.x + 10, y: at.y - 12)], loop: false, offset: 0, seed: &seed)
            addActor("PersonTeal", kind: .walk, path: [CGPoint(x: at.x - 14, y: at.y - 26), CGPoint(x: at.x + 14, y: at.y - 20)], loop: false, offset: 0.6, seed: &seed)
        }
        if busy && style != .airstrip {
            let lap = [CGPoint(x: at.x - 30, y: at.y + 8), CGPoint(x: at.x - 6, y: at.y + 16), CGPoint(x: at.x + 18, y: at.y + 10),
                       CGPoint(x: at.x - 4, y: at.y + 2)]
            addActor("BaggageTractor", kind: .road, path: lap, loop: true, offset: 0, seed: &seed)
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
                a.node.zRotation = CGFloat(sin(t * 1.3) * 0.05)
            case .air: a.node.yScale = 0.8 + 0.2 * abs(sin(t * 6))
            default: break
            }
            a.node.position = pos
            a.node.xScale = facing
            actors[i] = a
        }
    }
}
