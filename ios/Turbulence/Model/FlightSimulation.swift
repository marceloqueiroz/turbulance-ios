import Foundation

// Pure game model for one flight. No SpriteKit/UIKit here so it stays unit-testable and portable.
// World geometry comes from the flight's CabinLayout: nose on the left, y grows downward.

enum Tuning {
    static let stopDistance = 24.0

    static let boardingEnds = 6.0
    static let landingLead = 18.0      // final approach: no new spawns

    static let crewSpeed = 260.0
    static let crossSpeed = 200.0      // changing aisle at a galley
    static let trayCapacity = 2        // GDD §6a: a tray carries two things
    static let wadingFactor = 0.3
    static let binJamFactor = 0.5
    static let cartFactor = 0.35

    static let calmUntil = 0.45
    static let urgentUntil = 0.78
    static let criticalDrainPerSecond = 0.35
    static let stepRelief = 0.35
    static let vipFuseScale = 0.8

    static let startingSatisfaction = 70.0
    static let unresolvedAtLandingPenalty = 8.0
    static let starThresholds: [Double] = [40, 65, 85]

    static let aisleSeatDuration = 0.5
    static let reachPerSeat = 0.25     // each seat further from the aisle takes longer
    static let windowSeatDuration = 1.0
    static let callDuration = 0.4
    static let pickDuration = 0.25
    static let occupancy = 0.86
    static let spawnInterval = 4.0...7.0

    static let lavUsesBeforeClog = 3
    static let babyDrainPerSecond = 0.12
    static let toiletDrainPerSecond = 0.1

    // Turbulence (GDD §5a): seatbelt chime + warning, then the cabin shakes.
    static let turbulenceSchedule = [TurbulenceBump(start: 60, duration: 7, intensity: 0.375)]
    static let turbulenceWarning = 6.0          // light; heavy bumps warn for 9 s (GDD §5b)
    static let heavyTurbulenceWarning = 9.0
    static let turbulenceFuseRate = 0.5         // everyone's strapped in: problems escalate at half speed
    static let buckleDuration = 0.5
    static let unbuckleDuration = 0.3
    static let crewStumblePenalty = 5.0
    static let crewKnockdown = 1.5
    static let crewStumbleEvery = 3.0
    static let turbulenceCrewFactor = 0.6
    static let turbulenceSpawnBoost = 1.6
    static let stumbleSpillChance = 0.5

    // Aisle traffic (GDD §4): passengers get up to chat or use the lavatory.
    static let strollChancePerSecond = 0.12
    static let maxStrollers = 2
    static let paxWalkSpeed = 55.0
    static let paxStepSpeed = 50.0
    static let hurryFactor = 1.6
    static let chatDwell = 4.0...7.0
    static let lavDwell = 4.0...6.0
    static let squeezeFactor = 0.5
    static let squeezeDistance = 20.0

    // Drink service cart (GDD §4a A320-Current, §5a broken drink cart).
    static let cartSpeed = 30.0
    static let cartServePause = 1.2
    static let cartWindow = 0.2...0.75          // share of the flight the cart is out
    static let cartTroubleChancePerSecond = 0.035

    // Twists (GDD §6a).
    static let mealServiceWindow = 0.35...0.6
    static let helperSpeed = 140.0
    static let redEyeAsleep = 0.65

    // Dozing and noise (GDD §7): passengers nod off; unattended problems get louder and wake them.
    static let dozeChancePerSecond = 0.0015          // per seated, awake passenger during cruise
    static let wakePenalty = 1.0
    static func noiseRows(_ state: Escalation) -> Int { state == .urgent ? 1 : state == .critical ? 2 : 0 }

    static func stars(for satisfaction: Double) -> Int { starThresholds.filter { satisfaction >= $0 }.count }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Item: String, CaseIterable {
    case towel, water, juice, snack, coffee, meal, toy, plunger, tool, usedBag, coldCoffee, coldMeal

    /// Drinks that splash out when the crew slips or stumbles.
    static let liquids: Set<Item> = [.water, .juice, .coffee, .coldCoffee]
    /// Hot items go cold after this long on the tray (GDD §6a).
    var keepsHotFor: Double? { self == .coffee ? 18 : self == .meal ? 22 : nil }
    var cold: Item? { self == .coffee ? .coldCoffee : self == .meal ? .coldMeal : nil }
    var displayName: String {
        switch self {
        case .towel: return "Towel"
        case .water: return "Water"
        case .juice: return "Juice"
        case .snack: return "Snack"
        case .coffee: return "Coffee"
        case .meal: return "Hot meal"
        case .toy: return "Toy"
        case .plunger: return "Plunger"
        case .tool: return "Toolkit"
        case .usedBag: return "Used sick bag"
        case .coldCoffee: return "Cold coffee"
        case .coldMeal: return "Cold meal"
        }
    }
}

/// What one step of an occurrence takes.
enum Step: Equatable {
    case item(Item)          // bring this
    case combo([Item])       // bring all of these on the tray at once
    case hands               // a free hand (call buttons, bins, carts, bags)
    case trash               // bin the used sick bag you're carrying
    case order               // go and take their order; the icon only shows the item afterwards
}

struct TurbulenceBump: Equatable {
    let start: Double
    let duration: Double
    let intensity: Double          // 1 = heavy (≈8 pt shake), 0.375 = light (≈3 pt)
    var warning: Double? = nil     // default: 6 s light, 9 s heavy

    var warningTime: Double { warning ?? (intensity >= 0.7 ? Tuning.heavyTurbulenceWarning : Tuning.turbulenceWarning) }
}

enum Turbulence: Equatable { case none, warning, active(intensity: Double) }

enum StrollPurpose: Equatable { case chat(partner: Int), lavatory(Int) }
enum StrollStage: Equatable { case leaving, walking, dwelling, returning, sitting }

/// A passenger out of their seat. Position is in world units; y is their lane in the aisle.
struct Stroll: Equatable {
    var purpose: StrollPurpose
    var stage: StrollStage
    var x: Double
    var y: Double
    var targetX: Double
    var laneY: Double
    var dwell = 0.0
    var inLavatory = false
    var face = -1.0
    /// Standing in the aisle (slows the crew a little, stumbles in turbulence).
    var inAisle: Bool { stage == .walking || stage == .returning || (stage == .dwelling && !inLavatory) }
}

enum Archetype: CaseIterable { case business, family, nervous, sleeper, chatterbox }

struct Passenger: Identifiable {
    let id: Int
    let row: Int              // index into layout.rows
    let seat: Int             // index into that row's seats
    let x: Double
    let y: Double
    let aisle: Int
    let reach: Int
    let isWindow: Bool
    let premium: Bool
    let label: String         // "12C"
    let archetype: Archetype
    let skin: Int
    let hair: Int
    let hairStyle: Int
    let hasKid: Bool
    let phase: Double
    var vip = false
    var sick = false
    var grumpy = false
    var asleep = false
    var stroll: Stroll?
    var drawX: Double { stroll?.x ?? x }
    var drawY: Double { stroll?.y ?? y }
}

enum OccurrenceKind: Equatable, CaseIterable {
    case sick, call, drink, baby, spill, binJam, carryOn, toilet, stuckCart, brokenCart
    /// Happens at a seat to a passenger.
    var atSeat: Bool { self == .sick || self == .call || self == .drink || self == .baby }
    /// Sits in the aisle and slows the crew down until cleared.
    var slows: Bool { self == .spill || self == .binJam || self == .carryOn }
    var isCart: Bool { self == .stuckCart || self == .brokenCart }
    /// Stays put after failing, until someone clears it.
    var lingers: Bool { !atSeat }

    var penalty: Double {
        switch self {
        case .sick: return 15
        case .spill, .baby: return 10
        case .call: return 4
        default: return 8
        }
    }
}

enum Escalation: Equatable {
    case calm, urgent, critical, failed
    static func forFraction(_ f: Double) -> Escalation {
        f < Tuning.calmUntil ? .calm : f < Tuning.urgentUntil ? .urgent : .critical
    }
}

struct Occurrence: Identifiable {
    let id: Int
    let kind: OccurrenceKind
    let passenger: Int?
    let row: Int
    let x: Double
    let y: Double
    let aisle: Int
    let steps: [Step]
    let fuse: Double
    let seed: Double
    var lavatory: Int?
    var vip = false
    /// Spills grow (1–3) when someone slips in them carrying drinks (GDD §5a).
    var size = 1
    var step = 0
    var age = 0.0
    var life = 0.0
    var state: Escalation = .calm
    var failed = false
    var dead = false

