import CoreGraphics
import Foundation

/// Where everything sits on the route map (Route Map Plan: regions on a code-drawn sea).
/// Loaded from `MapLayout.json`; a future route adds a region and its airports there, nothing else moves.
/// World units have y pointing down, like the region art; the map view flips them for SpriteKit.
struct MapLayout: Decodable {
    struct World: Decodable {
        let width: Double
        let height: Double
        let sea: String
    }

    struct Region: Decodable, Identifiable {
        enum Kind: String, Decodable { case route, special, comingSoon }
        let id: String
        let image: String
        let kind: Kind
        var route: Int?                 // the Campaign route on this land (kind == .route)
        var name: String?               // for specials and regions not built yet
        let center: [Double]
        let size: [Double]
        var life: [Life]?               // moving city life, authored after the art (Route Map Plan, City life)

        var frame: CGRect {
            CGRect(x: center[0] - size[0] / 2, y: center[1] - size[1] / 2, width: size[0], height: size[1])
        }
    }

    /// One strand of city life: a path actors travel, or an anchor for an effect. Points are 0…1 inside the region image.
    struct Life: Codable, Equatable {
        enum Kind: String, Codable, CaseIterable {
            case road       // cars and vans drive it back and forth
            case walk       // people hop along it back and forth
            case water      // boats sail it (a loop when `loop` is true)
            case moored     // boats bob in place at each point
            case air        // gulls circle it as a loop
            case smoke      // chimney puffs rise from each point
            case glow       // a lamp pulses at each point (lighthouses)
        }
        var kind: Kind
        var points: [[Double]]
        var actors: [String]?           // asset names under Map/, e.g. "CarCoral"; defaults per kind
        var count: Int?                 // how many actors share the path (default 1)
        var loop: Bool?
    }

    struct Airport: Decodable {
        enum Style: String, Decodable { case airstrip, town, city }
        let city: String
        let region: String
        let at: [Double]                // position inside the region image, 0…1 from its top-left
        let style: Style
    }

    let world: World
    let regions: [Region]
    let airports: [Airport]

    static let main: MapLayout = {
        guard let url = Bundle.main.url(forResource: "MapLayout", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(MapLayout.self, from: data) else {
            fatalError("MapLayout.json is missing or malformed")
        }
        return layout
    }()

    func region(_ id: String) -> Region? { regions.first { $0.id == id } }

    func region(forRoute route: Int) -> Region? { regions.first { $0.route == route } }

    func airport(_ city: String) -> Airport? { airports.first { $0.city == city } }

    /// The airport's centre in world units.
    func position(of city: String) -> CGPoint? {
        guard let a = airport(city), let r = region(a.region) else { return nil }
        let f = r.frame
        return CGPoint(x: f.minX + a.at[0] * f.width, y: f.minY + a.at[1] * f.height)
    }

    var bounds: CGRect { CGRect(x: 0, y: 0, width: world.width, height: world.height) }
}
