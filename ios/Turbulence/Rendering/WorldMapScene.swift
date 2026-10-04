import SpriteKit
import UIKit

/// The route map world (Route Map Plan, step 5): toy-3D regions on a code-drawn sea, airports, flight paths and pins,
/// soft clouds over locked routes and storms over places not built yet. Drag to pan (with momentum), pinch to zoom,
/// double-tap to zoom in; taps on pins and covered regions are reported through `onTap`.
/// Layout points have y pointing down; the scene flips them so the art reads the right way up.
final class WorldMapScene: SKScene, UIGestureRecognizerDelegate {
    enum Tap {
        case flight(FlightPlan)
        case lockedRoute(Route, needs: Int, have: Int)
        case comingSoon(String)
    }

    var onTap: (Tap) -> Void = { _ in }
    var reduceMotion = false
    var haptics = true

    let layout: MapLayout
    private(set) var profile = Profile(name: "", avatar: 0)

    private let cam = SKCameraNode()
    private let regionLayer = SKNode(), pathLayer = SKNode(), airportLayer = SKNode()
    private let pinLayer = SKNode(), coverLayer = SKNode(), badgeLayer = SKNode()
    private let life = MapLifeLayer()
    private let plane = SKSpriteNode(imageNamed: "Map/ToyPlane"), planeShadow = SKShapeNode(ellipseOf: CGSize(width: 34, height: 12))
    private var cloudNodes: [String: [SKNode]] = [:], badgeNodes: [String: SKNode] = [:]
    private var hiding: Set<Int> = []

    // MARK: Developer path editor (debug builds, -mapEditor)
    var editing = false { didSet { drawEditor() } }
    var editorKind: MapLayout.Life.Kind = .walk
    /// Life per region as being edited, starting from MapLayout.json.
    private(set) var editorLife: [String: [MapLayout.Life]] = [:]
    private var editorRegion: String?
    private let editorLayer = SKNode()
    /// Nodes drawn at a constant size on screen, whatever the zoom.
    private var screenSized: [SKNode] = []
    private var pathNodes: [(node: SKShapeNode, width: CGFloat)] = []
    private var pins: [(node: SKNode, plan: FlightPlan)] = []
    private var badges: [(node: SKNode, tap: Tap)] = []
    private var covered: [(frame: CGRect, tap: Tap)] = []
    private var cityLabels: [SKNode] = []

    private var gestures: [UIGestureRecognizer] = []
    private var velocity = CGVector.zero
    private var lastUpdate: TimeInterval = 0
    private var panning = false

    static let minZoomFloor: CGFloat = 0.12
    static let maxZoom: CGFloat = 1.2