    init(id: Int, kind: OccurrenceKind, passenger: Int?, row: Int, x: Double, y: Double, aisle: Int,
         steps: [Step], fuse: Double, seed: Double) {
        self.id = id; self.kind = kind; self.passenger = passenger; self.row = row
        self.x = x; self.y = y; self.aisle = aisle; self.steps = steps; self.fuse = fuse; self.seed = seed
    }

    var need: Step { steps[min(step, steps.count - 1)] }
    var remaining: Double { max(0, min(1, 1 - age / fuse)) }
}

/// The drink trolley working its way down the aisle during service.
struct ServiceCart: Equatable {
    var x: Double
    let aisle: Int
    var dir = 1.0
    var pause = 0.0
    var nextRow = 0
    var stuck = false
    var active = true
}

enum MachineState: Equatable { case idle, working(left: Double), ready }

/// Twist: a trainee who answers call buttons on their own, slowly (GDD §6a).
struct Helper: Equatable {
    var x: Double
    var aisle = 0
    var target: Int?
    var busy = 0.0
    var face = 1.0
    var walk = 0.0
}

enum Phase: Equatable { case boarding, cruise, landing, ended }

enum TargetAction: Equatable {
    case none
    case bin(Int)
    case clear(occurrence: Int)          // mop, shut a bin, stow a bag, push/fix the cart, plunge
    case seat(row: Int, seat: Int)
    case jumpSeat(Int)
}

struct CrewTarget: Equatable {
    var x: Double
    var aisle = 0
    var action: TargetAction
}

enum BusyTask: Equatable {
    case pick(bin: Int)
    case apply(occurrence: Int)
    case buckle(seat: Int)
    case unbuckle
    case knockedDown
}

struct BusyAction: Equatable {
    var t = 0.0
    let duration: Double
    let task: BusyTask
    var progress: Double { min(1, t / duration) }
}

struct Crew {
    var x = 120.0
    var y = 180.0
    var aisle = 0
    var target: CrewTarget?
    var queued: CrewTarget?
    var busy: BusyAction?
    /// What's on the tray (up to Tuning.trayCapacity).
    var tray: [Item] = []
    /// Buckled into this jump seat (GDD §5b).
    var seated: Int?
    /// Seconds left before each hot item on the tray goes cold (one entry per hot item, any order).
    var warmth: [(item: Item, left: Double)] = []
    var stumbleTimer = 0.0
    var face = -1.0
    var walk = 0.0
    var wading = false
    var squeezing = false
    var slowedBy: OccurrenceKind?
    var bubble: String?
    var bubbleTime = 0.0
    var isMoving: Bool { target != nil && busy == nil }
    var hasFreeHand: Bool { tray.count < Tuning.trayCapacity }
    /// Convenience for single-item cases: the first thing on the tray; setting replaces the tray.
    var held: Item? {
        get { tray.first }
        set { tray = newValue.map { [$0] } ?? [] }
    }
}

struct FlightStats {
    var resolved = 0
    var failed = 0
    var woken = 0
    var ordersMissed = 0
    var crewStumbles = 0
    var vipFailed = false
    var fixTimes: [Double] = []
    var averageFix: Double? { fixTimes.isEmpty ? nil : fixTimes.reduce(0, +) / Double(fixTimes.count) }
}

enum SimEvent: Equatable {
    case spawned(OccurrenceKind, x: Double, y: Double)
    case stepDone(x: Double, y: Double)
    case resolved(x: Double, y: Double, bonus: Int, passenger: Int?)
    case failed(x: Double, y: Double, penalty: Int)
    case mopped(x: Double, y: Double)
    case picked
    case trashed
    case machineReady(station: Int)
    case nope
    case phase(Phase)
    case toast(String)
    case seatbelt(on: Bool)
    case turbulence(intensity: Double)     // 0 = calm again
    case stumble(x: Double, y: Double)
    case crewStumble(x: Double, y: Double)
    case slipped(x: Double, y: Double)
    case wentCold
    case buckled(Bool)
    case wokeUp(x: Double, y: Double)
    case cart(out: Bool)
}

final class FlightSimulation {
    private(set) var t = 0.0
    private(set) var phase: Phase = .boarding
    private(set) var passengers: [Passenger] = []
    private(set) var occurrences: [Occurrence] = []
    private(set) var satisfaction = Tuning.startingSatisfaction
    private(set) var stats = FlightStats()
    private(set) var running = false
    let plan: FlightPlan
    let layout: CabinLayout
    private(set) var turbulence: Turbulence = .none
    private(set) var lavatoryUses = 0
    private(set) var lavUsesSinceClog: [Int: Int] = [:]
    private(set) var cart: ServiceCart?
    private(set) var machines: [Int: MachineState] = [:]
    private(set) var helper: Helper?
    private(set) var mealServiceOn = false
    var crew = Crew()
    /// Set from the plan; tests switch them off to keep older scenarios deterministic.
    var turbulenceSchedule: [TurbulenceBump]
    var strollsEnabled: Bool
    var sleepEnabled: Bool
    var cartMode: CartMode

    private var spawnTimer = 1.0
    private var script: [OccurrenceKind]
    private var hinted = Set<String>()
    private var nextID = 1
    private var bagQueue: [Int] = []           // sick occurrences whose used bag is on the tray
    private var deferredSpawns = 0             // problems held back while the cabin is strapped in
    private var carryOnsLeft = 0               // boarding rush: bags still to be dropped in the aisle
    private var rng: SplitMix64
    private var events: [SimEvent] = []

    init(plan: FlightPlan = .prototype, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.plan = plan
        layout = plan.aircraft.layout
        script = plan.script
        turbulenceSchedule = plan.turbulence
        strollsEnabled = plan.strolls
        sleepEnabled = plan.dozing
        cartMode = plan.cart
        rng = SplitMix64(seed: seed)
        crew.y = layout.aisles[0]
        let bias = plan.story.bias
        let weights = Archetype.allCases.map { bias[$0] ?? 1 }
        var id = 0
        for (ri, row) in layout.rows.enumerated() {
            for (si, spot) in row.seats.enumerated() where random() < Tuning.occupancy {
                let arch = Archetype.allCases[pickWeighted(weights)]
                var p = Passenger(
                    id: id, row: ri, seat: si, x: row.x, y: spot.y, aisle: spot.aisle, reach: spot.reach,
                    isWindow: spot.window, premium: row.premium, label: "\(row.number)\(spot.letter)", archetype: arch,
                    skin: randomInt(5), hair: randomInt(6), hairStyle: randomInt(3),
                    hasKid: arch == .family && !row.premium && random() < 0.6, phase: random() * 10)
                p.asleep = arch == .sleeper || (plan.twist == .redEye && random() < Tuning.redEyeAsleep)
                passengers.append(p)
                id += 1
            }
        }
        if plan.story.vip, !passengers.isEmpty {
            let pool = passengers.indices.filter { passengers[$0].premium }
            let candidates = pool.isEmpty ? passengers.indices.filter { passengers[$0].reach == 0 && !passengers[$0].hasKid } : pool
            if let v = candidates.isEmpty ? nil : candidates[randomInt(candidates.count)] {
                passengers[v].vip = true
                passengers[v].asleep = false
            }
        }
        if plan.twist == .helper { helper = Helper(x: layout.lastRowX, aisle: 0) }
    }

    var stars: Int { Tuning.stars(for: satisfaction) }
    var timeRemaining: Double { max(0, plan.duration - t) }
    var liveOccurrences: [Occurrence] { occurrences.filter { !$0.dead } }
    var seatbeltOn: Bool { turbulence != .none }
    var turbulenceIntensity: Double { if case .active(let i) = turbulence { return i }; return 0 }
    var strollerCount: Int { passengers.filter { $0.stroll != nil }.count }
    var vipIndex: Int? { passengers.firstIndex { $0.vip } }

    /// Whether this flight's bonus goal was met (GDD §6a). Evaluated after landing.
    var goalMet: Bool {
        switch plan.goal {
        case .noMisses: return stats.failed == 0
        case .noneWoken: return stats.woken == 0
        case .serveAllOrders: return stats.ordersMissed == 0
        case .vipHappy: return !stats.vipFailed
        case .quickService: return (stats.averageFix ?? 99) < 10 && stats.resolved >= 4
        case .highScore(let s): return satisfaction >= Double(s)
        case .seatedEveryBump: return stats.crewStumbles == 0
        }
    }

