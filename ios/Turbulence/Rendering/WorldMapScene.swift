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

    let layout: MapLayout
    private(set) var profile = Profile(name: "", avatar: 0)

    private let cam = SKCameraNode()
    private let regionLayer = SKNode(), pathLayer = SKNode(), airportLayer = SKNode()
    private let pinLayer = SKNode(), coverLayer = SKNode(), badgeLayer = SKNode()
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
        for (layer, z) in [(regionLayer, 1), (pathLayer, 2), (airportLayer, 3), (pinLayer, 5), (coverLayer, 6), (badgeLayer, 20)] as [(SKNode, CGFloat)] {
            layer.zPosition = z
            addChild(layer)
        }
        buildSea()
        buildRegions()
        buildAirports()
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

    /// Rebuilds pins, paths, clouds and badges for this profile's progress.
    func configure(profile: Profile) {
        self.profile = profile
        for layer in [pathLayer, pinLayer, coverLayer, badgeLayer] { layer.removeAllChildren() }
        screenSized.removeAll(); pathNodes.removeAll(); pins.removeAll(); badges.removeAll(); covered.removeAll(); cityLabels.removeAll()
        let state = MapState(profile: profile)

        for route in Campaign.routes where state.access(route) == .open {
            for (i, plan) in route.flights.enumerated() {
                guard let a = scenePoint(city: route.cities[i]), let b = scenePoint(city: route.cities[i + 1]) else { continue }
                addPath(from: a, to: b, open: state.access(plan) != .locked)
                addPin(plan, number: i + 1, at: b, access: state.access(plan), city: route.cities[i + 1])
            }
        }
        if let home = Campaign.route1.cities.first, let p = scenePoint(city: home) { addHome(at: p, city: home) }

        for region in layout.regions {
            let frame = sceneFrame(region)
            switch state.cover(region) {
            case .none: break
            case .clouds:
                guard let id = region.route, let route = Campaign.routes.first(where: { $0.id == id }),
                      case let .locked(needs, have) = state.access(route) else { continue }
                let tap = Tap.lockedRoute(route, needs: needs, have: have)
                addClouds(over: frame, storm: false)
                addBadge(lines: ["Route \(route.id) · \(route.name)", "\(needs) ★ to unlock"], symbol: "lock.fill", at: CGPoint(x: frame.midX, y: frame.midY), tap: tap)
                covered.append((frame, tap))
            case .storm:
                let name = region.name ?? region.route.flatMap { id in Campaign.routes.first { $0.id == id }?.name } ?? "New route"
                let tap = Tap.comingSoon(name)
                addClouds(over: frame, storm: true)
                addBadge(lines: [name, "Coming soon"], symbol: "cloud.bolt.fill", at: CGPoint(x: frame.midX, y: frame.midY), tap: tap)
                covered.append((frame, tap))
            }
        }
        applyZoom()
    }

    private func sceneFrame(_ r: MapLayout.Region) -> CGRect {
        let f = r.frame
        return CGRect(x: f.minX, y: worldHeight - f.maxY, width: f.width, height: f.height)
    }

    /// A leg as a gentle upward arc; open legs are solid coral, locked ones dashed grey.
    private func addPath(from a: CGPoint, to b: CGPoint, open: Bool) {
        let bulge = min(120, 0.15 * hypot(b.x - a.x, b.y - a.y))
        let control = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + bulge)
        let path = CGMutablePath()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)
        let node = SKShapeNode(path: open ? path : path.copy(dashingWithPhase: 0, lengths: [14, 16]))
        node.strokeColor = open ? Palette.coral : Palette.steel.withAlphaComponent(0.8)
        node.lineCap = .round
        node.isAntialiased = true
        pathLayer.addChild(node)
        pathNodes.append((node, open ? 4 : 3))
    }

    private func addPin(_ plan: FlightPlan, number: Int, at p: CGPoint, access: MapState.FlightAccess, city: String) {
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
            for k in 0..<3 {
                let star = symbol(k < stars ? "star.fill" : "star", size: 9, color: k < stars ? Palette.calm : Palette.cream)
                star.position = CGPoint(x: CGFloat(k - 1) * 11, y: -24)
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
    private func addClouds(over frame: CGRect, storm: Bool) {
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
                if !reduceMotion {
                    let dx = CGFloat([18, -24, 30, -16][k % 4]), t = Double([5.5, 7, 6.2, 8][k % 4])
                    cloud.run(.repeatForever(.sequence([.moveBy(x: dx, y: 0, duration: t), .moveBy(x: -dx, y: 0, duration: t)])))
                }
                k += 1
            }
        }
    }

    /// A rounded navy label on top of a covered region: lock + star target, or storm + "Coming soon".
    private func addBadge(lines: [String], symbol name: String, at p: CGPoint, tap: Tap) {
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
    }

    private func symbol(_ name: String, size: CGFloat, color: UIColor) -> SKSpriteNode {
        let config = UIImage.SymbolConfiguration(pointSize: size * 2, weight: .heavy)
        let image = UIImage(systemName: name, withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.size = CGSize(width: image.size.width / 2, height: image.size.height / 2)
        return node
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
        // pins and badges are hit in screen points, so they are as easy to tap at any zoom
        func screenDistance(_ node: SKNode, offset: CGFloat) -> CGFloat {
            let v = convertPoint(toView: CGPoint(x: node.position.x, y: node.position.y + offset / zoom))
            return hypot(v.x - viewPoint.x, v.y - viewPoint.y)
        }
        if let hit = pins.map({ ($0, screenDistance($0.node, offset: 36)) }).filter({ $0.1 < 30 }).min(by: { $0.1 < $1.1 }) {
            onTap(.flight(hit.0.plan)); return
        }
        if let b = badges.first(where: { screenDistance($0.node, offset: 0) < 60 }) { onTap(b.tap); return }
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
        let s = 1 / zoom
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

    func focus(city: String, zoom z: CGFloat = 0.55, animated: Bool = true) {
        guard let p = scenePoint(city: city) else { return }
        move(to: p, zoom: z, duration: animated ? 0.6 : 0)
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
        guard !panning, abs(velocity.dx) + abs(velocity.dy) > 4 else { return }
        cam.position.x += velocity.dx * dt
        cam.position.y += velocity.dy * dt
        let decay = pow(0.04, dt)                                   // momentum fades over about a second
        velocity = CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
        clampCamera()
    }
}
