import Foundation
import Observation

/// App navigation, the saved profiles and the device settings (GDD §9a flow:
/// launch → studio logo → title card → landing → Continue (pick a profile) or New Game → route map
/// → briefing (only when loading a flight) → flight → scorecard → route map).
@Observable
final class AppModel {
    enum Screen: Equatable { case studio, splash, landing, map, game }

    /// The card on top of the current screen; one at a time.
    enum Sheet: Equatable {
        case picker             // Continue: pick a profile
        case replace            // New Game with all slots full: delete one to make room
        case newCrew(Int)       // the name-and-look card filling this slot
        case options
        case about
        case paywall            // Unlock the full game (GDD §9)
    }

    /// Where a Full Game purchase or restore stands, for the paywall and Options.
    enum StoreStatus: Equatable {
        case idle
        case working
        case message(String)
    }

    var screen: Screen = .studio
    var sheet: Sheet?
    private(set) var slots: ProfileSlots
    private(set) var device: DeviceSettings
    var briefing: FlightPlan?
    /// Set when the last flight beat the profile's best satisfaction.
    var newBest = false
    /// A flight just finished with at least one star: the route map flies the toy plane along its leg once.
    var pendingLeg: FlightPlan?
    let game = GameController()
    /// Off in tests, so they never touch the saves on disk.
    private let persist: Bool
    /// The developer path editor on the route map (debug builds, -mapEditor).
    private(set) var mapEditor = false

    /// The Full Game purchase (GDD §9) belongs to the Apple ID, so every profile on the device shares it.
    private let store: FullGameStore?
    private(set) var storeOwnsFullGame = false
    private(set) var fullGamePrice: String?
    private(set) var storeStatus = StoreStatus.idle
    #if DEBUG
    /// The Options dev tool: overrides the store either way.
    var devFullGame = DevSettings.fullGame { didSet { if persist { DevSettings.fullGame = devFullGame } } }
    #endif

    var ownsFullGame: Bool {
        #if DEBUG
        switch devFullGame {
        case .owned: return true
        case .locked: return false
        case .store: break
        }
        #endif
        return storeOwnsFullGame
    }