    func drainEvents() -> [SimEvent] {
        defer { events.removeAll() }
        return events
    }

    // MARK: - Flow

    func start() {
        running = true
        emitToast("Boarding. Tap the aisle to walk. Your tray carries two things at once.")
        if plan.twist == .boardingRush {
            spawn(.carryOn)                          // the rest follow one at a time while boarding
            carryOnsLeft = 2
            hint("carryOn", "Boarding rush! Carry-on bags are blocking the aisle. Tap them with a free hand to stow them.")
        }
        if plan.twist == .galleyClosed {
            hint("galleyClosed", "The forward galley is closed today. Supplies come from the middle and the back.")
        }
        let startX = plan.twist == .galleyClosed ? layout.firstRowX + 40 : 120
        if crew.seated != nil {
            // buckled in for the countdown: unbuckle on Go and walk to the start position (GDD §8b)
            crew.busy = BusyAction(duration: Tuning.unbuckleDuration, task: .unbuckle)
            crew.queued = CrewTarget(x: startX, aisle: 0, action: .none)
        } else {
            crew.x = startX
        }
    }

    func update(dt: Double) {
        guard running else { return }
        t += dt
        if phase == .boarding && t >= Tuning.boardingEnds {
            phase = .cruise
            events.append(.phase(.cruise))
            emitToast("Seatbelt sign off. Cruise. Keep an eye on the cabin.")
        }
        if phase == .cruise && t >= plan.landingAt {
            phase = .landing
            events.append(.phase(.landing))
            emitToast("Final approach. Clear what you can before touchdown.")
        }

        if carryOnsLeft > 0 && t >= Double(3 - carryOnsLeft) * 2 {
            carryOnsLeft -= 1
            spawn(.carryOn)
        }
        updateTurbulence()
        updateMealService()
        runDirector(dt: dt)
        updateCart(dt: dt)
        updateMachines(dt: dt)
        updateStrolls(dt: dt)
        updateSleep(dt: dt)

        let fuseDt = turbulenceIntensity > 0 ? dt * Tuning.turbulenceFuseRate : dt
        for i in occurrences.indices where !occurrences[i].dead && !occurrences[i].failed {
            occurrences[i].age += fuseDt
            occurrences[i].life += dt
            let f = occurrences[i].age / occurrences[i].fuse
            occurrences[i].state = Escalation.forFraction(f)
            if occurrences[i].state == .critical { satisfaction -= Tuning.criticalDrainPerSecond * dt }
            if occurrences[i].kind == .baby { satisfaction -= Tuning.babyDrainPerSecond * dt }
            if occurrences[i].kind == .toilet { satisfaction -= Tuning.toiletDrainPerSecond * dt }
            if f >= 1 { fail(i) }
        }
        occurrences.removeAll { $0.dead }

        moveCrew(dt: dt)
        coolTray(dt: dt)
        moveHelper(dt: dt)
        occurrences.removeAll { $0.dead }
        satisfaction = min(100, max(0, satisfaction))

        if t >= plan.duration { endFlight() }
    }

    private var activeCount: Int { occurrences.filter { !$0.dead && !$0.failed }.count }

    private func runDirector(dt: Double) {
        guard phase == .cruise else { return }
        spawnTimer -= dt * (turbulenceIntensity > 0 ? Tuning.turbulenceSpawnBoost : 1)
        guard spawnTimer <= 0 else { return }
        if turbulenceIntensity > 0 {
            // everyone's strapped in: new problems wait and arrive as a rush when it clears (GDD §5b)
            deferredSpawns = min(2, deferredSpawns + 1)
            spawnTimer = random(in: Tuning.spawnInterval)
            return
        }
        let cap = plan.cap(at: t) + (mealServiceOn ? 1 : 0)
        if activeCount < cap {
            let kind = script.isEmpty ? rollKind() : script.removeFirst()
            if !spawn(kind), kind != .call { spawn(.call) }
            spawnTimer = random(in: Tuning.spawnInterval)
        } else {
            spawnTimer = 1
        }
    }

    /// Weighted pick among the kinds this flight allows; turbulence, drink service and meal service shift the odds.
    private func rollKind() -> OccurrenceKind {
        let shaking = turbulenceIntensity > 0
        let serving = cart?.active == true
        let all: [(kind: OccurrenceKind, weight: Double)] = [
            (.call, 0.5),
            (.drink, mealServiceOn ? 1.5 : 0.5),
            (.sick, shaking ? 0.7 : 0.35),
            (.spill, serving ? 0.4 : 0.25),
            (.baby, occurrences.contains { $0.kind == .baby && !$0.dead } ? 0 : 0.25),
            (.binJam, shaking ? 0.5 : 0.25)
        ]
        var weights: [(kind: OccurrenceKind, weight: Double)] = []
        var total = 0.0
        for w in all where plan.kinds.contains(w.kind) && w.weight > 0 { weights.append(w); total += w.weight }
        guard let last = weights.last else { return .call }
        var r = random() * total
        for w in weights { r -= w.weight; if r <= 0 { return w.kind } }
        return last.kind
    }

    private func endFlight() {
        for o in occurrences where !o.dead && !o.failed {
            satisfaction -= Tuning.unresolvedAtLandingPenalty
            stats.failed += 1
            if o.kind == .drink { stats.ordersMissed += 1 }
            if o.vip { stats.vipFailed = true }
        }
        satisfaction = min(100, max(0, satisfaction))
        running = false
        phase = .ended
        events.append(.phase(.ended))
    }

    // MARK: - Occurrences

    /// Seated, awake-or-not, free passengers who could have a new problem.
    private func freePassengers(_ extra: (Passenger) -> Bool = { _ in true }) -> [Int] {
        let taken = Set(occurrences.filter { !$0.dead }.compactMap { $0.passenger })
        return passengers.indices.filter {
            !taken.contains($0) && !passengers[$0].grumpy && passengers[$0].stroll == nil && extra(passengers[$0])
        }
    }

    @discardableResult
    func spawn(_ kind: OccurrenceKind) -> Bool {
        switch kind {
        case .sick:
            let candidates = freePassengers()
            guard !candidates.isEmpty else { return false }
            let pi = candidates[randomInt(candidates.count)]
            addSick(passenger: pi)
            let p = passengers[pi]
            events.append(.spawned(.sick, x: p.x, y: p.y))
            hint("sick", "\(p.label) is feeling sick. Their icon shows what they need next, one step at a time.")
            curtainHint(p)
        case .call, .drink:
            let candidates = freePassengers { !$0.asleep }
            guard !candidates.isEmpty else { return false }
            // business travellers press the button and order more
            let pi = candidates[pickWeighted(candidates.map { passengers[$0].archetype == .business ? 2.5 : 1 })]
            let p = passengers[pi]
            if kind == .call {
                addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 16)
                hint("call", "Call button at \(p.label). Walk over and tap them. It just needs a free hand.")
            } else {
                addAtSeat(.drink, passenger: pi, steps: [.order, orderStep()], fuse: 26)
                hint("drink", "Someone wants to order. Walk over and take their order, then the icon shows what to bring.")
            }
            events.append(.spawned(kind, x: p.x, y: p.y))
            curtainHint(p)
        case .baby:
            let candidates = freePassengers { $0.hasKid }
            guard !candidates.isEmpty else { return false }
            let pi = candidates[randomInt(candidates.count)]
            addAtSeat(.baby, passenger: pi, steps: [.item(.toy)], fuse: 26)
            events.append(.spawned(.baby, x: passengers[pi].x, y: passengers[pi].y))
            hint("baby", "A baby is crying and keeping the rows around them awake. Check the icon for what will calm them.")
        case .spill, .binJam, .carryOn:
            var candidates: [(Int, Int)] = []
            for r in 1..<layout.rows.count { for a in layout.aisles.indices where obstacleAllowed(row: r, aisle: a) { candidates.append((r, a)) } }
            guard !candidates.isEmpty else { return false }
            let (row, aisle) = candidates[randomInt(candidates.count)]
            let n = layout.rows[row].number
            switch kind {
            case .spill:
                addSpill(row: row, aisle: aisle)
                hint("spill", "Spilled drink at row \(n). It slows everyone down, so grab a towel and tap the spill.")
            case .binJam:
                addBinJam(row: row, aisle: aisle)
                hint("binJam", "An overhead bin popped open at row \(n). Tap it with a free hand to shut it.")
            default:
                addAisle(.carryOn, row: row, aisle: aisle, steps: [.hands], fuse: 25)
            }
            events.append(.spawned(kind, x: layout.rows[row].x, y: layout.aisles[aisle]))
        case .toilet:
            return false          // triggered by lavatory use, not rolled
        case .stuckCart, .brokenCart:
            guard var c = cart, c.active, !c.stuck else { return false }
            c.stuck = true
            cart = c
            let row = layout.nearestRow(toX: c.x)
            let steps: [Step] = kind == .stuckCart ? [.hands] : [.item(.tool)]
            let fuse = kind == .stuckCart ? 20.0 : 24.0
            add(Occurrence(id: nextID, kind: kind, passenger: nil, row: row, x: c.x, y: layout.aisles[c.aisle], aisle: c.aisle,
                           steps: steps, fuse: fuse, seed: random() * 6))
            events.append(.spawned(kind, x: c.x, y: layout.aisles[c.aisle]))
            if kind == .stuckCart {
                hint("stuckCart", "The drink cart is stuck! Tap it with a free hand to push it free.")
            } else {
                hint("brokenCart", "The drink cart broke down. The icon shows what fixes it.")
            }
        }
        return true
    }

