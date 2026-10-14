import XCTest
@testable import Turbulence

/// The route map's layout data and state rules (Route Map Plan, step 4).
final class MapTests: XCTestCase {
    private let layout = MapLayout.main

    // MARK: Layout

    func testEveryCampaignCityHasAnAirportOnItsRoutesRegion() {
        for route in Campaign.routes {
            for (i, city) in route.cities.enumerated() {
                let airport = layout.airport(city)
                XCTAssertNotNil(airport, "\(city) on route \(route.id) has no airport in MapLayout.json")
                // a route's first city can be the last stop of the route before it (Vale City, Beacon Isle)
                if i > 0, let airport { XCTAssertEqual(layout.region(airport.region)?.route, route.id, "\(city) sits on the wrong region") }
            }
        }
    }

    func testAirportsSitInsideTheirRegionAndRegionsInsideTheWorld() {
        for a in layout.airports {
            XCTAssertNotNil(layout.region(a.region), "\(a.city) names an unknown region")
            XCTAssertTrue((0...1).contains(a.at[0]) && (0...1).contains(a.at[1]), "\(a.city) is outside its region image")
        }
        for r in layout.regions {
            XCTAssertTrue(layout.bounds.contains(r.frame), "region \(r.id) runs off the world")
            XCTAssertEqual(r.center.count, 2); XCTAssertEqual(r.size.count, 2)
        }
        XCTAssertEqual(Set(layout.airports.map(\.city)).count, layout.airports.count, "a city is placed twice")
    }

    func testRegionsDoNotOverlap() {
        for (i, a) in layout.regions.enumerated() {
            for b in layout.regions.dropFirst(i + 1) {
                XCTAssertFalse(a.frame.intersects(b.frame), "regions \(a.id) and \(b.id) overlap")
            }
        }
    }

    func testEveryRouteHasARegionAndItsImageShips() {
        for route in Campaign.routes { XCTAssertNotNil(layout.region(forRoute: route.id), "route \(route.id) has no region") }
        for r in layout.regions { XCTAssertNotNil(UIImage(named: r.image), "\(r.image) is missing from the asset catalog") }
    }

    func testCityLifePointsSitInTheirRegionAndActorsShip() {
        for r in layout.regions {
            for entry in r.life ?? [] {
                XCTAssertFalse(entry.points.isEmpty, "an empty \(entry.kind) path in \(r.id)")
                for p in entry.points {
                    XCTAssertTrue(p.count == 2 && (0...1).contains(p[0]) && (0...1).contains(p[1]), "\(r.id) life point \(p) is outside the region")
                }
                for name in entry.actors ?? [] {
                    XCTAssertNotNil(UIImage(named: "Map/\(name)"), "\(r.id) uses a missing actor \(name)")
                }
            }
        }
    }

    // MARK: States

    private func profile(stars: [String: Int] = [:], seen: Set<Int>? = nil) -> Profile {
        var p = Profile(name: "Ana", avatar: 0)
        p.stars = stars
        p.seenRoutes = seen
        return p
    }

    /// Two stars on every flight of the given routes.
    private func twoStars(on routeIDs: [Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Campaign.routes.filter { routeIDs.contains($0.id) }.flatMap(\.flights).map { ($0.id, 2) })
    }

    func testRouteTwoWaitsForEveryRouteOneFlightToBePassed() {
        let state = MapState(profile: profile(), fullGame: true)
        XCTAssertEqual(state.access(Campaign.route1), .open)
        XCTAssertEqual(state.access(Campaign.route2), .needsRoute(1))
        XCTAssertEqual(state.cover(layout.region("R1")!), .none)
        XCTAssertEqual(state.cover(layout.region("R2")!), .clouds)

        var stars = Dictionary(uniqueKeysWithValues: Campaign.route1.flights.map { ($0.id, 3) })
        stars[Campaign.route1.flights.last!.id] = nil
        XCTAssertEqual(MapState(profile: profile(stars: stars), fullGame: true).access(Campaign.route2), .needsRoute(1),
                       "lots of stars aren't enough: the last flight still needs one")
        stars[Campaign.route1.flights.last!.id] = 1
        XCTAssertEqual(MapState(profile: profile(stars: stars), fullGame: true).access(Campaign.route2), .open)
        XCTAssertEqual(MapState(profile: profile(stars: stars), fullGame: false).access(Campaign.route2), .needsFullGame,
                       "finishing Route 1 doesn't open Route 2 without the purchase")
    }

    func testRouteThreeOpensAtThirtySixStars() {
        let state = MapState(profile: profile(stars: twoStars(on: [1, 2])), fullGame: true)
        XCTAssertEqual(state.access(Campaign.route3), .open)
        XCTAssertEqual(state.cover(layout.region("R3")!), .none)
    }

