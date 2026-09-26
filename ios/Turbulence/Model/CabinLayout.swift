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

struct Lavatory: Equatable {
    let doorX: Double
    let aisle: Int
}

/// A fixed fixture drawn in the static cabin art.
struct CabinBlock: Equatable {
    enum Kind: Equatable { case counter, lavatory, closet }
    let kind: Kind
    let x: Double, y: Double, w: Double, h: Double
    var label = ""
}

/// A galley station: a bin you take an item from, a machine that prepares one, or a trash bin.
enum StationKind: Equatable {
    case bin(Item)
    case machine(Item, prep: Double)     // coffee brews, meals heat: start it, come back when ready
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

    /// The item this station hands out (nil for trash).
    var item: Item? {
        switch kind {
        case .bin(let i), .machine(let i, _): return i
        case .trash: return nil
        }
    }
    var label: String {
        switch kind {
        case .bin(let i): return i.displayName
        case .machine(let i, _): return i == .coffee ? "Coffee" : "Oven"
        case .trash: return "Trash"
        }
    }
}

/// World geometry for one aircraft. Nose on the left, y grows downward, units as in the web prototype.
/// The Comet is short (12 rows) so early flights are about choices, not walking (GDD §4a).
struct CabinLayout: Equatable {
    let aircraft: Aircraft
    let width: Double
    let height: Double
    let aisles: [Double]
    let rows: [CabinRow]
    let bins: [SupplyBin]
    let lavatories: [Lavatory]
    let blocks: [CabinBlock]
    /// x positions where the floor joins every aisle, so the crew can change aisle (galleys).
    let crossovers: [Double]
    /// x ranges drawn as galley floor (tiles instead of carpet).
    let galleyFloors: [ClosedRange<Double>]
    let curtainX: Double?
    let aftX: Double

