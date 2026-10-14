import Foundation

/// What the route map shows for one profile (Route Map Plan, Design → States). Pure rules, no drawing.
struct MapState {
    enum RouteAccess: Equatable {
        case open
        case needsFullGame                       // routes 2 and up without the purchase: clouds + padlock (GDD §9)
        case needsRoute(Int)                     // owned, but every flight of that route needs a star first: clouds + padlock
        case locked(needs: Int, have: Int)      // owned but not enough stars yet: clouds + padlock
        case comingSoon                          // not built yet: storm clouds
    }

    enum FlightAccess: Equatable {
        case done(stars: Int)
        case next(stars: Int)                    // the first open flight without three stars (a replay counts); pulses
        case open
        case locked                              // the flight before it has no star yet
    }

    enum Cover: Equatable { case none, clouds, storm, hidden }

    let profile: Profile
    /// The device owns the Full Game purchase.
    let fullGame: Bool
    var routes: [Route] = Campaign.routes

    init(profile: Profile, fullGame: Bool) {
        self.profile = profile
        self.fullGame = fullGame
    }

    /// Checked in this order, so a player without the purchase sees the paywall first, even with enough stars.
    func access(_ route: Route) -> RouteAccess {
        if route.inDevelopment { return .comingSoon }
        if route.requiresFullGame && !fullGame { return .needsFullGame }
        if let before = route.opensAfter, !profile.hasPassed(route: before) { return .needsRoute(before) }
        return profile.isUnlocked(route, fullGame: fullGame) ? .open : .locked(needs: route.unlockStars, have: profile.totalStars)
    }

    func access(_ plan: FlightPlan) -> FlightAccess {
        guard profile.isUnlocked(plan, fullGame: fullGame) else { return .locked }
        let stars = profile.stars[plan.id] ?? 0
        if plan == profile.nextFlight(fullGame: fullGame) { return .next(stars: stars) }
        return stars > 0 ? .done(stars: stars) : .open
    }

    /// Hidden regions aren't drawn at all; specials and future routes stay under storm clouds until they are built.
    func cover(_ region: MapLayout.Region) -> Cover {
        if region.hidden == true { return .hidden }
        guard region.kind == .route, let id = region.route, let route = routes.first(where: { $0.id == id }) else { return .storm }
        switch access(route) {
        case .open: return .none
        case .locked, .needsFullGame, .needsRoute: return .clouds
        case .comingSoon: return .storm
        }
    }

    var openRoutes: Set<Int> { Set(routes.filter { access($0) == .open }.map(\.id)) }

    /// Routes open now that this profile hasn't watched clear yet, in order. A profile that has never opened the
    /// new map counts everything already open as seen, so existing players aren't hit with a reveal for every route.
    /// Buying Full Game opens routes here too, so the purchase plays the same reveal.
    var pendingReveals: [Int] {
        guard let seen = profile.seenRoutes else { return [] }
        return openRoutes.subtracting(seen).sorted()
    }

    /// The seen set to store once the map has shown its reveals (or on the first visit, to start tracking).
    var seenAfterVisit: Set<Int> { (profile.seenRoutes ?? []).union(openRoutes) }
}
