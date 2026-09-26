import XCTest
@testable import Turbulence

final class FlightSimulationTests: XCTestCase {
    private func runningSim(seed: UInt64 = 42, plan: FlightPlan = .prototype) -> FlightSimulation {
        let sim = FlightSimulation(plan: plan, seed: seed)
        sim.cartMode = .none
        sim.turbulenceSchedule = []
        sim.strollsEnabled = false
        sim.sleepEnabled = false
        sim.start()
        _ = sim.drainEvents()
        return sim
    }

    private func step(_ sim: FlightSimulation, seconds: Double, dt: Double = 1.0 / 60) {
        var t = 0.0
        while t < seconds { sim.update(dt: dt); t += dt }
    }

    private func flight(_ id: String) -> FlightPlan { Campaign.routes.flatMap(\.flights).first { $0.id == id }! }

    private func station(_ sim: FlightSimulation, _ kind: StationKind) -> SupplyBin {
        sim.layout.bins.first { $0.kind == kind }!
    }

    /// Walks to a station and uses it.
    private func use(_ sim: FlightSimulation, _ b: SupplyBin) {
        sim.crew.aisle = b.aisle
        sim.crew.y = sim.layout.aisles[b.aisle]
        sim.tap(x: b.x, y: b.y)
        step(sim, seconds: 3)
    }

    // MARK: Escalation

    func testEscalationThresholds() {
        XCTAssertEqual(Escalation.forFraction(0), .calm)
        XCTAssertEqual(Escalation.forFraction(0.449), .calm)
        XCTAssertEqual(Escalation.forFraction(0.45), .urgent)
        XCTAssertEqual(Escalation.forFraction(0.779), .urgent)
        XCTAssertEqual(Escalation.forFraction(0.78), .critical)
    }

    func testOccurrenceEscalatesThenFails() {
        let sim = runningSim()
        let pi = 0
        sim.addSick(passenger: pi)
        step(sim, seconds: 30 * 0.5)
        XCTAssertEqual(sim.occurrences.first?.state, .urgent)
        step(sim, seconds: 30 * 0.3)
        XCTAssertEqual(sim.occurrences.first?.state, .critical)
        step(sim, seconds: 30 * 0.25)
        XCTAssertTrue(sim.occurrences.filter { $0.kind == .sick && $0.passenger == pi }.isEmpty)
        XCTAssertTrue(sim.passengers[pi].grumpy)
        XCTAssertGreaterThanOrEqual(sim.stats.failed, 1)
    }

    func testFailedSpillStays() {
        let sim = runningSim()
        let id = sim.addSpill(row: 10, age: 22 - 0.01)
        step(sim, seconds: 0.1)
        let o = sim.occurrences.first { $0.id == id }!
        XCTAssertTrue(o.failed)
        XCTAssertEqual(o.state, .failed)
    }

    // MARK: Movement

    func testWadingSlowsCrewToThirtyPercent() {
        let sim = runningSim()
        let spillX = sim.layout.rows[10].x
        sim.addSpill(row: 10)
        sim.crew.x = spillX - 10
        sim.crew.target = CrewTarget(x: spillX + 200, action: .none)
        sim.update(dt: 0.1)
        let before = sim.crew.x
        sim.update(dt: 0.1)
        XCTAssertEqual(sim.crew.x - before, Tuning.crewSpeed * Tuning.wadingFactor * 0.1, accuracy: 0.001)
    }

    func testSpillIsNotAHardBlock() {
        let sim = runningSim()
        sim.addSpill(row: 5)
        sim.crew.x = 120
        sim.tap(x: 2000, y: sim.layout.aisles[0])
        step(sim, seconds: 8)
        XCTAssertEqual(sim.crew.x, sim.layout.maxX, accuracy: 0.001)
    }

    // MARK: Sick passenger (GDD §5a): towel → bin the used bag → water