    init(layout: MapLayout = .main) {
        self.layout = layout
        super.init(size: CGSize(width: 800, height: 400))
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = UIColor(hex: 0x2C7A96)
        camera = cam
        addChild(cam)
        for (layer, z) in [(regionLayer, 1), (pathLayer, 2), (airportLayer, 3), (life, 4), (pinLayer, 5), (coverLayer, 6), (badgeLayer, 20)] as [(SKNode, CGFloat)] {
            layer.zPosition = z
            addChild(layer)
        }
        buildSea()
        buildRegions()
        buildAirports()
        buildPlane()
        editorLayer.zPosition = 30
        addChild(editorLayer)
        for r in layout.regions { editorLife[r.id] = r.life ?? [] }
        cam.position = CGPoint(x: layout.world.width / 2, y: layout.world.height / 2)
        cam.setScale(1 / 0.4)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// One map for the app's lifetime, so the camera stays where the player left it.
    static let shared = WorldMapScene()

    // MARK: Coordinates

    private var worldHeight: CGFloat { layout.world.height }

    /// Layout (y down) → scene (y up).
    func scenePoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: worldHeight - p.y) }

    func scenePoint(city: String) -> CGPoint? { layout.position(of: city).map(scenePoint) }

    var zoom: CGFloat { 1 / cam.xScale }

    /// Bigger screens get bigger pins and a closer opening view: 1× on iPhone (about 402 pt tall), up to 1.5× on iPad.
    var uiScale: CGFloat { min(1.5, max(1, size.height / 402)) }

    // MARK: Static layers

    /// The sea: one flat colour with a sprinkle of soft wave dashes, drawn once into a texture.
    private func buildSea() {
        let pad: CGFloat = 1600
        let size = CGSize(width: layout.world.width + pad * 2, height: layout.world.height + pad * 2)
        let px = CGSize(width: size.width / 4, height: size.height / 4)
        let image = UIGraphicsImageRenderer(size: px).image { ctx in
            UIColor(hex: 0x2C7A96).setFill()
            ctx.fill(CGRect(origin: .zero, size: px))
            var rng = SystemRandomNumberGenerator()
            UIColor.white.withAlphaComponent(0.07).setFill()
            for _ in 0..<1400 {
                let x = CGFloat.random(in: 0..<px.width, using: &rng), y = CGFloat.random(in: 0..<px.height, using: &rng)
                UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 7, height: 2.4), cornerRadius: 1.2).fill()
            }
        }
        let sea = SKSpriteNode(texture: SKTexture(image: image), size: size)
        sea.position = CGPoint(x: layout.world.width / 2, y: layout.world.height / 2)
        sea.zPosition = 0
        addChild(sea)
    }

    private func buildRegions() {
        for r in layout.regions {
            let node = SKSpriteNode(imageNamed: r.image)
            node.size = CGSize(width: r.size[0], height: r.size[1])
            node.position = scenePoint(CGPoint(x: r.center[0], y: r.center[1]))
            regionLayer.addChild(node)
        }
    }

    private func buildAirports() {
        for a in layout.airports {
            guard let p = scenePoint(city: a.city) else { continue }
            let (image, width): (String, CGFloat) = switch a.style {
            case .airstrip: ("Map/AirportAirstrip", 92)
            case .town: ("Map/AirportTown", 112)
            case .city: ("Map/AirportCity", 132)
            }
            let node = SKSpriteNode(imageNamed: image)
            node.size = CGSize(width: width, height: width * node.size.height / max(node.size.width, 1))
            node.position = p
            airportLayer.addChild(node)
        }
    }

    // MARK: Profile-driven layers

    /// Rebuilds pins, paths, clouds, badges and city life for this profile's progress. Routes in `hiding` still show
    /// as locked (their reveal hasn't played yet); `drawIn` animates that route's paths and pins appearing.
    func configure(profile: Profile, hiding: Set<Int> = [], drawIn: Int? = nil) {
        self.profile = profile
        self.hiding = hiding
        for layer in [pathLayer, pinLayer, coverLayer, badgeLayer] { layer.removeAllChildren() }
        screenSized.removeAll(); pathNodes.removeAll(); pins.removeAll(); badges.removeAll(); covered.removeAll(); cityLabels.removeAll()
        cloudNodes.removeAll(); badgeNodes.removeAll()
        let state = MapState(profile: profile)
        let isOpen = { (r: Route) in state.access(r) == .open && !hiding.contains(r.id) }

        for route in Campaign.routes where isOpen(route) {
            for (i, plan) in route.flights.enumerated() {
                guard let a = scenePoint(city: route.cities[i]), let b = scenePoint(city: route.cities[i + 1]) else { continue }
                let delay = route.id == drawIn ? 0.25 * Double(i) : nil
                addPath(from: a, to: b, open: state.access(plan) != .locked, drawInAfter: delay)
                addPin(plan, number: i + 1, at: b, access: state.access(plan), city: route.cities[i + 1], popAfter: delay.map { $0 + 0.4 })
            }
        }
        if let home = Campaign.route1.cities.first, let p = scenePoint(city: home) { addHome(at: p, city: home) }

        var lifeEntries: [(entries: [MapLayout.Life], toScene: (CGPoint) -> CGPoint)] = []
        for region in layout.regions {
            let frame = sceneFrame(region)
            let routeID = region.route
            let cover: MapState.Cover = routeID.map(hiding.contains) == true ? .clouds : state.cover(region)
            switch cover {
            case .none:
                if let entries = region.life {
                    lifeEntries.append((entries, { p in CGPoint(x: frame.minX + p.x * frame.width, y: frame.maxY - p.y * frame.height) }))
                }
            case .clouds:
                guard let id = routeID, let route = Campaign.routes.first(where: { $0.id == id }) else { continue }
                let needs = route.unlockStars, have = profile.totalStars
                let tap = Tap.lockedRoute(route, needs: needs, have: have)
                addClouds(over: frame, storm: false, region: region.id)
                addBadge(lines: ["Route \(route.id) · \(route.name)", "\(needs) ★ to unlock"], symbol: "lock.fill",
                         at: CGPoint(x: frame.midX, y: frame.midY), tap: tap, region: region.id)
                covered.append((frame, tap))
            case .storm:
                let name = region.name ?? routeID.flatMap { id in Campaign.routes.first { $0.id == id }?.name } ?? "New route"
                let tap = Tap.comingSoon(name)
                addClouds(over: frame, storm: true, region: region.id)
                addBadge(lines: [name, "Coming soon"], symbol: "cloud.bolt.fill", at: CGPoint(x: frame.midX, y: frame.midY), tap: tap, region: region.id)
                covered.append((frame, tap))
            }
        }

        // busy airports: every open city gets a parked plane, the next flight's departure gets a boarding queue
        let next = profile.nextFlight
        let nextFrom = Campaign.route(containing: next.id).flatMap { r in r.flights.firstIndex(of: next).map { r.cities[$0] } }
        var airportLife: [(at: CGPoint, style: MapLayout.Airport.Style, isNext: Bool)] = []
        for route in Campaign.routes where isOpen(route) {
            for (i, city) in route.cities.enumerated() where i == 0 || state.access(route.flights[i - 1]) != .locked {
                guard let a = layout.airport(city), let p = scenePoint(city: city) else { continue }
                airportLife.append((p, a.style, city == nextFrom))
            }
        }
        life.build(life: lifeEntries, airports: airportLife, reduceMotion: reduceMotion)
        if let from = nextFrom { park(at: from) }
        applyZoom()
    }

    private func sceneFrame(_ r: MapLayout.Region) -> CGRect {
        let f = r.frame
        return CGRect(x: f.minX, y: worldHeight - f.maxY, width: f.width, height: f.height)
    }

    /// A leg as a gentle upward arc; open legs are solid coral, locked ones dashed grey.
    /// The same gentle upward arc for paths and the toy plane.
    private func legControl(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let bulge = min(120, 0.15 * hypot(b.x - a.x, b.y - a.y))
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + bulge)
    }

    private func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    /// A leg as a gentle upward arc; open legs are solid coral, locked ones dashed grey. `drawInAfter` grows it from its start.
    private func addPath(from a: CGPoint, to b: CGPoint, open: Bool, drawInAfter delay: Double? = nil) {
        let control = legControl(a, b)
        func shape(upTo t: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: a)
            for k in 1...24 { path.addLine(to: quad(a, control, b, t * CGFloat(k) / 24)) }
            return open ? path : path.copy(dashingWithPhase: 0, lengths: [14, 16])
        }
        let node = SKShapeNode(path: shape(upTo: 1))
        node.strokeColor = open ? Palette.coral : Palette.steel.withAlphaComponent(0.8)
        node.lineCap = .round
        node.isAntialiased = true
        pathLayer.addChild(node)
        pathNodes.append((node, open ? 4 : 3))
        if let delay, !reduceMotion {
            node.path = shape(upTo: 0.001)
            node.run(.sequence([.wait(forDuration: delay), .customAction(withDuration: 0.5) { n, e in
                (n as? SKShapeNode)?.path = shape(upTo: max(0.001, e / 0.5))
            }]))
        }
    }

    private func addPin(_ plan: FlightPlan, number: Int, at p: CGPoint, access: MapState.FlightAccess, city: String, popAfter: Double? = nil) {
        let anchor = SKNode()
        anchor.position = p
        let pin = SKNode()
        pin.position = CGPoint(x: 0, y: 36)
        anchor.addChild(pin)

        let locked = access == .locked
        let disc = SKShapeNode(circleOfRadius: 15)
        disc.fillColor = locked ? Palette.failed : Palette.coral
        disc.strokeColor = Palette.navy
        disc.lineWidth = 3
        pin.addChild(disc)
        if locked {
            pin.addChild(symbol("lock.fill", size: 13, color: Palette.navy))
        } else {
            let n = SKLabelNode(text: "\(number)")
            n.fontName = "AvenirNext-Heavy"; n.fontSize = 15; n.fontColor = .white
            n.verticalAlignmentMode = .center
            pin.addChild(n)
        }
        let stars: Int
        switch access {
        case .done(let s), .next(let s): stars = s
        default: stars = 0
        }
        if !locked {
            // above the disc on a navy pill, clear of the airport art and the next-flight ring
            let tray = SKShapeNode(rectOf: CGSize(width: 52, height: 20), cornerRadius: 10)
            tray.fillColor = Palette.navy.withAlphaComponent(0.9)
            tray.strokeColor = .clear
            tray.position = CGPoint(x: 0, y: 36)
            pin.addChild(tray)
            for k in 0..<3 {
                let star = symbol(k < stars ? "star.fill" : "star", size: 13, color: Palette.calm)
                star.position = CGPoint(x: CGFloat(k - 1) * 16, y: 36)
                pin.addChild(star)
            }
        }
        if case .next = access {
            let ring = SKShapeNode(circleOfRadius: 21)
            ring.strokeColor = Palette.calm; ring.lineWidth = 3; ring.fillColor = .clear
            pin.addChild(ring)
            if !reduceMotion {
                ring.run(.repeatForever(.sequence([.group([.scale(to: 1.18, duration: 0.8), .fadeAlpha(to: 0.25, duration: 0.8)]),
                                                   .group([.scale(to: 0.95, duration: 0.8), .fadeAlpha(to: 0.9, duration: 0.8)])])))
            }
        }
        anchor.addChild(cityLabel(city, below: true))
        pinLayer.addChild(anchor)
        screenSized.append(anchor)
        pins.append((anchor, plan))
        if let popAfter, !reduceMotion {
            pin.setScale(0)
            pin.run(.sequence([.wait(forDuration: popAfter), .scale(to: 1.15, duration: 0.18), .scale(to: 1, duration: 0.12)]))
        }
    }

    private func addHome(at p: CGPoint, city: String) {
        let anchor = SKNode()
        anchor.position = p
        let dot = SKShapeNode(circleOfRadius: 8)
        dot.fillColor = Palette.teal; dot.strokeColor = Palette.navy; dot.lineWidth = 2.5
        dot.position = CGPoint(x: 0, y: 26)
        anchor.addChild(dot)
        let house = symbol("house.fill", size: 9, color: .white)
        house.position = dot.position
        anchor.addChild(house)
        anchor.addChild(cityLabel("\(city) · Home", below: true))
        pinLayer.addChild(anchor)
        screenSized.append(anchor)
    }

    private func cityLabel(_ text: String, below: Bool) -> SKNode {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Heavy"; label.fontSize = 10; label.fontColor = Palette.text
        label.verticalAlignmentMode = .center
        let shadow = SKLabelNode(text: text)
        shadow.fontName = label.fontName; shadow.fontSize = 10; shadow.fontColor = Palette.navy
        shadow.verticalAlignmentMode = .center
        shadow.position = CGPoint(x: 0.8, y: -1.2)
        let holder = SKNode()
        holder.addChild(shadow); holder.addChild(label)
        holder.position = CGPoint(x: 0, y: below ? -14 : 50)
        cityLabels.append(holder)
        return holder
    }

    /// Soft clouds (or a storm) scattered over a covered region, drifting gently.
    private func addClouds(over frame: CGRect, storm: Bool, region: String) {
        // locked routes get a dense, staggered blanket (a little peeks through at the edges); storms sit as a few big clouds
        let step: CGFloat = storm ? 330 : 270
        let cols = max(1, Int((frame.width / step).rounded(.up))) + (storm ? 0 : 1)
        let rows = max(1, Int((frame.height / step).rounded(.up))) + (storm ? 0 : 1)
        var k = 0
        for j in 0..<rows {
            for i in 0..<cols {
                let fx = cols == 1 ? 0.5 : CGFloat(i) / CGFloat(cols - 1), fy = rows == 1 ? 0.5 : CGFloat(j) / CGFloat(rows - 1)
                let inset: CGFloat = storm ? 0.5 : 0.12                                    // keep clouds a little inside the edges
                let x = frame.minX + frame.width * (storm ? (CGFloat(i) + 0.5) / CGFloat(cols) : inset + fx * (1 - 2 * inset)) + (j % 2 == 0 ? 0 : step * 0.35)
                let y = frame.minY + frame.height * (storm ? (CGFloat(j) + 0.5) / CGFloat(rows) : inset + fy * (1 - 2 * inset))
                let image = storm ? "Map/StormCloud" : "Map/Cloud\(k % 6 + 1)"
                let cloud = SKSpriteNode(imageNamed: image)
                // a fixed scatter per cloud, so the blanket looks natural but the same on every visit
                let jx = CGFloat((k * 37) % 23 - 11) / 11, jy = CGFloat((k * 53) % 19 - 9) / 9
                let w = storm ? step * 1.25 : step * (1.15 + 0.45 * CGFloat((k * 29) % 10) / 10)
                cloud.size = CGSize(width: w, height: w * cloud.size.height / max(cloud.size.width, 1))
                cloud.position = CGPoint(x: x + jx * step * 0.3, y: y + jy * step * 0.25)
                cloud.zPosition = CGFloat(k % 3)
                coverLayer.addChild(cloud)
                cloudNodes[region, default: []].append(cloud)
                if storm && !reduceMotion {                      // lightning: now and then the cloud flashes white, twice
                    let flash = SKAction.sequence([.colorize(with: .white, colorBlendFactor: 0.75, duration: 0.05),
                                                   .colorize(withColorBlendFactor: 0, duration: 0.12)])
                    cloud.run(.repeatForever(.sequence([.wait(forDuration: 3.5 + Double(k % 4) * 1.3, withRange: 3), flash,
                                                        .wait(forDuration: 0.09), flash])), withKey: "lightning")
                }
                if !reduceMotion {
                    let dx = CGFloat([18, -24, 30, -16][k % 4]), t = Double([5.5, 7, 6.2, 8][k % 4])
                    cloud.run(.repeatForever(.sequence([.moveBy(x: dx, y: 0, duration: t), .moveBy(x: -dx, y: 0, duration: t)])))
                }
                k += 1
            }
        }
    }

    /// A rounded navy label on top of a covered region: lock + star target, or storm + "Coming soon".
    private func addBadge(lines: [String], symbol name: String, at p: CGPoint, tap: Tap, region: String) {
        let node = SKNode()
        node.position = p
        let title = SKLabelNode(text: lines[0])
        title.fontName = "AvenirNext-Heavy"; title.fontSize = 13; title.fontColor = Palette.text
        title.verticalAlignmentMode = .center; title.position = CGPoint(x: 10, y: 8)
        let sub = SKLabelNode(text: lines[1])
        sub.fontName = "AvenirNext-DemiBold"; sub.fontSize = 11; sub.fontColor = Palette.calm
        sub.verticalAlignmentMode = .center; sub.position = CGPoint(x: 10, y: -9)
        let w = max(title.frame.width, sub.frame.width) + 52
        let box = SKShapeNode(rect: CGRect(x: -w / 2, y: -21, width: w, height: 42), cornerRadius: 14)
        box.fillColor = Palette.navy.withAlphaComponent(0.92); box.strokeColor = Palette.panelLine; box.lineWidth = 1.5
        let icon = symbol(name, size: 15, color: Palette.calm)
        icon.position = CGPoint(x: -w / 2 + 18, y: 0)
        title.position.x = -w / 2 + 34 + title.frame.width / 2
        sub.position.x = -w / 2 + 34 + sub.frame.width / 2
        for n in [box, icon, title, sub] { node.addChild(n) }
        badgeLayer.addChild(node)
        screenSized.append(node)
        badges.append((node, tap))
        badgeNodes[region] = node
    }

    /// An SF Symbol as a sprite in its colour. The symbol is drawn into a bitmap first: SKTexture(image:) on a symbol
    /// drops the tint and renders it black (filled stars came out dark instead of the HUD's yellow).
    private func symbol(_ name: String, size: CGFloat, color: UIColor) -> SKSpriteNode {
        let config = UIImage.SymbolConfiguration(pointSize: size * 2, weight: .heavy)
        let tinted = UIImage(systemName: name, withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: tinted.size, format: format).image { _ in tinted.draw(at: .zero) }
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.size = CGSize(width: tinted.size.width / 2, height: tinted.size.height / 2)
        return node
    }

    // MARK: Toy plane

    private func buildPlane() {
        let w: CGFloat = 70
        plane.size = CGSize(width: w, height: w * plane.size.height / max(plane.size.width, 1))
        plane.zPosition = 4.6
        planeShadow.fillColor = UIColor.black.withAlphaComponent(0.18)
        planeShadow.strokeColor = .clear
        planeShadow.zPosition = 4.5
        addChild(planeShadow)
        addChild(plane)
        plane.isHidden = true; planeShadow.isHidden = true
    }

    /// Between flights the hero plane is hidden: the departure airport's parked plane and boarding queue mark the next leg.
    func park(at city: String) {
        guard plane.action(forKey: "fly") == nil else { return }
        plane.isHidden = true; planeShadow.isHidden = true
    }

    /// Flies the leg a finished flight covered, climbing and descending along the path's arc.
    func flyLeg(_ plan: FlightPlan, completion: @escaping () -> Void) {
        guard let r = Campaign.route(containing: plan.id), let i = r.flights.firstIndex(of: plan),
              let a = scenePoint(city: r.cities[i]), let b = scenePoint(city: r.cities[i + 1]) else { completion(); return }
        let c = legControl(a, b)
        plane.isHidden = false; planeShadow.isHidden = false
        move(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), zoom: min(0.7, max(0.3, size.width / (abs(b.x - a.x) * 1.8 + 1))), duration: 0.5)
        guard !reduceMotion else {
            plane.position = CGPoint(x: b.x - 30, y: b.y + 24); completion(); return
        }
        let duration = min(3.2, max(1.6, Double(hypot(b.x - a.x, b.y - a.y)) / 260))
        plane.xScale = b.x >= a.x ? -1 : 1                                           // the piece faces left
        let fly = SKAction.customAction(withDuration: duration) { [weak self] node, e in
            guard let self else { return }
            let t = CGFloat(e / duration), k = t * t * (3 - 2 * t)
            let p = self.quad(a, c, b, k), ahead = self.quad(a, c, b, min(1, k + 0.02))
            let lift = sin(k * .pi)                                                  // climb, cruise, descend
            node.position = CGPoint(x: p.x, y: p.y + 24 + lift * 30)
            let tilt = atan2(ahead.y - p.y, abs(ahead.x - p.x) + 0.001)
            node.zRotation = max(-0.35, min(0.35, tilt)) * (b.x >= a.x ? 1 : -1)
            let s = 1 + 0.25 * lift
            node.yScale = s; node.xScale = (b.x >= a.x ? -1 : 1) * s
            self.planeShadow.position = CGPoint(x: p.x + 4 + lift * 10, y: p.y - 4)
            self.planeShadow.setScale(1 - 0.35 * lift)
        }
        plane.position = CGPoint(x: a.x, y: a.y + 24); plane.zRotation = 0
        // contrail: soft puffs left behind the tail while it flies
        let puff = SKAction.run { [weak self] in
            guard let self else { return }
            let tail = CGPoint(x: self.plane.position.x + (b.x >= a.x ? -26 : 26), y: self.plane.position.y - 4)
            let p = SKShapeNode(circleOfRadius: 4)
            p.fillColor = UIColor.white.withAlphaComponent(0.7); p.strokeColor = .clear
            p.position = tail; p.zPosition = 4.55
            self.addChild(p)
            p.run(.sequence([.group([.scale(to: 2.4, duration: 0.9), .fadeOut(withDuration: 0.9)]), .removeFromParent()]))
        }
        run(.sequence([.wait(forDuration: 0.5), .repeat(.sequence([puff, .wait(forDuration: 0.06)]), count: Int(duration / 0.06))]), withKey: "contrail")
        plane.run(.sequence([.wait(forDuration: 0.5), fly, .run { [weak self] in
            guard let self else { return }
            if self.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            self.plane.run(.fadeOut(withDuration: 0.4)) { self.plane.isHidden = true; self.plane.alpha = 1; self.plane.zRotation = 0 }
            self.planeShadow.run(.fadeOut(withDuration: 0.4)) { self.planeShadow.isHidden = true; self.planeShadow.alpha = 1 }
            completion()
        }]), withKey: "fly")
    }

    // MARK: Unlock reveal

    /// The camera flies to a newly opened route, its clouds part, and the route's paths and pins draw in.
    func reveal(route id: Int, completion: @escaping () -> Void) {
        guard let region = layout.region(forRoute: id) else { completion(); return }
        let center = CGPoint(x: sceneFrame(region).midX, y: sceneFrame(region).midY)
        focus(route: id)
        let part = SKAction.run { [weak self] in
            guard let self else { return }
            if self.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            self.badgeNodes[region.id]?.run(.fadeOut(withDuration: 0.3))
            for cloud in self.cloudNodes[region.id] ?? [] {
                cloud.removeAllActions()
                let away = CGVector(dx: cloud.position.x - center.x, dy: cloud.position.y - center.y)
                let len = max(1, hypot(away.dx, away.dy))
                let push = CGVector(dx: away.dx / len * 700, dy: away.dy / len * 500)
                cloud.run(.group([.move(by: push, duration: 1.2), .fadeOut(withDuration: 1.2), .scale(by: 1.3, duration: 1.2)]))
            }
        }
        let open = SKAction.run { [weak self] in
            guard let self else { return }
            self.configure(profile: self.profile, hiding: self.hiding.subtracting([id]), drawIn: id)
        }
        // hold until the last pin has popped (paths draw 0.25 s apart, each pin pops 0.4 s after its path and takes 0.3 s);
        // finishing earlier rebuilds the map and the remaining pins would appear all at once
        let flights = Campaign.routes.first { $0.id == id }?.flights.count ?? 1
        let drawIn = 0.25 * Double(flights - 1) + 0.4 + 0.3 + 0.4
        let steps = reduceMotion ? [open, .run(completion)] : [.wait(forDuration: 0.9), part, .wait(forDuration: 1.0), open, .wait(forDuration: drawIn), .run(completion)]
        run(.sequence(steps), withKey: "reveal")
    }

    // MARK: Path editor

    /// Starts a new path of the current kind in whichever region the next tap lands in.
    func editorNewPath() { editorRegion = nil; drawEditor() }

    func editorUndo() {
        guard let id = editorRegion, var list = editorLife[id], var last = list.popLast() else { return }
        last.points.removeLast()
        if !last.points.isEmpty { list.append(last) } else { editorRegion = nil }
        editorLife[id] = list
        drawEditor()
    }

    func editorDeleteLast() {
        guard let id = editorRegion ?? layout.regions.first(where: { !(editorLife[$0.id] ?? []).isEmpty })?.id else { return }
        _ = editorLife[id]?.popLast()
        editorRegion = nil
        drawEditor()
    }

    /// The edited life of every region that has any, as JSON keyed by region id.
    func editorExport() -> String {
        let out = editorLife.filter { !$0.value.isEmpty }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(out)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func editorAdd(_ p: CGPoint) {
        guard let region = layout.regions.first(where: { sceneFrame($0).contains(p) }) else { return }
        let f = sceneFrame(region)
        let point = [((p.x - f.minX) / f.width * 1000).rounded() / 1000, ((f.maxY - p.y) / f.height * 1000).rounded() / 1000].map(Double.init)
        var list = editorLife[region.id] ?? []
        if editorRegion == region.id, var last = list.popLast(), last.kind == editorKind {
            last.points.append(point); list.append(last)
        } else {
            list.append(MapLayout.Life(kind: editorKind, points: [point], loop: editorKind == .air ? true : nil))
        }
        editorLife[region.id] = list
        editorRegion = region.id
        drawEditor()
    }

    private func drawEditor() {
        editorLayer.removeAllChildren()
        guard editing else { return }
        let colours: [MapLayout.Life.Kind: UIColor] = [.road: Palette.coral, .walk: Palette.calm, .water: .cyan, .moored: .white,
                                                       .air: .magenta, .smoke: .lightGray, .glow: .yellow]
        for region in layout.regions {
            let f = sceneFrame(region)
            for (i, entry) in (editorLife[region.id] ?? []).enumerated() {
                let pts = entry.points.map { CGPoint(x: f.minX + $0[0] * f.width, y: f.maxY - $0[1] * f.height) }
                let current = region.id == editorRegion && i == (editorLife[region.id]?.count ?? 0) - 1
                let colour = colours[entry.kind] ?? .white
                if pts.count > 1, ![.smoke, .glow, .moored].contains(entry.kind) {          // anchors are separate spots
                    let path = CGMutablePath(); path.addLines(between: pts)
                    let line = SKShapeNode(path: path)
                    line.strokeColor = colour; line.lineWidth = (current ? 3 : 1.5) / zoom
                    editorLayer.addChild(line)
                }
                for p in pts {
                    let dot = SKShapeNode(circleOfRadius: (current ? 5 : 3.5) / zoom)
                    dot.fillColor = colour; dot.strokeColor = Palette.navy; dot.lineWidth = 1 / zoom
                    dot.position = p
                    editorLayer.addChild(dot)
                }
            }
        }
    }

    // MARK: Camera

    override func didMove(to view: SKView) {
        // taps come from touchesEnded (SpriteView keeps single-tap recognizers from firing); pan and pinch are recognizers
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gestures = [pan, pinch]
        for g in gestures {
            g.delegate = self
            view.addGestureRecognizer(g)
        }
        clampCamera()
        applyZoom()
    }

    override func willMove(from view: SKView) {
        gestures.forEach { view.removeGestureRecognizer($0) }
        gestures = []
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard cam.parent != nil else { return }
        // the first focus often lands before SpriteView sizes the scene; redo it until the player touches the map
        if let city = settleFocus, size != oldSize { focus(city: city, animated: false) }
        clampCamera()
        applyZoom()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer) || (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
    }

    /// The smallest zoom still fills the screen with world (no empty band past the edges).
    private var minZoom: CGFloat {
        max(Self.minZoomFloor, max(size.width / layout.world.width, size.height / layout.world.height))
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let view = g.view else { return }
        settleFocus = nil
        let t = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        cam.position.x -= t.x / zoom
        cam.position.y += t.y / zoom
        clampCamera()
        switch g.state {
        case .began: panning = true; velocity = .zero; cam.removeAction(forKey: "move")
        case .ended, .cancelled:
            panning = false
            let v = g.velocity(in: view)
            velocity = reduceMotion ? .zero : CGVector(dx: -v.x / zoom, dy: v.y / zoom)
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let view = g.view else { return }
        settleFocus = nil
        cam.removeAction(forKey: "move")
        let focus = convertPoint(fromView: g.location(in: view))
        let before = focus
        setZoom(zoom * g.scale)
        g.scale = 1
        let after = convertPoint(fromView: g.location(in: view))
        cam.position.x += before.x - after.x
        cam.position.y += before.y - after.y
        clampCamera()
    }

    private var touchStart: (point: CGPoint, time: TimeInterval)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let t = touches.first, let view else { touchStart = nil; return }
        touchStart = (t.location(in: view), t.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let view, let start = touchStart, event?.allTouches?.count ?? 1 == 1 else { return }
        touchStart = nil
        let at = t.location(in: view)
        guard hypot(at.x - start.point.x, at.y - start.point.y) < 12, t.timestamp - start.time < 0.4 else { return }
        if t.tapCount >= 2 {
            let p = convertPoint(fromView: at)
            let target = zoom * 1.8 > Self.maxZoom ? minZoom * 1.6 : zoom * 1.8
            move(to: p, zoom: target, duration: 0.35)
        } else {
            handleTap(at: at)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchStart = nil }

    private func handleTap(at viewPoint: CGPoint) {
        let p = convertPoint(fromView: viewPoint)
        if editing { editorAdd(p); return }
        // pins and badges are hit in screen points, so they are as easy to tap at any zoom
        func screenDistance(_ node: SKNode, offset: CGFloat) -> CGFloat {
            let v = convertPoint(toView: CGPoint(x: node.position.x, y: node.position.y + offset / zoom))
            return hypot(v.x - viewPoint.x, v.y - viewPoint.y)
        }
        if let hit = pins.map({ ($0, screenDistance($0.node, offset: 36 * uiScale)) }).filter({ $0.1 < 30 * uiScale }).min(by: { $0.1 < $1.1 }) {
            onTap(.flight(hit.0.plan)); return
        }
        if let b = badges.first(where: { screenDistance($0.node, offset: 0) < 60 * uiScale }) { onTap(b.tap); return }
        if let c = covered.first(where: { $0.frame.contains(p) }) { onTap(c.tap) }
    }

    private func setZoom(_ z: CGFloat) {
        cam.setScale(1 / min(Self.maxZoom, max(minZoom, z)))
        applyZoom()
    }

    /// Keeps the screen inside the world; an axis smaller than the screen stays centred.
    private func clampCamera() {
        let halfW = size.width / 2 / zoom, halfH = size.height / 2 / zoom
        let w = layout.world.width, h = layout.world.height
        cam.position.x = halfW * 2 >= w ? w / 2 : min(max(cam.position.x, halfW), w - halfW)
        cam.position.y = halfH * 2 >= h ? h / 2 : min(max(cam.position.y, halfH), h - halfH)
    }

    /// Pins, badges and lines keep their on-screen size; city names fade out when zoomed far out.
    private func applyZoom() {
        let s = uiScale / zoom
        for n in screenSized { n.setScale(s) }
        for p in pathNodes { p.node.lineWidth = p.width * s }
        let labelAlpha = min(1, max(0, (zoom - 0.3) / 0.12))
        for l in cityLabels { l.alpha = labelAlpha }
    }

    /// Glides the camera to a point and zoom (or jumps, with Reduce Motion).
    func move(to p: CGPoint, zoom target: CGFloat, duration: TimeInterval = 0.6) {
        velocity = .zero
        let z = min(Self.maxZoom, max(minZoom, target))
        cam.removeAction(forKey: "move")
        guard !reduceMotion, duration > 0 else {
            cam.setScale(1 / z); cam.position = p; clampCamera(); applyZoom(); return
        }
        let startScale = cam.xScale, startPos = cam.position, endScale = 1 / z
        let action = SKAction.customAction(withDuration: duration) { [weak self] node, t in
            guard let self else { return }
            let k = CGFloat(t / duration), e = k * k * (3 - 2 * k)          // smoothstep
            node.setScale(startScale + (endScale - startScale) * e)
            node.position = CGPoint(x: startPos.x + (p.x - startPos.x) * e, y: startPos.y + (p.y - startPos.y) * e)
            self.clampCamera(); self.applyZoom()
        }
        cam.run(action, withKey: "move")
    }

    /// The opening focus, kept until the player pans or pinches so a late resize can reframe it.
    private var settleFocus: String?

    func focus(city: String, zoom z: CGFloat = 0.55, animated: Bool = true) {
        guard let p = scenePoint(city: city) else { return }
        settleFocus = animated ? nil : city
        move(to: p, zoom: z * uiScale, duration: animated ? 0.6 : 0)
    }

    /// Frames a whole route's region.
    func focus(route id: Int, animated: Bool = true) {
        guard let r = layout.region(forRoute: id) else { return }
        let f = sceneFrame(r)
        let z = min(size.width / (f.width * 1.1), size.height / (f.height * 1.25))
        move(to: CGPoint(x: f.midX, y: f.midY), zoom: z, duration: animated ? 0.7 : 0)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(0.05, currentTime - lastUpdate)
        lastUpdate = currentTime
        // city life only moves on screen, and fades away when zoomed out too far to see it
        life.alpha = min(1, max(0, (zoom - 0.24) / 0.1))
        if life.alpha > 0, !reduceMotion {
            let half = CGSize(width: size.width / 2 / zoom + 60, height: size.height / 2 / zoom + 60)
            life.update(dt: dt, visible: CGRect(x: cam.position.x - half.width, y: cam.position.y - half.height,
                                                width: half.width * 2, height: half.height * 2), reduceMotion: false)
        }
        guard !panning, abs(velocity.dx) + abs(velocity.dy) > 4 else { return }
        cam.position.x += velocity.dx * dt
        cam.position.y += velocity.dy * dt
        let decay = pow(0.04, dt)                                   // momentum fades over about a second
        velocity = CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
        clampCamera()
    }
}
