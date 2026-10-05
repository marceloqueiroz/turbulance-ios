#if DEBUG
import Foundation

/// Developer switches from the Options card's Developer section (debug builds only).
/// Kept out of `DeviceSettings` so release saves never carry them.
enum DevSettings {
    private static let skipIntroKey = "dev.skipFlightIntro"

    /// Boarding goes straight to the 3-2-1 countdown, without the 3D intro cutscene.
    static var skipFlightIntro: Bool {
        get { UserDefaults.standard.bool(forKey: skipIntroKey) }
        set { UserDefaults.standard.set(newValue, forKey: skipIntroKey) }
    }
}

extension ProfileSlots {
    static let devName = "Dev"

    /// The slot the Dev crew member goes in: its own if it exists, else the first empty one; nil when four others are full.
    var devSlot: Int? { slots.firstIndex { $0?.name == Self.devName } ?? firstEmpty }

    /// Creates (or resets) the Dev crew member with two stars on every flight, which opens every route, and makes it active.
    @discardableResult
    mutating func makeDev() -> Bool {
        guard let slot = devSlot else { return false }
        var p = Profile(name: Self.devName, avatar: 0)
        for f in Campaign.routes.flatMap(\.flights) { p.stars[f.id] = 2 }
        slots[slot] = p
        active = slot
        return true
    }
}
#endif
