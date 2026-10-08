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
                             widths: ["drinks": 52, "coffee": 34, "oven": 36, "snack": 33, "toy": 35, "trash": 30, "crewseat": 33])
        default:
            return nil
        }
    }

    /// Every fitting picture has a 6 px margin; the body (the machine without added steam or handles) starts at its top-left.
    private static let margin: CGFloat = 6

    /// The sprite for a station: texture, size in world units and the anchor that puts the body's centre on the station.
    func station(_ kind: StationKind, machine: MachineState?) -> (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        let name: String
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
        return sprite(name, width: widths[name.split(separator: "-").first.map(String.init) ?? name] ?? 34)
    }

    /// A trash bin with its flap pushed open (shown while someone drops something in).
    var trashOpen: (texture: SKTexture, size: CGSize, anchor: CGPoint)? { sprite("trash-open", width: widths["trash"] ?? 30) }

    /// The crew's fold-down seat by the end walls.
    var crewSeat: (texture: SKTexture, size: CGSize, anchor: CGPoint)? { sprite("crewseat", width: widths["crewseat"] ?? 33) }

    private func sprite(_ name: String, width: CGFloat) -> (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        guard let t = textures[name] else { return nil }
        let px = t.size()
        let m = Self.margin
        let bodyW = px.width - 2 * m
        let bodyH = min(px.height - 2 * m, bodyW * Self.aspect(name))
        let k = width / bodyW
        // anchor: the body's centre, measured from the picture's bottom-left
        let anchor = CGPoint(x: 0.5, y: 1 - (m + bodyH / 2) / px.height)
        return (t, CGSize(width: px.width * k, height: px.height * k), anchor)
    }

    /// Body height / width of each fitting as exported (the oven's states share a taller canvas for the ready handle).
    private static func aspect(_ name: String) -> CGFloat {
        switch name.split(separator: "-").first.map(String.init) ?? name {
        case "oven": return 520.0 / 468.0
        default: return 10                        // the body fills the canvas height
        }
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

    // MARK: Walk cycles (24 frames per facing; side faces right and is mirrored for left), same frame size as the attendant's

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
