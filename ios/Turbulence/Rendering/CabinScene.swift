import SpriteKit
import UIKit

/// Renders a `FlightSimulation`. Owns no game rules: it mirrors model state into nodes each frame
/// and plays one-shot effects for model events. World node uses model units (1000 × 380), y flipped.
final class CabinScene: SKScene {
    weak var game: GameController?

    private let world = SKNode()
    private let skyNode = SKSpriteNode()
    private let vignetteNode = SKSpriteNode()
    private let cam = SKCameraNode()
    /// Screen areas the cabin must stay clear of: the camera cutout, the home indicator and the HUD.
    var contentInsets = UIEdgeInsets.zero { didSet { if oldValue != contentInsets { layoutWorld() } } }
    private let paxLayer = SKNode()
    private let spillLayer = SKNode()
    private let iconLayer = SKNode()
    private let fxLayer = SKNode()
    private var clouds: [(node: SKSpriteNode, speed: CGFloat)] = []
    private var binHighlights: [SKShapeNode] = []
    private var paxNodes: [PaxNode] = []
    private var iconNodes: [Int: IconNode] = [:]
    private var spillNodes: [Int: SpillNode] = [:]
    private let crewNode = CrewNode()
    private let targetMarker = SKShapeNode(ellipseOf: CGSize(width: 20, height: 9))
    private var worldBase = CGPoint.zero
    private var shake: CGFloat = 0
    /// Options → Screen shake: 1 full, 0.4 reduced, 0 off.
    var shakeScale: CGFloat = 1
    private var turbAmp: CGFloat = 0
    private var noiseTimers: [Int: Double] = [:]
    /// Screen points of shake at turbulence intensity 1 (GDD §5a: light ≈ 3 pt, heavy ≈ 8 pt).
    static let heavyShake: CGFloat = 8
    private var lastTime: TimeInterval = 0
    private var clock: Double = 0
    private var renderedSize = CGSize.zero

    enum Tex {
        static let items: [Item: SKTexture] = Dictionary(uniqueKeysWithValues: Item.allCases.map { ($0, SKTexture(image: Art.itemImage($0))) })
        static let dot = SKTexture(image: Art.softDot())
        static let sparkle = SKTexture(image: Art.sparkle())
        static let glow = SKTexture(image: Art.glow())
        static let cloud = SKTexture(image: Art.cloud())
        static let heart = SKTexture(image: Art.heart())
        static let grumpy = SKTexture(image: Art.grumpyCloud())
        static let chat = SKTexture(image: Art.chatBubble())
        static let cart = SKTexture(image: Art.cart(stuck: false))
        static let cartStuck = SKTexture(image: Art.cart(stuck: true))
        static let binJam = SKTexture(image: Art.binJam())
        static let hands = SKTexture(image: Art.stepImage(.hands))
        static let clean = SKTexture(image: Art.stepImage(.clean))
        static let bell = SKTexture(image: Art.bell())
        static let trash = SKTexture(image: Art.trashImage())
        static let order = SKTexture(image: Art.notepad())
        static let suitcase = SKTexture(image: Art.suitcase())
        static let crown = SKTexture(image: Art.crown())
        private static var combos: [String: SKTexture] = [:]
        static func step(_ s: Step) -> SKTexture {
            switch s {
            case .item(let item): return items[item]!
            case .hands: return hands
            case .clean: return clean
            case .trash: return trash
            case .order: return order
            case .combo(let list):
                let key = list.map(\.rawValue).joined(separator: "+")
                if let t = combos[key] { return t }
                let t = SKTexture(image: Art.comboImage(list)); combos[key] = t; return t
            }
        }
        /// What an occurrence's icon shows: a bell for call buttons, otherwise what the next step needs.
        static func icon(_ o: Occurrence) -> SKTexture { o.kind == .call ? bell : step(o.need) }
    }

    private var worldW = 1000.0
    private var worldH = 380.0
    private var builtFor: String?
    private var freshNodes: [Int: SKSpriteNode] = [:]      // stations new on this flight, popped in at Go
    private var dustTimer = 0.0
    /// Jump seats as sprites, so they can fold away after Go on flights without turbulence.
    private var jumpSeatNodes: [SKSpriteNode] = []
    /// A coloured frame around each seat that's asking for something, under the passenger.
    private var seatFrames: [Int: SKShapeNode] = [:]
    private let seatLayer = SKNode()
    /// Three streaks behind the crew while running.
    private lazy var speedLines: SKNode = {
        let n = SKNode()
        for (k, dy) in [-9.0, 0.0, 9.0].enumerated() {
            let line = SKShapeNode(rectOf: CGSize(width: k == 1 ? 22 : 15, height: 2.6), cornerRadius: 1.3)
            line.fillColor = .white; line.strokeColor = .clear
            line.position = CGPoint(x: -(k == 1 ? 11 : 7.5), y: dy)      // grow backwards from the crew
            n.addChild(line)
        }
        n.zPosition = 5.4; n.isHidden = true
        world.addChild(n)
        return n
    }()
    private var badgeTextures: [Item: SKTexture] = [:]
    private var staticNodes: [SKNode] = []
    private var jamNodes: [Int: SKSpriteNode] = [:]
    private let cartNode = SKSpriteNode(texture: Tex.cart)
    private var machineRings: [Int: SKShapeNode] = [:]
    private var machineCold: [Int: SKSpriteNode] = [:]      // the cold cup/plate waiting in a machine
    private var flightNodes: [SKNode] = []          // per-flight overlays (closed galley)
    private let dimNode = SKSpriteNode(color: UIColor(hex: 0x0B1330), size: .zero)
    private let helperNode = CrewNode()
    private var jumpGlows: [SKShapeNode] = []

