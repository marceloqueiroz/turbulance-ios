import Foundation

/// One bump of turbulence as the galley feels it (GDD §9a): when (seconds on the menu's clock), how hard (0–1)
/// and which way (+1 or −1). Every loose item gets the same kick, so they all lurch the same way.
struct GalleyKick: Equatable {
    let time: TimeInterval
    let strength: Double
    let sign: Double

    static func random(at time: TimeInterval) -> GalleyKick {
        GalleyKick(time: time, strength: .random(in: 0.6...1), sign: Bool.random() ? 1 : -1)
    }
}

/// A damped spring that each kick sets ringing. The spring is linear, so its motion is the sum of each kick's
/// ringing: two bumps close together add up, and the value is a pure function of the time and the kicks.
struct Sway {
    /// The swing a full-strength kick gives at its peak (degrees, or wall pixels for a slide).
    let amplitude: Double
    /// How fast it rings (Hz).
    let frequency: Double
    /// Seconds until it has died down to about 2%.
    let settle: Double
    /// Seconds it lags the kick (so neighbours move slightly out of step).
    var delay: Double = 0
    /// Never further than this, however the kicks add up (default 1.5 × the amplitude).
    var limit: Double?

    private var decay: Double { 4 / settle }
    private var omega: Double { 2 * .pi * frequency }

    /// Scales the ringing so a full kick peaks at exactly `amplitude`.
    private var peakScale: Double {
        let tPeak = atan(omega / decay) / omega
        return 1 / (exp(-decay * tPeak) * sin(omega * tPeak))
    }

    func value(at t: TimeInterval, kicks: [GalleyKick]) -> Double {
        var v = 0.0
        for k in kicks {
            let dt = t - k.time - delay
            guard dt > 0, dt < settle * 1.5 else { continue }
            v += k.sign * k.strength * exp(-decay * dt) * sin(omega * dt)
        }
        let cap = limit ?? amplitude * 1.5
        return max(-cap, min(cap, v * amplitude * peakScale))
    }

    /// True once every kick has died down, so the clock can stop.
    func isResting(at t: TimeInterval, kicks: [GalleyKick]) -> Bool {
        kicks.allSatisfy { t - $0.time - delay > settle * 1.5 }
    }
}

/// How each loose thing in the galley moves (GDD §9a "Turbulence on the galley"; specs/galley-main-menu).
/// Starting values to tune on device. Angles in degrees, slides and hops in wall pixels.
enum GalleyMotion {
    static let tag = Sway(amplitude: 18, frequency: 0.9, settle: 2.6, delay: 0.04, limit: 24)
    static let manualTip = Sway(amplitude: 7, frequency: 1.6, settle: 1.0, limit: 8)
    static let manualSlide = Sway(amplitude: 18, frequency: 1.6, settle: 1.0, delay: 0.02, limit: 22)
    static let cartTilt = Sway(amplitude: 1.3, frequency: 2.4, settle: 0.7)
    static let cartSlide = Sway(amplitude: 12, frequency: 2.4, settle: 0.7)
    /// The second cart lags the first a little.
    static let cartLag = 0.07
    static let cupHop = Sway(amplitude: 10, frequency: 3, settle: 0.45)
    static let coffeeTilt = Sway(amplitude: 12, frequency: 1.1, settle: 2.0)
    static let lightFlicker = Sway(amplitude: 1, frequency: 7, settle: 0.35)

    /// Kicks older than this no longer move anything (the slowest item, the tag, settles in 2.6 s).
    static let memory: TimeInterval = 4

    /// Between bumps: the tag drifts in the air from a vent and the coffee ripples.
    static func tagDrift(at t: TimeInterval) -> Double { 1.6 * sin(t * 2 * .pi * 0.35) + 0.5 * sin(t * 2 * .pi * 0.9) }
    static func coffeeRipple(at t: TimeInterval) -> Double { 0.8 * sin(t * 2 * .pi * 0.4) }

    static var all: [Sway] { [tag, manualTip, manualSlide, cartTilt, cartSlide, cupHop, coffeeTilt, lightFlicker] }
}
