import SpriteKit

/// A painted cabin set in the jet-age look (sprite plan §6b): one base picture of the aircraft's cabin
/// (floor, runner, seats, walls, counters, lavatories) plus the galley fittings as separate sprites, so
/// the machines can show their state. Placed from the CabinLayout; aircraft without a set keep `Art.cabin`.
///
/// Sources: branding/sprites/cabin/<aircraft>/ (the approved concept with the seats emptied and the
/// fittings taken off, and each fitting isolated from it). The base picture maps onto world units with
/// `baseRect` (the concept was painted at the layout's proportions).
struct CabinSkin {
    let base: SKTexture
    /// The part of the world (top-down y, like CabinLayout) the base picture covers.
    let baseRect: CGRect
    /// Each fitting's body width in world units (its picture is scaled to it).
    private let widths: [String: CGFloat]
    /// The fittings, loaded once (the scene compares textures by identity to see a machine change state).
    private let textures: [String: SKTexture]

    init(base: SKTexture, baseRect: CGRect, parts: SKTextureAtlas, widths: [String: CGFloat]) {
        self.base = base; self.baseRect = baseRect; self.widths = widths
        textures = Dictionary(uniqueKeysWithValues: parts.textureNames.map { n in
            let name = (n as NSString).deletingPathExtension.replacingOccurrences(of: "@2x", with: "").replacingOccurrences(of: "@3x", with: "")
            return (name, parts.textureNamed(name))
        })
    }

    static func forAircraft(_ aircraft: Aircraft) -> CabinSkin? {
        switch aircraft {
        case .comet:
            guard let img = UIImage(named: "CabinCometBase") else { return nil }
            return CabinSkin(base: SKTexture(image: img),
                             baseRect: CGRect(x: 264 / 7.96, y: 18, width: 6336 / 7.96, height: 336),
                             parts: SKTextureAtlas(named: "CabinComet"),
                             // the bottom row (oven, snack, toy) sits 36 apart, so those fittings are kept to ~36 wide
                             widths: ["drinks": 52, "coffee": 34, "oven": 36, "snack": 33, "toy": 35, "trash": 30, "jumpseat": 39])
        default:
            return nil
        }
    }

    /// Every fitting picture has a 6 px margin; the body (the machine without added steam or handles) starts at its
    /// top-left, unless `bodyTop` says it sits lower to leave room for something above it.
    private static let margin: CGFloat = 6

    /// The sprite for a station: texture, size in world units and the anchor that puts the body's centre on the station.
    /// An oven is shallower than its neighbours and looked set back, so both ovens are stretched front to back to the coffee
    /// machine's depth: above the aisle (`topRow`) in line with the coffee machine, below it standing on the wall like the
    /// snack tray (bottom edges in line; it reaches a little past the tray's rim). The scene flips the bottom-row oven upside
    /// down so its door faces the aisle (`ovenFlipped`).
    func station(_ kind: StationKind, machine: MachineState?, topRow: Bool = false) -> (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        var name: String
        switch kind {
        case .drinks: name = "drinks"
        case .trash: name = "trash"
        case .bin(.snack): name = "snack"
        case .bin(.toy): name = "toy"
        case .coffee, .oven:
            let base = kind == .coffee ? "coffee" : "oven"
            switch machine ?? .idle {
            case .idle: name = "\(base)-idle"
            case .working: name = "\(base)-working"
            case .ready: name = "\(base)-ready"
            case .cold: name = "\(base)-cold"
            }
        default:
            return nil
        }
        // upside down, the ready oven's steam would hang below it: the flipped one uses a copy with the steam cut away
        if Self.ovenFlipped(kind, topRow: topRow) && name == "oven-ready" && textures["oven-ready-flipped"] != nil { name = "oven-ready-flipped" }
        // upside down, the ready oven's steam would hang below it: the flipped one uses a copy with the steam cut away
        if Self.ovenFlipped(kind, topRow: topRow) && name == "oven-ready" && textures["oven-ready-flipped"] != nil { name = "oven-ready-flipped" }
        guard var s = sprite(name, width: widths[name.split(separator: "-").first.map(String.init) ?? name] ?? 34) else { return nil }
        if kind == .oven, let oven = bodyHeight(name), let edges = topRow ? coffeeEdges : snackTrayEdges {
            s.size.height *= (edges.bottom - edges.top) / oven   // the anchor is a share of the picture: the body stays centred
            // then moves to the middle of those edges; the bottom-row oven is drawn flipped about its anchor (its door faces
            // the aisle above it), which mirrors that move too
            s.anchor.y += (topRow ? 1 : -1) * (edges.top + edges.bottom) / 2 / s.size.height
        }
        return s
    }

