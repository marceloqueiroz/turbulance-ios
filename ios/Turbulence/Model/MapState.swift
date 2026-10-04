import Foundation

/// What the route map shows for one profile (Route Map Plan, Design → States). Pure rules, no drawing.
struct MapState {
    enum RouteAccess: Equatable {
        case open
        case locked(needs: Int, have: Int)      // not enough stars yet: soft clouds
        case comingSoon                          // not built yet: storm clouds
    }

    enum FlightAccess: Equatable {
        case done(stars: Int)
        case next(stars: Int)                    // the first open flight without three stars (a replay counts); pulses
        case open
        case locked                              // the flight before it has no star yet
    }

    enum Cover: Equatable { case none, clouds, storm }

    let profile: Profile
    var routes: [Route] = Campaign.routes

    func access(_ route: Route) -> RouteAccess {
        if route.inDevelopment { return .comingSoon }
        return profile.isUnlocked(route) ? .open : .locked(needs: route.unlockStars, have: profile.totalStars)
    }

    func access(_ plan: FlightPlan) -> FlightAccess {
        guard profile.isUnlocked(plan) else { return .locked }
        let stars = profile.stars[plan.id] ?? 0
        if plan == profile.nextFlight { return .next(stars: stars) }
        return stars > 0 ? .done(stars: stars) : .open
    }

    /// Specials and future routes stay under storm clouds until they are built.
    func cover(_ region: MapLayout.Region) -> Cover {
        guard region.kind == .route, let id = region.route, let route = routes.first(where: { $0.id == id }) else { return .storm }
        switch access(route) {
        case .open: return .none
        case .locked: return .clouds
        case .comingSoon: return .storm
        }
    }

    var openRoutes: Set<Int> { Set(routes.filter { access($0) == .open }.map(\.id)) }

    /// Routes open now that this profile hasn't watched clear yet, in order. A profile that has never opened the
    /// new map counts everything already open as seen, so existing players aren't hit with a reveal for every route.
    var pendingReveals: [Int] {
        guard let seen = profile.seenRoutes else { return [] }
        return openRoutes.subtracting(seen).sorted()
    }

    /// The seen set to store once the map has shown its reveals (or on the first visit, to start tracking).
    var seenAfterVisit: Set<Int> { (profile.seenRoutes ?? []).union(openRoutes) }
}
