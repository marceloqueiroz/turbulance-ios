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
        if let pi = o.passenger { sim.tap(x: sim.passengers[pi].x, y: sim.passengers[pi].y) }
        else if let li = o.lavatory { let lav = sim.layout.lavatories[li]; sim.tap(x: lav.seatX, y: lav.seatY) }   // its icon
        else { sim.tap(x: o.x, y: o.y) }
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
    // what this attendant can act on: their own side (two attendants), and off-screen problems only once they've
    // been there a moment (the follow camera's awareness cost, GDD §8a)
    let half = CameraRig.visibleHalf(sim.layout)
    func noticed(_ o: Occurrence) -> Bool {
        let onScreen = abs(o.x - crew.x) <= half.w && abs(o.y - crew.y) <= half.h + 40
        return onScreen || o.life >= BotSkill.offScreenDelay
    }
    // how pressing each problem is: its timer, or for a dirty lavatory (no timer) how long its line is
    func urgency(_ o: Occurrence) -> Double {
        if o.failed { return -1 }
        if o.kind == .dirtyLav, let li = o.lavatory { return 0.45 + 0.2 * Double(sim.lavQueue(li)) }
        return o.age / o.fuse
    }
    let live = sim.occurrences.filter { !$0.dead && (!sim.twoCrew || sim.owner(of: $0) == sim.active) && noticed($0) }
        .sorted { urgency($0) > urgency($1) }
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
    static let offScreenDelay = 1.0  // seconds before a problem off screen gets noticed (its edge marker)
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
        // one decision at a time, like a player: with two attendants it acts for whichever is free (GDD §8a)
        let free = sim.crews.indices.filter { i in
            let c = sim.crews[i]
            return c.busy == nil && c.target == nil && c.queued == nil
        }
        if !free.isEmpty {
            let since = thinkingSince ?? sim.t
            thinkingSince = since
            if sim.t - since >= reaction {
                for i in free {
                    if sim.active != i { sim.select(i) }
                    botAct(sim)
                    let c = sim.crews[i]
                    let acted = c.busy != nil || c.target != nil || c.queued != nil
                    if acted && reaction > 0 { break }   // an expert decides at once for both; anyone else, one at a time
                }
                thinkingSince = nil
            }
        } else {
            thinkingSince = nil
        }
        sim.update(dt: 1.0 / 30)
        onFrame?(sim)
        n += 1
    }
    return sim
}
