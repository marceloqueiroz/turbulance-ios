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

    /// Stands at a passenger's seat and serves them.
    private func serve(_ sim: FlightSimulation, passenger pi: Int) {
        let p = sim.passengers[pi]
        sim.crew.x = p.x
        sim.crew.aisle = p.aisle
        sim.crew.y = sim.layout.aisles[p.aisle]
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1.5)
    }

    /// Walks to a station and uses it.
    private func use(_ sim: FlightSimulation, _ b: SupplyBin) {
        sim.crew.aisle = b.aisle
        sim.crew.y = sim.layout.aisles[b.aisle]
        sim.tap(x: b.x, y: b.y)
        step(sim, seconds: 4)
    }

    // MARK: Escalation

    func testTappingAMachineFromAfarWalksThereFirst() {
        let sim = runningSim()
        let i = sim.layout.bins.firstIndex { $0.kind == .drinks }!
        sim.crew.x = sim.layout.bins[i].x + 400
        XCTAssertFalse(sim.isAtStation(i))
        sim.walk(toStation: i)
        step(sim, seconds: 8)
        XCTAssertTrue(sim.isAtStation(i), "arrived at the machine")
        XCTAssertTrue(sim.crew.tray.isEmpty, "walking up doesn't use the machine")
    }

    // MARK: - Two attendants (GDD §8a)

    func testTwinAislePlanesHaveOneAttendantPerAisle() {
        let sim = runningSim(plan: flight("TB307"))
        XCTAssertTrue(sim.twoCrew)
        XCTAssertEqual(sim.crews.count, 2)
        XCTAssertEqual(sim.crews[0].aisle, 0)
        XCTAssertEqual(sim.crews[1].aisle, sim.layout.aisles.count - 1)
        XCTAssertFalse(runningSim(plan: flight("TB201")).twoCrew)
    }

    func testAProblemGoesToTheAttendantOnItsSide() {
        let sim = runningSim(plan: flight("TB307"))
        step(sim, seconds: 2)
        let bottom = sim.layout.aisles.count - 1
        guard let pi = sim.passengers.indices.first(where: { sim.passengers[$0].aisle == bottom }) else { return XCTFail("no passenger") }
        _ = sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 30)
        XCTAssertEqual(sim.active, 0)
        sim.tap(x: sim.passengers[pi].x, y: sim.passengers[pi].y)
        XCTAssertEqual(sim.active, 0, "control stays with the attendant you're playing")
        let partner = sim.crews[1]
        XCTAssertTrue(partner.target != nil || partner.queued != nil, "the bottom-aisle attendant takes it")
        XCTAssertNil(sim.crews[0].target, "the top-aisle attendant stays put")
    }

    func testSwitchingMovesControlToTheOtherAttendant() {
        let sim = runningSim(plan: flight("TB307"))
        step(sim, seconds: 2)
        sim.switchCrew()
        XCTAssertEqual(sim.active, 1)
        sim.tap(x: 600, y: sim.layout.aisles[sim.homeAisle(1)])
        XCTAssertNotNil(sim.crews[1].target ?? sim.crews[1].queued)
        sim.switchCrew()
        XCTAssertEqual(sim.active, 0)
    }

    func testTheOtherAttendantBucklesInByThemselves() {
        let sim = FlightSimulation(plan: flight("TB307"), seed: 7)
        sim.cartMode = .none; sim.strollsEnabled = false; sim.sleepEnabled = false
        sim.turbulenceSchedule = [TurbulenceBump(start: Tuning.boardingEnds + 4, duration: 6, intensity: 0.4)]
        sim.start()
        step(sim, seconds: Tuning.boardingEnds + 3.8)
        step(sim, seconds: 6)
        XCTAssertNotNil(sim.crews[1].seated, "the partner found a jump seat")
    }

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
        let f = Tuning.sickFuse
        step(sim, seconds: f * 0.5)
        XCTAssertEqual(sim.occurrences.first?.state, .urgent)
        step(sim, seconds: f * 0.3)
        XCTAssertEqual(sim.occurrences.first?.state, .critical)
        step(sim, seconds: f * 0.25)
        XCTAssertTrue(sim.occurrences.filter { $0.kind == .sick && $0.passenger == pi }.isEmpty)
        XCTAssertTrue(sim.passengers[pi].grumpy)
        XCTAssertGreaterThanOrEqual(sim.stats.failed, 1)
    }

    func testSpillHasNoTimer() {
        let sim = runningSim()
        let id = sim.addSpill(row: 10)
        step(sim, seconds: 60, dt: 0.1)
        let o = sim.occurrences.first { $0.id == id }!
        XCTAssertFalse(o.failed, "a spill never runs out: it waits to be mopped")
        XCTAssertEqual(o.state, .calm)
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

    // MARK: Sick passenger (GDD §5a): clean up → bin the used bag → water

    func testSickFlowCleanUpThenBinTheBagThenWater() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.row >= 2 && $0.reach == 0 }) else { return XCTFail() }
        let p = sim.passengers[pi]
        let id = sim.addSick(passenger: pi)
        var o: Occurrence? { sim.occurrences.first { $0.id == id } }
        XCTAssertEqual(o?.need, .clean, "no towel or sick bag to fetch")

        sim.crew.x = p.x
        sim.tap(x: p.x, y: p.y)
        sim.update(dt: 1.0 / 60)
        XCTAssertEqual(o?.need, .trash, "cleaned up the moment the crew arrives")
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

    func testCleaningUpASickPassengerNeedsAFreeHandForTheirBag() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.row >= 2 && $0.reach == 0 }) else { return XCTFail() }
        let p = sim.passengers[pi]
        let id = sim.addSick(passenger: pi)
        sim.crew.tray = [.juice, .snack]
        sim.crew.x = p.x
        _ = sim.drainEvents()
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 0.2)
        XCTAssertEqual(sim.occurrences.first { $0.id == id }?.need, .clean)
        XCTAssertTrue(sim.drainEvents().contains(.nope))
    }

    func testHandingOverIsInstantEvenAtTheWindowSeat() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.isWindow }) else { return XCTFail() }
        let p = sim.passengers[pi]
        let id = sim.addAtSeat(.drink, passenger: pi, steps: [.item(.juice)], fuse: 60)
        sim.crew.x = p.x
        sim.crew.aisle = p.aisle
        sim.crew.tray = [.juice]
        sim.tap(x: p.x, y: p.y)
        sim.update(dt: 1.0 / 60)
        XCTAssertFalse(sim.occurrences.contains { $0.id == id }, "given the moment the crew arrives")
        XCTAssertTrue(sim.crew.tray.isEmpty)
    }

    // MARK: Tray, machines, orders (GDD §6a)

    func testTrayCarriesTwoItemsAndBinsTakeThemBack() {
        let sim = runningSim(plan: flight("TB106"))
        use(sim, station(sim, .bin(.toy)))
        use(sim, station(sim, .bin(.snack)))
        XCTAssertEqual(sim.crew.tray, [.toy, .snack])
        _ = sim.drainEvents()
        use(sim, station(sim, .bin(.plunger)))
        XCTAssertEqual(sim.crew.tray.count, 2, "tray full")
        XCTAssertTrue(sim.drainEvents().contains(.nope))
        use(sim, station(sim, .bin(.toy)))
        XCTAssertEqual(sim.crew.tray, [.snack], "tapping the same bin puts it back")
    }

    func testCoffeeBrewsThenHandsOver() {
        let sim = runningSim()
        let machine = station(sim, .coffee)
        let i = sim.layout.bins.firstIndex(of: machine)!
        sim.crew.aisle = 0; sim.crew.x = machine.x
        sim.tap(x: machine.x, y: machine.y, choice: .coffee)
        step(sim, seconds: 0.5)
        if case .working = sim.machines[i] {} else { XCTFail("machine should be brewing") }
        XCTAssertTrue(sim.crew.tray.isEmpty)
        step(sim, seconds: 3)
        if case .ready = sim.machines[i] {} else { XCTFail("coffee should be ready") }
        sim.tap(x: machine.x, y: machine.y)
        step(sim, seconds: 0.5)
        XCTAssertEqual(sim.crew.tray, [.coffee])
        XCTAssertEqual(sim.machines[i], .idle)
    }

    func testCoffeeCoolsInTheMachineAndKeepsItsClockOnTheTray() {
        let sim = runningSim()
        let machine = station(sim, .coffee)
        let i = sim.layout.bins.firstIndex(of: machine)!
        sim.crew.aisle = 0; sim.crew.x = machine.x
        sim.tap(x: machine.x, y: machine.y, choice: .coffee)
        step(sim, seconds: 3.5)                                  // brewed
        step(sim, seconds: 9)                                    // then waited about half its 18 s
        let w = sim.warmth(ofMachine: i) ?? 0
        XCTAssertLessThan(w, 0.6, "cooling while it waits in the machine")
        sim.tap(x: machine.x, y: machine.y)
        step(sim, seconds: 0.5)
        XCTAssertEqual(sim.crew.tray, [.coffee])
        XCTAssertEqual(sim.warmth(ofTraySlot: 0) ?? 1, w, accuracy: 0.08, "the clock carries on from the machine")
        step(sim, seconds: 9)
        XCTAssertEqual(sim.crew.tray, [.coldCoffee], "the rest of the time ran out on the tray")
    }

    func testForgottenCoffeeGoesColdInTheMachineAndATapStartsAFreshOne() {
        let sim = runningSim()
        let machine = station(sim, .coffee)
        let i = sim.layout.bins.firstIndex(of: machine)!
        sim.crew.aisle = 0; sim.crew.x = machine.x
        sim.tap(x: machine.x, y: machine.y, choice: .coffee)
        _ = sim.drainEvents()
        step(sim, seconds: 3.5 + Item.coffee.keepsHotFor! + 0.5)
        XCTAssertEqual(sim.machines[i], .cold(.coffee))
        XCTAssertTrue(sim.drainEvents().contains { if case .machineCold = $0 { return true }; return false })
        sim.tap(x: machine.x, y: machine.y, choice: .coffee)
        step(sim, seconds: 0.5)
        XCTAssertTrue(sim.crew.tray.isEmpty, "the cold one is tipped out, not handed over")
        if case .working = sim.machines[i] {} else { XCTFail("a fresh pot is brewing") }
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
        let sim = FlightSimulation(plan: flight("TB105"), seed: 3)
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
        XCTAssertTrue(sim.layout.bins.indices.contains { sim.stationOpen($0) && sim.layout.bins[$0].kind == .trash }, "the aft closet still works")
    }

    func testVipHasShorterFusesAndPaysMore() {
        let sim = runningSim(plan: flight("TB106"))
        guard let v = sim.vipIndex else { return XCTFail("celebrity flight has a VIP") }
        let id = sim.addAtSeat(.call, passenger: v, steps: [.hands], fuse: 16)
        let o = sim.occurrences.first { $0.id == id }!
        XCTAssertTrue(o.vip)
        XCTAssertEqual(o.fuse, 16 * Tuning.vipFuseScale * sim.plan.pace.fuseScale, accuracy: 0.001)
        let before = sim.satisfaction
        serve(sim, passenger: v)
        XCTAssertEqual(sim.satisfaction - before, ((3 + 2) * Tuning.vipPay).rounded(), accuracy: 0.01, "a quick VIP call pays 1.5×")
        let late = sim.addAtSeat(.call, passenger: v, steps: [.hands], fuse: 16)
        step(sim, seconds: 16)
        XCTAssertTrue(sim.occurrences.allSatisfy { $0.id != late })
        XCTAssertTrue(sim.stats.vipFailed)
    }

    func testGoalsAreTracked() {
        let sim = runningSim()
        XCTAssertTrue(sim.goalMet, "no misses yet")
        sim.addAtSeat(.call, passenger: 20, steps: [.hands], fuse: 10, age: 10 - 0.01)
        step(sim, seconds: 0.1)
        XCTAssertFalse(sim.goalMet)
    }

    func testStarsUseEachFlightsTargets() {
        for plan in Campaign.routes.flatMap(\.flights) {
            let t = plan.targets
            XCTAssertEqual(t.count, 3)
            XCTAssertTrue(t[0] > 0 && t[0] < t[1] && t[1] < t[2], plan.id)
            XCTAssertEqual(plan.stars(for: Double(t[0] - 1)), 0)
            XCTAssertEqual(plan.stars(for: Double(t[0])), 1)
            XCTAssertEqual(plan.stars(for: Double(t[1])), 2)
            XCTAssertEqual(plan.stars(for: Double(t[2] + 50)), 3)
        }
        XCTAssertEqual(Set(Campaign.routes.flatMap(\.flights).map(\.id)), Set(Campaign.starTargets.keys), "every flight has authored targets")
    }

    // MARK: Scoring (GDD §2): satisfaction only goes up; mistakes reset the streak

    func testSatisfactionStartsAtZero() {
        XCTAssertEqual(FlightSimulation(plan: .prototype, seed: 1).satisfaction, 0)
    }

    func testStreakClimbsWithCleanFixesAndMultipliesPay() {
        let sim = runningSim()
        var multipliers: [Int] = []
        for pi in 0..<5 {
            sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 30)
            serve(sim, passenger: pi)
            for case let .resolved(_, _, _, streak, _) in sim.drainEvents() { multipliers.append(streak) }
        }
        XCTAssertEqual(multipliers, [1, 1, 2, 2, 3], "every 2 clean fixes raise the streak")
        XCTAssertEqual(sim.streak, 3)
        XCTAssertEqual(sim.stats.bestStreak, 3)
    }

    func testMistakeResetsTheStreakButNeverTakesPoints() {
        let sim = runningSim()
        for pi in 0..<2 {
            sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 30)
            serve(sim, passenger: pi)
        }
        XCTAssertEqual(sim.streak, 2)
        let before = sim.satisfaction
        _ = sim.drainEvents()
        sim.addAtSeat(.call, passenger: 20, steps: [.hands], fuse: 10, age: 10 - 0.01)
        step(sim, seconds: 0.1)
        XCTAssertEqual(sim.streak, 1)
        XCTAssertEqual(sim.satisfaction, before, "a miss costs the streak, not points")
        XCTAssertTrue(sim.drainEvents().contains { if case .streakLost = $0 { return true }; return false })
    }

    func testStreakCannotClimbWhileSomethingIsCritical() {
        let sim = runningSim()
        sim.addAtSeat(.call, passenger: 9, steps: [.hands], fuse: 30, age: 30 * 0.8)
        for pi in 0..<2 {
            sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 60)
            serve(sim, passenger: pi)
        }
        XCTAssertEqual(sim.streak, 1)
    }

    func testCriticalFixPaysOnlyTheBase() {
        let sim = runningSim()
        sim.addAtSeat(.call, passenger: 0, steps: [.hands], fuse: 30, age: 30 * 0.8)
        let before = sim.satisfaction
        serve(sim, passenger: 0)
        XCTAssertEqual(sim.satisfaction - before, OccurrenceKind.call.basePay, accuracy: 0.01)
    }

    /// A simple greedy player: every flight is winnable and satisfaction never goes down.
    /// Stars must be reachable on every flight: an expert earns three and a newcomer at least one (two on the
    /// first flight, the tutorial).
    /// Score only drops through the penalties. Prints `CAL <id> <expert median> <novice median> ...` lines.
    /// 17 seeds: enough that targets aren't fitted to a lucky handful of runs.
    static let starSeeds: [UInt64] = [3, 11, 29, 41, 57, 73, 88, 5, 17, 23, 37, 61, 79, 97, 113, 131, 149]

    func testBotEarnsStarsOnEveryFlightAndScoreNeverDrops() {
        var report: [String] = []
        for plan in Campaign.routes.flatMap(\.flights) {
            var expert: [Double] = [], novice: [Double] = [], mid: [Double] = []
            for seed: UInt64 in Self.starSeeds {
                var last = 0.0
                let sim = flyWithBot(plan, seed: seed) { sim in
                    // only the penalties (a wrong item, a passenger slipping, a line at a dirty lavatory) may take points away
                    let penalised = sim.drainEvents().contains { e in
                        switch e { case .wrongItem, .paxSlipped, .queueCost: return true; default: return false }
                    }
                    if !penalised { XCTAssertGreaterThanOrEqual(sim.satisfaction, last, "\(plan.id) satisfaction dropped") }
                    last = sim.satisfaction
                }
                expert.append(sim.satisfaction)
                novice.append(flyWithBot(plan, seed: seed, reaction: BotSkill.novice).satisfaction)
                mid.append(flyWithBot(plan, seed: seed, reaction: BotSkill.mid).satisfaction)
            }
            let e = expert.sorted()[expert.count / 2]
            let n = novice.sorted()[novice.count / 2]
            let expertThrees = expert.filter { plan.stars(for: $0) == 3 }.count
            report.append("CAL \(plan.id) \(Int(e)) \(Int(n)) targets \(plan.targets) expert \(plan.stars(for: e))★ (3★ on \(expertThrees)/\(expert.count)) novice \(plan.stars(for: n))★ "
                          + "expertRuns \(expert.map { Int($0) }.sorted()) midRuns \(mid.map { Int($0) }.sorted()) noviceRuns \(novice.map { Int($0) }.sorted())")
            let first = plan == Campaign.route1.flights[0]
            XCTAssertGreaterThanOrEqual(plan.stars(for: n), first ? 2 : 1, "\(plan.id): a newcomer earns \(first ? "two stars" : "a star")")
            XCTAssertEqual(plan.stars(for: e), 3, "\(plan.id): expert play earns three stars")
            XCTAssertGreaterThanOrEqual(expertThrees, expert.count - 2,
                                        "\(plan.id): expert play reaches three stars on all but at most 2 of \(expert.count) runs")
        }
        print("BOT REPORT\n" + report.joined(separator: "\n"))
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
        sim.addAtSeat(.call, passenger: 20, steps: [.hands], fuse: 60)   // too young to fail before touchdown
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

    // MARK: Crew seating in turbulence (GDD §5b)

    func testHeavyTurbulenceWarnsLonger() {
        XCTAssertEqual(TurbulenceBump(start: 0, duration: 5, intensity: 0.375).warningTime, 6)
        XCTAssertEqual(TurbulenceBump(start: 0, duration: 5, intensity: 1).warningTime, 9)
    }

    func testCrewBucklesInAndStaysSeatedUntilClear() {
        let sim = runningSim()
        sim.turbulenceSchedule = [TurbulenceBump(start: 20, duration: 4, intensity: 0.375)]
        step(sim, seconds: 14.5)
        XCTAssertEqual(sim.turbulence, .warning, "about 6 s of warning")
        let j = sim.layout.jumpSeats[sim.nearestJumpSeat()!]
        sim.tap(x: j.x, y: sim.jumpSeatY(j))
        step(sim, seconds: 6)
        XCTAssertNotNil(sim.crew.seated)
        XCTAssertGreaterThan(sim.turbulenceIntensity, 0)
        XCTAssertEqual(sim.stats.crewStumbles, 0)
        _ = sim.drainEvents()
        sim.tap(x: 400, y: 180)
        step(sim, seconds: 0.5)
        XCTAssertTrue(sim.drainEvents().contains(.nope), "stay seated while it's bumpy")
        XCTAssertNotNil(sim.crew.seated)
        step(sim, seconds: 4)
        XCTAssertEqual(sim.turbulence, .none)
        // an empty stretch of aisle (a tap on a spill would mop it instead)
        let free = [400.0, 300, 500, 250].first { x in !sim.occurrences.contains { !$0.kind.atSeat && abs($0.x - x) < 40 } }!
        sim.tap(x: free, y: 180)
        step(sim, seconds: 3)
        XCTAssertNil(sim.crew.seated)
        XCTAssertEqual(sim.crew.x, free, accuracy: 0.5, "unbuckles, then goes where you tapped")
        XCTAssertTrue(sim.goalMet || sim.plan.goal != .seatedEveryBump)
    }

    func testStandingCrewStumblesAndDropsTheTray() {
        let sim = runningSim()
        sim.turbulenceSchedule = [TurbulenceBump(start: 12, duration: 6, intensity: 0.375)]
        sim.crew.x = sim.layout.rows[5].x
        sim.crew.tray = [.juice, .usedBag]
        step(sim, seconds: 12.1)
        XCTAssertEqual(sim.stats.crewStumbles, 1)
        XCTAssertEqual(sim.crew.tray, [.usedBag], "drinks drop, the tied-off bag stays")
        XCTAssertTrue(sim.occurrences.contains { $0.kind == .spill }, "the juice spills")
        step(sim, seconds: 3.1)
        XCTAssertEqual(sim.stats.crewStumbles, 2, "keeps stumbling until seated")
    }

    func testFusesRunAtHalfSpeedAndSpawnsWait() {
        let sim = runningSim()
        sim.turbulenceSchedule = [TurbulenceBump(start: 10, duration: 20, intensity: 0.375)]
        step(sim, seconds: 10.5)
        let id = sim.addSpill(row: 3)
        let before = sim.occurrences.count
        step(sim, seconds: 10)
        XCTAssertEqual(sim.occurrences.first { $0.id == id }!.age, 5, accuracy: 0.1)
        XCTAssertEqual(sim.occurrences.count, before, "no new problems while strapped in")
    }

    // MARK: Orders (GDD §5a): hidden until taken

    func testOrderIsHiddenUntilYouTakeIt() {
        let sim = runningSim()
        let pi = sim.passengers.firstIndex { $0.reach == 0 && $0.row >= 2 }!
        let p = sim.passengers[pi]
        let id = sim.addAtSeat(.drink, passenger: pi, steps: [.order, .item(.juice)], fuse: 26)
        XCTAssertEqual(sim.occurrences.first { $0.id == id }?.need, .order)
        sim.crew.x = p.x
        sim.crew.tray = [.water, .snack]                // a full tray doesn't stop you taking an order
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertEqual(sim.occurrences.first { $0.id == id }?.need, .item(.juice))
        XCTAssertEqual(sim.crew.tray, [.water, .snack])
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
        sim.addSick(passenger: loud, age: Tuning.sickFuse * 0.3)
        sim.update(dt: 0.01)
        XCTAssertTrue(sim.passengers[sleeper].asleep)
        step(sim, seconds: Tuning.sickFuse * 0.2)                 // urgent: not loud enough yet (GDD §7)
        XCTAssertTrue(sim.passengers[sleeper].asleep, "only critical problems wake sleepers")
        step(sim, seconds: Tuning.sickFuse * 0.35)                // critical now
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
        for k: StationKind in [.drinks, .coffee, .oven, .bin(.snack), .bin(.toy), .trash, .bin(.plunger)] {
            XCTAssertTrue(kinds.contains(k), "\(k)")
        }
        XCTAssertFalse(L.bins.contains { $0.item == .usedBag })
        XCTAssertEqual(L.bins.filter { $0.kind == .oven }.count, 2, "two ovens")
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
        XCTAssertEqual(CabinLayout.swift.rows.filter(\.premium).flatMap(\.seats).count, 12)        // 3 rows of 2-2
        XCTAssertEqual(CabinLayout.voyager.rows.filter(\.premium).flatMap(\.seats).count, 20)      // 5 rows of 1-2-1
        XCTAssertEqual(CabinLayout.longhaul.lavatories.count, 4)                                     // forward, mid, two aft
        XCTAssertEqual(CabinLayout.voyager.aisles.count, 2)
    }

    func testAftServiceBlocksAndEndWallsFrameTheWorkArea() {
        for a in Aircraft.allCases {
            let L = a.layout
            // two equal aft blocks: a lavatory and one station each, on both sides of the cabin
            let aft = L.blocks.filter { $0.x >= L.aftX }
            XCTAssertEqual(aft.filter { $0.kind == .lavatory }.count, 2, "\(a) has two aft lavatories")
            XCTAssertEqual(Set(aft.map { $0.w }).count, 2, "\(a) aft blocks: one lavatory width and one station width")
            XCTAssertTrue(L.bins.contains { $0.item == .plunger && $0.x > L.aftX }, "\(a) plunger aft")
            XCTAssertLessThanOrEqual(L.bins.map(\.x).max()!, L.maxX, "\(a) every station is in reach")
            // the camera keeps 32 pt between the work area and the screen edges
            let s = CameraRig.fitScale(availW: CameraRig.referenceView.w, availH: CameraRig.referenceView.h, layout: L)
            let r = CameraRig.xRange(L, scale: s)
            XCTAssertEqual((L.startX - r.lowerBound) * s, CameraRig.endPad, accuracy: 0.001)
            XCTAssertEqual((r.upperBound - L.endX) * s, CameraRig.endPad, accuracy: 0.001)
        }
        XCTAssertTrue(CabinLayout.swift.blocks.contains { $0.kind == .wardrobe }, "a wardrobe faces the forward lavatory")
        XCTAssertTrue(CabinLayout.longhaul.bins.filter { $0.kind == .drinks }.count == 2, "the B757 mid galley pours drinks")
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
        // roll the cart where no stray bag lies within reach, so the tap below can only mean the cart
        let at = [600.0, 700, 800, 900, 1000].first { x in !sim.occurrences.contains { abs($0.x - x) < 80 } } ?? 600
        sim.rollOutCart(at: at)
        sim.crew.x = at - 20
        sim.crew.target = CrewTarget(x: at + 400, action: .none)
        sim.update(dt: 0.1)
        XCTAssertEqual(sim.crew.x - (at - 20), Tuning.crewSpeed * Tuning.cartFactor * 0.1, accuracy: 0.5)

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
        step(sim, seconds: o.fuse * 0.5)                         // urgent by now, whatever the flight's timer scale
        XCTAssertFalse(sim.isBehindCurtain(o))
    }

    // MARK: Campaign

    func testEveryFlightMixesSeveralKindsOfTask() {
        for plan in Campaign.routes.flatMap(\.flights) {
            let minimum = plan == Campaign.route1.flights[0] ? 2 : 3     // the first flight is nearly a tutorial
            XCTAssertGreaterThanOrEqual(plan.kinds.count, minimum, "\(plan.id) should mix at least \(minimum) kinds of task (GDD §6a)")
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

    func testBoardingRushBagsArriveOneAtATime() {
        let sim = FlightSimulation(plan: flight("TB201"), seed: 5)
        sim.start()
        var bags: Int { sim.occurrences.filter { $0.kind == .carryOn }.count }
        XCTAssertEqual(bags, 1)
        step(sim, seconds: 2.1)
        XCTAssertEqual(bags, 2)
        step(sim, seconds: 2)
        XCTAssertEqual(bags, 3)
    }

    func testCrewWaitsInTheJumpSeatThenWalksToTheStart() {
        let sim = FlightSimulation(plan: flight("TB103"), seed: 2)
        sim.seatCrewForCountdown()
        XCTAssertNotNil(sim.crew.seated, "buckled in during the countdown")
        sim.start()                                   // Go!
        step(sim, seconds: 2)
        XCTAssertNil(sim.crew.seated)
        XCTAssertEqual(sim.crew.x, 120, accuracy: 0.5, "walked to the start position")
    }

    // MARK: Slipping and cold food (GDD §5a, §6a)

    func testWalkingThroughASpillWithDrinksOnlySlowsYou() {
        let sim = runningSim()
        let id = sim.addSpill(row: 6)
        let spill = sim.occurrences.first { $0.id == id }!
        sim.crew.x = spill.x - 60
        sim.crew.tray = [.juice, .snack]
        _ = sim.drainEvents()
        sim.crew.target = CrewTarget(x: spill.x + 100, action: .none)
        step(sim, seconds: 0.5)
        XCTAssertEqual(sim.crew.tray, [.juice, .snack], "walking: nothing splashes")
        XCTAssertEqual(sim.occurrences.first { $0.id == id }!.size, 1)
        XCTAssertFalse(sim.drainEvents().contains { if case .fell = $0 { return true }; return false })
    }

    func testRunningIntoASpillWithDrinksSplashesThemAndGrowsTheSpill() {
        let sim = runningSim()
        let id = sim.addSpill(row: 6)
        var spill: Occurrence { sim.occurrences.first { $0.id == id }! }
        sim.crew.x = spill.x - 90
        sim.crew.tray = [.juice, .snack]
        let sat = sim.satisfaction
        for _ in 0..<3 {
            sim.tap(x: spill.x + 150, y: sim.layout.aisles[0])
            step(sim, seconds: 0.1)
        }
        step(sim, seconds: 0.5)
        XCTAssertEqual(sim.crew.tray, [.snack], "the juice splashed out, the snack stayed")
        XCTAssertEqual(spill.size, 2)
        XCTAssertEqual(sim.satisfaction, sat, "a fall resets the streak, it doesn't take points")
        XCTAssertGreaterThan(sim.reach(spill), Tuning.stopDistance, "a bigger puddle covers more aisle")
    }

    func testCoffeeGoesColdOnTheTrayAndIsRefused() {
        let sim = runningSim()
        sim.crew.tray = [.coffee]
        step(sim, seconds: 1)
        XCTAssertLessThan(sim.warmth(ofTraySlot: 0) ?? 1, 1)
        step(sim, seconds: Item.coffee.keepsHotFor!)
        XCTAssertEqual(sim.crew.tray, [.coldCoffee])
        let pi = sim.passengers.firstIndex { $0.reach == 0 && $0.row >= 2 }!
        let p = sim.passengers[pi]
        let id = sim.addAtSeat(.drink, passenger: pi, steps: [.item(.coffee)], fuse: 26)
        sim.crew.x = p.x
        _ = sim.drainEvents()
        sim.tap(x: p.x, y: p.y)
        step(sim, seconds: 1)
        XCTAssertTrue(sim.drainEvents().contains(.nope), "cold coffee is refused")
        XCTAssertNotNil(sim.occurrences.first { $0.id == id })
    }

    // MARK: Profile slots (GDD §9a)

    func testProfileSlotsCreateSwitchAndDelete() {
        var s = ProfileSlots()
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.current)
        XCTAssertEqual(s.firstEmpty, 0)
        s.create(in: 0, name: " Ana ", avatar: 2)
        s.create(in: 2, name: "Bo", avatar: 1)
        XCTAssertEqual(s.active, 2, "a new profile becomes the active one")
        XCTAssertEqual(s.current?.name, "Bo")
        XCTAssertEqual(s.firstEmpty, 1)
        XCTAssertNil(s.create(in: 0, name: "X", avatar: 0), "can't overwrite a filled slot")

        s.current?.stars["TB101"] = 3
        s.switchTo(0)
        XCTAssertEqual(s.current?.name, "Ana")
        XCTAssertEqual(s.current?.totalStars, 0, "stars belong to each profile")
        s.switchTo(1)
        XCTAssertEqual(s.active, 0, "can't switch to an empty slot")

        s.delete(0)
        XCTAssertEqual(s.active, 2, "deleting the active profile moves to the one left")
        XCTAssertEqual(s.current?.totalStars, 3)
        s.delete(2)
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.current)
    }

    func testProfileSlotsHoldFourAndRoundTrip() throws {
        var s = ProfileSlots()
        for i in 0..<ProfileSlots.count { s.create(in: i, name: "P\(i)", avatar: i) }
        XCTAssertNil(s.firstEmpty)
        XCTAssertNil(s.create(in: 4, name: "Five", avatar: 0))
        let back = try JSONDecoder().decode(ProfileSlots.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    // MARK: Galley, lavatories, hurry, pace (GDD §6a, §5a)

    func testDrinksDispenserHandsOverThePickWithNoWait() {
        let sim = runningSim()
        let m = station(sim, .drinks)
        let i = sim.layout.bins.firstIndex(of: m)!
        XCTAssertEqual(sim.choices(atStation: i), [.water, .juice, .soda], "coffee has its own machine")
        sim.crew.aisle = 0; sim.crew.x = m.x
        _ = sim.drainEvents()
        sim.tap(x: m.x, y: m.y)                                  // no pick: nothing to hand over
        step(sim, seconds: 0.4)
        XCTAssertTrue(sim.crew.tray.isEmpty)
        XCTAssertTrue(sim.drainEvents().contains(.nope))
        sim.tap(x: m.x, y: m.y, choice: .soda)
        step(sim, seconds: 0.4)
        XCTAssertEqual(sim.crew.tray, [.soda], "grabbed on arrival")
        XCTAssertNotNil(sim.choices(atStation: i), "always ready for the next one")
    }

    func testCoffeeMachineBrewsWithOneTap() {
        let sim = runningSim()
        let m = station(sim, .coffee)
        let i = sim.layout.bins.firstIndex(of: m)!
        XCTAssertNil(sim.choices(atStation: i), "nothing to pick: tapping it starts a brew")
        sim.crew.aisle = 0; sim.crew.x = m.x
        sim.tap(x: m.x, y: m.y)
        step(sim, seconds: 0.4)
        if case .working(.coffee, _)? = sim.machines[i] {} else { XCTFail("brewing") }
    }

    func testOvenHeatsTheDishYouPickAndTheWrongOneDoesNotCount() {
        let sim = runningSim()
        let oven = station(sim, .oven)
        let pi = sim.passengers.firstIndex { $0.reach == 0 && $0.row == 4 }!
        let id = sim.addAtSeat(.drink, passenger: pi, steps: [.item(.pasta)], fuse: 60)
        sim.crew.aisle = 0; sim.crew.x = oven.x
        sim.tap(x: oven.x, y: oven.y, choice: .chicken)
        step(sim, seconds: 0.5 + Item.chicken.prepTime)
        sim.tap(x: oven.x, y: oven.y)
        step(sim, seconds: 0.5)
        XCTAssertEqual(sim.crew.tray, [.chicken])
        _ = sim.drainEvents()
        serve(sim, passenger: pi)
        XCTAssertTrue(sim.occurrences.contains { $0.id == id }, "they asked for pasta: still waiting")
        XCTAssertTrue(sim.crew.tray.isEmpty, "the chicken was handed over anyway (and cost points)")
    }

    func testDirtyLavatoryIsCleanedOnTheSpot() {
        let sim = runningSim(plan: flight("TB102"))
        let id = sim.makeDirty(lavatory: 0)
        let o = sim.occurrences.first { $0.id == id }!
        XCTAssertEqual(o.need, .clean, "no towel needed")
        XCTAssertFalse(sim.isClogged(0), "dirty still works")
        sim.crew.aisle = o.aisle; sim.crew.x = o.x - 40
        sim.tap(x: o.x, y: o.y)
        step(sim, seconds: 2.5)
        XCTAssertFalse(sim.occurrences.contains { $0.id == id })
    }

    func testDirtyLavatoryHasNoTimer() {
        let sim = runningSim(plan: flight("TB102"))
        let id = sim.makeDirty(lavatory: 0)
        step(sim, seconds: 60)
        let o = sim.occurrences.first { $0.id == id }
        XCTAssertNotNil(o, "still waiting to be cleaned")
        XCTAssertEqual(o?.failed, false)
        XCTAssertEqual(sim.stats.failed, 0)
    }

    func testADirtyLavatoryDrawsALineThatCostsSatisfaction() {
        let sim = runningSim(plan: flight("TB102"))
        sim.strollsEnabled = true
        step(sim, seconds: Tuning.boardingEnds + 0.5)
        sim.makeDirty(lavatory: 0)
        step(sim, seconds: 30)
        XCTAssertGreaterThan(sim.lavQueue(0), 0, "passengers line up for it")
        XCTAssertGreaterThan(sim.stats.queueCost, 0, "and waiting costs points")
        XCTAssertFalse(sim.isClogged(0), "no plunger on TB102: the line just waits")
    }

    func testAFullLineClogsTheLavatoryOnceClogsAreIn() {
        let sim = runningSim(plan: flight("TB105"))
        sim.strollsEnabled = true
        step(sim, seconds: Tuning.boardingEnds + 0.5)
        sim.makeDirty(lavatory: 0)
        step(sim, seconds: 45)
        XCTAssertTrue(sim.isClogged(0), "the line filled up: someone went in anyway")
    }

    func testQuickTapsMakeTheCrewHurryUpToACap() {
        let sim = runningSim()
        sim.crew.x = 120
        let far = sim.layout.maxX
        for _ in 0..<6 {
            sim.tap(x: far, y: sim.layout.aisles[0])
            step(sim, seconds: 0.2)
        }
        XCTAssertEqual(sim.crew.hurry, Tuning.maxHurry, accuracy: 0.001)
        step(sim, seconds: Tuning.hurryHold + 1)
        XCTAssertLessThan(sim.crew.hurry, 1.2, "it wears off")
    }

    func testRunningStopsOnArrival() {
        let sim = runningSim()
        sim.crew.x = 120
        let goal = sim.layout.rows[6].x
        for _ in 0..<4 {
            sim.tap(x: goal, y: sim.layout.aisles[0])
            step(sim, seconds: 0.1)
        }
        XCTAssertGreaterThan(sim.crew.hurry, 1.2, "running")
        step(sim, seconds: 1.5)                                  // arrives well within this
        XCTAssertNil(sim.crew.target)
        XCTAssertEqual(sim.crew.hurry, 1, "back to walking the moment they get there")
        sim.tap(x: sim.layout.maxX, y: sim.layout.aisles[0])     // a later single tap walks
        step(sim, seconds: 0.2)
        XCTAssertEqual(sim.crew.hurry, 1)
    }

    func testHurryingIntoASpillKnocksTheCrewDown() {
        let sim = runningSim()
        let id = sim.addSpill(row: 8)
        let spill = sim.occurrences.first { $0.id == id }!
        sim.crew.x = spill.x - 90
        sim.crew.tray = [.water]
        _ = sim.drainEvents()
        for _ in 0..<3 {
            sim.tap(x: spill.x + 150, y: sim.layout.aisles[0])
            step(sim, seconds: 0.1)
        }
        step(sim, seconds: 0.5)
        XCTAssertTrue(sim.drainEvents().contains { if case .fell = $0 { return true }; return false })
        XCTAssertEqual(sim.crew.busy?.task, .knockedDown)
        XCTAssertTrue(sim.crew.tray.isEmpty, "the water splashed out")
        step(sim, seconds: Tuning.fallDuration + 0.2)
        XCTAssertNotEqual(sim.crew.busy?.task, .knockedDown, "back up")
    }

    func testStationsAFlightDoesNotUseAreHiddenAndNewOnesPopIn() {
        let first = FlightSimulation(plan: flight("TB101"), seed: 1)
        let kinds = first.layout.bins.map(\.kind)
        XCTAssertTrue(kinds.contains(.drinks))
        XCTAssertFalse(kinds.contains(.oven), "no meals yet")
        XCTAssertFalse(kinds.contains(.bin(.toy)))
        XCTAssertFalse(kinds.contains(.bin(.plunger)))
        XCTAssertTrue(first.freshStations.isEmpty, "the first flight has nothing to compare with")
        let third = FlightSimulation(plan: flight("TB103"), seed: 1)
        let fresh = third.freshStations.map { third.layout.bins[$0].kind }
        XCTAssertEqual(fresh.filter { $0 == .oven }.count, 2, "the ovens pop in on TB103")
        XCTAssertTrue(fresh.contains(.bin(.toy)))
        third.start()
        XCTAssertTrue(third.drainEvents().contains { if case .newStations = $0 { return true }; return false })
    }

    func testMidFlightRushGoesOverTheCap() {
        var plan = FlightPlan.prototype                                    // any flight with the rush on
        plan.pace.rush = true
        let sim = FlightSimulation(plan: plan, seed: 4)
        sim.turbulenceSchedule = []; sim.strollsEnabled = false; sim.sleepEnabled = false
        sim.start()
        step(sim, seconds: sim.plan.duration * Tuning.rushAt - 0.5, dt: 0.1)
        _ = sim.drainEvents()
        step(sim, seconds: 6, dt: 0.1)
        XCTAssertTrue(sim.drainEvents().contains(.rush))
    }

    // MARK: Request bubbles (GDD §8a)

    func testTappingARequestBubbleServesThatSeat() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.reach == 0 && !$0.isWindow && $0.row == 5 }) else { return XCTFail() }
        let p = sim.passengers[pi]
        let id = sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 60)
        let o = sim.occurrences.first { $0.id == id }!
        let c = sim.bubbleCenter(o)
        XCTAssertEqual(abs(c.y - p.y), Tuning.bubbleOffset, accuracy: 0.01)
        XCTAssertLessThan(abs(c.y - sim.layout.aisles[p.aisle]), abs(p.y - sim.layout.aisles[p.aisle]), "aisle seat: bubble over the aisle")
        let t = sim.target(forTapAt: c.x + 8, c.y + 10)
        XCTAssertEqual(t.action, .seat(row: p.row, seat: p.seat), "the bubble is part of the seat's tap target")
        sim.crew.x = p.x
        sim.tap(x: c.x, y: c.y)
        step(sim, seconds: 0.3)
        XCTAssertFalse(sim.occurrences.contains { $0.id == id }, "served from a bubble tap")
    }

    func testWindowSeatBubbleFloatsTowardTheWall() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.isWindow }) else { return XCTFail() }
        let p = sim.passengers[pi]
        let id = sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 60)
        let c = sim.bubbleCenter(sim.occurrences.first { $0.id == id }!)
        XCTAssertGreaterThan(abs(c.y - sim.layout.aisles[p.aisle]), abs(p.y - sim.layout.aisles[p.aisle]))
        XCTAssertEqual(sim.target(forTapAt: c.x, c.y).action, .seat(row: p.row, seat: p.seat))
    }

    // MARK: Route 1 flight checklist (GDD §9a): each flight shows only what it uses

    func testFirstFlightHasNoTrashLavatoriesOrJumpSeatsInPlay() {
        let sim = FlightSimulation(plan: flight("TB101"), seed: 1)
        XCTAssertFalse(sim.layout.bins.contains { $0.kind == .trash }, "nothing to bin yet")
        XCTAssertTrue(sim.layout.lavatories.isEmpty, "nobody walks to the loo yet")
        XCTAssertFalse(sim.layout.blocks.contains { $0.kind == .lavatory }, "drawn as plain closets")
        XCTAssertFalse(sim.jumpSeatsInPlay, "no turbulence")
        sim.start()
        XCTAssertTrue(sim.drainEvents().contains(.jumpSeatsAway), "the take-off seat folds away after Go")
        let j = sim.layout.jumpSeats[0]
        XCTAssertNotEqual(sim.target(forTapAt: j.x, sim.jumpSeatY(j)).action, .jumpSeat(0), "not tappable in play")
    }

    func testFixturesArriveOnTheFlightsThatUseThem() {
        let tb102 = FlightSimulation(plan: flight("TB102"), seed: 1)
        XCTAssertTrue(tb102.layout.bins.contains { $0.kind == .trash }, "cold coffee needs binning")
        XCTAssertFalse(tb102.layout.lavatories.isEmpty, "dirty lavatories")
        XCTAssertFalse(tb102.jumpSeatsInPlay)
        for id in ["TB104", "TB105", "TB106"] {
            XCTAssertTrue(FlightSimulation(plan: flight(id), seed: 1).jumpSeatsInPlay, "\(id) has a bump")
        }
    }

    func testWithoutATrashBinTheDrinksMachinePoursADrinkAway() {
        let sim = FlightSimulation(plan: flight("TB101"), seed: 1)
        sim.start()
        let m = sim.layout.bins.first { $0.kind == .drinks }!
        let i = sim.layout.bins.firstIndex(of: m)!
        sim.crew.x = m.x; sim.crew.aisle = 0
        sim.crew.tray = [.juice]
        XCTAssertTrue(sim.poursAway(atStation: i))
        sim.tap(x: m.x, y: m.y)
        step(sim, seconds: 0.5)
        XCTAssertTrue(sim.crew.tray.isEmpty, "poured away")
        XCTAssertFalse(sim.poursAway(atStation: i), "nothing left to pour")
        let tb102 = FlightSimulation(plan: flight("TB102"), seed: 1)
        tb102.crew.tray = [.juice]
        XCTAssertFalse(tb102.poursAway(atStation: tb102.layout.bins.firstIndex { $0.kind == .drinks }!), "once there's a bin, use it")
    }

    // MARK: Wrong items, wet floors, the premium curtain

    func testWrongItemIsHandedOverCostsPointsAndDoesNotSayWhatsNeeded() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.reach == 0 && $0.row == 4 }) else { return XCTFail() }
        for k in 0..<3 {                                          // earn some points first
            sim.addAtSeat(.call, passenger: k + 10, steps: [.hands], fuse: 60)
            serve(sim, passenger: k + 10)
        }
        let id = sim.addAtSeat(.drink, passenger: pi, steps: [.item(.juice)], fuse: 60)
        sim.crew.tray = [.water]
        let before = sim.satisfaction
        _ = sim.drainEvents()
        serve(sim, passenger: pi)
        XCTAssertEqual(sim.satisfaction, before - Tuning.wrongItemPenalty, accuracy: 0.01)
        XCTAssertTrue(sim.occurrences.contains { $0.id == id }, "still waiting for juice")
        XCTAssertTrue(sim.crew.tray.isEmpty, "the wrong item is handed over anyway")
        XCTAssertFalse((sim.crew.bubble ?? "").lowercased().contains("juice"), "the crew doesn't say what they wanted")
        XCTAssertTrue(sim.drainEvents().contains { if case .wrongItem = $0 { return true }; return false })
    }

    func testEmptyTrayIsNotPenalised() {
        let sim = runningSim()
        guard let pi = sim.passengers.firstIndex(where: { $0.reach == 0 && $0.row == 4 }) else { return XCTFail() }
        sim.addAtSeat(.drink, passenger: pi, steps: [.item(.juice)], fuse: 60)
        let before = sim.satisfaction
        serve(sim, passenger: pi)
        XCTAssertEqual(sim.satisfaction, before)
    }

    func testWalkingPassengerSlipsOnASpillOnce() {
        let sim = runningSim()
        for k in 0..<3 {
            sim.addAtSeat(.call, passenger: k + 10, steps: [.hands], fuse: 60)
            serve(sim, passenger: k + 10)
        }
        let row = 6
        sim.addSpill(row: row)
        let spillX = sim.layout.rows[row].x
        guard let i = sim.passengers.firstIndex(where: { $0.row == row - 3 && $0.aisle == 0 }) else { return XCTFail() }
        sim.crew.x = sim.layout.maxX                             // out of the way
        sim.placeStroller(passenger: i, x: spillX - 60)       // walking aft, toward the lavatory, over the spill
        let before = sim.satisfaction
        _ = sim.drainEvents()
        step(sim, seconds: 4)
        XCTAssertEqual(sim.stats.paxSlips, 1, "slips once on that spill")
        XCTAssertEqual(sim.satisfaction, before - Tuning.paxSlipPenalty, accuracy: 0.01)
    }

    func testPremiumRequestStaysVisibleOnceSeen() {
        let sim = runningSim(plan: flight("TB202"))
        let pi = sim.passengers.firstIndex { $0.premium && !$0.vip }!
        let id = sim.addAtSeat(.call, passenger: pi, steps: [.hands], fuse: 60)
        var o: Occurrence { sim.occurrences.first { $0.id == id }! }
        sim.crew.x = 150                                          // in the premium cabin: seen
        sim.update(dt: 0.01)
        sim.crew.x = sim.layout.rows.last!.x                      // back behind the curtain
        sim.update(dt: 0.01)
        XCTAssertFalse(sim.isBehindCurtain(o), "doesn't hide again")
    }
}
