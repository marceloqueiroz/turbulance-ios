import Foundation

/// The aircraft roster (GDD §4a) that has cabins built so far.
enum Aircraft: String, CaseIterable, Equatable {
    case comet, swift, current, longhaul, voyager

    var displayName: String {
        switch self {
        case .comet: return "RJ-100 Comet"
        case .swift: return "N737-Swift"
        case .current: return "A320-Current"
        case .longhaul: return "B757-Longhaul"
        case .voyager: return "A330-Voyager"
        }
    }

    var layout: CabinLayout {
        switch self {
        case .comet: return CabinLayout.comet
        case .swift: return CabinLayout.swift
        case .current: return CabinLayout.current
        case .longhaul: return CabinLayout.longhaul
        case .voyager: return CabinLayout.voyager
        }
    }
}

extension Aircraft {
    /// The follow camera's zoom (GDD §8a Follow camera); nil = fixed camera, the whole cabin fits on screen.
    var followZoom: Double? { self == .comet ? nil : 0.83 }
}

/// What the follow camera shows, in cabin units, on a reference phone (iPhone 17 Pro in landscape, clear of the
/// HUD and cutout). The renderer uses the real screen; the test bot uses this to know what's off screen.
enum CameraRig {
    static let referenceView = (w: 828.0, h: 350.0)
    static let hullMargin = 22.0
    /// Screen points between each end of the crew's work area and the screen edge (GDD §8a).
    static let endPad = 32.0
    /// Cabin units of wall the camera may crop above and below: the window strip, never the seats.
    static let wallCrop = 36.0

    /// The whole-cabin camera scale: the work area plus `endPad` fills the width, unless the cabin is too tall.
    static func fitScale(availW: Double, availH: Double, layout: CabinLayout) -> Double {
        min((availW - 2 * endPad) / (layout.endX - layout.startX), availH / (layout.height - 2 * wallCrop))
    }

    /// The x range the camera may show at a scale: the work area and its margin, no further.
    static func xRange(_ layout: CabinLayout, scale s: Double) -> ClosedRange<Double> {
        (layout.startX - endPad / s)...(layout.endX + endPad / s)
    }

    /// Half the visible width and height around the camera's centre, in cabin units.
    static func visibleHalf(_ layout: CabinLayout, view: (w: Double, h: Double) = referenceView) -> (w: Double, h: Double) {
        let fit = fitScale(availW: view.w, availH: view.h, layout: layout)
        let s = max(fit, layout.aircraft.followZoom ?? fit)
        let r = xRange(layout, scale: s), ih = layout.height - 2 * hullMargin
        return (min(r.upperBound - r.lowerBound, view.w / s) / 2, min(ih, view.h / s) / 2)
    }
}

struct SeatSpot: Equatable {
    let y: Double
    let aisle: Int            // which aisle the crew serves this seat from
    let window: Bool
    let reach: Int            // seats between this one and the aisle (0 = aisle seat)
    let letter: String
}

struct CabinRow: Equatable {
    let number: Int           // printed row number
    let x: Double
    let premium: Bool
    let seats: [SeatSpot]
}

/// A fold-down crew seat; the crew must be buckled in one during turbulence (GDD §5b).
struct JumpSeat: Equatable {
    let x: Double
    let aisle: Int
}

struct Lavatory: Equatable {
    let doorX: Double
    let aisle: Int
    /// Which side of its aisle it stands: problems over a lavatory show on that side.
    var above = true
    /// Where a lavatory's problem icon sits, inside it and clear of the door (over the toilet seat where possible).
    var seatX = 0.0, seatY = 0.0
}

/// A fixed fixture drawn in the static cabin art.
struct CabinBlock: Equatable {
    enum Kind: Equatable { case counter, lavatory, closet, wardrobe }
    let kind: Kind
    let x: Double, y: Double, w: Double, h: Double
    var label = ""
}

