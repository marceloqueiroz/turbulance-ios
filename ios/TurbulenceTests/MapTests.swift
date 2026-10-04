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

    func testRouteOneIsOpenFromTheStartAndTheRestWaitForStars() {
        let state = MapState(profile: profile())
        XCTAssertEqual(state.access(Campaign.route1), .open)
        XCTAssertEqual(state.access(Campaign.route2), .locked(needs: 12, have: 0))
        XCTAssertEqual(state.cover(layout.region("R1")!), .none)
        XCTAssertEqual(state.cover(layout.region("R2")!), .clouds)
    }

    func testRouteTwoOpensAtTwelveStars() {
        let state = MapState(profile: profile(stars: twoStars(on: [1])))
        XCTAssertEqual(state.access(Campaign.route2), .open)
        XCTAssertEqual(state.cover(layout.region("R2")!), .none)
        XCTAssertEqual(state.access(Campaign.route3), .locked(needs: 36, have: 12))
    }

    func testSpecialsAndUnbuiltRoutesSitUnderStorms() {
        let state = MapState(profile: profile(stars: twoStars(on: [1, 2, 3])))
        for id in ["S1", "S2", "R4", "R5"] { XCTAssertEqual(state.cover(layout.region(id)!), .storm, id) }
        let unbuilt = Route(id: 9, name: "Later", aircraftNames: "", cities: ["A"], flights: [], unlockStars: 0)
        XCTAssertEqual(state.access(unbuilt), .comingSoon)
    }

    func testFlightStatesFollowStarsAndTheNextFlight() {
        let f = Campaign.route1.flights
        let state = MapState(profile: profile(stars: [f[0].id: 3, f[1].id: 1]))
        XCTAssertEqual(state.access(f[0]), .done(stars: 3))
        XCTAssertEqual(state.access(f[1]), .next(stars: 1), "the next flight is the first without three stars, replays included")
        XCTAssertEqual(state.access(f[2]), .open)
        XCTAssertEqual(state.access(f[3]), .locked, "a flight opens only after a star on the one before")
    }

    func testRevealsPlayOncePerNewRouteAndNotForOldSaves() {
        let stars = twoStars(on: [1])
        XCTAssertEqual(MapState(profile: profile(stars: stars, seen: nil)).pendingReveals, [], "a first visit counts open routes as seen")
        XCTAssertEqual(MapState(profile: profile(stars: stars, seen: nil)).seenAfterVisit, [1, 2])

        let unlocked = MapState(profile: profile(stars: stars, seen: [1]))
        XCTAssertEqual(unlocked.pendingReveals, [2], "route 2 just opened")
        XCTAssertEqual(MapState(profile: profile(stars: stars, seen: unlocked.seenAfterVisit)).pendingReveals, [], "it plays once")
    }

    func testOldSavesWithoutSeenRoutesStillLoad() throws {
        let old = #"{"name":"Ana","avatar":1,"stars":{"TB101":2},"best":{},"medals":[],"options":{"shake":"full","largeText":false}}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertNil(p.seenRoutes)
        XCTAssertEqual(p.stars["TB101"], 2)
    }
}