    /// Model point (y down) → world node point (y up).
    func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: worldH - y) }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Art.wallMid
        anchorPoint = .zero

        skyNode.anchorPoint = .zero; skyNode.zPosition = -100
        vignetteNode.anchorPoint = .zero; vignetteNode.zPosition = 100
        addChild(cam); camera = cam
        cam.addChild(skyNode); cam.addChild(vignetteNode)     // sky and vignette stay fixed on screen
        addChild(world)

        for i in 0..<16 {
            let layer = i % 2
            let n = SKSpriteNode(texture: Tex.cloud)
            let w = layer == 1 ? CGFloat.random(in: 260...420) : CGFloat.random(in: 140...240)
            n.size = CGSize(width: w, height: w * 0.5)
            n.anchorPoint = CGPoint(x: 0, y: 1)
            n.alpha = layer == 1 ? 0.09 : 0.05
            n.position = pt(Double.random(in: -400...1400), Double.random(in: -420...760))
            n.zPosition = -60
            n.isHidden = true                    // the camera stays inside the cabin (GDD §8a)
            world.addChild(n)
            clouds.append((n, layer == 1 ? .random(in: 90...140) : .random(in: 35...60)))
        }
        buildStatic(Aircraft.comet.layout)
        cartNode.size = CGSize(width: 48, height: 30)
        cartNode.zPosition = 5
        cartNode.isHidden = true
        world.addChild(cartNode)
        dimNode.anchorPoint = .zero; dimNode.alpha = 0.34; dimNode.zPosition = 5.5; dimNode.isHidden = true
        world.addChild(dimNode)
        helperNode.zPosition = 6; helperNode.setScale(0.9); helperNode.isHidden = true
        helperNode.setLook(skin: UIColor(hex: 0xF5D7BE), hair: UIColor(hex: 0xC9A15B))
        let badge = SKLabelNode(text: "TRAINEE")
        badge.fontName = "AvenirNext-Heavy"; badge.fontSize = 7; badge.fontColor = Palette.calm
        badge.position = CGPoint(x: 0, y: -26)
        helperNode.addChild(badge)
        world.addChild(helperNode)

        seatLayer.zPosition = 1.9; paxLayer.zPosition = 2; spillLayer.zPosition = 4; iconLayer.zPosition = 7; fxLayer.zPosition = 8
        [seatLayer, paxLayer, spillLayer, iconLayer, fxLayer].forEach(world.addChild)

        targetMarker.strokeColor = Palette.teal.withAlphaComponent(0.8); targetMarker.lineWidth = 2
        targetMarker.fillColor = .clear; targetMarker.zPosition = 5
        world.addChild(targetMarker)
        crewNode.zPosition = 6
        world.addChild(crewNode)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutWorld()
    }

    /// The hull wall around the cabin's interior (in the art, the inside starts 22 pt in): the camera frames the
    /// inside (seats, galleys, lavatories), not the fuselage, and the wall colour fills the rest (GDD §8a).
    static let hullMargin = 22.0

    /// The camera scale that fits a cabin's interior into the clear area; shared with the intro's final shot.
    static func fitScale(availW: Double, availH: Double, width: Double, height: Double) -> Double {
        min(availW / (width - 2 * hullMargin), availH / (height - 2 * hullMargin))
    }

    /// Where the world's bottom edge sits (scene y, up): the interior centred in the clear area.
    static func worldBaseY(viewH: Double, insetTop: Double, insetBottom: Double, worldH: Double, scale s: Double) -> Double {
        let availH = viewH - insetTop - insetBottom
        return insetBottom + (availH - worldH * s) / 2                // the interior, centred in the clear area
    }

    /// Fits the cabin's interior on screen (GDD §4: fixed camera, every icon visible).
    private func layoutWorld() {
        guard size.width > 1, size.height > 1 else { return }
        // fit the cabin into the clear area (no clipping under the cutout), centred in it
        let i = contentInsets
        let availW = size.width - i.left - i.right, availH = size.height - i.top - i.bottom
        let s = CGFloat(Self.fitScale(availW: Double(availW), availH: Double(availH), width: worldW, height: worldH))
        world.setScale(s)
        // model y runs down while the scene's y runs up: the top inset lowers the cabin, the bottom inset raises it
        worldBase = CGPoint(x: i.left + (availW - worldW * s) / 2,
                            y: Self.worldBaseY(viewH: size.height, insetTop: i.top, insetBottom: i.bottom, worldH: worldH, scale: s))
        world.position = worldBase
        if renderedSize != size {
            renderedSize = size
            skyNode.texture = SKTexture(image: Art.wall(size)); skyNode.size = size   // inside only: no sky
            vignetteNode.texture = SKTexture(image: Art.vignette(size)); vignetteNode.size = size
        }
        skyNode.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        vignetteNode.position = skyNode.position
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Cabin art, wings and bin highlights for one aircraft; rebuilt when the flight's aircraft changes.
    private func staticKey(_ layout: CabinLayout, _ hiding: Set<Int>) -> String {
        "\(layout.aircraft)|\(layout.bins.map(\.label).joined(separator: ","))|\(hiding.sorted())"
    }

    private func buildStatic(_ layout: CabinLayout, hiding: Set<Int> = []) {
        staticNodes.forEach { $0.removeFromParent() }
        staticNodes.removeAll()
        binHighlights.forEach { $0.removeFromParent() }
        binHighlights.removeAll()
        worldW = layout.width
        worldH = layout.height
        builtFor = staticKey(layout, hiding)

        // no wings: the camera frames the inside of the cabin only (GDD §8a)
        let cabin = SKSpriteNode(texture: SKTexture(image: Art.cabin(layout, hiding: hiding, jumpSeats: false)))
        cabin.size = CGSize(width: worldW + 2 * Double(Art.cabinPad), height: worldH)
        cabin.anchorPoint = .zero
        cabin.position = CGPoint(x: -Art.cabinPad, y: 0)
        cabin.zPosition = 0
        world.addChild(cabin); staticNodes.append(cabin)

        machineRings.values.forEach { $0.removeFromParent() }
        machineRings.removeAll()
        machineCold.values.forEach { $0.removeFromParent() }
        machineCold.removeAll()
        freshNodes.values.forEach { $0.removeFromParent() }
        freshNodes.removeAll()
        jumpSeatNodes.forEach { $0.removeFromParent() }
        let seatTex = SKTexture(image: Art.jumpSeatImage())
        jumpSeatNodes = layout.jumpSeats.map { j in
            let n = SKSpriteNode(texture: seatTex, size: CGSize(width: 32, height: 28))
            n.position = pt(j.x, layout.aisles[j.aisle] - 30)
            n.zPosition = 0.4
            world.addChild(n)
            return n
        }
        for i in hiding where layout.bins.indices.contains(i) {
            let b = layout.bins[i]
            let n = SKSpriteNode(texture: SKTexture(image: Art.stationImage(b)))
            n.size = CGSize(width: 64, height: 64)
            n.position = pt(b.x, b.y)
            n.zPosition = 0.5; n.alpha = 0; n.setScale(0.2)
            world.addChild(n); freshNodes[i] = n
        }
        for (i, b) in layout.bins.enumerated() {
            let hw: CGFloat = b.kind == .drinks ? 27 : 19
            let h = SKShapeNode(rect: CGRect(x: -hw, y: -20, width: hw * 2, height: 40), cornerRadius: 8)
            h.strokeColor = Palette.teal; h.lineWidth = 3; h.glowWidth = 2; h.fillColor = .clear
            h.position = pt(b.x, b.y - 4)
            h.zPosition = 1; h.isHidden = true
            world.addChild(h); binHighlights.append(h)
            if b.isMachine {
                let ring = SKShapeNode()
                ring.lineWidth = 3; ring.lineCap = .round; ring.zPosition = 1.5
                ring.position = pt(b.x, b.y - 4)
                world.addChild(ring); machineRings[i] = ring
                // what's in the machine: the pick while it's being made, then ready, then cold (frosted)
                let badge = SKSpriteNode(color: .clear, size: CGSize(width: 22, height: 22))
                badge.position = pt(b.x + (b.kind == .drinks ? 24 : 16), b.y - 22)
                badge.zPosition = 2; badge.isHidden = true
                world.addChild(badge); machineCold[i] = badge
            }
        }
        dimNode.size = CGSize(width: worldW + 6000, height: worldH + 6000)   // the whole screen, whatever the fit
        dimNode.position = CGPoint(x: -3000, y: -3000)
        jumpGlows.forEach { $0.removeFromParent() }
        jumpGlows = layout.jumpSeats.map { j in
            let g = SKShapeNode(rect: CGRect(x: -14, y: -9, width: 28, height: 18), cornerRadius: 5)
            g.strokeColor = Palette.calm; g.lineWidth = 2.5; g.glowWidth = 3; g.fillColor = Palette.calm.withAlphaComponent(0.18)
            g.position = pt(j.x, layout.aisles[j.aisle] - 30)
            g.zPosition = 5.6; g.isHidden = true
            world.addChild(g)
            return g
        }
        crewNode.worldWidth = worldW
        layoutWorld()
    }

    private func buildWings() {
        let dx = (worldW - 1000) * 0.45            // wings sit mid-fuselage, the tail at the end
        let tx = worldW - 1000
        let H = worldH
        func add(_ n: SKNode) { world.addChild(n); staticNodes.append(n) }
        func poly(_ pts: [(Double, Double)]) -> CGPath {
            let p = CGMutablePath()
            p.addLines(between: pts.map { pt($0.0, $0.1) }); p.closeSubpath(); return p
        }
        for m in [1.0, -1.0] {
            let Y: (Double) -> Double = { m == 1 ? $0 : H - $0 }
            let wing = SKShapeNode(path: poly([(430 + dx, Y(24)), (620 + dx, Y(-380)), (690 + dx, Y(-380)), (610 + dx, Y(24))]))
            wing.fillColor = UIColor(hex: 0xA3AAB6); wing.strokeColor = .clear; wing.zPosition = -40
            add(wing)
            let flap = SKShapeNode(path: { let p = CGMutablePath(); p.move(to: pt(592 + dx, Y(24))); p.addLine(to: pt(672 + dx, Y(-380))); return p }())
            flap.strokeColor = Art.navy(0.22); flap.lineWidth = 1.5; flap.zPosition = -39
            add(flap)
            let tip = SKShapeNode(path: poly([(620 + dx, Y(-380)), (690 + dx, Y(-380)), (686 + dx, Y(-362)), (628 + dx, Y(-362))]))
            tip.fillColor = Palette.coral; tip.strokeColor = .clear; tip.zPosition = -39
            add(tip)
            let ey = Y(-90)
            let nacShadow = SKShapeNode(rect: CGRect(x: 456 + dx, y: H - ey - 15, width: 98, height: 28), cornerRadius: 14)
            nacShadow.fillColor = UIColor(white: 0, alpha: 0.25); nacShadow.strokeColor = .clear; nacShadow.zPosition = -38
            add(nacShadow)
            let nacelle = SKShapeNode(rect: CGRect(x: 450 + dx, y: H - ey - 13, width: 98, height: 26), cornerRadius: 13)
            nacelle.fillColor = UIColor(hex: 0x5B6475); nacelle.strokeColor = .clear; nacelle.zPosition = -37
            add(nacelle)
            let nacTop = SKShapeNode(rect: CGRect(x: 456 + dx, y: H - ey + 2, width: 86, height: 7), cornerRadius: 3.5)
            nacTop.fillColor = UIColor(hex: 0x7C8597); nacTop.strokeColor = .clear; nacTop.zPosition = -36
            add(nacTop)
            let intake = SKShapeNode(ellipseOf: CGSize(width: 10, height: 22))
            intake.position = pt(455 + dx, ey); intake.fillColor = UIColor(hex: 0x1B2230); intake.strokeColor = .clear; intake.zPosition = -35
            add(intake)
            let band = SKShapeNode(rect: CGRect(x: 470 + dx, y: H - ey - 13, width: 3, height: 26))
            band.fillColor = Palette.coral; band.strokeColor = .clear; band.zPosition = -35
            add(band)
            let tail = SKShapeNode(path: poly([(898 + tx, Y(24)), (972 + tx, Y(-100)), (1004 + tx, Y(-100)), (985 + tx, Y(40))]))
            tail.fillColor = UIColor(hex: 0xA3AAB6); tail.strokeColor = .clear; tail.zPosition = -40
            add(tail)
        }
    }

    // MARK: - Model binding

    /// Rebuild per-flight nodes after the controller swaps in a new simulation.
    func reset() {
        paxLayer.removeAllChildren(); seatLayer.removeAllChildren(); spillLayer.removeAllChildren(); iconLayer.removeAllChildren(); fxLayer.removeAllChildren()
        iconNodes.removeAll(); seatFrames.removeAll(); spillNodes.removeAll(); jamNodes.removeAll(); noiseTimers.removeAll()
        guard let sim = game?.sim else { paxNodes = []; return }
        let hiding = Set(sim.freshStations)
        if builtFor != staticKey(sim.layout, hiding) { buildStatic(sim.layout, hiding: hiding) }
        for n in freshNodes.values { n.removeAllActions(); n.alpha = 0; n.setScale(0.2) }
        for n in jumpSeatNodes { n.removeAllActions(); n.alpha = 1; n.setScale(1) }   // back for the take-off countdown
        cartNode.isHidden = true
        flightNodes.forEach { $0.removeFromParent() }
        flightNodes.removeAll()
        for (i, b) in sim.layout.bins.enumerated() where !sim.stationOpen(i) {
            let x = SKLabelNode(text: "✕")
            x.fontName = "AvenirNext-Heavy"; x.fontSize = 30; x.fontColor = Palette.critical
            x.verticalAlignmentMode = .center
            x.position = pt(b.x, b.y - 4); x.zPosition = 1.6
            world.addChild(x); flightNodes.append(x)
        }
        dimNode.isHidden = sim.plan.twist != .redEye
        helperNode.isHidden = sim.helper == nil
        paxNodes = sim.passengers.map { p in
            let n = PaxNode(p)
            n.position = pt(p.x, p.y)
            paxLayer.addChild(n)
            return n
        }
        shake = 0
        turbAmp = 0
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.05, currentTime - lastTime)
        lastTime = currentTime
        clock += dt
        game?.tick(dt)
        render(dt: dt)
    }

    private func render(dt: Double) {
        for c in clouds {
            c.node.position.x -= c.speed * dt
            if c.node.position.x < -500 {
                c.node.position = pt(1400, Double.random(in: -420...760))
            }
        }
        guard let sim = game?.sim else { return }

        let turbulence = sim.turbulenceIntensity
        for (i, p) in sim.passengers.enumerated() where i < paxNodes.count {
            let n = paxNodes[i]
            n.position = pt(p.drawX, p.drawY)
            n.zPosition = p.stroll != nil ? 3 : 0
            n.sync(p, clock: clock, dt: dt, turbulence: turbulence)
        }

        var live = Set<Int>()
        for o in sim.occurrences where !o.dead {
            live.insert(o.id)
            if o.kind == .spill {
                let sn = spillNodes[o.id] ?? {
                    let n = SpillNode(o); n.position = pt(o.x, o.y)
                    spillLayer.addChild(n); spillNodes[o.id] = n; return n
                }()
                sn.sync(o, clock: clock)
            }
            if o.kind == .binJam || o.kind == .carryOn, jamNodes[o.id] == nil {
                let n = o.kind == .binJam ? SKSpriteNode(texture: Tex.binJam, size: CGSize(width: 48, height: 48))
                                          : SKSpriteNode(texture: Tex.suitcase, size: CGSize(width: 40, height: 36))
                n.position = pt(o.x, o.y + 4)
                n.setScale(0)
                n.run(.scale(to: 1, duration: 0.2))
                spillLayer.addChild(n); jamNodes[o.id] = n
            }
            let icon = iconNodes[o.id] ?? {
                let n = IconNode(o)
                if o.kind.atSeat, o.passenger != nil {
                    // off the seat, into free space, with a tail pointing back at the seat (tappable: GDD §8a)
                    let c = sim.bubbleCenter(o)
                    n.position = pt(c.x, c.y)
                    n.pointTail(c.y > o.y ? -1 : 1)
                } else {
                    n.position = pt(o.x, o.y - (o.kind.isCart ? 22 : o.kind.atLavatory ? 30 : 2))
                }
                iconLayer.addChild(n); iconNodes[o.id] = n; return n
            }()
            icon.sync(o, clock: clock)
            icon.isHidden = sim.isBehindCurtain(o)
            if o.kind.atSeat, let pi = o.passenger {
                let frame = seatFrames[o.id] ?? {
                    let p = sim.passengers[pi]
                    let w: CGFloat = p.premium ? 40 : 36, h: CGFloat = p.premium ? 48 : 46
                    let f = SKShapeNode(rect: CGRect(x: -w / 2 + 1, y: -h / 2, width: w, height: h), cornerRadius: 9)
                    f.lineWidth = 3.5; f.glowWidth = 2
                    f.position = pt(p.x, p.y)
                    seatLayer.addChild(f); seatFrames[o.id] = f
                    return f
                }()
                let color = Palette.escalation(o.state)
                frame.strokeColor = color
                frame.fillColor = color.withAlphaComponent(0.22)
                frame.isHidden = icon.isHidden
                frame.alpha = o.state == .critical ? 0.7 + 0.3 * CGFloat(sin(clock * 14)) : 1
            }

            let noise = sim.noiseLevel(o)
            if noise > 0 {
                let left = (noiseTimers[o.id] ?? 0) - dt
                if left <= 0 {
                    noiseWave(x: o.x, y: o.y, level: noise)
                    noiseTimers[o.id] = noise >= 2 ? 0.55 : 1.1
                } else {
                    noiseTimers[o.id] = left
                }
            }
        }
        for (id, f) in seatFrames where !live.contains(id) {
            seatFrames[id] = nil
            f.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        }
        for (id, n) in iconNodes where !live.contains(id) {
            iconNodes[id] = nil
            n.run(.sequence([.scale(to: 0, duration: 0.15), .removeFromParent()]))
        }
        for (id, n) in spillNodes where !live.contains(id) {
            spillNodes[id] = nil
            n.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        for (id, n) in jamNodes where !live.contains(id) {
            jamNodes[id] = nil
            n.run(.sequence([.scale(to: 0, duration: 0.15), .removeFromParent()]))
        }

        for (i, b) in sim.layout.bins.enumerated() where i < binHighlights.count {
            binHighlights[i].isHidden = b.item.map { !sim.crew.tray.contains($0) } ?? true
        }
        for (i, ring) in machineRings {
            switch sim.machines[i] ?? .idle {
            case .idle:
                ring.isHidden = true
            case .working(let item, let left):
                let prep = max(0.1, item.prepTime)
                let r: CGFloat = sim.layout.bins[i].kind == .drinks ? 30 : 22
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - (1 - left / prep) * 2 * .pi, clockwise: true)
                ring.path = path; ring.strokeColor = Palette.calm; ring.glowWidth = 0; ring.isHidden = false
            case .ready:
                // ready: the ring shrinks as it cools, green → red near the end
                let w = sim.warmth(ofMachine: i) ?? 1
                let r: CGFloat = sim.layout.bins[i].kind == .drinks ? 30 : 22
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - w * 2 * .pi, clockwise: true)
                ring.path = path
                ring.strokeColor = w < 0.3 ? Palette.critical : UIColor(hex: 0x6FD08C)
                ring.glowWidth = 3 + CGFloat(sin(clock * (w < 0.3 ? 12 : 6))) * 1.5; ring.isHidden = false
            case .cold:
                let r: CGFloat = sim.layout.bins[i].kind == .drinks ? 30 : 22
                ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
                ring.strokeColor = UIColor(hex: 0x9CC8E8); ring.glowWidth = 0; ring.isHidden = false
            }
            if let badge = machineCold[i] {
                let shown: Item?
                switch sim.machines[i] ?? .idle {
                case .idle: shown = nil
                case .working(let item, _), .ready(let item, _): shown = item
                case .cold(let item): shown = item.cold ?? item
                }
                if let shown {
                    let tex = badgeTextures[shown] ?? SKTexture(image: Art.itemImage(shown, size: 22))
                    badgeTextures[shown] = tex
                    if badge.texture !== tex { badge.texture = tex }
                    badge.isHidden = false
                } else {
                    badge.isHidden = true
                }
            }
        }
        // jump seats light up while the seatbelt sign is on; the nearest one pulses until you're seated
        let nearest = sim.crew.seated == nil ? sim.nearestJumpSeat() : nil
        for (i, g) in jumpGlows.enumerated() {
            g.isHidden = !sim.seatbeltOn
            let pulse = i == nearest ? 1 + CGFloat(sin(clock * 9)) * 0.18 : 1
            g.setScale(pulse)
            g.strokeColor = sim.crew.seated == i ? Palette.teal : Palette.calm
        }

        if let h = sim.helper {
            var c = Crew()
            c.x = h.x; c.y = sim.layout.aisles[h.aisle]; c.face = h.face; c.walk = h.walk
            c.target = h.target != nil && h.busy <= 0 ? CrewTarget(x: h.x, action: .none) : nil
            helperNode.sync(c, clock: clock)
            helperNode.position = pt(h.x, c.y)
        }

        if let cart = sim.cart, cart.active {
            cartNode.isHidden = false
            cartNode.texture = cart.stuck ? Tex.cartStuck : Tex.cart
            let wobble = cart.stuck ? sin(clock * 30) * 0.8 : 0
            cartNode.position = pt(cart.x + wobble, sim.layout.aisles[cart.aisle] + 2)
        } else {
            cartNode.isHidden = true
        }

        let crew = sim.crew
        crewNode.trayWarmth = crew.tray.indices.map { sim.warmth(ofTraySlot: $0) }
        // running (GDD §6a Hurry): smoke puffs kick up at the feet and speed lines trail behind, more the faster
        let running = crew.hurry > 1.05 && crew.target != nil && crew.busy == nil
        let strength = CGFloat(min(1, max(0, (crew.hurry - 1) / (Tuning.maxHurry - 1))))
        if running {
            dustTimer -= dt
            if dustTimer <= 0 {
                footSmoke(x: crew.x - crew.face * 12, y: crew.y + 10, strength: strength)
                dustTimer = 0.11 - 0.06 * Double(strength)
            }
        }
        speedLines.isHidden = !running
        if running {
            speedLines.position = pt(crew.x - crew.face * 26, crew.y)
            speedLines.xScale = crew.face < 0 ? -1 : 1
            speedLines.alpha = 0.35 + 0.65 * strength
            speedLines.children.enumerated().forEach { k, n in
                n.xScale = 0.6 + 0.6 * strength + 0.15 * CGFloat(sin(clock * 30 + Double(k) * 2))
            }
        }
        crewNode.sync(crew, clock: clock)
        crewNode.position = pt(crew.x, crew.y)
        if let t = crew.target {
            targetMarker.isHidden = false
            targetMarker.position = pt(t.x, sim.layout.aisles[min(t.aisle, sim.layout.aisles.count - 1)] + 22)
            targetMarker.setScale(1 + CGFloat(sin(clock * 8)) * 0.2)
        } else {
            targetMarker.isHidden = true
        }
        if crew.isMoving && Double.random(in: 0...1) < dt * (crew.wading ? 14 : 6) {
            let color = crew.wading ? UIColor(hex: 0x8A4B22, alpha: 0.8) : UIColor(hex: 0xC8BCAA, alpha: 0.8)
            particle(.dust, x: crew.x - crew.face * 6, y: crew.y + .random(in: -8...8), color: color,
                     velocity: CGVector(dx: -crew.face * .random(in: 5...20), dy: .random(in: -5...5)))
        }

        turbAmp += (CGFloat(turbulence) * CabinScene.heavyShake * shakeScale - turbAmp) * CGFloat(min(1, dt * 4))
        var offset = CGPoint.zero
        if turbAmp > 0.05 {
            let c = CGFloat(clock)
            offset.x = turbAmp * (sin(c * 21) + 0.6 * sin(c * 47 + 1.3)) / 1.6
            offset.y = turbAmp * (sin(c * 26 + 0.7) + 0.6 * sin(c * 39)) / 1.6
        }
        if shake > 0 {
            shake = max(0, shake - dt)
            let a = shake * 8 * shakeScale
            offset.x += .random(in: -a...a) / 2
            offset.y += .random(in: -a...a) / 2
        }
        let target = CGPoint(x: worldBase.x + offset.x, y: worldBase.y + offset.y)
        if world.position != target { world.position = target }
    }

    func setCrewLook(skin: UIColor, hair: UIColor) { crewNode.setLook(skin: skin, hair: hair) }

    /// Clouds hide during the intro hand-over and drift back in afterwards.
    func setClouds(visible: Bool) {
        for (i, c) in clouds.enumerated() {
            let target: CGFloat = visible ? (i % 2 == 1 ? 0.09 : 0.05) : 0
            c.node.removeAction(forKey: "cloudFade")
            if visible { c.node.run(.fadeAlpha(to: target, duration: 2.5), withKey: "cloudFade") } else { c.node.alpha = 0 }
        }
    }

    /// Where a world point is on screen, in view coordinates (for SwiftUI overlays such as the machine menu).
    func viewPoint(x: Double, y: Double) -> CGPoint? {
        guard view != nil else { return nil }
        return convertPoint(toView: world.convert(pt(x, y), to: self))
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if game?.screen == .intro { game?.skipIntro(); return }
        let p = touch.location(in: world)
        let x = Double(p.x), y = worldH - Double(p.y)
        if game?.screen == .playing {
            let ring = SKShapeNode(circleOfRadius: 6)
            ring.strokeColor = Palette.teal; ring.lineWidth = 2; ring.fillColor = .clear
            ring.position = p
            fxLayer.addChild(ring)
            ring.run(.sequence([.group([.scale(to: 3.6, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
        game?.tap(x: x, y: y)
    }

    // MARK: - One-shot effects

    func play(_ event: SimEvent) {
        switch event {
        case let .resolved(x, y, bonus, streak, passenger):
            burst(.spark, x: x, y: y, count: 16, colors: [Palette.calm, Palette.teal, .white, Palette.coral])
            floatText(streak > 1 ? "+\(bonus) ×\(streak)" : "+\(bonus)", x: x, y: y - 18, color: Palette.teal)
            if passenger != nil { heartPop(x: x, y: y - 14) }
        case let .stepDone(x, y):
            burst(.spark, x: x, y: y, count: 6, colors: [Palette.teal, .white])
            floatText("✓", x: x, y: y - 18, color: Palette.teal)
        case let .failed(x, y):
            shake = 0.35
            burst(.puff, x: x, y: y, count: 10, colors: [UIColor(hex: 0x78808C, alpha: 0.8), UIColor(hex: 0x5A6270, alpha: 0.7)])
            floatText("Missed", x: x, y: y - 18, color: Palette.critical)
        case let .mopped(x, y):
            floatText("+1", x: x, y: y - 18, color: Palette.teal)
        case .trashed:
            if let c = game?.sim.crew {
                burst(.puff, x: c.x, y: c.y - 10, count: 5, colors: [UIColor(hex: 0x9AA2AE, alpha: 0.8)])
                floatText("Binned", x: c.x, y: c.y - 30, color: Palette.teal)
            }
        case let .stumble(x, y):
            shake = max(shake, 0.2)
            burst(.puff, x: x, y: y, count: 6, colors: [UIColor(hex: 0xC8BCAA, alpha: 0.9)])
            floatText("Whoa!", x: x, y: y - 20, color: Palette.urgent)
        case let .crewStumble(x, y):
            shake = max(shake, 0.4)
            burst(.puff, x: x, y: y, count: 8, colors: [UIColor(hex: 0xC8BCAA, alpha: 0.9)])
            floatText("Ouch!", x: x, y: y - 24, color: Palette.critical)
        case let .wokeUp(x, y):
            burst(.spark, x: x, y: y - 6, count: 4, colors: [Palette.urgent])
            floatText("!", x: x, y: y - 18, color: Palette.urgent)
        case let .fell(x, y):
            shake = max(shake, 0.35)
            burst(.puff, x: x, y: y, count: 12, colors: [UIColor(hex: 0x8A4B22, alpha: 0.85), UIColor(hex: 0xC8BCAA, alpha: 0.9)])
            floatText("Oof!", x: x, y: y - 28, color: Palette.critical)
        case .rush:
            if let c = game?.sim.crew { floatText("Rush!", x: c.x, y: c.y - 56, color: Palette.coral) }
        case .jumpSeatsAway:
            for n in jumpSeatNodes {
                n.run(.sequence([.wait(forDuration: 1.2),
                                 .group([.scaleX(to: 1, y: 0.1, duration: 0.35), .fadeOut(withDuration: 0.35)])]))
            }
        case .newStations(let list):
            for (k, i) in list.enumerated() {
                guard let n = freshNodes[i], let b = game?.sim.layout.bins[i] else { continue }
                let delay = 0.35 + Double(k) * 0.3
                n.run(.sequence([.wait(forDuration: delay),
                                 .group([.fadeIn(withDuration: 0.15), .scale(to: 1.25, duration: 0.18)]),
                                 .scale(to: 1, duration: 0.15)]))
                run(.sequence([.wait(forDuration: delay + 0.1), .run { [weak self] in
                    self?.burst(.spark, x: b.x, y: b.y, count: 14, colors: [Palette.calm, Palette.teal, .white])
                    self?.floatText("NEW", x: b.x, y: b.y - 38, color: Palette.coral)
                }]))
            }
        case let .streakLost(x, y):
            floatText("Streak lost", x: x, y: y - 44, color: Palette.critical)
        case .streakUp(let n):
            if let c = game?.sim.crew {
                burst(.spark, x: c.x, y: c.y - 20, count: 10, colors: [Palette.calm, Palette.coral, .white])
                floatText("×\(n)!", x: c.x, y: c.y - 40, color: Palette.coral)
            }
        default:
            break
        }
    }

    enum ParticleKind { case spark, puff, dust }

    /// One puff of smoke at the crew's feet: pops out, drifts back and fades. Bigger when running faster.
    private func footSmoke(x: Double, y: Double, strength: CGFloat) {
        let r = 4 + 4 * strength + CGFloat.random(in: 0...2)
        let puff = SKShapeNode(circleOfRadius: r)
        puff.fillColor = UIColor(white: 0.97, alpha: 0.85); puff.strokeColor = UIColor(hex: 0xC8BCAA, alpha: 0.9); puff.lineWidth = 1
        puff.position = pt(x + Double.random(in: -3...3), y + Double.random(in: -4...4))
        puff.zPosition = 5.3
        fxLayer.addChild(puff)
        let drift = CGFloat(game?.sim.crew.face ?? 1) * -(10 + 12 * strength)
        puff.run(.sequence([.group([.moveBy(x: drift, y: CGFloat.random(in: -4...6), duration: 0.5),
                                    .scale(to: 2.1, duration: 0.5), .fadeOut(withDuration: 0.5)]),
                            .removeFromParent()]))
    }

    private func burst(_ kind: ParticleKind, x: Double, y: Double, count: Int, colors: [UIColor]) {
        for _ in 0..<count {
            let a = Double.random(in: 0...(2 * .pi))
            let sp = kind == .spark ? Double.random(in: 40...110) : Double.random(in: 10...40)
            particle(kind, x: x, y: y, color: colors.randomElement()!, velocity: CGVector(dx: cos(a) * sp, dy: sin(a) * sp))
        }
    }

    private func particle(_ kind: ParticleKind, x: Double, y: Double, color: UIColor, velocity v: CGVector) {
        let life = kind == .spark ? Double.random(in: 0.45...0.8) : kind == .puff ? Double.random(in: 0.5...0.9) : 0.5
        let size = kind == .spark ? CGFloat.random(in: 2.5...4.5) : kind == .puff ? CGFloat.random(in: 4...8) : 2.4
        let n = SKSpriteNode(texture: kind == .spark ? Tex.sparkle : Tex.dot)
        n.color = color; n.colorBlendFactor = 1
        n.size = kind == .spark ? CGSize(width: size * 4, height: size * 4) : CGSize(width: size * 2, height: size * 2)
        n.position = pt(x, y)
        fxLayer.addChild(n)
        let travel = CGVector(dx: v.dx * life * 0.55, dy: -v.dy * life * 0.55)       // damped drift
        let endScale: CGFloat = kind == .puff ? 1.6 : kind == .spark ? 0.6 : 0.5
        let move = SKAction.move(by: travel, duration: life); move.timingMode = .easeOut
        n.run(.sequence([.group([move, .fadeOut(withDuration: life), .scale(to: endScale, duration: life)]), .removeFromParent()]))
    }

    private func floatText(_ s: String, x: Double, y: Double, color: UIColor) {
        let label = SKLabelNode()
        var font = UIFont.systemFont(ofSize: 16, weight: .bold)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: d, size: 16) }
        label.attributedText = NSAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: color, .strokeColor: UIColor.white, .strokeWidth: -6
        ])
        label.verticalAlignmentMode = .center
        label.position = pt(x, y)
        label.zPosition = 2
        label.setScale(0)
        fxLayer.addChild(label)
        let pop = SKAction.scale(to: 1, duration: 0.2); pop.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 1.1); fade.timingMode = .easeIn
        label.run(.sequence([.group([pop, .moveBy(x: 0, y: 26, duration: 1.1), fade]), .removeFromParent()]))
    }

    /// Sound-wave arcs on both sides of a waiting passenger; bigger and redder as they get louder.
    private func noiseWave(x: Double, y: Double, level: Int) {
        let color = level >= 2 ? Palette.critical : Palette.urgent
        let reach = level >= 2 ? 3.0 : 2.2
        for side in [-1.0, 1.0] {
            let path = CGMutablePath()
            let mid = side < 0 ? CGFloat.pi : 0
            path.addArc(center: .zero, radius: 10, startAngle: mid - 0.7, endAngle: mid + 0.7, clockwise: false)
            let arc = SKShapeNode(path: path)
            arc.strokeColor = color; arc.lineWidth = level >= 2 ? 2.5 : 2; arc.lineCap = .round
            arc.position = pt(x, y)
            arc.alpha = 0.9
            fxLayer.addChild(arc)
            let grow = SKAction.scale(to: reach, duration: 0.7); grow.timingMode = .easeOut
            arc.run(.sequence([.group([grow, .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
        }
    }

    private func heartPop(x: Double, y: Double) {
        let h = SKSpriteNode(texture: Tex.heart)
        h.size = CGSize(width: 16, height: 14)
        h.position = pt(x, y)
        h.setScale(0)
        fxLayer.addChild(h)
        let pop = SKAction.scale(to: 1, duration: 0.25); pop.timingMode = .easeOut
        h.run(.sequence([.group([pop, .moveBy(x: 0, y: 18, duration: 1.2), .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.8)])]), .removeFromParent()]))
    }
}

// MARK: - Passenger node

final class PaxNode: SKNode {
    private let flip = SKNode()                  // mirrors the passenger when they walk aft
    private let body: SKSpriteNode
    private let normalTex: SKTexture
    private let sickTex: SKTexture
    private let grumpy = SKSpriteNode(texture: CabinScene.Tex.grumpy)
    private let mask = SKShapeNode(rect: CGRect(x: -10.5, y: -5, width: 4, height: 10), cornerRadius: 2)
    private let zzz = SKLabelNode(text: "z")
    private let chatHolder = SKNode()
    private let chat = SKSpriteNode(texture: CabinScene.Tex.chat, size: CGSize(width: 18, height: 11))
    private let archetype: Archetype
    private let phase: Double
    private var shownSick = false
    private var visible: CGFloat = 1

    init(_ p: Passenger) {
        normalTex = SKTexture(image: Art.passenger(p, sick: false))
        sickTex = SKTexture(image: Art.passenger(p, sick: true))
        body = SKSpriteNode(texture: normalTex, size: Art.passengerSize)
        archetype = p.archetype
        phase = p.phase
        super.init()
        addChild(flip)
        flip.addChild(body)
        if p.vip {
            let crown = SKSpriteNode(texture: CabinScene.Tex.crown, size: CGSize(width: 16, height: 11))
            crown.position = CGPoint(x: -2, y: 13); crown.zPosition = 2
            addChild(crown)
        }
        body.run(.sequence([.wait(forDuration: p.phase.truncatingRemainder(dividingBy: 1.8)),
                            .repeatForever(.sequence([.scaleX(to: 1.03, y: 1.03, duration: 0.9), .scaleX(to: 1, y: 1, duration: 0.9)]))]))
        // eye mask for anyone who nods off (sleepers already wear one in their texture)
        mask.fillColor = UIColor(hex: 0x2C3E66); mask.strokeColor = .clear; mask.isHidden = true
        flip.addChild(mask)
        grumpy.size = CGSize(width: 20, height: 18); grumpy.position = CGPoint(x: 0, y: 17); grumpy.isHidden = true
        addChild(grumpy)

        zzz.fontName = "AvenirNext-Heavy"; zzz.fontSize = 8; zzz.fontColor = Palette.navy
        zzz.verticalAlignmentMode = .center; zzz.alpha = 0
        addChild(zzz)
        zzz.run(.sequence([.wait(forDuration: p.phase.truncatingRemainder(dividingBy: 3.2)), .repeatForever(.sequence([
            .run { [weak self] in self?.zzz.position = CGPoint(x: 4, y: 12); self?.zzz.alpha = 1 },
            .group([.moveBy(x: 5, y: 13, duration: 1.6), .fadeOut(withDuration: 1.6)]),
            .wait(forDuration: 1.6)
        ]))]))

        chat.position = CGPoint(x: -4, y: 20.5); chat.isHidden = true
        chatHolder.addChild(chat)
        addChild(chatHolder)
        if p.archetype == .chatterbox {            // chatterboxes talk from their seat now and then
            chat.run(.sequence([.wait(forDuration: p.phase.truncatingRemainder(dividingBy: 7)), .repeatForever(.sequence([
                .unhide(), .wait(forDuration: 2.4), .hide(), .wait(forDuration: 4.6)
            ]))]))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func sync(_ p: Passenger, clock: Double, dt: Double, turbulence: Double) {
        if p.sick != shownSick { shownSick = p.sick; body.texture = p.sick ? sickTex : normalTex }
        grumpy.isHidden = !p.grumpy
        let dozing = p.asleep && !p.sick
        mask.isHidden = !dozing || archetype == .sleeper
        zzz.isHidden = !dozing
        chatHolder.isHidden = p.sick || p.grumpy || p.asleep
        var chatting = false
        if p.stroll?.stage == .dwelling, case .chat? = p.stroll?.purpose { chatting = true }
        if chatting { chat.isHidden = false } else if archetype != .chatterbox { chat.isHidden = true }

        let t = clock + phase
        var dx = 0.0, dy = 0.0
        if archetype == .nervous && !p.grumpy && !p.asleep { dx += sin(t * 23) * 0.6 }
        if p.sick { dx += sin(t * 9) * 0.9 }
        if turbulence > 0 { dx += sin(t * 31) * 1.6 * turbulence; dy += sin(t * 27 + 1) * 1.2 * turbulence }
        if let s = p.stroll {
            flip.xScale = s.face > 0 ? -1 : 1
            if s.stage == .walking || s.stage == .returning { dy += sin(clock * 14 + phase) * 0.9 }
        } else {
            flip.xScale = 1
        }
        body.position = CGPoint(x: dx, y: dy)

        let want: CGFloat = (p.stroll?.inLavatory ?? false) ? 0 : 1
        visible += (want - visible) * CGFloat(min(1, dt * 8))
        alpha = visible
    }
}

// MARK: - Spill node

final class SpillNode: SKNode {
    private let sprite: SKSpriteNode
    private let ripple = SKShapeNode(ellipseOf: CGSize(width: 20, height: 12))
    private let seed: Double
    private var shownFailed = false
    private var shownSize: CGFloat = 1

    init(_ o: Occurrence) {
        seed = o.seed
        sprite = SKSpriteNode(texture: SKTexture(image: Art.spill(seed: o.seed, failed: false)), size: CGSize(width: 64, height: 56))
        sprite.anchorPoint = CGPoint(x: 30.0 / 64, y: 26.0 / 56)
        super.init()
        addChild(sprite)
        ripple.strokeColor = .white; ripple.lineWidth = 1; ripple.fillColor = .clear
        ripple.position = CGPoint(x: 0, y: -2)
        addChild(ripple)
    }

    required init?(coder: NSCoder) { fatalError() }

    func sync(_ o: Occurrence, clock: Double) {
        if o.failed && !shownFailed {
            shownFailed = true
            sprite.texture = SKTexture(image: Art.spill(seed: seed, failed: true))
        }
        shownSize += (CGFloat(o.size) - shownSize) * 0.15            // grows smoothly after a slip
        sprite.setScale((0.4 + 0.6 * min(1, o.life / 0.4)) * (1 + 0.35 * (shownSize - 1)))
        let rt = (clock + seed).truncatingRemainder(dividingBy: 2.4)
        if rt < 1 && !o.failed {
            ripple.isHidden = false
            ripple.alpha = 0.35 * (1 - rt)
            ripple.xScale = 1 + rt * 1.2
            ripple.yScale = 1 + rt * 1.15
        } else {
            ripple.isHidden = true
        }
    }
}

// MARK: - Occurrence icon

final class IconNode: SKNode {
    private let body = SKNode()
    private let glow = SKSpriteNode(texture: CabinScene.Tex.glow)
    private let ringFG = SKShapeNode()
    private let disc = SKShapeNode(circleOfRadius: 13)
    private let item = SKSpriteNode()
    private var pips: [SKShapeNode] = []
    private var lastRem = -1.0
    /// A speech-bubble tail pointing back at the seat (at-seat problems only).
    private let tail = SKShapeNode()
    static let scale: CGFloat = 1.25

    init(_ o: Occurrence) {
        super.init()
        glow.size = CGSize(width: 68, height: 68); glow.isHidden = true
        addChild(glow)
        addChild(body)
        let t = CGMutablePath()
        t.move(to: CGPoint(x: -7, y: 0)); t.addLine(to: CGPoint(x: 0, y: -11)); t.addLine(to: CGPoint(x: 7, y: 0)); t.closeSubpath()
        tail.path = t
        tail.fillColor = Art.white(0.95); tail.strokeColor = Palette.navy; tail.lineWidth = 2
        tail.isHidden = true
        body.addChild(tail)
        let shadow = SKShapeNode(circleOfRadius: 18)
        shadow.fillColor = Art.ink(0.3); shadow.strokeColor = .clear; shadow.position = CGPoint(x: 2, y: -3)
        body.addChild(shadow)
        let ringBG = SKShapeNode(circleOfRadius: 17)
        ringBG.strokeColor = o.vip ? Palette.calm : Art.white(0.85); ringBG.lineWidth = 3.5; ringBG.fillColor = .clear
        body.addChild(ringBG)
        ringFG.strokeColor = Palette.navy; ringFG.lineWidth = 3.5; ringFG.lineCap = .butt
        body.addChild(ringFG)
        disc.strokeColor = Palette.navy; disc.lineWidth = 2
        body.addChild(disc)
        let hl = SKShapeNode(path: { let p = CGMutablePath(); p.addArc(center: .zero, radius: 10, startAngle: .pi * 0.45, endAngle: .pi * 0.95, clockwise: false); return p }())
        hl.strokeColor = Art.white(0.45); hl.lineWidth = 2
        body.addChild(hl)
        item.size = CGSize(width: 17.4, height: 17.4)
        body.addChild(item)
        if o.steps.count > 1 {
            for i in 0..<o.steps.count {
                let pip = SKShapeNode(circleOfRadius: 2.6)
                pip.strokeColor = Palette.navy; pip.lineWidth = 1.2
                pip.position = CGPoint(x: CGFloat(i - 1) * 7, y: -22)
                body.addChild(pip); pips.append(pip)
            }
        }
        body.setScale(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Points the bubble's tail at the seat: +1 = the seat is below the icon on screen, −1 = above.
    func pointTail(_ direction: CGFloat) {
        tail.isHidden = false
        tail.zRotation = direction > 0 ? 0 : .pi
        tail.position = CGPoint(x: 0, y: direction > 0 ? -15 : 15)
        tail.zPosition = -1
    }

    func sync(_ o: Occurrence, clock: Double) {
        let crit = o.state == .critical
        let pop = easeOutBack(min(1, o.life / 0.35))
        let pulse = crit ? 1 + 0.09 * sin(clock * 14) : 1
        body.setScale(pop * pulse * IconNode.scale)
        glow.isHidden = !crit
        if crit { glow.setScale(pulse * IconNode.scale) }
        disc.fillColor = Palette.escalation(o.state)
        item.texture = CabinScene.Tex.icon(o)
        for (i, pip) in pips.enumerated() { pip.fillColor = i < o.step ? Palette.teal : .white }
        let rem = o.failed ? 0 : o.remaining
        if abs(rem - lastRem) > 0.002 {
            lastRem = rem
            let p = CGMutablePath()
            if rem > 0.002 { p.addArc(center: .zero, radius: 17, startAngle: .pi / 2, endAngle: .pi / 2 - rem * 2 * .pi, clockwise: true) }
            ringFG.path = p
        }
    }
}

func easeOutBack(_ t: Double) -> Double { 1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2) }

// MARK: - Crew node (teal uniform, coral scarf, hair in a bun; walk cycle)

final class CrewNode: SKNode {
    private let feet = [SKShapeNode(ellipseOf: CGSize(width: 9, height: 5.2)), SKShapeNode(ellipseOf: CGSize(width: 9, height: 5.2))]
    private let arms = [SKShapeNode(ellipseOf: CGSize(width: 11, height: 6.8)), SKShapeNode(ellipseOf: CGSize(width: 11, height: 6.8))]
    private let hands = [SKShapeNode(circleOfRadius: 2.4), SKShapeNode(circleOfRadius: 2.4)]
    private let torso = SKNode()
    private let heldNodes = [SKNode(), SKNode()]
    private let heldItems = [SKSpriteNode(), SKSpriteNode()]
    private let warmthRings = [SKShapeNode(), SKShapeNode()]
    private let steams: [SKShapeNode] = (0..<2).map { _ in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: 10), control1: CGPoint(x: 4, y: 3), control2: CGPoint(x: -4, y: 7))
        let n = SKShapeNode(path: p)
        n.lineWidth = 1.8; n.lineCap = .round; n.strokeColor = Art.white(0.85)
        return n
    }
    /// 0…1 heat left for each tray slot (nil = not a hot item), set by the scene each frame.
    var trayWarmth: [Double?] = []
    private let busyBG = SKShapeNode(circleOfRadius: 22)
    private let busyFG = SKShapeNode()
    private let bubbleNode = SKNode()
    private let strap = SKShapeNode(rect: CGRect(x: -11, y: -2, width: 22, height: 4), cornerRadius: 2)
    private var shownBubble: String?
    var worldWidth = 1000.0

    override init() {
        super.init()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 26, height: 34))
        shadow.fillColor = Art.ink(0.25); shadow.strokeColor = .clear; shadow.position = CGPoint(x: 3, y: -4)
        addChild(shadow)
        for f in feet { f.fillColor = Palette.navy; f.strokeColor = .clear; addChild(f) }
        for a in arms { a.fillColor = UIColor(hex: 0x197476); a.strokeColor = .clear; addChild(a) }
        for h in hands { h.fillColor = UIColor(hex: 0xE9B892); h.strokeColor = .clear; addChild(h) }
        addChild(torso)

        let bodyShape = SKShapeNode(ellipseOf: CGSize(width: 20, height: 31))
        bodyShape.fillColor = Palette.teal; bodyShape.strokeColor = Palette.navy; bodyShape.lineWidth = 2
        torso.addChild(bodyShape)
        let hl = SKShapeNode(ellipseOf: CGSize(width: 10, height: 12))
        hl.fillColor = Art.white(0.16); hl.strokeColor = .clear; hl.position = CGPoint(x: -2, y: 6)
        torso.addChild(hl)
        let scarf = SKShapeNode(path: { let p = CGMutablePath(); p.addLines(between: [CGPoint(x: -4, y: 5), CGPoint(x: -9, y: 0), CGPoint(x: -4, y: -5)]); p.closeSubpath(); return p }())
        scarf.fillColor = Palette.coral; scarf.strokeColor = .clear
        torso.addChild(scarf)
        let knot = SKShapeNode(circleOfRadius: 2.2)
        knot.fillColor = Palette.coral; knot.strokeColor = .clear; knot.position = CGPoint(x: -8, y: 0)
        torso.addChild(knot)
        let head = SKShapeNode(circleOfRadius: 8)
        head.name = "head"
        head.fillColor = UIColor(hex: 0xE9B892); head.strokeColor = Palette.navy; head.lineWidth = 1.5; head.position = CGPoint(x: -1, y: 0)
        torso.addChild(head)
        let hair = SKShapeNode(path: { let p = CGMutablePath(); p.addArc(center: .zero, radius: 8, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false); p.closeSubpath(); return p }())
        hair.name = "hair"
        hair.fillColor = UIColor(hex: 0x3A2A20); hair.strokeColor = .clear
        torso.addChild(hair)
        let bun = SKShapeNode(circleOfRadius: 3.8)
        bun.name = "bun"
        bun.fillColor = UIColor(hex: 0x3A2A20); bun.strokeColor = .clear; bun.position = CGPoint(x: 8.5, y: 0)
        torso.addChild(bun)

        for (node, item) in zip(heldNodes, heldItems) {
            let heldShadow = SKShapeNode(circleOfRadius: 11)
            heldShadow.fillColor = Art.ink(0.25); heldShadow.strokeColor = .clear; heldShadow.position = CGPoint(x: 1.5, y: -2)
            node.addChild(heldShadow)
            let heldDisc = SKShapeNode(circleOfRadius: 11)
            heldDisc.fillColor = .white; heldDisc.strokeColor = Palette.teal; heldDisc.lineWidth = 2
            node.addChild(heldDisc)
            item.size = CGSize(width: 19.6, height: 19.6)
            node.addChild(item)
            node.zPosition = 3
            addChild(node)
        }

        strap.fillColor = Palette.calm; strap.strokeColor = Palette.navy; strap.lineWidth = 1
        strap.zPosition = 2.5; strap.isHidden = true
        addChild(strap)
        busyBG.strokeColor = Art.white(0.85); busyBG.lineWidth = 4; busyBG.fillColor = .clear
        busyFG.strokeColor = Palette.teal; busyFG.lineWidth = 4
        busyBG.zPosition = 2; busyFG.zPosition = 2
        addChild(busyBG); addChild(busyFG)
        bubbleNode.zPosition = 4
        addChild(bubbleNode)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setLook(skin: UIColor, hair: UIColor) {
        (torso.childNode(withName: "head") as? SKShapeNode)?.fillColor = skin
        (torso.childNode(withName: "hair") as? SKShapeNode)?.fillColor = hair
        (torso.childNode(withName: "bun") as? SKShapeNode)?.fillColor = hair
        for h in hands { h.fillColor = skin }
    }

    func sync(_ c: Crew, clock: Double) {
        let moving = c.isMoving
        let face = CGFloat(c.face)
        let sw = moving ? CGFloat(sin(c.walk)) : 0
        let sq = moving ? 1 + abs(sw) * 0.04 : 1 + CGFloat(sin(clock * 2)) * 0.015

        feet[0].isHidden = !moving; feet[1].isHidden = !moving
        feet[0].position = CGPoint(x: face * (3 + sw * 6), y: 5)
        feet[1].position = CGPoint(x: face * (3 - sw * 6), y: -5)
        arms[0].position = CGPoint(x: -sw * 4 * face, y: 13.5)
        arms[1].position = CGPoint(x: sw * 4 * face, y: -13.5)
        hands[0].position = CGPoint(x: -sw * 4 * face + face * 5, y: 13.5)
        hands[1].position = CGPoint(x: sw * 4 * face + face * 5, y: -13.5)
        torso.xScale = (face < 0 ? 1 : -1) / sq
        torso.yScale = sq

        strap.isHidden = c.seated == nil               // buckled into a jump seat
        // the tray: up to two items above the crew member's head (the HUD no longer repeats this)
        for k in 0..<heldNodes.count {
            if warmthRings[k].parent == nil {
                warmthRings[k].lineWidth = 2.5; warmthRings[k].strokeColor = Palette.urgent; warmthRings[k].lineCap = .round
                warmthRings[k].zPosition = 1
                heldNodes[k].addChild(warmthRings[k])
                steams[k].position = CGPoint(x: 0, y: 12)
                heldNodes[k].addChild(steams[k])
            }
            // hot items: a shrinking warmth ring and a wisp of steam; nothing once they've gone cold
            let heat = k < trayWarmth.count ? trayWarmth[k] : nil
            if let heat, heat > 0 {
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: 13.5, startAngle: .pi / 2, endAngle: .pi / 2 - heat * 2 * .pi, clockwise: true)
                warmthRings[k].path = path
                warmthRings[k].strokeColor = heat > 0.3 ? Palette.urgent : Palette.critical
                warmthRings[k].isHidden = false
                steams[k].isHidden = false
                steams[k].alpha = 0.4 + 0.4 * CGFloat(heat)
                steams[k].position = CGPoint(x: 0, y: 13 + CGFloat(sin(clock * 4 + Double(k))) * 1.5)
            } else {
                warmthRings[k].isHidden = true
                steams[k].isHidden = true
            }
            if k < c.tray.count {
                heldNodes[k].isHidden = false
                heldItems[k].texture = CabinScene.Tex.items[c.tray[k]]
                let x: CGFloat = c.tray.count == 1 ? 0 : (k == 0 ? -12 : 12)
                heldNodes[k].position = CGPoint(x: x, y: 30 + CGFloat(sin(clock * 6 + Double(k))) * 1.5)
            } else {
                heldNodes[k].isHidden = true
            }
        }

        if let busy = c.busy {
            busyBG.isHidden = false; busyFG.isHidden = false
            let p = CGMutablePath()
            p.addArc(center: .zero, radius: 22, startAngle: .pi / 2, endAngle: .pi / 2 - busy.progress * 2 * .pi, clockwise: true)
            busyFG.path = p
        } else {
            busyBG.isHidden = true; busyFG.isHidden = true
        }

        if c.bubble != shownBubble {
            shownBubble = c.bubble
            bubbleNode.removeAllChildren()
            if let text = c.bubble {
                let label = SKLabelNode(text: text)
                var font = UIFont.systemFont(ofSize: 11, weight: .heavy)
                if let d = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: d, size: 11) }
                label.attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: Palette.navy])
                label.verticalAlignmentMode = .center
                let w = label.frame.width + 16
                let shadow = SKShapeNode(rect: CGRect(x: -w / 2 + 2, y: -13, width: w, height: 22), cornerRadius: 11)
                shadow.fillColor = Art.ink(0.25); shadow.strokeColor = .clear
                let bg = SKShapeNode(rect: CGRect(x: -w / 2, y: -11, width: w, height: 22), cornerRadius: 11)
                bg.fillColor = .white; bg.strokeColor = Palette.navy; bg.lineWidth = 2
                label.position = CGPoint(x: 0, y: -1)
                [shadow, bg, label].forEach(bubbleNode.addChild)
                bubbleNode.userData = ["w": w]
            }
        }
        if c.bubble != nil {
            let w = (bubbleNode.userData?["w"] as? CGFloat) ?? 60
            let bx = min(max(c.x, Double(w / 2 + 24)), worldWidth - Double(w / 2) - 24)
            bubbleNode.position = CGPoint(x: bx - c.x, y: c.tray.isEmpty ? 38 : 56)
        }
    }
}


