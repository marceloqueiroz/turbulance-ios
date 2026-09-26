import Foundation

enum ShakeLevel: String, Codable, CaseIterable {
    case full, reduced, off
    var scale: Double { self == .full ? 1 : self == .reduced ? 0.4 : 0 }
    var label: String { rawValue.capitalized }
}

/// Per-profile options (GDD §9a), so accessibility settings follow the person.
struct GameOptions: Codable, Equatable {
    var volume = 0.8
    var haptics = true
    var shake = ShakeLevel.full
    var largeText = false
}

/// A local player profile (GDD §9a); up to four per device in `ProfileSlots`.
struct Profile: Codable, Equatable {
    var name: String
    var avatar: Int
    var stars: [String: Int] = [:]      // best stars per flight id
    var best: [String: Int] = [:]       // best satisfaction per flight id
    var medals: Set<String> = []        // flights whose bonus goal was met (GDD §6a)
    var options = GameOptions()

    var totalStars: Int { stars.values.reduce(0, +) }

    func isUnlocked(_ route: Route) -> Bool { !route.inDevelopment && totalStars >= route.unlockStars }

    /// A flight opens once the one before it on its route has at least one star.
    func isUnlocked(_ plan: FlightPlan) -> Bool {
        guard let route = Campaign.route(containing: plan.id), isUnlocked(route),
              let i = route.flights.firstIndex(of: plan) else { return false }
        return i == 0 || (stars[route.flights[i - 1].id] ?? 0) > 0
    }

    /// The flight the Fly button should open: the first unlocked one without three stars.
    var nextFlight: FlightPlan {
        let open = Campaign.routes.flatMap(\.flights).filter(isUnlocked)
        return open.first { (stars[$0.id] ?? 0) < 3 } ?? open.last ?? Campaign.route1.flights[0]
    }

    /// Keeps the best result; returns true when it's a new best.
    @discardableResult
    mutating func record(_ plan: FlightPlan, stars s: Int, satisfaction: Int, goalMet: Bool = false) -> Bool {
        if goalMet { medals.insert(plan.id) }
        let improved = satisfaction > (best[plan.id] ?? -1)
        stars[plan.id] = max(stars[plan.id] ?? 0, s)
        if improved { best[plan.id] = satisfaction }
        return improved
    }
}

/// Up to four local profiles per device, one of them active (GDD §9a).
struct ProfileSlots: Codable, Equatable {
    static let count = 4
    var slots: [Profile?] = Array(repeating: nil, count: count)
    var active = 0

    var current: Profile? {
        get { slots.indices.contains(active) ? slots[active] : nil }
        set { if slots.indices.contains(active) { slots[active] = newValue } }
    }
    var firstEmpty: Int? { slots.firstIndex { $0 == nil } }
    var isEmpty: Bool { slots.allSatisfy { $0 == nil } }

    /// Creates a profile in an empty slot and makes it active.
    @discardableResult
    mutating func create(in slot: Int, name: String, avatar: Int) -> Profile? {
        guard slots.indices.contains(slot), slots[slot] == nil else { return nil }
        let p = Profile(name: name.trimmingCharacters(in: .whitespaces), avatar: avatar)
        slots[slot] = p
        active = slot
        return p
    }

    mutating func switchTo(_ slot: Int) {
        guard slots.indices.contains(slot), slots[slot] != nil else { return }
        active = slot
    }

    /// Deleting the active profile moves to the first one left (or none).
    mutating func delete(_ slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = nil
        if slot == active { active = slots.firstIndex { $0 != nil } ?? slot }
    }
}

/// Saves the profile slots as JSON in Application Support. iCloud sync comes in build step 2.
enum ProfileStore {
    private static var dir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var url: URL { dir.appendingPathComponent("profiles.json") }
    /// The single-profile save from before profile slots.
    static var legacyURL: URL { dir.appendingPathComponent("profile.json") }

    static func load() -> ProfileSlots {
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(ProfileSlots.self, from: data) {
            return s
        }
        var s = ProfileSlots()
        if let data = try? Data(contentsOf: legacyURL), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            s.slots[0] = p                       // keep the old save's progress in slot 1
            save(s)
            try? FileManager.default.removeItem(at: legacyURL)
        }
        return s
    }

    static func save(_ s: ProfileSlots) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: legacyURL)
    }
}
