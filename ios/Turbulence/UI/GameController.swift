import Foundation
import Observation
import SpriteKit
import SwiftUI
import UIKit

struct FlightResult: Equatable {
    let stars: Int
    let resolved: Int
    let missed: Int
    let averageFix: Double?
    let satisfaction: Int
    var bestStreak = 1
    var goal: Goal = .noMisses
    var goalMet = false
    /// Every fix, penalty and miss in order, and the star targets: the scorecard counts them up.
    var log: [ScoreEvent] = []
    var targets: [Int] = [1, 2, 3]
}

/// Glue between the model, the SpriteKit renderer and the SwiftUI HUD.
@Observable
final class GameController {
    enum Screen: Equatable { case idle, intro, countdown, playing, paused, ended }

    var screen: Screen = .idle
    var timeText = "2:30"
    var clockFraction = 1.0
    var phaseText = "Boarding"
    var landing = false
    var satisfaction = 0
    /// Streak multiplier (×1–×4) and the flight's star targets for the HUD pips (GDD §2 Scoring).
    var streak = 1
    var starTargets: [Int] = [1, 2, 3]
    var toast: String?
    var muted = false
    var result: FlightResult?
    var seatbelt = false
    /// Twin-aisle planes: two attendants and a switch button, with a dot when the other side needs you (GDD §8a).
    var twoCrew = false
    var partnerAlert = false
    var activeCrew = 0
    /// The menu over a drinks machine or oven, in view coordinates (GDD §6a).
    var picker: MachinePicker?
    struct MachinePicker: Equatable {
        let station: Int
        let options: [Item]
        let point: CGPoint
    }
    /// "Take your seat" while the sign is on and the crew is standing; "buckled" once seated.
    var seatPrompt: SeatPrompt = .none
    enum SeatPrompt: Equatable { case none, takeSeat, buckled }
    var plan = Campaign.route1.flights[0]
    var largeText = false
    /// Letterbox captions during the intro cutscene (GDD §8b).
    var introTitle: String?
    var introSubtitle: String?
    /// The 3D cutscene while it plays (GDD §8b).
    var intro3D: IntroScene3D?
    /// "3", "2", "1", "Go!" after the intro, before the flight clock starts.
    var countdownText: String?
    /// The fade through black between the intro and the play view (GDD §8b), 0…1.
    var blackout = 0.0

    /// Called once when a flight lands, before the scorecard shows.
    @ObservationIgnored var onEnded: ((FlightPlan, FlightResult) -> Void)?
    @ObservationIgnored private(set) var sim: FlightSimulation
    @ObservationIgnored let scene: CabinScene
    @ObservationIgnored private let synth = Synth()
    @ObservationIgnored private var haptics = true
    @ObservationIgnored private var crewLook = Avatar.look(0)
    @ObservationIgnored private var toastTimer = 0.0
    @ObservationIgnored private var grumbleTimer = 0.0
    @ObservationIgnored private var bumpTimer = 0.0
    @ObservationIgnored private let bump = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let jolt = UIImpactFeedbackGenerator(style: .medium)

    var flightLabel: String { "\(plan.id) · \(plan.aircraft.displayName)" }

