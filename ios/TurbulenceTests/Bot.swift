@testable import Turbulence

/// A simple greedy player used to measure flights: buckles up, bins junk, then works on the most urgent problem.
/// It carries one thing at a time and never plans ahead, so it plays like a careful beginner.
func botAct(_ sim: FlightSimulation) {
    let crew = sim.crew
    if sim.seatbeltOn {
        if crew.seated == nil, let j = sim.nearestJumpSeat() {
            let js = sim.layout.jumpSeats[j]
            sim.tap(x: js.x, y: sim.jumpSeatY(js))
        }
        return
    }
    func nearest(_ match: (StationKind) -> Bool) -> Int? {
        sim.layout.bins.indices.filter { sim.stationOpen($0) && match(sim.layout.bins[$0].kind) }
            .min { abs(sim.layout.bins[$0].x - crew.x) < abs(sim.layout.bins[$1].x - crew.x) }
    }
    func tapStation(_ i: Int) { let b = sim.layout.bins[i]; sim.tap(x: b.x, y: b.y) }
    func trash() { if let i = nearest({ $0 == .trash }) { tapStation(i) } }
    func tapProblem(_ o: Occurrence) {
        if let pi = o.passenger { sim.tap(x: sim.passengers[pi].x, y: sim.passengers[pi].y) } else { sim.tap(x: o.x, y: o.y) }
    }
    func fetch(_ it: Item) {
        guard crew.hasFreeHand else { return trash() }
        if let i = nearest({ $0 == .bin(it) }) { return tapStation(i) }
        // a machine already making or holding it: wait for it / take it
        let mine = sim.layout.bins.indices.filter { i in
            switch sim.machines[i] {
            case .working(it, _)?, .ready(it, _)?: return true
            default: return false
            }
        }.first
        if let i = mine {
            if case .ready? = sim.machines[i] { tapStation(i) }
            return
        }
        if it == .coffee, let i = nearest({ $0 == .coffee }) { return tapStation(i) }
        if let i = sim.layout.bins.indices.filter({ sim.choices(atStation: $0)?.contains(it) == true })
            .min(by: { abs(sim.layout.bins[$0].x - crew.x) < abs(sim.layout.bins[$1].x - crew.x) }) {
            let b = sim.layout.bins[i]
            sim.tap(x: b.x, y: b.y, choice: it)
        }
    }
    if crew.tray.contains(where: \.isCold) { return trash() }
    let live = sim.occurrences.filter { !$0.dead }
        .sorted { ($0.failed ? -1 : $0.age / $0.fuse) > ($1.failed ? -1 : $1.age / $1.fuse) }
    for o in live {
        switch o.need {
        case .trash:
            if crew.tray.contains(.usedBag) { return trash() }
        case .hands, .order:
            return crew.hasFreeHand ? tapProblem(o) : trash()
        case .clean:
            return o.kind == .sick && !crew.hasFreeHand ? trash() : tapProblem(o)
        case .item(let it):
            return crew.tray.contains(it) ? tapProblem(o) : fetch(it)
        case .combo(let items):
            if let missing = items.first(where: { !crew.tray.contains($0) }) { return fetch(missing) }
            return tapProblem(o)
        }
    }
}

/// How quickly the bot decides: the seconds it waits before each decision once it's free (GDD §2 Stars).
enum BotSkill {
    static let expert = 0.0          // reacts at once and never wastes a step: a near-perfect run
    static let mid = 0.75            // a decent player: 2★ is fitted to this one
    static let novice = 1.5          // a newcomer: notices things late and thinks before each move
}

/// Flies a whole flight with the bot. `onFrame` runs after every update (for measuring).
@discardableResult
func flyWithBot(_ plan: FlightPlan, seed: UInt64, reaction: Double = BotSkill.expert,
                onFrame: ((FlightSimulation) -> Void)? = nil) -> FlightSimulation {
    let sim = FlightSimulation(plan: plan, seed: seed)
    sim.start()
    var thinkingSince: Double?
    var n = 0
    while sim.phase != .ended && n < 40_000 {
        let free = sim.crew.busy == nil && sim.crew.target == nil && sim.crew.queued == nil
        if free {
            let since = thinkingSince ?? sim.t
            thinkingSince = since
            if sim.t - since >= reaction { botAct(sim); thinkingSince = nil }
        } else {
            thinkingSince = nil
        }
        sim.update(dt: 1.0 / 30)
        onFrame?(sim)
        n += 1
    }
    return sim
}