    func testOnlyLongHaulSitsUnderStormsAndTheOtherUnbuiltPlacesAreHidden() {
        let state = MapState(profile: profile(stars: twoStars(on: [1, 2, 3])), fullGame: true)
        XCTAssertEqual(state.cover(layout.region("R4")!), .storm)
        for id in ["S1", "S2", "R5"] { XCTAssertEqual(state.cover(layout.region(id)!), .hidden, id) }
        let comingSoon = layout.regions.filter { state.cover($0) == .storm }.map(\.id)
        XCTAssertEqual(comingSoon, ["R4"], "exactly one region says Coming soon")
        for id in ["R1", "R2", "R3"] { XCTAssertNotEqual(state.cover(layout.region(id)!), .hidden, id) }
        let unbuilt = Route(id: 9, name: "Later", aircraftNames: "", cities: ["A"], flights: [], unlockStars: 0)
        XCTAssertEqual(state.access(unbuilt), .comingSoon)
    }

    // MARK: Full Game (GDD §9)

    func testWithoutFullGameRoutesTwoAndUpWaitBehindThePaywallEvenWithStars() {
        let state = MapState(profile: profile(stars: twoStars(on: [1, 2, 3])), fullGame: false)
        XCTAssertEqual(state.access(Campaign.route1), .open, "Route 1 is free")
        XCTAssertEqual(state.access(Campaign.route2), .needsFullGame)
        XCTAssertEqual(state.access(Campaign.route3), .needsFullGame)
        XCTAssertEqual(state.cover(layout.region("R2")!), .clouds)
        XCTAssertEqual(state.access(Campaign.route2.flights[0]), .locked)
        XCTAssertEqual(state.openRoutes, [1])
    }

    func testOwningFullGameStillNeedsTheStarsForRouteThree() {
        let state = MapState(profile: profile(stars: twoStars(on: [1])), fullGame: true)
        XCTAssertEqual(state.access(Campaign.route2), .open)
        XCTAssertEqual(state.access(Campaign.route3), .locked(needs: 36, have: 12))
    }

    func testNextFlightStaysOnRouteOneWithoutFullGame() {
        let p = profile(stars: Dictionary(uniqueKeysWithValues: Campaign.route1.flights.map { ($0.id, 3) }))
        XCTAssertEqual(p.nextFlight(fullGame: false), Campaign.route1.flights.last, "everything open is done: the last open flight")
        XCTAssertEqual(p.nextFlight(fullGame: true), Campaign.route2.flights[0])
    }

    func testBuyingFullGameRevealsTheRoutesItOpens() {
        let fresh = MapState(profile: profile(seen: [1]), fullGame: false)
        XCTAssertEqual(fresh.pendingReveals, [], "nothing to reveal without the purchase")
        XCTAssertEqual(MapState(profile: profile(seen: fresh.seenAfterVisit), fullGame: true).pendingReveals, [],
                       "a new player who buys still has Route 1 to finish")
        XCTAssertEqual(MapState(profile: profile(stars: twoStars(on: [1]), seen: [1]), fullGame: true).pendingReveals, [2],
                       "Route 1 finished: buying opens Route 2 straight away")

        let stars = twoStars(on: [1, 2])           // 12 + 24 stars: enough for Route 3 too
        let before = MapState(profile: profile(stars: stars, seen: [1]), fullGame: false)
        XCTAssertEqual(before.seenAfterVisit, [1])
        XCTAssertEqual(MapState(profile: profile(stars: stars, seen: before.seenAfterVisit), fullGame: true).pendingReveals, [2, 3])
    }

    func testFlightStatesFollowStarsAndTheNextFlight() {
        let f = Campaign.route1.flights
        let state = MapState(profile: profile(stars: [f[0].id: 3, f[1].id: 1]), fullGame: false)
        XCTAssertEqual(state.access(f[0]), .done(stars: 3))
        XCTAssertEqual(state.access(f[1]), .next(stars: 1), "the next flight is the first without three stars, replays included")
        XCTAssertEqual(state.access(f[2]), .open)
        XCTAssertEqual(state.access(f[3]), .locked, "a flight opens only after a star on the one before")
    }

    func testRevealsPlayOncePerNewRouteAndNotForOldSaves() {
        let stars = twoStars(on: [1])
        XCTAssertEqual(MapState(profile: profile(stars: stars, seen: nil), fullGame: true).pendingReveals, [], "a first visit counts open routes as seen")
        XCTAssertEqual(MapState(profile: profile(stars: stars, seen: nil), fullGame: true).seenAfterVisit, [1, 2])

        let unlocked = MapState(profile: profile(stars: stars, seen: [1]), fullGame: true)
        XCTAssertEqual(unlocked.pendingReveals, [2], "route 2 just opened")
        XCTAssertEqual(MapState(profile: profile(stars: stars, seen: unlocked.seenAfterVisit), fullGame: true).pendingReveals, [], "it plays once")
    }

    func testOldSavesWithoutSeenRoutesStillLoad() throws {
        let old = #"{"name":"Ana","avatar":1,"stars":{"TB101":2},"best":{},"medals":[],"options":{"shake":"full","largeText":false}}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertNil(p.seenRoutes)
        XCTAssertEqual(p.stars["TB101"], 2)
    }
}