/// A galley station: a bin you take an item from, a machine you pick something on and come back for, or a trash bin.
enum StationKind: Equatable {
    case bin(Item)
    case drinks                          // cold drinks: tap, pick one, grab it on arrival (GDD §6a)
    case coffee                          // brews coffee: tap it, come back when it's ready
    case oven                            // heats chicken or pasta: tap, pick, come back
    case trash
}

struct SupplyBin: Equatable {
    let kind: StationKind
    let x: Double
    let y: Double
    let aisle: Int

    init(_ kind: StationKind, x: Double, y: Double, aisle: Int) {
        self.kind = kind; self.x = x; self.y = y; self.aisle = aisle
    }
    init(item: Item, x: Double, y: Double, aisle: Int) { self.init(.bin(item), x: x, y: y, aisle: aisle) }

    /// The item a plain bin hands out (nil for machines and trash).
    var item: Item? { if case .bin(let i) = kind { return i }; return nil }
    /// Makes something over time (and can hold it, or let it go cold).
    var isMachine: Bool { kind == .coffee || kind == .oven }
    /// Everything this station can produce.
    var offers: [Item] {
        switch kind {
        case .bin(let i): return [i]
        case .drinks: return Item.coldDrinks
        case .coffee: return [.coffee]
        case .oven: return Item.meals
        case .trash: return []
        }
    }
    var label: String {
        switch kind {
        case .bin(let i): return i.displayName
        case .drinks: return "Drinks"
        case .coffee: return "Coffee"
        case .oven: return "Oven"
        case .trash: return "Trash"
        }
    }
}

/// World geometry for one aircraft. Nose on the left, y grows downward, units as in the web prototype.
/// The Comet is short (12 rows) so early flights are about choices, not walking (GDD §4a).
struct CabinLayout: Equatable {
    let aircraft: Aircraft
    var width: Double
    let height: Double
    let aisles: [Double]
    let rows: [CabinRow]
    var bins: [SupplyBin]
    var lavatories: [Lavatory]
    var blocks: [CabinBlock]
    /// x positions where the floor joins every aisle, so the crew can change aisle (galleys).
    let crossovers: [Double]
    /// x ranges drawn as galley floor (tiles instead of carpet).
    let galleyFloors: [ClosedRange<Double>]
    let curtainX: Double?
    let aftX: Double
    var jumpSeats: [JumpSeat]

    /// Only the stations this flight can use are fitted; the rest stay hidden (GDD §6a "Only what this flight uses").
    func equipped(for plan: FlightPlan) -> CabinLayout {
        var copy = self
        copy.bins = bins.filter { plan.uses($0.kind) }
        if !plan.usesLavatories {                   // nobody walks yet: the lavatories are plain closets
            copy.lavatories = []
            copy.blocks = blocks.map { $0.kind == .lavatory ? CabinBlock(kind: .closet, x: $0.x, y: $0.y, w: $0.w, h: $0.h) : $0 }
            if !copy.bins.contains(where: { $0.x >= aftX }) {
                // nothing to do at the back: the cabin ends just after the last row, no empty closets
                copy.blocks.removeAll { $0.x >= aftX }
                copy.jumpSeats.removeAll { $0.x >= aftX }
                copy.width = aftX + 40
            }
        }
        return copy
    }

    /// The crew's work area from the forward galley to the end of the aft service blocks (or the last row
    /// when nothing is fitted aft): the camera keeps this in view with a fixed margin, and the end walls close it.
    var startX: Double { blocks.map(\.x).min() ?? 60 }
    var endX: Double { max(blocks.map { $0.x + $0.w }.max() ?? 0, lastRowX + 20) }

    var minX: Double { 70 }
    var maxX: Double { min(aftX + 96, width - 30) }
    var firstRowX: Double { rows.first?.x ?? 235 }
    var lastRowX: Double { rows.last?.x ?? 631 }
    var seatCount: Int { rows.reduce(0) { $0 + $1.seats.count } }

