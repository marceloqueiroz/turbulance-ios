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

/// A local player profile (GDD §9a). v1.0 step 1 keeps one per device.
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

/// Saves the profile as JSON in Application Support. iCloud sync comes in build step 2.
enum ProfileStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.json")
    }

    static func load() -> Profile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    static func save(_ p: Profile) {
        guard let data = try? JSONEncoder().encode(p) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func delete() { try? FileManager.default.removeItem(at: url) }
}