    /// Whether a station is drawn upside down: an oven below the aisle, so its door faces the aisle.
    static func ovenFlipped(_ kind: StationKind, topRow: Bool) -> Bool { kind == .oven && !topRow }

    /// The coffee machine's top and bottom edges, from its station point (world units, top-down).
    private var coffeeEdges: (top: CGFloat, bottom: CGFloat)? {
        bodyHeight("coffee-idle").map { (-$0 / 2, $0 / 2) }
    }

    /// Where the bottom-row oven goes, from its station point: as deep as the coffee machine, its bottom edge on the snack
    /// tray's (the tray's body is its whole picture, packets included).
    private var snackTrayEdges: (top: CGFloat, bottom: CGFloat)? {
        guard let tray = bodyHeight("snack"), let coffee = coffeeEdges else { return nil }
        return (tray / 2 - (coffee.bottom - coffee.top), tray / 2)
    }

    /// A fitting's body height in world units, as `sprite` draws it.
    private func bodyHeight(_ name: String) -> CGFloat? {
        guard let t = textures[name] else { return nil }
        let px = t.size()
        let bodyW = px.width - 2 * Self.margin
        let top = Self.margin + Self.bodyTop(name) * px.height
        let w = widths[name.split(separator: "-").first.map(String.init) ?? name] ?? 34
        return min(px.height - top - Self.margin, bodyW * Self.aspect(name)) * w / bodyW
    }

    /// One aft lavatory's painted open door and toilet, placed from the layout's `aftX` (world units, top-down y).
    struct LavArt {
        let openDoor: SKTexture
        /// Where the open-door picture goes: x from `aftX`, y absolute (top-down).
        let doorRect: CGRect
        /// The toilet seat, x from `aftX`; a passenger inside sits here.
        let toilet: CGPoint
        /// Turns a seated passenger (who faces the nose) to face the way this toilet faces.
        let facing: CGFloat
    }

    /// The painted lavatory above (true) or below (false) the aisle, if this set has them.
    func lavatory(above: Bool) -> LavArt? {
        guard let t = textures[above ? "lavdoor-top-open" : "lavdoor-bottom-open"] else { return nil }
        return above
            ? LavArt(openDoor: t, doorRect: CGRect(x: -0.7, y: 98, width: 70.4, height: 47.5), toilet: CGPoint(x: 34.5, y: 76.8), facing: .pi / 2)
            : LavArt(openDoor: t, doorRect: CGRect(x: 4.3, y: 220.5, width: 70.4, height: 47.5), toilet: CGPoint(x: 83.7, y: 304.2), facing: -.pi / 2)
    }

    /// A trash bin with its flap pushed open (shown while someone drops something in).
    var trashOpen: (texture: SKTexture, size: CGSize, anchor: CGPoint)? { sprite("trash-open", width: widths["trash"] ?? 30) }

    /// The crew's fold-down jump seat on an end wall (GDD §5b): stowed flat against the wall, or folded down to sit on.
    /// Both pictures share one canvas with the wall along their left edge, so the seat doesn't move as it folds.
    /// 39 wide (wall plate to cushion edge) so it matches the seat in the attendant's seated picture.
    func jumpSeat(down: Bool) -> (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        let name = down ? "jumpseat-down" : "jumpseat-up"
        guard var s = sprite(name, width: widths["jumpseat"] ?? 39), let px = textures[name]?.size() else { return nil }
        let k = s.size.width / px.width                   // world units per picture pixel
        s.anchor.x = (Self.margin + Self.jumpSeatWallInset / k) / px.width   // the wall plate on the wall
        return s
    }

    /// How far the layout's jump seat point sits out from its end wall (CabinLayout: 72 against the nose wall at 57).
    /// The pictures hang their wall plate there, whatever size they're drawn.
    static let jumpSeatWallInset: CGFloat = 15

    /// The attendant buckled into a folded-down jump seat (the countdown, turbulence), seen from above like the cabin
    /// and the seated passengers. Her seat (wall plate to cushion edge, 834 px) is drawn as wide as the empty jump seat,
    /// and the wall plate hangs on the wall like the empty seat's.
    /// Source: branding/sprites/cabin/comet/jumpseat-crew-source.png.
    var crewInJumpSeat: (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        guard let t = textures["jumpseat-crew"] else { return nil }
        let px = t.size()
        let k = (widths["jumpseat"] ?? 39) / 834          // world units per picture pixel
        let anchor = CGPoint(x: (Self.margin + Self.jumpSeatWallInset / k) / px.width, y: 0.5)
        return (t, CGSize(width: px.width * k, height: px.height * k), anchor)
    }