    func testSickFlowTowelThenBinTheBagThenWater() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.row >= 2 && $0.reach == 0 }) else { return XCTFail() }
        let p = sim.passengers[pi]
        let id = sim.addSick(passenger: pi)
        var o: Occurrence? { sim.occurrences.first { $0.id == id } }
        XCTAssertEqual(o?.need, .item(.towel), "no sick bag to fetch: they already have one")

        sim.crew.tray = [.towel]
        sim.crew.x = p.x
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertEqual(o?.need, .trash)
        XCTAssertEqual(sim.crew.tray, [.usedBag], "the used bag goes on the tray")

        // tapping the passenger again doesn't help: the bag has to go in a bin
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertEqual(o?.need, .trash)

        use(sim, station(sim, .trash))
        XCTAssertTrue(sim.crew.tray.isEmpty)
        XCTAssertEqual(o?.need, .item(.water))

        sim.crew.tray = [.water]
        sim.crew.aisle = p.aisle
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 4)
        XCTAssertNil(o)
        XCTAssertEqual(sim.stats.resolved, 1)
    }

    func testWindowSeatTakesLonger() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.isWindow }) else { return XCTFail() }
        let p = sim.passengers[pi]
        let id = sim.addSick(passenger: pi)
        sim.crew.x = p.x
        sim.crew.tray = [.towel]
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: Tuning.aisleSeatDuration + 0.1)
        XCTAssertEqual(sim.occurrences.first { $0.id == id }?.step, 0, "window seat should not be done at aisle-seat speed")
        step(sim, seconds: Tuning.windowSeatDuration - Tuning.aisleSeatDuration)
        XCTAssertEqual(sim.occurrences.first { $0.id == id }?.step, 1)
    }

    // MARK: Tray, machines, orders (GDD §6a)

    func testTrayCarriesTwoItemsAndBinsTakeThemBack() {
        let sim = runningSim()
        use(sim, station(sim, .bin(.water)))
        use(sim, station(sim, .bin(.juice)))
        XCTAssertEqual(sim.crew.tray, [.water, .juice])
        _ = sim.drainEvents()
        use(sim, station(sim, .bin(.snack)))
        XCTAssertEqual(sim.crew.tray.count, 2, "tray full")
        XCTAssertTrue(sim.drainEvents().contains(.nope))
        use(sim, station(sim, .bin(.water)))
        XCTAssertEqual(sim.crew.tray, [.juice], "tapping the same bin puts it back")
    }

    func testCoffeeBrewsThenHandsOver() {
        let sim = runningSim()
        let machine = station(sim, .machine(.coffee, prep: 3))
        let i = sim.layout.bins.firstIndex(of: machine)!
        sim.crew.aisle = 0; sim.crew.x = machine.x
        sim.tap(x: machine.x, y: machine.y)
        step(sim, seconds: 0.5)
        if case .working = sim.machines[i] {} else { XCTFail("machine should be brewing") }
        XCTAssertTrue(sim.crew.tray.isEmpty)
        step(sim, seconds: 3)
        XCTAssertEqual(sim.machines[i], .ready)
        sim.tap(x: machine.x, y: machine.y)
        step(sim, seconds: 0.5)
        XCTAssertEqual(sim.crew.tray, [.coffee])
        XCTAssertEqual(sim.machines[i], .idle)
    }

    func testComboOrderNeedsBothItemsAtOnce() {
        let sim = runningSim()
        let pi = sim.passengers.firstIndex { $0.reach == 0 && $0.row == 4 }!
        let p = sim.passengers[pi]
        let id = sim.addAtSeat(.drink, passenger: pi, steps: [.combo([.coffee, .snack])], fuse: 26)
        sim.crew.x = p.x
        sim.crew.tray = [.coffee]
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertNotNil(sim.occurrences.first { $0.id == id }, "half a combo isn't enough")
        sim.crew.tray = [.snack, .coffee]
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertNil(sim.occurrences.first { $0.id == id })
        XCTAssertTrue(sim.crew.tray.isEmpty)
    }

    func testCallButtonNeedsAFreeHand() {
        let sim = runningSim()
        let pi = sim.passengers.firstIndex { $0.reach == 0 && $0.row == 5 }!
        let p = sim.passengers[pi]
        let id = sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 16)
        sim.crew.x = p.x
        sim.crew.tray = [.water, .juice]
        _ = sim.drainEvents()
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertTrue(sim.drainEvents().contains(.nope))
        sim.crew.tray = [.water]
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertNil(sim.occurrences.first { $0.id == id })
        XCTAssertEqual(sim.crew.tray, [.water], "a call button uses nothing from the tray")
    }

    func testCryingBabyIsNoisyFromTheStart() {
        let sim = runningSim(plan: flight("TB103"))
        guard let pi = sim.passengers.firstIndex(where: { $0.hasKid }) else { return }
        let id = sim.addAtSeat(.baby, passenger: pi, steps: [.item(.toy)], fuse: 26)
        let o = sim.occurrences.first { $0.id == id }!
        XCTAssertEqual(o.state, .calm)
        XCTAssertGreaterThanOrEqual(sim.noiseLevel(o), 1)
    }

    func testLavatoryClogsAndThePlungerFixesIt() {
        let sim = runningSim(plan: flight("TB105"))
        let id = sim.clog(lavatory: 0)
        XCTAssertTrue(sim.isClogged(0))
        let o = sim.occurrences.first { $0.id == id }!
        XCTAssertEqual(o.need, .item(.plunger))
        use(sim, station(sim, .bin(.plunger)))
        XCTAssertEqual(sim.crew.tray, [.plunger])
        sim.crew.aisle = o.aisle
        sim.tap(x: o.x, y: o.y)
        step(sim, seconds: 4)
        XCTAssertFalse(sim.isClogged(0))
    }

    // MARK: Twists and stories (GDD §6a)

    func testRedEyeStartsMostlyAsleep() {
        let sim = FlightSimulation(plan: flight("TB104"), seed: 3)
        let asleep = sim.passengers.filter(\.asleep).count
        XCTAssertGreaterThan(Double(asleep) / Double(sim.passengers.count), 0.5)
    }

    func testTraineeAnswersCallButtons() {
        let sim = runningSim(plan: flight("TB205"))
        XCTAssertNotNil(sim.helper)
        let pi = sim.passengers.firstIndex { $0.aisle == 0 && $0.row == 2 }!
        let id = sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 16)
        step(sim, seconds: 12)
        XCTAssertNil(sim.occurrences.first { $0.id == id }, "the trainee got there")
    }

    func testGalleyClosedShutsTheForwardGallery() {
        let sim = runningSim(plan: flight("TB308"))
        let fwd = sim.layout.bins.indices.filter { sim.layout.bins[$0].x < 215 }
        XCTAssertFalse(fwd.isEmpty)
        XCTAssertTrue(fwd.allSatisfy { !sim.stationOpen($0) })
        XCTAssertTrue(sim.layout.bins.indices.contains { sim.stationOpen($0) && sim.layout.bins[$0].item == .towel })
    }

    func testVipHasShorterFusesAndDoublePenalties() {
        let sim = runningSim(plan: flight("TB106"))
        guard let v = sim.vipIndex else { return XCTFail("celebrity flight has a VIP") }
        let id = sim.addAtSeat(.call, passenger: v, steps: [.hands], fuse: 16)
        let o = sim.occurrences.first { $0.id == id }!
        XCTAssertTrue(o.vip)
        XCTAssertEqual(o.fuse, 16 * Tuning.vipFuseScale, accuracy: 0.001)
        let before = sim.satisfaction
        step(sim, seconds: 16)
        XCTAssertLessThanOrEqual(sim.satisfaction, before - OccurrenceKind.call.penalty * 2 + 0.01)
        XCTAssertTrue(sim.stats.vipFailed)
    }

    func testGoalsAreTracked() {
        let sim = runningSim()
        XCTAssertTrue(sim.goalMet, "no misses yet")
        sim.addSpill(row: 3, age: 21.99)
        step(sim, seconds: 0.1)
        XCTAssertFalse(sim.goalMet)
    }

    func testStars() {
        XCTAssertEqual(Tuning.stars(for: 39), 0)
        XCTAssertEqual(Tuning.stars(for: 40), 1)
        XCTAssertEqual(Tuning.stars(for: 65), 2)
        XCTAssertEqual(Tuning.stars(for: 85), 3)
        XCTAssertEqual(Tuning.stars(for: 100), 3)
    }

    // MARK: Director

    func testDirectorScriptAndCaps() {
        let sim = runningSim()
        step(sim, seconds: 7.5)
        XCTAssertEqual(sim.occurrences.first?.kind, .sick, "first scripted spawn is a sick passenger")
        XCTAssertEqual(FlightPlan.prototype.cap(at: 10), 2)
        XCTAssertEqual(FlightPlan.prototype.cap(at: 100), 3)
    }

    func testFlightEndsAndPenalisesUnresolved() {
        let sim = runningSim()
        step(sim, seconds: 140, dt: 0.1)
        sim.addSpill(row: 2)                       // too young to fail before touchdown
        let failedBefore = sim.stats.failed
        step(sim, seconds: 11, dt: 0.1)
        XCTAssertEqual(sim.phase, .ended)
        XCTAssertFalse(sim.running)
        XCTAssertGreaterThanOrEqual(sim.stats.failed, failedBefore + 1, "unresolved at landing counts as missed")
    }

    // MARK: Turbulence (GDD §5a)

    func testTurbulenceWarnsThenShakesThenClears() {
        let sim = runningSim()
        sim.turbulenceSchedule = [TurbulenceBump(start: 10, duration: 4, intensity: 0.375)]
        step(sim, seconds: 7.5)
        XCTAssertEqual(sim.turbulence, .warning)
        XCTAssertTrue(sim.seatbeltOn)
        XCTAssertTrue(sim.drainEvents().contains(.seatbelt(on: true)))
        step(sim, seconds: 3)
        XCTAssertEqual(sim.turbulenceIntensity, 0.375)
        step(sim, seconds: 4)
        XCTAssertEqual(sim.turbulence, .none)
    }

    func testTurbulenceSlowsTheCrew() {
        let calm = runningSim(), bumpy = runningSim()
        bumpy.turbulenceSchedule = [TurbulenceBump(start: 6, duration: 30, intensity: 0.375)]
        for sim in [calm, bumpy] {
            step(sim, seconds: 7)
            sim.crew.x = 240
            sim.crew.target = CrewTarget(x: 700, action: .none)
            step(sim, seconds: 0.5)
        }
        XCTAssertEqual(bumpy.crew.x - 240, (calm.crew.x - 240) * Tuning.turbulenceCrewFactor, accuracy: 6)
    }

    func testStandingPassengerStumblesWhenTurbulenceHits() {
        let sim = runningSim()
        sim.turbulenceSchedule = [TurbulenceBump(start: 7, duration: 3, intensity: 0.375)]
        step(sim, seconds: 6.2)
        let far = sim.passengers.firstIndex { $0.row == 1 }!
        sim.placeStroller(passenger: far, x: sim.layout.rows[10].x)
        _ = sim.drainEvents()
        step(sim, seconds: 1)
        let events = sim.drainEvents()
        XCTAssertTrue(events.contains { if case .stumble = $0 { return true }; return false })
        XCTAssertEqual(sim.passengers[far].stroll?.stage, .returning)
    }

    // MARK: Aisle traffic (GDD §4)

    func testCrewSqueezesPastStandingPassengers() {
        let sim = runningSim()
        step(sim, seconds: 7)
        let p = sim.passengers.firstIndex { $0.row == 0 && $0.aisle == 0 }!
        sim.placeStroller(passenger: p, x: 500)
        sim.crew.x = 495
        sim.crew.target = CrewTarget(x: 700, action: .none)
        sim.update(dt: 0.1)
        XCTAssertTrue(sim.crew.squeezing)
        XCTAssertEqual(sim.crew.x, 495 + Tuning.crewSpeed * Tuning.squeezeFactor * 0.1, accuracy: 0.5)
    }

    func testStrollersComeBackAndSitDown() {
        let sim = runningSim()
        step(sim, seconds: 7)
        let p = sim.passengers.firstIndex { $0.row == 3 }!
        sim.placeStroller(passenger: p, x: sim.layout.lavatories[0].doorX)
        step(sim, seconds: 40)
        XCTAssertNil(sim.passengers[p].stroll)
        XCTAssertGreaterThanOrEqual(sim.lavatoryUses, 1)
    }

    // MARK: Dozing and noise (GDD §7)

    func testNoisyPassengerWakesNearbySleepers() {
        let sim = runningSim()
        sim.sleepEnabled = true
        guard let loud = sim.passengers.indices.first(where: { i in
            sim.passengers.contains { $0.row == sim.passengers[i].row && $0.id != sim.passengers[i].id }
        }) else { return XCTFail("no row with two passengers") }
        let sleeper = sim.passengers.indices.first { $0 != loud && sim.passengers[$0].row == sim.passengers[loud].row }!
        for i in sim.passengers.indices { sim.setAsleep(i, false) }
        sim.setAsleep(sleeper, true)
        sim.addSick(passenger: loud, age: 30 * 0.3)
        sim.update(dt: 0.01)
        XCTAssertTrue(sim.passengers[sleeper].asleep)
        step(sim, seconds: 30 * 0.2)
        XCTAssertFalse(sim.passengers[sleeper].asleep)
        XCTAssertGreaterThanOrEqual(sim.stats.woken, 1)
    }

    // MARK: Layouts

    func testCometIsShortAndStocked() {
        let L = CabinLayout.comet
        XCTAssertEqual(L.rows.count, 12, "short first plane (GDD §4a)")
        XCTAssertEqual(L.height, 380)
        XCTAssertEqual(L.aisles, [180])
        XCTAssertEqual(L.rows[0].seats.map(\.y), [64, 108, 252, 296])
        let kinds = L.bins.map(\.kind)
        for k: StationKind in [.bin(.water), .bin(.juice), .machine(.coffee, prep: 3), .machine(.meal, prep: 5),
                               .bin(.towel), .bin(.snack), .bin(.toy), .trash, .bin(.plunger)] {
            XCTAssertTrue(kinds.contains(k), "\(k)")
        }
        XCTAssertFalse(L.bins.contains { $0.item == .usedBag })
    }

    func testEveryAircraftFitsItsSeatsAndAisles() {
        for a in Aircraft.allCases {
            let L = a.layout
            XCTAssertGreaterThan(L.rows.count, 0, a.rawValue)
            for row in L.rows { for s in row.seats {
                XCTAssertTrue(s.y > 30 && s.y < L.height - 30, "\(a) seat inside hull")
            } }
            XCTAssertLessThan(L.lastRowX, L.aftX)
            XCTAssertEqual(L.aisles.count > 1, !L.crossovers.isEmpty, "\(a) two aisles need crossovers")
            XCTAssertTrue(L.bins.contains { $0.kind == .trash }, "\(a) has a trash bin")
        }
        XCTAssertEqual(CabinLayout.swift.rows.filter(\.premium).flatMap(\.seats).count, 6)
        XCTAssertEqual(CabinLayout.longhaul.lavatories.count, 3)
        XCTAssertEqual(CabinLayout.voyager.aisles.count, 2)
    }

    func testCrewChangesAisleOnlyAtAGalley() {
        let sim = runningSim(plan: flight("TB307"))
        let L = sim.layout
        let x = L.rows[4].x
        sim.crew.x = x
        sim.crew.target = CrewTarget(x: x, aisle: 1, action: .none)
        var crossedAt: [Double] = []
        for _ in 0..<600 {
            let before = sim.crew.y
            sim.update(dt: 1.0 / 60)
            if sim.crew.y != before { crossedAt.append(sim.crew.x) }
            if sim.crew.target == nil { break }
        }
        XCTAssertEqual(sim.crew.aisle, 1)
        XCTAssertEqual(sim.crew.x, x, accuracy: 0.5)
        XCTAssertTrue(crossedAt.allSatisfy { cx in L.crossovers.contains { abs($0 - cx) < 1 } })
    }

    func testCartSlowsTheCrewAndAStuckCartNeedsAFreeHand() {
        let sim = runningSim(plan: flight("TB208"))
        step(sim, seconds: 7)
        sim.rollOutCart(at: 600)
        sim.crew.x = 580
        sim.crew.target = CrewTarget(x: 1000, action: .none)
        sim.update(dt: 0.1)
        XCTAssertEqual(sim.crew.x - 580, Tuning.crewSpeed * Tuning.cartFactor * 0.1, accuracy: 0.5)

        XCTAssertTrue(sim.spawn(.stuckCart))
        let o = sim.occurrences.first { $0.kind == .stuckCart }!
        XCTAssertEqual(o.need, .hands)
        sim.crew.tray = [.water, .juice]
        sim.crew.target = nil
        sim.crew.x = o.x - 60
        _ = sim.drainEvents()
        sim.tap(x: o.x, y: o.y)
        step(sim, seconds: 1)
        XCTAssertTrue(sim.drainEvents().contains(.nope), "tray full")
        sim.crew.tray = [.water]
        sim.tap(x: o.x, y: o.y)
        step(sim, seconds: 2)
        XCTAssertFalse(sim.occurrences.contains { $0.id == o.id })
        XCTAssertEqual(sim.cart?.stuck, false)
    }

    func testBinJamSlowsAndClearsWithAFreeHand() {
        let sim = runningSim(plan: flight("TB302"))
        let id = sim.addBinJam(row: 10)
        let o = sim.occurrences.first { $0.id == id }!
        sim.crew.x = o.x - 10
        sim.crew.target = CrewTarget(x: o.x + 200, action: .none)
        let before = sim.crew.x
        sim.update(dt: 0.1)
        XCTAssertEqual(sim.crew.x - before, Tuning.crewSpeed * Tuning.binJamFactor * 0.1, accuracy: 0.5)
        sim.crew.target = nil
        sim.tap(x: o.x, y: o.y)
        step(sim, seconds: 2)
        XCTAssertFalse(sim.occurrences.contains { $0.id == id })
    }

    func testCurtainHidesCalmPremiumProblems() {
        let sim = runningSim(plan: flight("TB202"))
        let pi = sim.passengers.firstIndex { $0.premium && !$0.vip }!
        let id = sim.addSick(passenger: pi)
        var o: Occurrence { sim.occurrences.first { $0.id == id }! }
        sim.crew.x = sim.layout.rows.last!.x
        XCTAssertTrue(sim.isBehindCurtain(o))
        sim.crew.x = 150
        XCTAssertFalse(sim.isBehindCurtain(o))
        sim.crew.x = sim.layout.rows.last!.x
        step(sim, seconds: 30 * 0.5)
        XCTAssertFalse(sim.isBehindCurtain(o))
    }

    // MARK: Campaign

    func testEveryFlightMixesSeveralKindsOfTask() {
        for plan in Campaign.routes.flatMap(\.flights) {
            XCTAssertGreaterThanOrEqual(plan.kinds.count, 3, "\(plan.id) should mix at least three kinds of task (GDD §6a)")
        }
        let twists = Set(Campaign.routes.flatMap(\.flights).compactMap(\.twist).map(\.title))
        XCTAssertEqual(twists.count, 5, "all five twists appear")
    }

    func testEveryCampaignFlightFliesToLanding() {
        let flights = Campaign.routes.flatMap(\.flights)
        XCTAssertGreaterThanOrEqual(flights.count, 30)
        XCTAssertEqual(Set(flights.map(\.id)).count, flights.count)
        for plan in flights {
            let sim = FlightSimulation(plan: plan, seed: 7)
            sim.start()
            var n = 0
            while sim.phase != .ended && n < 10_000 {
                if n % 40 == 0 {
                    let b = sim.layout.bins[n / 40 % sim.layout.bins.count]
                    sim.tap(x: b.x, y: b.y)
                } else if n % 40 == 20 {
                    sim.tap(x: Double(n % 700) + 80, y: sim.layout.aisles[n % sim.layout.aisles.count])
                }
                sim.update(dt: 0.1)
                n += 1
            }
            XCTAssertEqual(sim.phase, .ended, plan.id)
            XCTAssertGreaterThan(sim.stats.resolved + sim.stats.failed, 0, "\(plan.id) spawned something")
        }
    }
}