    init() {
        sim = FlightSimulation()
        sim.stagePreview()
        scene = CabinScene(size: CGSize(width: 1000, height: 380))
        scene.game = self
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") {
            plan = .prototype
            sim = FlightSimulation()
            sim.stageDemo()
            screen = .playing
            if args.contains("-picker"), let i = sim.layout.bins.firstIndex(where: { $0.kind == .oven }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in   // show a machine menu (screenshots)
                    guard let self, let options = self.sim.choices(atStation: i) ?? Optional(Item.meals),
                          let point = self.scene.viewPoint(x: self.sim.layout.bins[i].x, y: self.sim.layout.bins[i].y) else { return }
                    self.picker = MachinePicker(station: i, options: options, point: point)
                }
            }
        } else if let i = args.firstIndex(of: "-flight"), i + 1 < args.count,
                  let p = Campaign.routes.flatMap(\.flights).first(where: { $0.id == args[i + 1] }) {
            plan = p                                 // jump straight into one flight, e.g. -flight TB307
            debugFlight = p
        } else if args.contains("-scorecard") {
            // a sample scorecard (screenshots): a run of fixes with a few misses and penalties
            plan = Campaign.route1.flights[1]
            var log: [ScoreEvent] = []
            let kinds: [OccurrenceKind] = [.call, .drink, .spill, .baby, .sick]
            for k in 0..<24 {
                log.append(ScoreEvent(kind: .fixed, delta: Double(6 + (k % 4) * 3), label: kinds[k % kinds.count].scoreName))
                if k % 7 == 3 { log.append(ScoreEvent(kind: .missed, delta: 0, label: "Order")) }
                if k % 9 == 5 { log.append(ScoreEvent(kind: .penalty, delta: -3, label: "Wrong item")) }
            }
            let total = Int(log.map(\.delta).reduce(0, +))
            result = FlightResult(stars: plan.stars(for: Double(total)), resolved: 24, missed: 4, averageFix: nil,
                                  satisfaction: total, goal: plan.goal, goalMet: true, log: log, targets: plan.targets)
            screen = .ended
        } else if args.contains("-autostart") || args.contains("-turbulence") {
            plan = .prototype
            sim = FlightSimulation()
            if args.contains("-turbulence") {        // bump right after boarding, for quick checks
                sim.turbulenceSchedule = [TurbulenceBump(start: 10, duration: 8, intensity: 0.375)]
            }
            sim.start()
            screen = .playing
        }
        scene.reset()
        if let p = debugFlight { start(p, intro: !args.contains("-nointro")) }
    }

    @ObservationIgnored private var debugFlight: FlightPlan?
    var isDebugLaunch: Bool { screen != .idle }

    /// Loads a flight. With `intro`, the cutscene plays first and the flight clock starts when it ends.
    func start(_ plan: FlightPlan, intro: Bool = true) {
        synth.warmUp()
        scene.removeAction(forKey: "countdown")
        scene.removeAction(forKey: "fade")
        blackout = 0
        countdownText = nil
        self.plan = plan
        sim = FlightSimulation(plan: plan)
        result = nil
        toast = nil
        seatbelt = false
        scene.reset()
        guard intro else { countdown(); return }
        let route = Campaign.route(containing: plan.id)
        let leg = route.flatMap { r in r.flights.firstIndex(of: plan).map { (r.cities[$0], r.cities[$0 + 1]) } }
        introTitle = ["FLIGHT \(plan.id)", leg.map { "\($0.0.uppercased()) → \($0.1.uppercased())" }, plan.aircraft.displayName.uppercased()]
            .compactMap { $0 }.joined(separator: "  ·  ")
        let destination = leg?.1 ?? "our destination"
        screen = .intro
        introSubtitle = nil
        // the captain on the PA: chime, then each line spoken over the cabin speakers under its subtitle
        let welcome = Story.captainWelcome(to: destination, flight: plan.id)
        let lines = [(welcome, welcome), (plan.story.captainQuip, plan.story.captainQuip)]
        // each line starts when the previous one has finished; the camera holds until the last one is done
        func say(_ k: Int) {
            guard k < lines.count else { self.intro3D?.release(); return }
            introSubtitle = "Captain: " + lines[k].0
            synth.captain(say: lines[k].1) { [weak self] in
                self?.scene.run(.sequence([.wait(forDuration: 0.25), .run { say(k + 1) }]), withKey: "introCaptions")
            }
        }
        scene.run(.sequence([.wait(forDuration: 0.4), .run { [weak self] in self?.synth.play(.paChime) },
                             .wait(forDuration: 1.3), .run { say(0) }]), withKey: "introCaptions")
        scene.setClouds(visible: false)          // the 3D intro has none: fade them in after Go instead of popping
        let intro = IntroScene3D(sim: sim, crewLook: crewLook) { [weak self] in
            (self?.scene.size ?? .zero, self?.scene.contentInsets ?? .zero)
        }
        intro3D = intro
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-introAt"), i + 1 < args.count, let t = Double(args[i + 1]) {
            intro.freeze(at: t)                    // debug: hold one frame of the cutscene
            return
        }
        intro.play { [weak self] in self?.countdown() }
    }

    /// 3, 2, 1, Go! over the play view, then the flight starts (GDD §8b).
    private func countdown() {
        scene.removeAction(forKey: "introCaptions")
        synth.stopCaptain()
        introTitle = nil
        introSubtitle = nil
        guard intro3D != nil else { enterCountdown(); return }
        // out of the cutscene through black: fade out, swap to the play view framed on the attendant, fade in
        withAnimation(.easeIn(duration: 0.35)) { blackout = 1 }
        scene.run(.sequence([.wait(forDuration: 0.4), .run { [weak self] in
            guard let self else { return }
            self.intro3D = nil
            self.enterCountdown()
            withAnimation(.easeOut(duration: 0.5)) { self.blackout = 0 }
        }]), withKey: "fade")
    }

    private func enterCountdown() {
        sim.seatCrewForCountdown()             // buckled into the forward jump seat until Go
        screen = .countdown
        scene.snapCamera()
        var steps: [SKAction] = [.wait(forDuration: 0.35)]
        for (n, sound) in [("3", Synth.Sound.count3), ("2", .count2), ("1", .count1)] {
            steps += [.run { [weak self] in self?.countdownText = n; self?.synth.play(sound) }, .wait(forDuration: 1.0)]
        }
        steps += [.run { [weak self] in self?.countdownText = "Go!"; self?.synth.play(.go); self?.beginFlight() },
                  .wait(forDuration: 0.6), .run { [weak self] in self?.countdownText = nil }]
        scene.run(.sequence(steps), withKey: "countdown")
    }

    func skipIntro() { intro3D?.skip() }

    private func beginFlight() {
        scene.setClouds(visible: true)
        sim.start()
        screen = .playing
    }

    /// The quiet cabin shown behind menus and the route map.
    func idle() {
        sim = FlightSimulation()
        sim.stagePreview()
        screen = .idle
        toast = nil
        seatbelt = false
        scene.reset()
    }

    func apply(_ device: DeviceSettings) {
        synth.volume = Float(device.volume)
        haptics = device.haptics
    }

    func apply(_ options: GameOptions, avatar: Int) {
        scene.shakeScale = CGFloat(options.shake.scale)
        largeText = options.largeText
        let look = Avatar.look(avatar)
        crewLook = look
        scene.setCrewLook(skin: look.skin, hair: look.hair)
    }

    func setPaused(_ paused: Bool) {
        guard screen == .playing || screen == .paused else { return }
        screen = paused ? .paused : .playing
    }

    func toggleMute() {
        muted.toggle()
        synth.muted = muted
    }

    /// A machine the attendant is walking to; its menu opens on arrival.
    @ObservationIgnored private var pendingPicker: Int?

    /// A cabin tap. Tapping a drinks machine or oven that's waiting for a pick opens its menu first
    /// (the "two-tap" machines, GDD §6a). From afar, the attendant walks there first and the menu opens on
    /// arrival. Any other tap closes an open menu.
    func tap(x: Double, y: Double) {
        guard screen == .playing else { return }
        picker = nil
        pendingPicker = nil
        if let i = sim.station(forTapAt: x, y), !sim.poursAway(atStation: i), let options = sim.choices(atStation: i), !options.isEmpty {
            if sim.isAtStation(i) {
                openPicker(i, options)
            } else {
                sim.walk(toStation: i)
                pendingPicker = i
            }
            return
        }
        sim.tap(x: x, y: y)
    }

    private func openPicker(_ i: Int, _ options: [Item]) {
        guard let point = scene.viewPoint(x: sim.layout.bins[i].x, y: sim.layout.bins[i].y) else { return }
        picker = MachinePicker(station: i, options: options, point: point)
        synth.play(.pick)
    }

    /// Opens a machine's menu once the attendant has walked up to it.
    private func checkPendingPicker() {
        guard let i = pendingPicker, screen == .playing else { return }
        let c = sim.crew
        if c.target == nil && c.busy == nil && c.queued == nil {
            pendingPicker = nil
            if sim.isAtStation(i), let options = sim.choices(atStation: i), !options.isEmpty { openPicker(i, options) }
        }
    }

    /// Sounds for the scorecard's count-up.
    func playUI(_ s: Synth.Sound) { synth.play(s) }

    /// The switch button: control (and the camera) moves to the other attendant.
    func switchCrew() {
        guard screen == .playing, sim.twoCrew else { return }
        picker = nil
        pendingPicker = nil
        sim.switchCrew()
        synth.play(.pick)
        if haptics { bump.impactOccurred(intensity: 0.6) }
    }

    /// The player picked something on a machine's menu: walk there and start it.
    func pick(_ item: Item) {
        guard let p = picker, screen == .playing else { picker = nil; return }
        picker = nil
        let b = sim.layout.bins[p.station]
        sim.tap(x: b.x, y: b.y, choice: item)
    }

    /// Called by the scene once per frame.
    func tick(_ dt: Double) {
        if screen == .playing {
            sim.update(dt: dt)
            playAmbience(dt)
            checkPendingPicker()
        }
        for e in sim.drainEvents() { handle(e) }
        if toast != nil && screen != .paused {
            toastTimer -= dt
            if toastTimer <= 0 { toast = nil }
        }
        syncHUD()
    }

    /// Shows a one-time tip (kept across launches), e.g. the first time the follow camera hides something.
    func hintOnce(_ key: String, _ text: String) {
        let k = "hint." + key
        guard screen == .playing, !UserDefaults.standard.bool(forKey: k) else { return }
        UserDefaults.standard.set(true, forKey: k)
        toast = text
        toastTimer = 6.5
    }

    private func handle(_ e: SimEvent) {
        scene.play(e)
        switch e {
        case .spawned(let kind, let x, _): synth.play(kind == .sick ? .sick : .spill, pan: scene.pan(forX: x))
        case .stepDone(let x, _), .mopped(let x, _): synth.play(.step, pan: scene.pan(forX: x))
        case .resolved(let x, _, _, _, _): synth.play(.ok, pan: scene.pan(forX: x))
        case .failed(let x, _): synth.play(.fail, pan: scene.pan(forX: x))
        case .picked: synth.play(.pick)
        case .trashed: synth.play(.step)
        case .machineReady(let i): synth.play(.ok, pan: scene.pan(forX: sim.layout.bins[i].x))
        case .machineCold: synth.play(.nope)
        case .nope: synth.play(.nope)
        case .seatbelt(let on):
            seatbelt = on
            if on { synth.play(.chime) }
        case .turbulence(let intensity):
            if intensity > 0 {
                synth.play(.rumble)
                if haptics { jolt.impactOccurred(intensity: min(1, 0.5 + intensity)) }
            }
        case .stumble(let x, _): synth.play(.whoa, pan: scene.pan(forX: x))
        case .crewStumble:
            synth.play(.fail)
            if haptics { jolt.impactOccurred(intensity: 1) }
        case .buckled: synth.play(.pick)
        case .wentCold: synth.play(.nope)
        case .wokeUp: break
        case .streakUp:
            synth.play(.streakUp)
            if haptics { bump.impactOccurred(intensity: 0.5) }
        case .streakLost: synth.play(.streakLost)
        case .fell:
            synth.play(.fail)
            if haptics { jolt.impactOccurred(intensity: 1) }
        case .rush:
            synth.play(.chime)
            if haptics { bump.impactOccurred(intensity: 0.7) }
        case .newStations: synth.play(.streakUp)
        case .jumpSeatsAway: break
        case .wrongItem:
            if haptics { jolt.impactOccurred(intensity: 0.6) }
        case .queueCost: break
        case .paxSlipped(let x, _):
            synth.play(.whoa, pan: scene.pan(forX: x))
            if haptics { jolt.impactOccurred(intensity: 0.5) }
        case .cart(let out): if out { synth.play(.chime) }
        case .toast(let text):
            toast = text
            toastTimer = 5.5
        case .phase(let p):
            synth.play(.ding)
            if p == .ended {
                toast = nil
                let r = FlightResult(stars: sim.stars, resolved: sim.stats.resolved, missed: sim.stats.failed,
                                     averageFix: sim.stats.averageFix, satisfaction: Int(sim.satisfaction.rounded()),
                                     bestStreak: sim.stats.bestStreak, goal: sim.plan.goal, goalMet: sim.goalMet,
                                     log: sim.scoreLog, targets: sim.plan.targets)
                result = r
                onEnded?(plan, r)
                screen = .ended
            }
        }
    }

    /// Repeating cues while something is ongoing: grumbles from the loudest waiting passenger,
    /// haptic bumps while the cabin shakes.
    private func playAmbience(_ dt: Double) {
        let loud = sim.occurrences.max { sim.noiseLevel($0) < sim.noiseLevel($1) }
        let loudest = loud.map(sim.noiseLevel) ?? 0
        if loudest > 0, let loud {
            grumbleTimer -= dt
            if grumbleTimer <= 0 {
                synth.play(loudest >= 2 ? .grumbleLoud : .grumble, pan: scene.pan(forX: loud.x))
                grumbleTimer = loudest >= 2 ? 1.6 : 3.2
            }
        } else {
            grumbleTimer = 0.8
        }
        let shaking = sim.turbulenceIntensity
        if shaking > 0 && haptics {
            bumpTimer -= dt
            if bumpTimer <= 0 {
                bump.impactOccurred(intensity: min(1, 0.3 + shaking))
                bumpTimer = Double.random(in: 0.25...0.6)
            }
        }
    }

    private func syncHUD() {
        let secs = Int(sim.timeRemaining.rounded(.up))
        let text = "\(secs / 60):\(String(format: "%02d", secs % 60))"
        if text != timeText { timeText = text }
        let frac = (sim.timeRemaining / sim.plan.duration * 200).rounded() / 200
        if frac != clockFraction { clockFraction = frac }
        let phase: String
        switch sim.phase {
        case .boarding: phase = "Boarding"
        case .cruise: phase = "Cruise"
        case .landing, .ended: phase = "Final approach"
        }
        if phase != phaseText { phaseText = phase }
        let isLanding = sim.phase == .landing
        if isLanding != landing { landing = isLanding }
        let prompt: SeatPrompt = !sim.seatbeltOn ? .none : sim.crew.seated != nil ? .buckled : .takeSeat
        if prompt != seatPrompt { seatPrompt = prompt }
        let sat = Int(sim.satisfaction.rounded())
        if sat != satisfaction { satisfaction = sat }
        if sim.streak != streak { streak = sim.streak }
        if sim.plan.targets != starTargets { starTargets = sim.plan.targets }
        if sim.twoCrew != twoCrew { twoCrew = sim.twoCrew }
        if sim.partnerNeedsYou != partnerAlert { partnerAlert = sim.partnerNeedsYou }
        if sim.active != activeCrew { activeCrew = sim.active }
    }
}