    /// What a drink/meal order asks for: one item from the flight's menu, or a combo on later flights.
    private func orderStep() -> Step {
        var menu = plan.menu.filter { item in
            layout.bins.enumerated().contains { i, b in b.item == item && stationOpen(i) }
        }
        if menu.isEmpty { menu = [.water] }
        let first = menu[randomInt(menu.count)]
        if plan.combos, random() < 0.35 {
            let sides = menu.filter { $0 != first }
            if !sides.isEmpty { return .combo([first, sides[randomInt(sides.count)]]) }
        }
        return .item(first)
    }

    private func curtainHint(_ p: Passenger) {
        if p.premium {
            hint("curtain", "Premium passengers are behind the curtain. You'll only see their problems once they get urgent, unless you're up front.")
        }
    }

    private func obstacleAllowed(row r: Int, aisle a: Int) -> Bool {
        let taken = occurrences.filter { !$0.kind.atSeat && !$0.dead && $0.aisle == a }.map { $0.row }
        let x = layout.rows[r].x
        return !taken.contains { abs($0 - r) <= 1 }
            && !(a == crew.aisle && abs(x - crew.x) < 60)
            && !(cart.map { $0.aisle == a && abs($0.x - x) < 60 } ?? false)
    }

    private func add(_ o: Occurrence) {
        var o = o
        if let pi = o.passenger, passengers[pi].vip { o.vip = true }
        occurrences.append(o)
        nextID += 1
    }

    private func fuse(_ base: Double, passenger pi: Int?) -> Double {
        guard let pi, passengers[pi].vip else { return base }
        return base * Tuning.vipFuseScale
    }

    @discardableResult
    func addSick(passenger pi: Int, step: Int = 0, age: Double = 0) -> Int {
        passengers[pi].sick = true
        passengers[pi].asleep = false
        let p = passengers[pi]
        var o = Occurrence(id: nextID, kind: .sick, passenger: pi, row: p.row, x: p.x, y: p.y, aisle: p.aisle,
                           steps: [.item(.towel), .trash, .item(.water)], fuse: fuse(30, passenger: pi), seed: random() * 6)
        o.step = step; o.age = age; o.life = age
        o.state = Escalation.forFraction(age / o.fuse)
        add(o)
        return o.id
    }

    @discardableResult
    func addAtSeat(_ kind: OccurrenceKind, passenger pi: Int, steps: [Step], fuse base: Double, age: Double = 0) -> Int {
        let p = passengers[pi]
        if kind == .baby { passengers[pi].asleep = false }
        var o = Occurrence(id: nextID, kind: kind, passenger: pi, row: p.row, x: p.x, y: p.y, aisle: p.aisle,
                           steps: steps, fuse: fuse(base, passenger: pi), seed: random() * 6)
        o.age = age; o.life = age
        o.state = Escalation.forFraction(age / o.fuse)
        add(o)
        return o.id
    }

    @discardableResult
    func addSpill(row: Int, aisle: Int = 0, age: Double = 0) -> Int {
        addAisle(.spill, row: row, aisle: aisle, steps: [.item(.towel)], fuse: 22, age: age)
    }

    @discardableResult
    func addBinJam(row: Int, aisle: Int = 0, age: Double = 0) -> Int {
        addAisle(.binJam, row: row, aisle: aisle, steps: [.hands], fuse: 20, age: age)
    }

    @discardableResult
    func addAisle(_ kind: OccurrenceKind, row: Int, aisle: Int, steps: [Step], fuse: Double, age: Double = 0) -> Int {
        var o = Occurrence(id: nextID, kind: kind, passenger: nil, row: row, x: layout.rows[row].x, y: layout.aisles[aisle],
                           aisle: aisle, steps: steps, fuse: fuse, seed: random() * 6)
        o.age = age; o.life = age
        o.state = Escalation.forFraction(age / o.fuse)
        add(o)
        return o.id
    }

    /// A lavatory clogs after a few visits (GDD §5a); walkers can't use it until it's plunged.
    @discardableResult
    func clog(lavatory li: Int) -> Int {
        let lav = layout.lavatories[li]
        var o = Occurrence(id: nextID, kind: .toilet, passenger: nil, row: layout.nearestRow(toX: lav.doorX), x: lav.doorX,
                           y: layout.aisles[lav.aisle], aisle: lav.aisle, steps: [.item(.plunger)], fuse: 30, seed: random() * 6)
        o.lavatory = li
        add(o)
        lavUsesSinceClog[li] = 0
        events.append(.spawned(.toilet, x: lav.doorX, y: layout.aisles[lav.aisle]))
        hint("toilet", "A lavatory is clogged! Nobody can use it until it's fixed. The icon shows what you need.")
        return o.id
    }

    func isClogged(_ li: Int) -> Bool { occurrences.contains { $0.kind == .toilet && !$0.dead && $0.lavatory == li } }

    private func fail(_ i: Int) {
        stats.failed += 1
        let o = occurrences[i]
        if o.kind == .drink { stats.ordersMissed += 1 }
        if o.vip { stats.vipFailed = true }
        let penalty = o.kind.penalty * (o.vip ? 2 : 1)
        satisfaction -= penalty
        events.append(.failed(x: o.x, y: o.y, penalty: Int(penalty)))
        if o.kind.lingers {
            // Obstacles and clogs stay put (and keep causing trouble) until someone clears them.
            occurrences[i].failed = true
            occurrences[i].state = .failed
        } else {
            if let pi = o.passenger { passengers[pi].sick = false; passengers[pi].grumpy = true }
            occurrences[i].dead = true
        }
    }

    /// Completes the current step of an occurrence; consumes what it used from the tray.
    private func applyStep(occurrence id: Int) {
        guard let i = occurrences.firstIndex(where: { $0.id == id }), !occurrences[i].dead else { return }
        switch occurrences[i].need {
        case .item(let it): take(it)
        case .combo(let items): items.forEach(take)
        case .hands, .trash, .order: break
        }
        let o = occurrences[i]
        if o.kind.isCart { cart?.stuck = false }
        if o.failed {
            occurrences[i].dead = true
            satisfaction += 1
            events.append(.mopped(x: o.x, y: o.y))
            return
        }
        occurrences[i].step += 1
        if occurrences[i].step >= o.steps.count {
            occurrences[i].dead = true
            let base: Double = o.kind == .call ? 3 : 6
            let speed: Double = o.kind == .call ? 2 : 4
            var bonus = base + (speed * min(1, max(0, 1 - o.life / (o.fuse * 1.6)))).rounded()
            if o.vip { bonus = (bonus * 1.5).rounded() }
            satisfaction += bonus
            stats.resolved += 1
            stats.fixTimes.append(o.life)
            if let pi = o.passenger { passengers[pi].sick = false }
            events.append(.resolved(x: o.x, y: o.y, bonus: Int(bonus), passenger: o.passenger))
        } else {
            occurrences[i].age *= Tuning.stepRelief       // each completed step buys back time
            if occurrences[i].need == .trash {
                // the passenger hands over the used bag: it fills a hand until it's binned
                crew.tray.append(.usedBag)
                bagQueue.append(o.id)
                say("Got the bag")
                hint("bag", "You're carrying the used sick bag. Throw it in a trash bin, then bring the passenger water.")
            }
            events.append(.stepDone(x: o.x, y: o.y))
        }
    }

    private func take(_ item: Item) {
        if let k = crew.tray.firstIndex(of: item) { crew.tray.remove(at: k) }
    }

