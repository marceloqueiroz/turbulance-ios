import XCTest
@testable import Turbulence

/// Landing page routing and the device/profile settings split (GDD §9a).
final class AppModelTests: XCTestCase {
    private func model(_ names: [String?], active: Int = 0) -> AppModel {
        var s = ProfileSlots()
        for (i, name) in names.enumerated() { if let name { s.create(in: i, name: name, avatar: 0) } }
        s.switchTo(active)
        return AppModel(slots: s, device: DeviceSettings(), persist: false)
    }

    func testTitleCardSettlesOnTheLandingPage() {
        let app = model([])
        XCTAssertEqual(app.screen, .studio)
        app.finishStudio()
        app.finishSplash()
        XCTAssertEqual(app.screen, .landing)
        XCTAssertNil(app.sheet, "the first run no longer pops the name card by itself")
    }

    func testContinueNeedsAProfileAndAlwaysShowsThePicker() {
        let empty = model([])
        empty.continueGame()
        XCTAssertNil(empty.sheet)

        let one = model(["Ana"])
        one.continueGame()
        XCTAssertEqual(one.sheet, .picker, "the picker shows even for a single profile")
        one.continueAs(0)
        XCTAssertNil(one.sheet)
        XCTAssertEqual(one.screen, .map)
        XCTAssertEqual(one.profile?.name, "Ana")
    }

    func testContinueAsSwitchesTheActiveProfile() {
        let app = model(["Ana", nil, "Bo"], active: 0)
        app.continueGame()
        app.continueAs(1)
        XCTAssertEqual(app.sheet, .picker, "an empty slot can't be flown")
        app.continueAs(2)
        XCTAssertEqual(app.profile?.name, "Bo")
        XCTAssertEqual(app.screen, .map)
    }

    func testNewGameFillsTheFirstEmptySlotAndOpensTheMap() {
        let app = model(["Ana", nil])
        app.newGame()
        XCTAssertEqual(app.sheet, .newCrew(1))
        app.createProfile(name: "Cy", avatar: 3)
        XCTAssertEqual(app.slots.slots[1]?.name, "Cy")
        XCTAssertEqual(app.profile?.name, "Cy", "the new crew member becomes active")
        XCTAssertEqual(app.screen, .map)
        XCTAssertNil(app.sheet)
    }

    func testNewGameWithAFullCrewDeletesThenNamesInTheFreedSlot() {
        let app = model(["A", "B", "C", "D"])
        app.newGame()
        XCTAssertEqual(app.sheet, .replace)
        app.deleteProfile(2)
        XCTAssertNil(app.slots.slots[2])
        XCTAssertEqual(app.sheet, .newCrew(2))
        app.createProfile(name: "E", avatar: 0)
        XCTAssertEqual(app.slots.slots[2]?.name, "E")
    }

    func testDeletingTheLastProfileClosesThePicker() {
        let app = model(["Ana"])
        app.continueGame()
        app.deleteProfile(0)
        XCTAssertTrue(app.slots.isEmpty)
        XCTAssertNil(app.sheet)
    }

    func testMenuReturnsToTheLanding() {
        let app = model(["Ana"])
        app.continueAs(0)
        app.briefing = Campaign.route1.flights[0]
        app.goToLanding()
        XCTAssertEqual(app.screen, .landing)
        XCTAssertNil(app.briefing)
    }

    func testDeviceSettingsDoNotNeedAProfile() {
        let app = model([])
        app.update(DeviceSettings(volume: 0.3, haptics: false))
        XCTAssertEqual(app.device, DeviceSettings(volume: 0.3, haptics: false))
    }

    func testLegacySaveHandsOverSoundAndHaptics() throws {
        let old = #"{"active":1,"slots":[null,{"name":"Ana","avatar":0,"stars":{},"best":{},"medals":[],"options":{"volume":0.25,"haptics":false,"shake":"reduced","largeText":true}},null,null]}"#
        let data = Data(old.utf8)
        XCTAssertEqual(DeviceSettingsStore.legacy(slots: data, profile: nil), DeviceSettings(volume: 0.25, haptics: false))
        let slots = try JSONDecoder().decode(ProfileSlots.self, from: data)
        XCTAssertEqual(slots.current?.options, GameOptions(shake: .reduced, largeText: true), "accessibility stays with the profile")

        var fresh = ProfileSlots()
        fresh.create(in: 0, name: "Bo", avatar: 0)
        XCTAssertNil(DeviceSettingsStore.legacy(slots: try JSONEncoder().encode(fresh), profile: nil), "a new-style save has nothing to hand over")
    }
}