    var minX: Double { 70 }
    var maxX: Double { aftX + 96 }
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
                      fwdLav: Bool, midGap: MidGap? = nil) -> CabinLayout {
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
            // premium: one wide seat per block, centred
            let mid = ys.reduce(0, +) / Double(n)
            let aisle = bi == 0 ? 0 : min(bi, aisles.count - 1)
            premium.append(SeatSpot(y: mid, aisle: aisle, window: true, reach: 0, letter: letters[bi * 3]))
        }

        var blocks: [CabinBlock] = []
        var bins: [SupplyBin] = []
        var lavs: [Lavatory] = []
        var crossovers: [Double] = aisles.count > 1 ? [170] : []
        var galleyFloors: [ClosedRange<Double>] = [56...212]
        let last = aisles.count - 1

        // Forward galley (GDD §6a): drinks, machines and food above the top aisle; towels, snacks, toys
        // and trash below the bottom aisle; a toolkit counter between aisles on wide-bodies.
        blocks.append(CabinBlock(kind: .counter, x: 60, y: 30, w: 150, h: topAisle - 86, label: "FWD GALLEY"))
        blocks.append(CabinBlock(kind: .counter, x: 60, y: bottomAisle + 56, w: 150, h: height - 50 - (bottomAisle + 56)))
        let topY = topAisle - 102, bottomY = bottomAisle + 102
        bins += [SupplyBin(item: .water, x: 78, y: topY, aisle: 0), SupplyBin(item: .juice, x: 114, y: topY, aisle: 0),
                 SupplyBin(.machine(.coffee, prep: 3), x: 150, y: topY, aisle: 0),
                 SupplyBin(.machine(.meal, prep: 5), x: 186, y: topY, aisle: 0)]
        bins += [SupplyBin(item: .towel, x: 78, y: bottomY, aisle: last), SupplyBin(item: .snack, x: 114, y: bottomY, aisle: last),
                 SupplyBin(item: .toy, x: 150, y: bottomY, aisle: last), SupplyBin(.trash, x: 186, y: bottomY, aisle: last)]
        for a in 0..<last {
            let top = aisles[a] + 56, bottom = aisles[a + 1] - 56
            blocks.append(CabinBlock(kind: .counter, x: 60, y: top, w: 150, h: bottom - top))
            bins += [SupplyBin(item: .tool, x: 114, y: (top + bottom) / 2 + 4, aisle: a),
                     SupplyBin(.trash, x: 150, y: (top + bottom) / 2 + 4, aisle: a)]
        }

        var x0 = 235.0
        if fwdLav {
            blocks.append(CabinBlock(kind: .lavatory, x: 222, y: bottomAisle + 62, w: 66, h: height - 30 - (bottomAisle + 62), label: "LAV"))
            lavs.append(Lavatory(doorX: 255, aisle: last))
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
                    blocks.append(CabinBlock(kind: .counter, x: gx + 10, y: 30, w: 76, h: topAisle - 86, label: "MID GALLEY"))
                    blocks.append(CabinBlock(kind: .counter, x: gx + 10, y: bottomAisle + 56, w: 76, h: height - 50 - (bottomAisle + 56)))
                    bins += [SupplyBin(item: .towel, x: gx + 30, y: topAisle - 102, aisle: 0),
                             SupplyBin(item: .water, x: gx + 66, y: topAisle - 102, aisle: 0),
                             SupplyBin(item: .snack, x: gx + 30, y: bottomAisle + 102, aisle: last),
                             SupplyBin(item: .juice, x: gx + 66, y: bottomAisle + 102, aisle: last)]
                    for a in 0..<last {
                        let top = aisles[a] + 56, bottom = aisles[a + 1] - 56
                        blocks.append(CabinBlock(kind: .counter, x: gx + 10, y: top, w: 76, h: bottom - top))
                        bins += [SupplyBin(item: .tool, x: gx + 30, y: (top + bottom) / 2 + 4, aisle: a),
                                 SupplyBin(.trash, x: gx + 66, y: (top + bottom) / 2 + 4, aisle: a)]
                    }
                    crossovers.append(gx + 48)
                    galleyFloors.append((gx + 4)...(gx + 92))
                } else {
                    blocks.append(CabinBlock(kind: .lavatory, x: gx + 14, y: 30, w: 68, h: topAisle - 72, label: "LAV"))
                    blocks.append(CabinBlock(kind: .closet, x: gx + 14, y: bottomAisle + 62, w: 68, h: height - 30 - (bottomAisle + 62)))
                    lavs.append(Lavatory(doorX: gx + 34, aisle: 0))
                }
                x += 96
            }
            rows.append(CabinRow(number: number, x: x, premium: false, seats: economy))
            number += 1
            x += 36
        }

        // Aft: lavatory on top; towels, trash and the plunger in the closet (two-aisle: lavs both sides).
        let aftX = rows.last!.x + 31
        blocks.append(CabinBlock(kind: .lavatory, x: aftX, y: 30, w: 66, h: topAisle - 72, label: "LAV"))
        lavs.append(Lavatory(doorX: aftX + 18, aisle: 0))
        let closetTop: Double, closetBottom: Double, closetAisle: Int
        if aisles.count > 1 {
            blocks.append(CabinBlock(kind: .lavatory, x: aftX, y: bottomAisle + 62, w: 66, h: height - 30 - (bottomAisle + 62), label: "LAV"))
            lavs.append(Lavatory(doorX: aftX + 18, aisle: last))
            closetTop = topAisle + 62; closetBottom = aisles[1] - 62; closetAisle = 0
        } else {
            closetTop = bottomAisle + 62; closetBottom = height - 30; closetAisle = last
        }
        blocks.append(CabinBlock(kind: .closet, x: aftX, y: closetTop, w: 110, h: closetBottom - closetTop, label: "AFT"))
        let by = aisles.count > 1 ? (closetTop + closetBottom) / 2 + 10 : bottomAisle + 110
        bins += [SupplyBin(item: .towel, x: aftX + 20, y: by, aisle: closetAisle),
                 SupplyBin(.trash, x: aftX + 56, y: by, aisle: closetAisle),
                 SupplyBin(item: .plunger, x: aftX + 92, y: by, aisle: closetAisle)]

        return CabinLayout(aircraft: aircraft, width: aftX + 132, height: height, aisles: aisles, rows: rows, bins: bins,
                           lavatories: lavs, blocks: blocks, crossovers: crossovers, galleyFloors: galleyFloors,
                           curtainX: curtainX, aftX: aftX)
    }

    static let comet = build(.comet, seatBlocks: [2, 2], premiumRows: 0, economyRows: 12, fwdLav: false)
    static let swift = build(.swift, seatBlocks: [3, 3], premiumRows: 3, economyRows: 20, fwdLav: true)
    static let current = build(.current, seatBlocks: [3, 3], premiumRows: 3, economyRows: 20, fwdLav: true)
    static let longhaul = build(.longhaul, seatBlocks: [3, 3], premiumRows: 0, economyRows: 24, fwdLav: true,
                                midGap: MidGap(afterRow: 12, galley: false))
    static let voyager = build(.voyager, seatBlocks: [2, 4, 2], premiumRows: 0, economyRows: 16, fwdLav: false,
                               midGap: MidGap(afterRow: 8, galley: true))
}