    private func use(on id: Int, duration: Double) {
        guard let o = occurrences.first(where: { $0.id == id && !$0.dead }) else { return }
        switch o.need {
        case .hands:
            guard crew.hasFreeHand else {
                say("Hands full!")
                hint("hands", "That needs a free hand. Put something back at a galley bin or throw it in the trash.")
                events.append(.nope)
                return
            }
        case .trash:
            say("Bin the bag first")
            events.append(.nope)
            return
        case .order:
            break                               // taking an order needs nothing
        case .item(let need):
            guard crew.tray.contains(need) else {
                if let cold = need.cold, crew.tray.contains(cold) { goneCold(); return }
                missing([need]); return
            }
        case .combo(let items):
            var tray = crew.tray
            for it in items {
                guard let k = tray.firstIndex(of: it) else {
                    if let cold = it.cold, tray.contains(cold) { goneCold(); return }
                    missing(items); return
                }
                tray.remove(at: k)
            }
        }
        crew.busy = BusyAction(duration: duration, task: .apply(occurrence: id))
    }

    private func goneCold() {
        say("It's gone cold!")
        hint("cold", "Hot drinks and meals go cold on your tray. Bin a cold one and make it fresh.")
        events.append(.nope)
    }

    /// Hot items on the tray count down and turn cold (GDD §6a). Tokens are matched to the tray every frame,
    /// so any way an item leaves the tray (served, binned, dropped) also drops its timer.
    private func coolTray(dt: Double) {
        for item in [Item.coffee, .meal] {
            let onTray = crew.tray.filter { $0 == item }.count
            var tokens = crew.warmth.filter { $0.item == item }.sorted { $0.left > $1.left }
            while tokens.count > onTray { tokens.removeLast() }                  // left the tray: drop the coldest
            while tokens.count < onTray { tokens.insert((item, item.keepsHotFor ?? 20), at: 0) }   // fresh from the machine
            crew.warmth.removeAll { $0.item == item }
            for t in tokens {
                let left = t.left - dt
                if left <= 0, let k = crew.tray.firstIndex(of: item), let cold = item.cold {
                    crew.tray[k] = cold
                    events.append(.wentCold)
                    hint("cold", "Your \(item.displayName.lowercased()) went cold. Passengers won't take it: bin it and make a fresh one.")
                } else {
                    crew.warmth.append((item, left))
                }
            }
        }
    }

    /// How hot the k-th item on the tray still is, 0…1 (nil if it isn't a hot item).
    func warmth(ofTraySlot k: Int) -> Double? {
        guard k < crew.tray.count else { return nil }
        let item = crew.tray[k]
        guard let full = item.keepsHotFor else { return nil }
        let nth = crew.tray[..<k].filter { $0 == item }.count
        let tokens = crew.warmth.filter { $0.item == item }.sorted { $0.left > $1.left }
        return nth < tokens.count ? max(0, tokens[nth].left / full) : 1
    }

    private func missing(_ items: [Item]) {
        let names = items.map { $0.displayName.lowercased() }.joined(separator: " + ")
        say(crew.tray.isEmpty ? "Bring \(names)" : "Needs \(names)")
        events.append(.nope)
    }

    /// True while a premium passenger's problem is still calm and the crew is outside the premium cabin:
    /// the curtain hides it (GDD §4a N737-Swift). The icon appears once it gets urgent.
    func isBehindCurtain(_ o: Occurrence) -> Bool {
        guard let pi = o.passenger, passengers[pi].premium, o.state == .calm, let curtain = layout.curtainX else { return false }
        return crew.x > curtain
    }

    // MARK: - Galley stations

    /// The forward galley is shut on "galley closed" flights (GDD §6a).
    func stationOpen(_ i: Int) -> Bool {
        guard plan.twist == .galleyClosed else { return true }
        return layout.bins[i].x > 215
    }

    private func updateMachines(dt: Double) {
        for (i, m) in machines {
            if case .working(let left) = m {
                if left - dt <= 0 {
                    machines[i] = .ready
                    events.append(.machineReady(station: i))
                } else {
                    machines[i] = .working(left: left - dt)
                }
            }
        }
    }

    // MARK: - Drink service cart

    private func updateCart(dt: Double) {
        guard cartMode != .none else { return }
        let f = t / plan.duration
        if cart == nil, phase == .cruise, Tuning.cartWindow.contains(f) {
            cart = ServiceCart(x: layout.firstRowX - 40, aisle: 0)
            events.append(.cart(out: true))
            hint("cart", "Drink service! The cart fills the aisle, so squeezing past it is slow. More drinks means more spills.")
        }
        guard var c = cart, c.active else { return }
        if c.stuck || seatbeltOn { return }          // the cart parks while the seatbelt sign is on
        let heading = f > Tuning.cartWindow.upperBound || phase != .cruise
        if heading { c.dir = -1 }
        if c.pause > 0 {
            c.pause -= dt
        } else {
            let rows = layout.rows
            let target: Double
            if c.dir > 0 && c.nextRow < rows.count {
                target = rows[c.nextRow].x
            } else {
                c.dir = -1
                target = layout.firstRowX - 40
            }
            // the crew in the way holds the cart up
            let blocked = crew.aisle == c.aisle && abs(crew.y - layout.aisles[c.aisle]) < 1
                && (crew.x - c.x) * c.dir > 0 && abs(crew.x - c.x) < 30
            if !blocked {
                let d = target - c.x
                if abs(d) <= Tuning.cartSpeed * dt {
                    c.x = target
                    if c.dir > 0 { c.nextRow += 1; c.pause = Tuning.cartServePause }
                    else { c.active = false; events.append(.cart(out: false)) }
                } else {
                    c.x += (d < 0 ? -1 : 1) * Tuning.cartSpeed * dt
                }
            }
            if c.active && !heading && cartMode != .service && activeCount < plan.cap(at: t)
                && random() < Tuning.cartTroubleChancePerSecond * dt {
                cart = c
                spawn(cartMode == .breaks ? .brokenCart : .stuckCart)
                return
            }
        }
        cart = c
    }

    // MARK: - Twists

    private func updateMealService() {
        guard plan.twist == .mealService else { return }
        let on = phase == .cruise && Tuning.mealServiceWindow.contains(t / plan.duration)
        if on && !mealServiceOn {
            emitToast("Meal service! Expect a rush of drink and meal orders. Use the coffee machine and oven early.")
        }
        mealServiceOn = on
    }

    /// The trainee answers call buttons on their own, slowly (GDD §6a).
    private func moveHelper(dt: Double) {
        guard var h = helper else { return }
        if h.busy > 0 {
            h.busy -= dt
            if h.busy <= 0, let id = h.target {
                if let i = occurrences.firstIndex(where: { $0.id == id && !$0.dead }) {
                    occurrences[i].dead = true
                    satisfaction += 2
                    stats.resolved += 1
                    events.append(.resolved(x: occurrences[i].x, y: occurrences[i].y, bonus: 2, passenger: occurrences[i].passenger))
                }
                h.target = nil
            }
            helper = h
            return
        }
        if h.target == nil || !occurrences.contains(where: { $0.id == h.target && !$0.dead }) {
            h.target = occurrences.filter { $0.kind == .call && !$0.dead && !$0.failed && $0.aisle == h.aisle }
                .min { abs($0.x - h.x) < abs($1.x - h.x) }?.id
        }
        if let id = h.target, let o = occurrences.first(where: { $0.id == id }) {
            let d = o.x - h.x
            let step = Tuning.helperSpeed * dt
            if abs(d) <= step { h.x = o.x; h.busy = 0.8 }
            else { h.x += d < 0 ? -step : step; h.face = d < 0 ? -1 : 1; h.walk += dt * 10 }
        }
        helper = h
    }

    // MARK: - Turbulence

    private func updateTurbulence() {
        var next: Turbulence = .none
        if phase == .cruise {
            for b in turbulenceSchedule {
                if t >= b.start - b.warningTime && t < b.start { next = .warning }
                if t >= b.start && t < b.start + b.duration { next = .active(intensity: b.intensity) }
            }
        }
        guard next != turbulence else { return }
        let previous = turbulence
        turbulence = next
        switch next {
        case .warning:
            events.append(.seatbelt(on: true))
            emitToast("Cabin crew, take your seats! Tap a jump seat (they light up) before the turbulence hits.")
            sendStrollersBack()
        case .active(let intensity):
            if previous == .none { events.append(.seatbelt(on: true)) }
            events.append(.turbulence(intensity: intensity))
            stumbleStandingPassengers()
            sendStrollersBack()
            if crew.seated == nil && !isBuckling { crewStumble() }
        case .none:
            events.append(.turbulence(intensity: 0))
            events.append(.seatbelt(on: false))
            if crew.seated != nil { emitToast("All clear. Tap anywhere to unbuckle and get back to work.") }
            // the problems that waited arrive now
            for _ in 0..<deferredSpawns { spawn(rollKind()) }
            deferredSpawns = 0
            spawnTimer = random(in: Tuning.spawnInterval)
        }
    }