    func nearestAisle(toY y: Double) -> Int {
        aisles.indices.min { abs(aisles[$0] - y) < abs(aisles[$1] - y) } ?? 0
    }

    /// Index of the row closest to x (for things that land "in row n", like a stumble spill).
    func nearestRow(toX x: Double) -> Int {
        rows.indices.min { abs(rows[$0].x - x) < abs(rows[$1].x - x) } ?? 0
    }

    func isPremium(x: Double) -> Bool { curtainX.map { x < $0 } ?? false }

    // MARK: - Builder

    static let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K"]

    struct MidGap { let afterRow: Int; let galley: Bool }

    static func build(_ aircraft: Aircraft, seatBlocks: [Int], premiumRows: Int, economyRows: Int,
                      fwdLav: Bool, midGap: MidGap? = nil, premiumSeats: [Int]? = nil) -> CabinLayout {
        // Vertical: seat blocks separated by aisles; 44 between seats, 72 from an aisle to its seats.
        var y = 64.0
        var blockYs: [[Double]] = []
        var aisles: [Double] = []
        for (bi, n) in seatBlocks.enumerated() {
            if bi > 0 { let a = y - 44 + 72; aisles.append(a); y = a + 72 }
            var ys: [Double] = []
            for _ in 0..<n { ys.append(y); y += 44 }
            blockYs.append(ys)
        }
        let height = y - 44 + 84
        let topAisle = aisles.first!, bottomAisle = aisles.last!

        // Seat spots, top to bottom.
        var economy: [SeatSpot] = []
        var premium: [SeatSpot] = []
        var letter = 0
        for (bi, ys) in blockYs.enumerated() {
            let n = ys.count
            for (k, sy) in ys.enumerated() {
                let aisle: Int, reach: Int
                if bi == 0 { aisle = 0; reach = n - 1 - k }
                else if bi == blockYs.count - 1 { aisle = aisles.count - 1; reach = k }
                else if k < n / 2 { aisle = bi - 1; reach = k }
                else { aisle = bi; reach = n - 1 - k }
                let window = (bi == 0 && k == 0) || (bi == blockYs.count - 1 && k == n - 1)
                economy.append(SeatSpot(y: sy, aisle: aisle, window: window, reach: reach, letter: letters[letter]))
                letter += 1
            }
            // premium: one wide seat per block, centred, or two (2-2 / 1-2-1), each next to its own aisle
            let lastBlock = blockYs.count - 1
            if (premiumSeats?[bi] ?? 1) == 2 {
                let inset = n >= 4 ? 22.0 : 10.0
                let upper = bi == 0 ? 0 : bi - 1, lower = bi == lastBlock ? aisles.count - 1 : (bi == 0 ? 0 : bi)
                premium.append(SeatSpot(y: ys.first! + inset, aisle: upper, window: bi == 0, reach: bi == 0 ? 1 : 0,
                                        letter: letters[min(bi * 3, 9)]))
                premium.append(SeatSpot(y: ys.last! - inset, aisle: lower, window: bi == lastBlock, reach: bi == lastBlock ? 1 : 0,
                                        letter: letters[min(bi * 3 + 2, 9)]))
            } else {
                let mid = ys.reduce(0, +) / Double(n)
                let aisle = bi == 0 ? 0 : min(bi, aisles.count - 1)
                premium.append(SeatSpot(y: mid, aisle: aisle, window: true, reach: 0, letter: letters[min(bi * 3, 9)]))
            }
        }

        var blocks: [CabinBlock] = []
        var bins: [SupplyBin] = []
        var lavs: [Lavatory] = []
        var jumpXs: [Double] = [72]                 // forward, by the flight deck door
        var crossovers: [Double] = aisles.count > 1 ? [170] : []
        var galleyFloors: [ClosedRange<Double>] = [56...212]
        let last = aisles.count - 1

        // Forward galley (GDD §6a): drinks, machines and food above the top aisle; snacks, toys
        // and trash below the bottom aisle; a toolkit counter between aisles on wide-bodies.
        blocks.append(CabinBlock(kind: .counter, x: 60, y: 30, w: 150, h: topAisle - 86, label: ""))      // no floor label (GDD §8a)
        blocks.append(CabinBlock(kind: .counter, x: 60, y: bottomAisle + 56, w: 150, h: height - 50 - (bottomAisle + 56)))
        let topY = topAisle - 102, bottomY = bottomAisle + 102
        bins += [SupplyBin(.drinks, x: 96, y: topY, aisle: 0),
                 SupplyBin(.coffee, x: 150, y: topY, aisle: 0), SupplyBin(.oven, x: 186, y: topY, aisle: 0),
                 SupplyBin(.oven, x: 78, y: bottomY, aisle: last)]
        bins += [SupplyBin(item: .snack, x: 114, y: bottomY, aisle: last),
                 SupplyBin(item: .toy, x: 150, y: bottomY, aisle: last)]
        // trash: a wall bin on the nose wall, below the aisle, under the fold-down crew seat (GDD §4a)
        bins.append(SupplyBin(.trash, x: 76, y: bottomAisle + 34, aisle: last))
        for a in 0..<last {
            let top = aisles[a] + 56, bottom = aisles[a + 1] - 56
            blocks.append(CabinBlock(kind: .counter, x: 60, y: top, w: 150, h: bottom - top))
            bins += [SupplyBin(item: .tool, x: 114, y: (top + bottom) / 2 + 4, aisle: a),
                     SupplyBin(.trash, x: 150, y: (top + bottom) / 2 + 4, aisle: a)]
        }

        var x0 = 235.0
        if fwdLav {
            blocks.append(CabinBlock(kind: .lavatory, x: 222, y: bottomAisle + 62, w: 66, h: height - 30 - (bottomAisle + 62), label: "LAV"))
            lavs.append(Lavatory(doorX: 255, aisle: last, above: false, seatX: 255, seatY: (bottomAisle + 62 + height - 30) / 2))
            // a wardrobe opposite, so the first premium row isn't fronted by empty floor
            blocks.append(CabinBlock(kind: .wardrobe, x: 222, y: 30, w: 66, h: topAisle - 72))
            x0 = 322
        }

        var rows: [CabinRow] = []
        var number = 1
        var curtainX: Double?
        var x = x0
        if premiumRows > 0 {
            for i in 0..<premiumRows {
                rows.append(CabinRow(number: number, x: x0 + 6 + 48 * Double(i), premium: true, seats: premium))
                number += 1
            }
            curtainX = rows.last!.x + 30
            x = curtainX! + 25
        }
        for i in 0..<economyRows {
            if let gap = midGap, i == gap.afterRow {
                let gx = x - 18
                if gap.galley {
                    blocks.append(CabinBlock(kind: .counter, x: gx + 10, y: 30, w: 76, h: topAisle - 86, label: ""))
                    blocks.append(CabinBlock(kind: .counter, x: gx + 10, y: bottomAisle + 56, w: 76, h: height - 50 - (bottomAisle + 56)))
                    bins += [SupplyBin(.drinks, x: gx + 48, y: topAisle - 102, aisle: 0),
                             SupplyBin(item: .snack, x: gx + 30, y: bottomAisle + 102, aisle: last),
                             SupplyBin(item: .toy, x: gx + 66, y: bottomAisle + 102, aisle: last)]
                    for a in 0..<last {
                        let top = aisles[a] + 56, bottom = aisles[a + 1] - 56
                        blocks.append(CabinBlock(kind: .counter, x: gx + 10, y: top, w: 76, h: bottom - top))
                        bins += [SupplyBin(item: .tool, x: gx + 30, y: (top + bottom) / 2 + 4, aisle: a),
                                 SupplyBin(.trash, x: gx + 66, y: (top + bottom) / 2 + 4, aisle: a)]
                    }
                    crossovers.append(gx + 48)
                    jumpXs.append(gx + 48)
                    galleyFloors.append((gx + 4)...(gx + 92))
                } else {
                    blocks.append(CabinBlock(kind: .lavatory, x: gx + 14, y: 30, w: 68, h: topAisle - 72, label: "LAV"))
                    // a small galley under it: drinks and snacks for the back half of the cabin
                    blocks.append(CabinBlock(kind: .counter, x: gx + 6, y: bottomAisle + 56, w: 88, h: height - 50 - (bottomAisle + 56)))
                    bins += [SupplyBin(.drinks, x: gx + 33, y: bottomAisle + 102, aisle: last),
                             SupplyBin(item: .snack, x: gx + 76, y: bottomAisle + 102, aisle: last)]
                    lavs.append(Lavatory(doorX: gx + 34, aisle: 0, seatX: gx + 48, seatY: 30 + (topAisle - 72) / 2))
                    jumpXs.append(gx + 62)
                }
                x += 96
            }
            rows.append(CabinRow(number: number, x: x, premium: false, seats: economy))
            number += 1
            x += 36
        }

        // Aft: two open-top lavatories, one each side of the aisle (a dirty one is cleaned on the spot: no cleaning
        // station), and a wall trash bin on the tail wall below the aisle, under the fold-down crew seat (GDD §4a).
        let aftX = rows.last!.x + 31
        let bottomTop = bottomAisle + 62
        blocks += [CabinBlock(kind: .lavatory, x: aftX, y: 30, w: 110, h: topAisle - 72, label: "LAV"),
                   CabinBlock(kind: .lavatory, x: aftX, y: bottomTop, w: 110, h: height - 30 - bottomTop, label: "LAV")]
        // problem icons over the top lavatory's toilet seat, and mirrored across the aisle for the bottom one, so
        // the two sit in the same spot on either side
        lavs += [Lavatory(doorX: aftX + 18, aisle: 0, seatX: aftX + 41, seatY: topAisle - 105),
                 Lavatory(doorX: aftX + 18, aisle: last, above: false, seatX: aftX + 41, seatY: bottomAisle + 105)]
        bins.append(SupplyBin(.trash, x: aftX + 96, y: bottomAisle + 34, aisle: last))

        jumpXs.append(aftX + 96)                    // aft, against the tail wall like the trash bin under it
        let jumps = jumpXs.flatMap { x in aisles.indices.map { JumpSeat(x: x, aisle: $0) } }

        return CabinLayout(aircraft: aircraft, width: aftX + 132, height: height, aisles: aisles, rows: rows, bins: bins,
                           lavatories: lavs, blocks: blocks, crossovers: crossovers, galleyFloors: galleyFloors,
                           curtainX: curtainX, aftX: aftX, jumpSeats: jumps)
    }

    static let comet = build(.comet, seatBlocks: [2, 2], premiumRows: 0, economyRows: 12, fwdLav: false)
    static let swift = build(.swift, seatBlocks: [3, 3], premiumRows: 3, economyRows: 20, fwdLav: true, premiumSeats: [2, 2])
    static let current = build(.current, seatBlocks: [3, 3], premiumRows: 3, economyRows: 20, fwdLav: true, premiumSeats: [2, 2])
    static let longhaul = build(.longhaul, seatBlocks: [3, 3], premiumRows: 5, economyRows: 24, fwdLav: true,
                                midGap: MidGap(afterRow: 12, galley: false), premiumSeats: [2, 2])
    static let voyager = build(.voyager, seatBlocks: [2, 4, 2], premiumRows: 5, economyRows: 16, fwdLav: false,
                               midGap: MidGap(afterRow: 8, galley: true), premiumSeats: [1, 2, 1])
}
