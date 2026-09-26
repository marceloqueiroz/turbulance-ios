import Foundation
import Observation

/// App navigation and the saved profiles (GDD §9a flow:
/// launch → studio logo → title card (auto) → route map → briefing (only when loading a flight) → flight → scorecard → route map).
@Observable
final class AppModel {
    enum Screen: Equatable { case studio, splash, map, game }

    var screen: Screen = .studio
    private(set) var slots: ProfileSlots
    var briefing: FlightPlan?
    var showOptions = false
    var showProfiles = false
    /// The slot the name-and-look card is filling (first run, or "+ New crew").
    var newCrewSlot: Int?
    /// Set when the last flight beat the profile's best satisfaction.
    var newBest = false
    let game = GameController()

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetProfile") { ProfileStore.delete() }
        slots = ProfileStore.load()
        if let p = slots.current { game.apply(p.options, avatar: p.avatar) }
        game.onEnded = { [weak self] plan, result in self?.record(plan, result) }
        if game.isDebugLaunch { screen = .game }
        else if args.contains("-map") { finishSplash() }
        else if args.contains("-profiles") { finishSplash(); showProfiles = profile != nil }
    }

    /// The active profile; writes go straight to disk.
    var profile: Profile? {
        get { slots.current }
        set { slots.current = newValue; ProfileStore.save(slots) }
    }

    var options: GameOptions { profile?.options ?? GameOptions() }

    func finishStudio() { screen = .splash }

    /// The title card hands over to the map; the first run asks for a crew member on top of it.
    func finishSplash() {
        guard screen != .map else { return }
        briefing = nil
        screen = .map
        if profile == nil { newCrewSlot = slots.firstEmpty ?? 0 }
    }

    /// The name-and-look card: creates the profile in its slot and makes it active, then back to the map.
    func createProfile(name: String, avatar: Int) {
        guard let slot = newCrewSlot, let p = slots.create(in: slot, name: name, avatar: avatar) else { return }
        ProfileStore.save(slots)
        game.apply(p.options, avatar: p.avatar)
        newCrewSlot = nil
        showProfiles = false
    }

    func startNewCrew(in slot: Int) { newCrewSlot = slot }

    /// Closing the new-crew card is only possible when someone is already on the roster.
    func cancelNewCrew() { if profile != nil { newCrewSlot = nil } }

    func switchProfile(to slot: Int) {
        slots.switchTo(slot)
        ProfileStore.save(slots)
        if let p = profile { game.apply(p.options, avatar: p.avatar) }
        showProfiles = false
    }

    func deleteProfile(_ slot: Int) {
        slots.delete(slot)
        ProfileStore.save(slots)
        if let p = profile {
            game.apply(p.options, avatar: p.avatar)
        } else {
            showProfiles = false
            newCrewSlot = slots.firstEmpty ?? 0
        }
    }

    func openMap(brief plan: FlightPlan? = nil) {
        game.idle()
        briefing = plan
        screen = .map
    }

    /// Boards a flight. The intro cutscene plays before every flight, retries included (GDD §8b).
    func board(_ plan: FlightPlan, intro: Bool = true) {
        briefing = nil
        newBest = false
        game.start(plan, intro: intro)
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
        game.apply(options, avatar: p.avatar)
    }

    private func record(_ plan: FlightPlan, _ result: FlightResult) {
        guard var p = profile, plan != .prototype else { return }       // debug flights don't count
        newBest = p.record(plan, stars: result.stars, satisfaction: result.satisfaction, goalMet: result.goalMet)
        profile = p
    }
}