    convenience init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetProfile") {
            ProfileStore.delete()
            DeviceSettingsStore.delete()
        }
        let device = DeviceSettingsStore.load()          // before the profiles: it reads sound and haptics from an old save
        #if DEBUG
        // -demoMap: in memory only, two stars on every Route 1 flight, so the map flies the last leg and reveals Route 2
        if args.contains("-demoMap"), var slots = Optional(ProfileStore.load()), var p = slots.current {
            for f in Campaign.route1.flights { p.stars[f.id] = 2 }
            p.seenRoutes = [1]
            slots.current = p
            self.init(slots: slots, device: device, persist: false, arguments: args)
            pendingLeg = Campaign.route1.flights.last
            screen = .map
            return
        }
        // -flyAllLegs: in memory only, the Dev crew with every route open, so the map can fly each leg in turn
        if args.contains("-flyAllLegs") {
            var slots = ProfileStore.load()
            slots.makeDev()
            slots.current?.seenRoutes = Set(Campaign.routes.map(\.id))
            self.init(slots: slots, device: device, persist: false, arguments: args)
            screen = .map
            return
        }
        #endif
        self.init(slots: ProfileStore.load(), device: device, persist: true, arguments: args)
    }

    init(slots: ProfileSlots, device: DeviceSettings, persist: Bool, arguments args: [String] = [],
         store: FullGameStore? = AppStoreFullGame()) {
        self.slots = slots
        self.device = device
        self.persist = persist
        self.store = store
        #if DEBUG
        if !persist { devFullGame = .store }        // tests and in-memory demos don't read this device's dev switch
        #endif
        if let store {
            store.listen { [weak self] owned in Task { @MainActor in self?.storeOwnsFullGame = owned } }
            Task { @MainActor [weak self] in
                let (owned, price) = await store.refresh()
                self?.storeOwnsFullGame = owned
                self?.fullGamePrice = price
            }
        }
        game.apply(device)
        if let p = slots.current { game.apply(p.options, avatar: p.avatar) }
        game.onEnded = { [weak self] plan, result in self?.record(plan, result) }
        #if DEBUG
        mapEditor = args.contains("-mapEditor")
        #endif
        if game.isDebugLaunch { screen = .game }
        else if args.contains("-map") { screen = profile == nil ? .landing : .map }
        else if args.contains("-landing") { screen = .landing }
        else if args.contains("-profiles") { screen = .landing; continueGame() }
    }

    /// The active profile (the one flown last); writes go straight to disk.
    var profile: Profile? {
        get { slots.current }
        set { slots.current = newValue; saveSlots() }
    }

    var options: GameOptions { profile?.options ?? GameOptions() }

    func finishStudio() { screen = .splash }

    /// The title card settles into the landing page.
    func finishSplash() {
        guard screen == .studio || screen == .splash else { return }
        screen = .landing
    }

    // MARK: Landing

    /// Continue opens the picker, even with a single profile.
    func continueGame() {
        guard !slots.isEmpty else { return }
        sheet = .picker
    }

    /// New Game fills the first empty slot; with all four full it asks to make room first.
    func newGame() {
        if let slot = slots.firstEmpty { sheet = .newCrew(slot) } else { sheet = .replace }
    }

    func dismissSheet() { sheet = nil }

    /// Picking a profile makes it active and opens its route map.
    func continueAs(_ slot: Int) {
        guard slots.slots.indices.contains(slot), slots.slots[slot] != nil else { return }
        slots.switchTo(slot)
        saveSlots()
        applyProfile()
        sheet = nil
        openMap()
    }

    /// An empty slot in the picker opens the name-and-look card for it.
    func startNewCrew(in slot: Int) { sheet = .newCrew(slot) }

    /// The name-and-look card: creates the profile in its slot, makes it active and opens the map on its first flight.
    func createProfile(name: String, avatar: Int) {
        guard case .newCrew(let slot) = sheet, slots.create(in: slot, name: name, avatar: avatar) != nil else { return }
        saveSlots()
        applyProfile()
        sheet = nil
        openMap()
    }

    /// Deleting from the replace picker goes straight on to the new crew member in the freed slot.
    func deleteProfile(_ slot: Int) {
        slots.delete(slot)
        saveSlots()
        applyProfile()
        if sheet == .replace { sheet = .newCrew(slot) }
        else if slots.isEmpty { sheet = nil }
    }

    func goToLanding() {
        game.idle()
        briefing = nil
        sheet = nil
        screen = .landing
    }

    // MARK: Map and flights

    func openMap(brief plan: FlightPlan? = nil) {
        game.idle()
        briefing = plan
        screen = .map
    }

    /// Boards a flight. The intro cutscene plays before every flight, retries included (GDD §8b).
    func board(_ plan: FlightPlan, intro: Bool = true) {
        briefing = nil
        newBest = false
        #if DEBUG
        let intro = intro && !DevSettings.skipFlightIntro
        #endif
        game.start(plan, intro: intro)
        screen = .game
    }

    /// The first visit to the route map starts tracking unlock reveals; routes already open count as seen.
    func markMapVisited() {
        guard var p = profile, p.seenRoutes == nil else { return }
        p.seenRoutes = MapState(profile: p, fullGame: ownsFullGame).seenAfterVisit
        profile = p
    }

    /// After the map has played its unlock reveals.
    func markRevealsSeen() {
        guard var p = profile else { return }
        p.seenRoutes = MapState(profile: p, fullGame: ownsFullGame).seenAfterVisit
        profile = p
    }

    var mapState: MapState? { profile.map { MapState(profile: $0, fullGame: ownsFullGame) } }

    func nextFlight(after plan: FlightPlan) -> FlightPlan? {
        guard let next = Campaign.flight(after: plan), profile?.isUnlocked(next, fullGame: ownsFullGame) == true else { return nil }
        return next
    }

    /// The route the scorecard offers to unlock: the next flight is on a route that needs Full Game, and it isn't owned.
    func routeToUnlock(after plan: FlightPlan) -> Route? {
        guard !ownsFullGame, let next = Campaign.flight(after: plan), let route = Campaign.route(containing: next.id),
              route.requiresFullGame, !route.inDevelopment else { return nil }
        return route
    }

    // MARK: Full Game (GDD §9)

    func showPaywall() {
        storeStatus = .idle
        sheet = .paywall
    }

    /// Buys Full Game; on success the card closes and the map plays the reveal for any route that now opens.
    @MainActor func buyFullGame() async {
        guard let store, storeStatus != .working else { return }
        storeStatus = .working
        switch await store.purchase() {
        case .purchased:
            storeOwnsFullGame = true
            storeStatus = .idle
            if sheet == .paywall { sheet = nil }
        case .pending: storeStatus = .message("Waiting for approval. Routes open as soon as it's approved.")
        case .cancelled: storeStatus = .idle
        case .failed(let why): storeStatus = .message(why)
        }
    }

    @MainActor func restorePurchases() async {
        guard let store, storeStatus != .working else { return }
        storeStatus = .working
        let owned = await store.restore()
        storeOwnsFullGame = owned
        storeStatus = .message(owned ? "Full game restored." : "Nothing to restore on this Apple Account.")
        if owned, sheet == .paywall { sheet = nil }
    }

    // MARK: Options

    #if DEBUG
    /// Developer section: the Dev crew member with two stars everywhere, opened on the route map.
    func makeDevProfile() {
        guard slots.makeDev() else { return }
        devFullGame = .owned
        saveSlots()
        applyProfile()
        sheet = nil
        openMap()
    }
    #endif

    func update(_ options: GameOptions) {
        guard var p = profile else { return }
        p.options = options
        profile = p
        game.apply(options, avatar: p.avatar)
    }

    func update(_ device: DeviceSettings) {
        self.device = device
        if persist { DeviceSettingsStore.save(device) }
        game.apply(device)
    }

    private func applyProfile() {
        if let p = profile { game.apply(p.options, avatar: p.avatar) }
    }

    private func saveSlots() {
        if persist { ProfileStore.save(slots) }
    }

    private func record(_ plan: FlightPlan, _ result: FlightResult) {
        guard var p = profile, plan != .prototype else { return }       // debug flights don't count
        newBest = p.record(plan, stars: result.stars, satisfaction: result.satisfaction, goalMet: result.goalMet)
        profile = p
        if result.stars > 0 { pendingLeg = plan }
    }
}