    private var isBuckling: Bool { if case .buckle? = crew.busy?.task { return true }; return false }

    /// Caught standing when turbulence hits: drinks spill, the tray drops, a knock-down (GDD §5b).
    private func crewStumble() {
        stats.crewStumbles += 1
        satisfaction -= Tuning.crewStumblePenalty
        crew.stumbleTimer = Tuning.crewStumbleEvery
        let spilled = crew.tray.contains { Item.liquids.contains($0) }
        crew.tray.removeAll { $0 != .usedBag }            // the tied-off bag stays in hand
        crew.target = nil; crew.queued = nil
        crew.busy = BusyAction(duration: Tuning.crewKnockdown, task: .knockedDown)
        events.append(.crewStumble(x: crew.x, y: crew.y))
        if spilled {
            let row = layout.nearestRow(toX: crew.x)
            if !occurrences.contains(where: { $0.kind.slows && !$0.dead && $0.aisle == crew.aisle && abs($0.row - row) <= 1 }) {
                addSpill(row: row, aisle: crew.aisle)
                events.append(.spawned(.spill, x: layout.rows[row].x, y: layout.aisles[crew.aisle]))
            }
        }
        say("Whoa!")
        hint("crewStumble", "You weren't seated! Get to a jump seat: you'll keep stumbling until you buckle in.")
    }

    private func stumbleStandingPassengers() {
        for i in passengers.indices {
            guard let s = passengers[i].stroll, s.inAisle else { continue }
            events.append(.stumble(x: s.x, y: s.y))
            let row = max(1, layout.nearestRow(toX: s.x))
            let aisle = passengers[i].aisle
            if random() < Tuning.stumbleSpillChance && obstacleAllowed(row: row, aisle: aisle) {
                addSpill(row: row, aisle: aisle)
                events.append(.spawned(.spill, x: layout.rows[row].x, y: layout.aisles[aisle]))
                hint("stumble", "Someone was still standing when the turbulence hit, and their drink went flying.")
            }
        }
    }

    // MARK: - Dozing and noise

    /// How loud an occurrence is, in rows: a crying baby is loud from the start; others once urgent.
    func noiseLevel(_ o: Occurrence) -> Int {
        guard o.passenger != nil, !o.dead, !o.failed, o.kind != .call else { return 0 }
        var rows = o.kind == .baby ? max(1, Tuning.noiseRows(o.state)) : Tuning.noiseRows(o.state)
        if rows > 0 && plan.twist == .redEye { rows += 1 }        // noise carries further at night
        return rows
    }

    private func updateSleep(dt: Double) {
        guard sleepEnabled || plan.twist == .redEye else { return }
        if phase == .cruise && !seatbeltOn {
            let chance = Tuning.dozeChancePerSecond * (plan.twist == .redEye ? 3 : 1)
            for i in passengers.indices where !passengers[i].asleep && passengers[i].stroll == nil && !passengers[i].vip
                && !passengers[i].sick && !passengers[i].grumpy && random() < chance * dt {
                passengers[i].asleep = true
            }
        }
        for o in occurrences {
            let rows = noiseLevel(o)
            guard rows > 0 else { continue }
            for i in passengers.indices where passengers[i].asleep && abs(passengers[i].row - o.row) <= rows {
                passengers[i].asleep = false
                satisfaction -= Tuning.wakePenalty
                stats.woken += 1
                events.append(.wokeUp(x: passengers[i].x, y: passengers[i].y))
                hint("woke", "Unattended passengers get noisy and wake the people sleeping around them.")
            }
        }
    }

    // MARK: - Aisle traffic

    private func updateStrolls(dt: Double) {
        if strollsEnabled && phase == .cruise && !seatbeltOn && strollerCount < Tuning.maxStrollers
            && random() < Tuning.strollChancePerSecond * dt {
            startStroll()
        }
        let hurry = seatbeltOn ? Tuning.hurryFactor : 1
        let walk = Tuning.paxWalkSpeed * hurry * (turbulenceIntensity > 0 ? Tuning.turbulenceCrewFactor : 1)
        for i in passengers.indices {
            guard var s = passengers[i].stroll else { continue }
            let home = passengers[i]
            switch s.stage {
            case .leaving:
                if approach(&s.y, s.laneY, Tuning.paxStepSpeed * hurry * dt) { s.stage = .walking }
            case .walking, .returning:
                let d = s.targetX - s.x
                if d != 0 { s.face = d < 0 ? -1 : 1 }
                if approach(&s.x, s.targetX, walk * dt) {
                    if s.stage == .returning {
                        s.stage = .sitting
                    } else {
                        s.stage = .dwelling
                        switch s.purpose {
                        case .lavatory(let li):
                            if isClogged(li) {
                                s.dwell = 1.5                   // turns back, annoyed
                            } else {
                                s.dwell = random(in: Tuning.lavDwell); s.inLavatory = true; lavatoryUses += 1
                                lavUsesSinceClog[li, default: 0] += 1
                                if plan.kinds.contains(.toilet), lavUsesSinceClog[li, default: 0] >= Tuning.lavUsesBeforeClog,
                                   activeCount < plan.cap(at: t) + 1 {
                                    clog(lavatory: li)
                                }
                            }
                        case .chat(let partner):
                            s.dwell = random(in: Tuning.chatDwell)
                            s.face = passengers[partner].x < s.x ? -1 : 1
                        }
                    }
                }
            case .dwelling:
                if case .chat(let partner) = s.purpose {              // lean toward whoever they're talking to
                    let aisleY = layout.aisles[home.aisle]
                    _ = approach(&s.y, aisleY + (passengers[partner].y < aisleY ? -20 : 20), 30 * dt)
                }
                s.dwell -= dt
                if s.dwell <= 0 { s.inLavatory = false; s.stage = .returning; s.targetX = home.x }
            case .sitting:
                if approach(&s.y, home.y, Tuning.paxStepSpeed * hurry * dt) { passengers[i].stroll = nil; continue }
            }
            passengers[i].stroll = s
        }
    }

    private func startStroll() {
        let busy = Set(occurrences.filter { !$0.dead }.compactMap { $0.passenger })
        let candidates = passengers.indices.filter { i in
            let p = passengers[i]
            return p.stroll == nil && !p.sick && !p.grumpy && !p.asleep && !p.hasKid && !p.vip
                && !busy.contains(i) && !(p.aisle == crew.aisle && abs(p.x - crew.x) < 40)
        }
        guard !candidates.isEmpty else { return }
        let i = candidates[pickWeighted(candidates.map { passengers[$0].archetype == .chatterbox ? 2.5 : 1 })]
        let p = passengers[i]
        let lavs = layout.lavatories.indices.filter { layout.lavatories[$0].aisle == p.aisle && !isClogged($0) }
        let wantsChat = lavs.isEmpty || random() < (p.archetype == .chatterbox ? 0.8 : 0.4)
        var purpose: StrollPurpose
        var targetX: Double
        if let li = lavs.min(by: { abs(layout.lavatories[$0].doorX - p.x) < abs(layout.lavatories[$1].doorX - p.x) }) {
            purpose = .lavatory(li); targetX = layout.lavatories[li].doorX
        } else {
            purpose = .chat(partner: i); targetX = p.x
        }
        if wantsChat {
            let friends = passengers.indices.filter { j in
                let q = passengers[j]
                return j != i && q.aisle == p.aisle && q.stroll == nil && !q.sick
                    && abs(q.row - p.row) >= 2 && abs(q.row - p.row) <= 5
            }
            if !friends.isEmpty {
                let f = friends[randomInt(friends.count)]
                purpose = .chat(partner: f)
                targetX = passengers[f].x + (passengers[f].x < p.x ? 14 : -14)
            } else if lavs.isEmpty {
                return
            }
        }
        let aisleY = layout.aisles[p.aisle]
        let lane = aisleY + (p.y < aisleY ? -9 : 9)
        passengers[i].stroll = Stroll(purpose: purpose, stage: .leaving, x: p.x, y: p.y, targetX: targetX, laneY: lane,
                                      face: targetX < p.x ? -1 : 1)
    }

