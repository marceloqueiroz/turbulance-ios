import Foundation
import Observation

/// App navigation and the saved profile (GDD §9a flow:
/// launch → splash → profile (first run) → menu → route map → briefing → flight → scorecard → route map).
@Observable
final class AppModel {
    enum Screen: Equatable { case studio, splash, onboarding, menu, map, game }

    var screen: Screen = .studio
    var profile: Profile?
    var briefing: FlightPlan?
    var showOptions = false
    /// Set when the last flight beat the profile's best satisfaction.
    var newBest = false
    let game = GameController()

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetProfile") { ProfileStore.delete() }
        profile = ProfileStore.load()
        if let p = profile { game.apply(p.options, avatar: p.avatar) }
        game.onEnded = { [weak self] plan, result in self?.record(plan, result) }
        if game.isDebugLaunch { screen = .game }
        else if args.contains("-map"), profile != nil { screen = .map }
    }

    var options: GameOptions { profile?.options ?? GameOptions() }

    func finishStudio() { screen = .splash }

    func finishSplash() { screen = profile == nil ? .onboarding : .menu }

    /// First run asks only for a name and an avatar, then goes straight to the first flight.
    func createProfile(name: String, avatar: Int) {
        let p = Profile(name: name.trimmingCharacters(in: .whitespaces), avatar: avatar)
        profile = p
        ProfileStore.save(p)
        game.apply(p.options, avatar: p.avatar)
        screen = .map
        briefing = Campaign.route1.flights[0]
    }

    func openMenu() { game.idle(); briefing = nil; screen = .menu }

    func openMap(brief plan: FlightPlan? = nil) {
        game.idle()
        briefing = plan
        screen = .map
    }

    func board(_ plan: FlightPlan) {
        briefing = nil
        newBest = false
        game.start(plan)
        screen = .game
    }

    func nextFlight(after plan: FlightPlan) -> FlightPlan? {
        guard let next = Campaign.flight(after: plan), profile?.isUnlocked(next) == true else { return nil }
        return next
    }

    func update(_ options: GameOptions) {
        guard var p = profile else { return }
        p.options = options
        profile = p
        ProfileStore.save(p)
        game.apply(options, avatar: p.avatar)
    }

    private func record(_ plan: FlightPlan, _ result: FlightResult) {
        guard var p = profile, plan != .prototype else { return }       // debug flights don't count
        newBest = p.record(plan, stars: result.stars, satisfaction: result.satisfaction, goalMet: result.goalMet)
        profile = p
        ProfileStore.save(p)
    }
}
