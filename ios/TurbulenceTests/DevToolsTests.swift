#if DEBUG
import XCTest
@testable import Turbulence

/// The Options card's Developer section (debug builds only).
final class DevToolsTests: XCTestCase {
    override func tearDown() {
        DevSettings.skipFlightIntro = false
        super.tearDown()
    }

    private func model(_ names: [String?]) -> AppModel {
        var s = ProfileSlots()
        for (i, name) in names.enumerated() { if let name { s.create(in: i, name: name, avatar: 0) } }
        return AppModel(slots: s, device: DeviceSettings(), persist: false)
    }

    func testDevProfileHasTwoStarsEverywhereAndOpensEveryRoute() throws {
        let app = model(["Ana"])
        app.makeDevProfile()
        let p = try XCTUnwrap(app.profile)
        XCTAssertEqual(p.name, "Dev")
        XCTAssertEqual(app.slots.active, 1, "goes in the first empty slot")
        XCTAssertEqual(app.screen, .map)
        for route in Campaign.routes { XCTAssertTrue(p.isUnlocked(route), "route \(route.id)") }
        for f in Campaign.routes.flatMap(\.flights) {
            XCTAssertEqual(p.stars[f.id], 2, f.id)
            XCTAssertTrue(p.isUnlocked(f), f.id)
        }
        XCTAssertEqual(app.slots.slots[0]?.name, "Ana")
    }

    func testDevProfileReusesItsSlotAndResetsIt() {
        var s = ProfileSlots()
        s.create(in: 0, name: "Ana", avatar: 0)
        s.create(in: 2, name: "Dev", avatar: 0)
        s.slots[2]?.stars["TB101"] = 3
        let app = AppModel(slots: s, device: DeviceSettings(), persist: false)
        app.makeDevProfile()
        XCTAssertEqual(app.slots.active, 2)
        XCTAssertEqual(app.profile?.stars["TB101"], 2)
        XCTAssertNil(app.slots.slots[1], "doesn't take a second slot")
    }

    func testDevProfileNeverOverwritesAFullCrew() {
        let app = model(["A", "B", "C", "D"])
        XCTAssertNil(app.slots.devSlot)
        app.makeDevProfile()
        XCTAssertEqual(app.slots.slots.map { $0?.name }, ["A", "B", "C", "D"])
        XCTAssertNotEqual(app.screen, .map)
    }

    func testSkipFlightIntroGoesStraightToTheCountdown() {
        let app = model(["Ana"])
        DevSettings.skipFlightIntro = true
        app.board(Campaign.route1.flights[0])
        XCTAssertNil(app.game.intro3D)
        XCTAssertEqual(app.game.screen, .countdown)

        DevSettings.skipFlightIntro = false
        app.board(Campaign.route1.flights[0])
        XCTAssertEqual(app.game.screen, .intro)
    }
}
#endif