    private func sendStrollersBack() {
        for i in passengers.indices {
            guard var s = passengers[i].stroll else { continue }
            switch s.stage {
            case .leaving: s.stage = .sitting
            case .walking, .dwelling:
                if s.inLavatory { s.inLavatory = false; s.x = s.targetX }
                s.stage = .returning; s.targetX = passengers[i].x; s.y = s.laneY
            case .returning, .sitting: break
            }
            passengers[i].stroll = s
        }
    }

    /// Moves `value` toward `target` by at most `step`; true once it arrives.
    private func approach(_ value: inout Double, _ target: Double, _ step: Double) -> Bool {
        let d = target - value
        if abs(d) <= step { value = target; return true }
        value += d < 0 ? -step : step
        return false
    }

    func isSqueezing(at x: Double, aisle: Int = 0) -> Bool {
        passengers.contains { p in
            guard let s = p.stroll, s.inAisle, p.aisle == aisle else { return false }
            return abs(s.x - x) < Tuning.squeezeDistance
        }
    }

    // MARK: - Input

    /// World coordinates (y down).
    func tap(x: Double, y: Double) {
        guard running else { return }
        let target = target(forTapAt: x, y)
        if crew.seated != nil {
            if seatbeltOn { say("Stay seated!"); events.append(.nope); return }
            crew.busy = BusyAction(duration: Tuning.unbuckleDuration, task: .unbuckle)
            crew.queued = target
            return
        }
        if crew.busy != nil { crew.queued = target } else { crew.target = target }
    }

    /// Where a jump seat is drawn: at the edge of its aisle.
    func jumpSeatY(_ j: JumpSeat) -> Double { layout.aisles[j.aisle] - 30 }

    func nearestJumpSeat() -> Int? {
        layout.jumpSeats.indices.min { a, b in
            let ja = layout.jumpSeats[a], jb = layout.jumpSeats[b]
            return abs(ja.x - crew.x) + (ja.aisle == crew.aisle ? 0 : 400) < abs(jb.x - crew.x) + (jb.aisle == crew.aisle ? 0 : 400)
        }
    }

    func target(forTapAt x: Double, _ y: Double) -> CrewTarget {
        for (i, j) in layout.jumpSeats.enumerated() where abs(x - j.x) < 22 && abs(y - jumpSeatY(j)) < 18 {
            return CrewTarget(x: j.x, aisle: j.aisle, action: .jumpSeat(i))
        }
        for (i, b) in layout.bins.enumerated() where abs(x - b.x) < 18 && abs(y - b.y) < 40 {
            return CrewTarget(x: b.x, aisle: b.aisle, action: .bin(i))
        }
        for o in occurrences where !o.kind.atSeat && !o.dead
            && abs(x - o.x) < (o.kind.isCart ? 26 : 22) && abs(y - o.y) < 44 {
            let side = (crew.aisle == o.aisle ? crew.x : x) < o.x ? -1.0 : 1.0
            let stand = o.kind == .toilet ? o.x : o.x + side * reach(o)
            return CrewTarget(x: stand, aisle: o.aisle, action: .clear(occurrence: o.id))
        }
        for (ri, row) in layout.rows.enumerated() where abs(x - row.x) <= (row.premium ? 22 : 17) {
            for (si, spot) in row.seats.enumerated() where abs(y - spot.y) <= 22 {
                return CrewTarget(x: row.x, aisle: spot.aisle, action: .seat(row: ri, seat: si))
            }
        }
        return CrewTarget(x: min(layout.maxX, max(layout.minX, x)), aisle: layout.nearestAisle(toY: y), action: .none)
    }

    // MARK: - Crew

    func isWading(at x: Double, aisle: Int = 0) -> Bool {
        occurrences.contains { $0.kind == .spill && !$0.dead && $0.aisle == aisle && abs($0.x - x) < reach($0) }
    }

    /// How far along the aisle an obstacle reaches: bigger spills cover more floor.
    func reach(_ o: Occurrence) -> Double { Tuning.stopDistance * (1 + 0.5 * Double(o.size - 1)) }

    /// Walked into a spill with drinks on the tray: they splash out and the puddle grows (GDD §5a).
    private func slip() {
        guard let i = occurrences.indices.first(where: {
            occurrences[$0].kind == .spill && !occurrences[$0].dead && occurrences[$0].aisle == crew.aisle
                && abs(occurrences[$0].x - crew.x) < reach(occurrences[$0])
        }) else { return }
        crew.tray.removeAll { Item.liquids.contains($0) }
        occurrences[i].size = min(3, occurrences[i].size + 1)
        satisfaction -= 2
        say("Slipped!")
        events.append(.slipped(x: crew.x, y: crew.y))
        hint("slip", "You slipped and your drinks splashed out, so the spill got bigger. Mop spills before carrying drinks through.")
    }

    /// The slowest thing the crew is pushing through at x in their aisle: spills, open bins, bags, the cart.
    private func obstacleFactor(at x: Double, aisle: Int) -> (Double, OccurrenceKind?) {
        var factor = 1.0
        var cause: OccurrenceKind?
        for o in occurrences where o.kind.slows && !o.dead && o.aisle == aisle && abs(o.x - x) < reach(o) {
            let f = o.kind == .spill ? Tuning.wadingFactor : Tuning.binJamFactor
            if f < factor { factor = f; cause = o.kind }
        }
        if let c = cart, c.active, c.aisle == aisle, abs(c.x - x) < 26, Tuning.cartFactor < factor {
            factor = Tuning.cartFactor; cause = .stuckCart
        }
        return (factor, cause)
    }

    private func moveCrew(dt: Double) {
        if crew.bubble != nil {
            crew.bubbleTime -= dt
            if crew.bubbleTime <= 0 { crew.bubble = nil }
        }
        if crew.seated == nil && turbulenceIntensity > 0 && !isBuckling {
            crew.stumbleTimer -= dt                  // still standing: stumble every few seconds until seated
            if crew.stumbleTimer <= 0 && crew.busy?.task != .knockedDown { crewStumble() }
        }
        if var busy = crew.busy {
            busy.t += dt
            if busy.t >= busy.duration {
                crew.busy = nil
                complete(busy.task)
                if let q = crew.queued { crew.target = q; crew.queued = nil }
            } else {
                crew.busy = busy
            }
            return
        }
        if crew.seated != nil { return }                // buckled in: not going anywhere
        guard let target = crew.target else { return }
        let turbulent = turbulenceIntensity > 0 ? Tuning.turbulenceCrewFactor : 1

        // Changing aisle: walk to the nearest galley crossover, then step across.
        if target.aisle != crew.aisle, !layout.crossovers.isEmpty {
            let cx = layout.crossovers.min { abs($0 - crew.x) + abs($0 - target.x) < abs($1 - crew.x) + abs($1 - target.x) }!
            if abs(crew.x - cx) > 0.5 {
                walk(toward: cx, dt: dt, factor: turbulent)
            } else {
                let goalY = layout.aisles[target.aisle]
                if approach(&crew.y, goalY, Tuning.crossSpeed * turbulent * dt) { crew.aisle = target.aisle }
                crew.walk += dt * 12
                hint("cross", "Two aisles! You can only cross between them at a galley.")
            }
            return
        }
        let laneY = layout.aisles[crew.aisle]
        if crew.y != laneY { _ = approach(&crew.y, laneY, Tuning.crossSpeed * dt); return }

        // Obstacles never hard-block (that could trap the crew away from every towel); they slow instead.
        let (factor, cause) = obstacleFactor(at: crew.x, aisle: crew.aisle)
        let wading = cause == .spill
        if wading && !crew.wading && crew.tray.contains(where: { Item.liquids.contains($0) }) {
            slip()
        } else if wading && !crew.wading {
            say("Slippery!")
            hint("wade", "Wading through a spill is slow. Mop it with a towel from either end of the cabin.")
        }
        if cause != nil && cause != crew.slowedBy {
            if cause == .binJam || cause == .carryOn { say("Mind the bags!") }
            if cause == .stuckCart { say("Squeezing past the cart") }
        }
        crew.wading = wading
        crew.slowedBy = cause
        let squeezing = isSqueezing(at: crew.x, aisle: crew.aisle)
        if squeezing && !crew.squeezing && cause == nil { say("Excuse me!") }
        crew.squeezing = squeezing
        var speed = factor * turbulent
        if squeezing { speed *= Tuning.squeezeFactor }
        if walk(toward: target.x, dt: dt, factor: speed) {
            crew.target = nil
            arrive(target)
        }
    }

