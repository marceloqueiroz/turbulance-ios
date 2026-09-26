import Foundation
import Observation
import SpriteKit
import UIKit

struct FlightResult: Equatable {
    let stars: Int
    let resolved: Int
    let missed: Int
    let averageFix: Double?
    let satisfaction: Int
    var goal: Goal = .noMisses
    var goalMet = false
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
    var satisfaction = 70
    var toast: String?
    var muted = false
    var result: FlightResult?
    var seatbelt = false
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

    /// Called once when a flight lands, before the scorecard shows.
    @ObservationIgnored var onEnded: ((FlightPlan, FlightResult) -> Void)?
    @ObservationIgnored private(set) var sim: FlightSimulation
    @ObservationIgnored let scene: CabinScene
    @ObservationIgnored private let synth = Synth()
    @ObservationIgnored private var haptics = true
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
        } else if let i = args.firstIndex(of: "-flight"), i + 1 < args.count,
                  let p = Campaign.routes.flatMap(\.flights).first(where: { $0.id == args[i + 1] }) {
            plan = p                                 // jump straight into one flight, e.g. -flight TB307
            debugFlight = p
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
                self?.scene.run(.sequence([.wait(forDuration: 0.5), .run { say(k + 1) }]), withKey: "introCaptions")
            }
        }
        scene.run(.sequence([.wait(forDuration: 0.4), .run { [weak self] in self?.synth.play(.paChime) },
                             .wait(forDuration: 1.3), .run { say(0) }]), withKey: "introCaptions")
        let intro = IntroScene3D(sim: sim) { [weak self] in (self?.scene.size ?? .zero, self?.scene.contentInsets ?? .zero) }
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
        intro3D = nil
        sim.seatCrewForCountdown()             // buckled into the forward jump seat until Go
        screen = .countdown
        var steps: [SKAction] = [.wait(forDuration: 0.35)]
        for n in ["3", "2", "1"] {
            steps += [.run { [weak self] in self?.countdownText = n; self?.synth.play(.pick) }, .wait(forDuration: 0.75)]
        }
        steps += [.run { [weak self] in self?.countdownText = "Go!"; self?.synth.play(.ok); self?.beginFlight() },
                  .wait(forDuration: 0.6), .run { [weak self] in self?.countdownText = nil }]
        scene.run(.sequence(steps), withKey: "countdown")
    }

    func skipIntro() { intro3D?.skip() }

    private func beginFlight() {
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

    func apply(_ options: GameOptions, avatar: Int) {
        synth.volume = Float(options.volume)
        haptics = options.haptics
        scene.shakeScale = CGFloat(options.shake.scale)
        largeText = options.largeText
        let look = Avatar.look(avatar)
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

    func tap(x: Double, y: Double) {
        guard screen == .playing else { return }
        sim.tap(x: x, y: y)
    }

    /// Called by the scene once per frame.
    func tick(_ dt: Double) {
        if screen == .playing {
            sim.update(dt: dt)
            playAmbience(dt)
        }
        for e in sim.drainEvents() { handle(e) }
        if toast != nil && screen != .paused {
            toastTimer -= dt
            if toastTimer <= 0 { toast = nil }
        }
        syncHUD()
    }

    private func handle(_ e: SimEvent) {
        scene.play(e)
        switch e {
        case .spawned(let kind, _, _): synth.play(kind == .sick ? .sick : .spill)
        case .stepDone, .mopped: synth.play(.step)
        case .resolved: synth.play(.ok)
        case .failed: synth.play(.fail)
        case .picked: synth.play(.pick)
        case .trashed: synth.play(.step)
        case .machineReady: synth.play(.ok)
        case .nope: synth.play(.nope)
        case .seatbelt(let on):
            seatbelt = on
            if on { synth.play(.chime) }
        case .turbulence(let intensity):
            if intensity > 0 {
                synth.play(.rumble)
                if haptics { jolt.impactOccurred(intensity: min(1, 0.5 + intensity)) }
            }
        case .stumble: synth.play(.whoa)
        case .crewStumble:
            synth.play(.fail)
            if haptics { jolt.impactOccurred(intensity: 1) }
        case .buckled: synth.play(.pick)
        case .wokeUp: break
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
                                     goal: sim.plan.goal, goalMet: sim.goalMet)
                result = r
                onEnded?(plan, r)
                screen = .ended
            }
        }
    }

    /// Repeating cues while something is ongoing: grumbles from the loudest waiting passenger,
    /// haptic bumps while the cabin shakes.
    private func playAmbience(_ dt: Double) {
        let loudest = sim.occurrences.map(sim.noiseLevel).max() ?? 0
        if loudest > 0 {
            grumbleTimer -= dt
            if grumbleTimer <= 0 {
                synth.play(loudest >= 2 ? .grumbleLoud : .grumble)
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
    }
}
