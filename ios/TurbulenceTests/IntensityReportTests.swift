import XCTest
@testable import Turbulence

/// Measures how intense each flight is, by flying it with the test bot over several seeds.
/// Run on its own to tune difficulty (GDD §6a Pace, Route 1 flight checklist):
///   xcodebuild test ... -only-testing:TurbulenceTests/IntensityReportTests
/// Each flight prints one line: `INTENSITY TB101 {json}`. The test only fails if a flight can't be flown.
final class IntensityReportTests: XCTestCase {
    struct Report: Codable {
        let flight: String
        var problemsPerMin = 0.0        // new problems per minute of cruise
        var meanOpen = 0.0              // problems open at once, averaged over the cruise
        var peakOpen = 0                // most open at once (median of the seeds)
        var timeTwoPlus = 0.0           // share of the cruise with 2+ open
        var timeThreePlus = 0.0         // share with 3+ open
        var botFailRate = 0.0           // share of problems the bot missed
        var botIdle = 0.0               // share of the cruise with nothing to do
        var meanFuse = 0.0              // average seconds a new problem gives you
        var kinds: [String] = []        // what turned up
        var stars = 0.0                 // the expert bot's average stars
        var targets: [Int] = []         // the flight's star targets
        var expertScore = 0.0           // median score, expert bot (instant decisions)
        var noviceScore = 0.0           // median score, newcomer bot (1.5 s before each decision)
        var expertStars = 0
        var noviceStars = 0
        var perfectShare = 0.0          // the 3-star target as a share of the expert's score
    }

    static let seeds: [UInt64] = [3, 11, 29, 41, 57]

    func testIntensityReport() throws {
        // ROUTE=2 (env var TEST_RUNNER_ROUTE, or via -only-testing) limits it to one route; default: every flight
        let only = ProcessInfo.processInfo.environment["ROUTE"].flatMap(Int.init)
        for plan in Campaign.routes.filter({ only == nil || $0.id == only }).flatMap(\.flights) {
            var reports: [Report] = []
            for seed in Self.seeds { reports.append(measure(plan, seed: seed)) }
            var r = Report(flight: plan.id)
            let n = Double(reports.count)
            r.problemsPerMin = reports.map(\.problemsPerMin).reduce(0, +) / n
            r.meanOpen = reports.map(\.meanOpen).reduce(0, +) / n
            r.peakOpen = reports.map(\.peakOpen).sorted()[reports.count / 2]
            r.timeTwoPlus = reports.map(\.timeTwoPlus).reduce(0, +) / n
            r.timeThreePlus = reports.map(\.timeThreePlus).reduce(0, +) / n
            r.botFailRate = reports.map(\.botFailRate).reduce(0, +) / n
            r.botIdle = reports.map(\.botIdle).reduce(0, +) / n
            r.meanFuse = reports.map(\.meanFuse).reduce(0, +) / n
            r.kinds = Array(Set(reports.flatMap(\.kinds))).sorted()
            r.stars = reports.map(\.stars).reduce(0, +) / n
            let expert = Self.seeds.map { flyWithBot(plan, seed: $0).satisfaction }.sorted()[Self.seeds.count / 2]
            let novice = Self.seeds.map { flyWithBot(plan, seed: $0, reaction: BotSkill.novice).satisfaction }.sorted()[Self.seeds.count / 2]
            r.targets = plan.targets
            r.expertScore = expert; r.noviceScore = novice
            r.expertStars = plan.stars(for: expert); r.noviceStars = plan.stars(for: novice)
            r.perfectShare = expert > 0 ? Double(plan.targets[2]) / expert : 0
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            let json = String(data: try enc.encode(r), encoding: .utf8)!
            print("INTENSITY \(plan.id) \(json)")
        }
    }