    /// Walks the crew along their aisle; true on arrival.
    @discardableResult
    private func walk(toward x: Double, dt: Double, factor: Double) -> Bool {
        let speed = Tuning.crewSpeed * factor
        let d = x - crew.x
        if abs(d) <= speed * dt { crew.x = x; return true }
        crew.x += (d < 0 ? -1 : 1) * speed * dt
        crew.face = d < 0 ? -1 : 1
        crew.walk += dt * 12
        return false
    }

    private func arrive(_ target: CrewTarget) {
        switch target.action {
        case .none:
            break
        case .bin(let i):
            crew.busy = BusyAction(duration: Tuning.pickDuration, task: .pick(bin: i))
        case .jumpSeat(let i):
            crew.busy = BusyAction(duration: Tuning.buckleDuration, task: .buckle(seat: i))
        case .clear(let id):
            guard let o = occurrences.first(where: { $0.id == id }) else { return }
            let d: Double
            switch o.kind {
            case .binJam, .carryOn: d = 0.8
            case .stuckCart: d = 1.2
            case .brokenCart, .toilet: d = 1.5
            default: d = 0.9 * Double(o.size)                 // bigger spills take longer to mop
            }
            use(on: id, duration: d)
        case .seat(let row, let seat):
            if let o = occurrences.first(where: { o in
                guard !o.dead, let pi = o.passenger else { return false }
                return passengers[pi].row == row && passengers[pi].seat == seat
            }), let pi = o.passenger {
                let quick = o.kind == .call || o.need == .order
                use(on: o.id, duration: quick ? Tuning.callDuration : seatDuration(passengers[pi]))
            }
        }
    }

    /// Aisle seats are quick; each seat further in takes longer (the Comet's window seat = 1 s).
    func seatDuration(_ p: Passenger) -> Double {
        if p.premium { return Tuning.aisleSeatDuration }
        if p.isWindow && p.reach == 1 { return Tuning.windowSeatDuration }
        return Tuning.aisleSeatDuration + Tuning.reachPerSeat * Double(p.reach)
    }

    private func complete(_ task: BusyTask) {
        switch task {
        case .pick(let i):
            useStation(i)
        case .apply(let id):
            applyStep(occurrence: id)
        case .buckle(let i):
            crew.seated = i
            crew.target = nil; crew.queued = nil
            events.append(.buckled(true))
            if seatbeltOn { say("Buckled in") }
        case .unbuckle:
            crew.seated = nil
            events.append(.buckled(false))
        case .knockedDown:
            break
        }
    }

    /// Bins hand out (or take back) an item; machines start, then hand over when ready; trash empties the tray.
    private func useStation(_ i: Int) {
        guard stationOpen(i) else { say("Galley closed"); events.append(.nope); return }
        switch layout.bins[i].kind {
        case .bin(let item):
            if let k = crew.tray.firstIndex(of: item) {
                crew.tray.remove(at: k)
                say("Put back")
            } else if crew.hasFreeHand {
                crew.tray.append(item)
            } else {
                say("Tray full!")
                hint("tray", "Your tray holds two things. Put one back or throw it away first.")
                events.append(.nope); return
            }
            events.append(.picked)
        case .machine(let item, let prep):
            switch machines[i] ?? .idle {
            case .idle:
                machines[i] = .working(left: prep)
                say(item == .coffee ? "Brewing…" : "Heating…")
                hint("machine", "Machines take a few seconds. Start one, go do something else, and come back when it's ready.")
                events.append(.picked)
            case .working:
                say("Not ready yet")
                events.append(.nope)
            case .ready:
                guard crew.hasFreeHand else { say("Tray full!"); events.append(.nope); return }
                crew.tray.append(item)
                machines[i] = .idle
                events.append(.picked)
            }
        case .trash:
            guard !crew.tray.isEmpty else { say("Nothing to throw"); events.append(.nope); return }
            let bags = crew.tray.filter { $0 == .usedBag }.count
            crew.tray.removeAll()
            events.append(.trashed)
            for _ in 0..<bags {
                guard !bagQueue.isEmpty else { break }
                let id = bagQueue.removeFirst()
                if let o = occurrences.first(where: { $0.id == id && !$0.dead }), o.need == .trash {
                    applyStep(occurrence: id)
                }
            }
        }
    }

    // MARK: - Helpers

    private func say(_ text: String) { crew.bubble = text; crew.bubbleTime = 1.6 }

    private func hint(_ key: String, _ text: String) {
        guard !hinted.contains(key) else { return }
        hinted.insert(key)
        emitToast(text)
    }

    private func emitToast(_ text: String) { events.append(.toast(text)) }

    func random() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }
    func random(in range: ClosedRange<Double>) -> Double { range.lowerBound + random() * (range.upperBound - range.lowerBound) }
    func randomInt(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
    private func pickWeighted(_ w: [Double]) -> Int {
        var r = random() * w.reduce(0, +)
        for (i, v) in w.enumerated() { r -= v; if r <= 0 { return i } }
        return w.count - 1
    }

    // MARK: - Staged states (menu backdrop, screenshots, tests)

    /// The idle cabin behind the menus: a sample of what play looks like.
    func stagePreview() {
        if let pi = passengers.firstIndex(where: { $0.row == 3 && $0.reach == 0 }) {
            addSick(passenger: pi, step: 0, age: 12)
        }
        if let pi = passengers.firstIndex(where: { $0.row == 8 && $0.reach == 1 }) {
            addAtSeat(.drink, passenger: pi, steps: [.item(.coffee)], fuse: 26, age: 5)
        }
        addSpill(row: min(6, layout.rows.count - 1), age: 4)
        crew.x = 150
        crew.tray = [.towel, .juice]
    }

    /// The attendant ends the intro buckled into the forward jump seat, and waits there through the countdown.
    func seatCrewForCountdown() {
        guard let i = layout.jumpSeats.indices.first(where: { layout.jumpSeats[$0].aisle == 0 }) else { return }
        let j = layout.jumpSeats[i]
        crew.x = j.x; crew.aisle = j.aisle; crew.y = layout.aisles[j.aisle]
        crew.seated = i
        crew.face = 1
    }

    /// Puts a passenger in the aisle (tests and staged scenes).
    func placeStroller(passenger i: Int, x: Double) {
        let p = passengers[i]
        let aisleY = layout.aisles[p.aisle]
        let lane = aisleY + (p.y < aisleY ? -9 : 9)
        let li = layout.lavatories.indices.last ?? 0
        passengers[i].stroll = Stroll(purpose: .lavatory(li), stage: .walking, x: x, y: lane,
                                      targetX: layout.lavatories.last?.doorX ?? x, laneY: lane, face: 1)
    }

    func setAsleep(_ i: Int, _ asleep: Bool) { passengers[i].asleep = asleep }

    /// Rolls the drink cart out now (tests).
    func rollOutCart(at x: Double? = nil, aisle: Int = 0) {
        cart = ServiceCart(x: x ?? layout.firstRowX, aisle: aisle)
    }

    /// A busy mid-flight moment (launch with `-demo`).
    func stageDemo() {
        running = true
        phase = .cruise
        t = 58
        spawnTimer = 6
        script = []
        hinted = ["sick", "spill", "wade", "drink", "call"]
        if let a = passengers.firstIndex(where: { $0.row == 2 && $0.reach == 0 }) { addSick(passenger: a, step: 1, age: 15) }
        if let b = passengers.firstIndex(where: { $0.row == 9 && $0.isWindow }) {
            addAtSeat(.drink, passenger: b, steps: [.combo([.coffee, .snack])], fuse: 26, age: 14)
        }
        if let c = passengers.firstIndex(where: { $0.row == 6 && $0.reach == 0 && !$0.sick }) {
            addAtSeat(.call, passenger: c, steps: [.hands], fuse: 16, age: 3)
        }
        let big = addSpill(row: 5, age: 6)
        if let i = occurrences.firstIndex(where: { $0.id == big }) { occurrences[i].size = 2 }
        if let w = passengers.firstIndex(where: { $0.row == 7 && $0.reach == 0 && $0.stroll == nil && !$0.sick }) {
            placeStroller(passenger: w, x: layout.rows[10].x)
        }
        crew.x = 300
        crew.face = 1
        crew.tray = [.coffee, .usedBag]
        crew.target = CrewTarget(x: layout.rows[5].x - Tuning.stopDistance, action: .none)
    }
}
