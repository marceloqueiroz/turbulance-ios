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
    enum Screen: Equatable { case idle, playing, paused, ended }

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
    var plan = Campaign.route1.flights[0]
    var largeText = false

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
            sim = FlightSimulation(plan: p)
            sim.start()
            screen = .playing
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
    }

    var isDebugLaunch: Bool { screen == .playing }

    func start(_ plan: FlightPlan) {
        synth.warmUp()
        self.plan = plan
        sim = FlightSimulation(plan: plan)
        sim.start()
        result = nil
        toast = nil
        seatbelt = false
        screen = .playing
        scene.reset()
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
        let sat = Int(sim.satisfaction.rounded())
        if sat != satisfaction { satisfaction = sat }
    }
}