    private func sprite(_ name: String, width: CGFloat) -> (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        guard let t = textures[name] else { return nil }
        let px = t.size()
        let m = Self.margin
        let bodyW = px.width - 2 * m
        let top = m + Self.bodyTop(name) * px.height
        let bodyH = min(px.height - top - m, bodyW * Self.aspect(name))
        let k = width / bodyW
        // anchor: the body's centre, measured from the picture's bottom-left
        let anchor = CGPoint(x: 0.5, y: 1 - (top + bodyH / 2) / px.height)
        return (t, CGSize(width: px.width * k, height: px.height * k), anchor)
    }

    /// Body height / width of each fitting as exported (the oven's states share a taller canvas for the ready handle).
    private static func aspect(_ name: String) -> CGFloat {
        switch name.split(separator: "-").first.map(String.init) ?? name {
        case "oven": return 520.0 / 468.0
        default: return 10                        // the body fills the canvas height
        }
    }

    /// How far below the margin the body starts, as a share of the canvas height: the ready oven's steam rises
    /// above it (113 of 700 px), so every oven state keeps its body in the same place.
    private static func bodyTop(_ name: String) -> CGFloat {
        name == "oven-ready" ? 113.0 / 700.0 : 0
    }
}

/// Painted seated passengers (sprite plan §6b): one look per archetype, relaxed and calling, seen from above facing the
/// nose like the painted seats. Each picture is 64 × 64 world units centred on the seat point; the seat itself is in the
/// cabin picture. Sources: branding/sprites/characters/passengers/seated/.
enum PassengerArt {
    static let size = CGSize(width: 64, height: 64)
    private static let atlas = SKTextureAtlas(named: "Passengers")
    private static let textures: [String: SKTexture] = Dictionary(uniqueKeysWithValues: atlas.textureNames.map { n in
        let name = (n as NSString).deletingPathExtension
        return (name, atlas.textureNamed(name))
    })

    /// The relaxed and calling pictures for this passenger, if their archetype is painted.
    static func textures(for p: Passenger) -> (seated: SKTexture, call: SKTexture)? {
        let look: String
        switch p.archetype {
        case .business: look = "business"
        case .family: look = p.hasKid ? "family" : "familysolo"     // only parents with a toddler show one (crying-baby problems)
        case .nervous: look = "nervous"
        case .sleeper: look = "sleeper"
        case .chatterbox: look = "chatterbox"
        }
        guard let s = textures["\(look)-seated"], let c = textures["\(look)-call"] else { return nil }
        return (s, c)
    }

    /// The archetype's walking look (parents only stroll without their toddler, so the father walks alone).
    static func walkLook(_ p: Passenger) -> String {
        switch p.archetype {
        case .business: return "business"
        case .family: return "familysolo"
        case .nervous: return "nervous"
        case .sleeper: return "sleeper"
        case .chatterbox: return "chatterbox"
        }
    }

    // MARK: Walk cycles (24 frames per facing; side faces right and is mirrored for left), drawn on the attendant's frame

    /// The walk frames are painted at the attendant's size, and a passenger on their feet stands as tall as she does.
    static let walkScale: CGFloat = 1
    static var walkSize: CGSize { CGSize(width: AttendantArt.frameSize.width * walkScale, height: AttendantArt.frameSize.height * walkScale) }

    private static let walkAtlas = SKTextureAtlas(named: "PassengerWalk")
    private static var walkCache: [String: [SKTexture]] = [:]
    static func walk(_ look: String, _ facing: AttendantArt.Facing) -> [SKTexture]? {
        let key = "\(look)-\(facing.rawValue)"
        if let t = walkCache[key] { return t.isEmpty ? nil : t }
        let names = Set(walkAtlas.textureNames.map { ($0 as NSString).deletingPathExtension })
        let frames = (0..<AttendantArt.frameCount).map { String(format: "%@-%02d", key, $0) }
        let t = frames.allSatisfy(names.contains) ? frames.map { walkAtlas.textureNamed($0) } : []
        walkCache[key] = t
        return t.isEmpty ? nil : t
    }
}