    private func measure(_ plan: FlightPlan, seed: UInt64) -> Report {
        var r = Report(flight: plan.id)
        let sim = FlightSimulation(plan: plan, seed: seed)
        sim.start()
        let dt = 1.0 / 30
        var cruise = 0.0, openSum = 0.0, two = 0.0, three = 0.0, idle = 0.0, peak = 0
        var seen = Set<Int>(), fuses: [Double] = [], kinds = Set<String>()
        var n = 0
        while sim.phase != .ended && n < 30_000 {
            for i in sim.crews.indices {
                let c = sim.crews[i]
                if c.busy == nil && c.target == nil && c.queued == nil { sim.select(i); botAct(sim) }
            }
            sim.update(dt: dt)
            _ = sim.drainEvents()
            for o in sim.occurrences where !seen.contains(o.id) {
                seen.insert(o.id)
                if o.fuse.isFinite { fuses.append(o.fuse) }
                kinds.insert("\(o.kind)")
            }
            if sim.phase == .cruise {
                let open = sim.occurrences.filter { !$0.dead && !$0.failed }.count
                cruise += dt
                openSum += Double(open) * dt
                if open >= 2 { two += dt }
                if open >= 3 { three += dt }
                if open == 0 { idle += dt }
                peak = max(peak, open)
            }
            n += 1
        }
        XCTAssertEqual(sim.phase, .ended, "\(plan.id) flies to landing")
        let minutes = max(cruise, 1) / 60
        r.problemsPerMin = Double(seen.count) / minutes
        r.meanOpen = openSum / max(cruise, 1)
        r.peakOpen = peak
        r.timeTwoPlus = two / max(cruise, 1)
        r.timeThreePlus = three / max(cruise, 1)
        let done = sim.stats.resolved + sim.stats.failed
        r.botFailRate = done == 0 ? 0 : Double(sim.stats.failed) / Double(done)
        r.botIdle = idle / max(cruise, 1)
        r.meanFuse = fuses.isEmpty ? 0 : fuses.reduce(0, +) / Double(fuses.count)
        r.kinds = kinds.sorted()
        r.stars = Double(sim.stars)
        return r
    }
}

/// How much a flight's outcome depends on the seed rather than the player (GDD §2 Stars). For each flight, flies
/// the expert bot over 17 seeds and prints `SPREAD <id> {json}`: the score's coefficient of variation (std ÷ mean),
/// worst ÷ median, and the spread of how many problems appeared and how many sleepers were woken.
/// Filter with TEST_RUNNER_ROUTE=<n>. Never fails.
final class ScoreSpreadReportTests: XCTestCase {
    struct Spread: Codable {
        let flight: String
        var scoreCV = 0.0           // std ÷ mean of the expert score (lower = fairer)
        var worstOverMedian = 0.0   // the worst run ÷ the median run
        var problemsMin = 0, problemsMax = 0
        var problemsCV = 0.0
        var wokenMin = 0, wokenMax = 0
        var failsMax = 0
    }

    static let seeds: [UInt64] = [3, 11, 29, 41, 57, 73, 88, 5, 17, 23, 37, 61, 79, 97, 113, 131, 149]

    func testScoreSpreadReport() throws {
        let only = ProcessInfo.processInfo.environment["ROUTE"].flatMap(Int.init)
        for plan in Campaign.routes.filter({ only == nil || $0.id == only }).flatMap(\.flights) {
            var scores: [Double] = [], problems: [Double] = [], woken: [Int] = [], fails: [Int] = []
            for seed in Self.seeds {
                let sim = flyWithBot(plan, seed: seed)
                scores.append(sim.satisfaction)
                problems.append(Double(sim.stats.resolved + sim.stats.failed))
                woken.append(sim.stats.woken)
                fails.append(sim.stats.failed)
            }
            func cv(_ xs: [Double]) -> Double {
                let m = xs.reduce(0, +) / Double(xs.count)
                guard m > 0 else { return 0 }
                let v = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
                return v.squareRoot() / m
            }
            let sorted = scores.sorted()
            var s = Spread(flight: plan.id)
            s.scoreCV = cv(scores)
            s.worstOverMedian = sorted[0] / max(1, sorted[sorted.count / 2])
            s.problemsMin = Int(problems.min()!); s.problemsMax = Int(problems.max()!)
            s.problemsCV = cv(problems)
            s.wokenMin = woken.min()!; s.wokenMax = woken.max()!
            s.failsMax = fails.max()!
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            print("SPREAD \(plan.id) \(String(data: try enc.encode(s), encoding: .utf8)!)")
        }
    }
}
