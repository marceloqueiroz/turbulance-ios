import Foundation

/// How the drink cart behaves on a flight.
enum CartMode: Equatable {
    case none
    case service      // rolls down the aisle as a moving obstacle
    case sticks       // …and now and then gets stuck (push it free with a free hand)
    case breaks       // …and now and then breaks down (fix it with the toolkit)
}

/// One rule per flight that changes how you move (GDD §6a).
enum Twist: Equatable {
    case boardingRush     // carry-on bags block the aisle at the start
    case galleyClosed     // the forward galley is out of service
    case redEye           // dim cabin, most asleep, noise carries further
    case helper           // a trainee answers call buttons on their own
    case mealService      // a rush of orders mid-flight, one more problem allowed

    var title: String {
        switch self {
        case .boardingRush: return "Boarding rush"
        case .galleyClosed: return "Forward galley closed"
        case .redEye: return "Red-eye"
        case .helper: return "Trainee on board"
        case .mealService: return "Meal service"
        }
    }
    var detail: String {
        switch self {
        case .boardingRush: return "Carry-on bags block the aisle. Stow them with a free hand."
        case .galleyClosed: return "Supplies come from the middle and back galleys only."
        case .redEye: return "Most passengers are asleep and noise carries a row further."
        case .helper: return "A trainee answers call buttons, slowly. Focus on everything else."
        case .mealService: return "Mid-flight rush of orders. Start coffee and meals early."
        }
    }
}

/// The bonus goal that earns a medal (GDD §6a).
enum Goal: Equatable {
    case noMisses
    case noneWoken
    case serveAllOrders
    case vipHappy
    case quickService          // average fix under 10 s
    case maxStreak             // reach the ×4 streak (GDD §2 Scoring)
    case seatedEveryBump       // buckled in before every turbulence bump (GDD §5b)

    var title: String {
        switch self {
        case .noMisses: return "No missed problems"
        case .noneWoken: return "Nobody wakes up"
        case .serveAllOrders: return "Serve every order"
        case .vipHappy: return "Keep the VIP happy"
        case .quickService: return "Average fix under 10 s"
        case .maxStreak: return "Reach a ×\(Tuning.maxStreak) streak"
        case .seatedEveryBump: return "Seated for every bump"
        }
    }
}

/// Who's on board: shifts the passenger mix and gives the flight a personality (GDD §6a).
struct Story: Equatable {
    let name: String
    let blurb: String
    var bias: [Archetype: Double] = [:]
    var vip = false

    static let commuters = Story(name: "Morning commuters", blurb: "Coffee, laptops and call buttons.", bias: [.business: 2.5])
    static let weekend = Story(name: "Weekend getaway", blurb: "Relaxed travellers who want a drink.", bias: [.chatterbox: 1.5])
    static let family = Story(name: "Family holiday", blurb: "Lots of little ones on board.", bias: [.family: 3])
    static let business = Story(name: "Business shuttle", blurb: "Busy people who expect fast service.", bias: [.business: 3])
    static let skiTrip = Story(name: "Ski trip", blurb: "A chatty group that won't stay seated.", bias: [.chatterbox: 3])
    static let celebrity = Story(name: "Celebrity on board", blurb: "A famous face is flying today.", bias: [:], vip: true)
    static let surfClub = Story(name: "Surf club", blurb: "Up and about, chatting across rows.", bias: [.chatterbox: 2.5])
    static let wedding = Story(name: "Wedding party", blurb: "Celebrations spill into the aisle.", bias: [.chatterbox: 2, .family: 1.5])
    static let earlyBirds = Story(name: "Early birds", blurb: "Everyone wants to sleep. Let them.", bias: [.sleeper: 3])
    static let sportsTeam = Story(name: "Sports team", blurb: "Loud, hungry and restless.", bias: [.chatterbox: 2, .business: 0.5])
    static let charter = Story(name: "Holiday charter", blurb: "Families off to the beach.", bias: [.family: 2.5])
    static let conference = Story(name: "Conference crowd", blurb: "Laptops open, coffee wanted.", bias: [.business: 3])
    static let themePark = Story(name: "Theme park trip", blurb: "Excited kids and tired parents.", bias: [.family: 3, .nervous: 1.5])
    static let lateCommute = Story(name: "Last flight home", blurb: "Tired travellers dozing off.", bias: [.sleeper: 2.5])
    static let honeymoon = Story(name: "Honeymooners", blurb: "A couple in premium expect perfection.", bias: [:], vip: true)
    static let finale = Story(name: "Full house", blurb: "Every kind of traveller at once.", bias: [:])
    static let band = Story(name: "Band on tour", blurb: "Musicians who never sit still.", bias: [.chatterbox: 3])
    static let backpackers = Story(name: "Backpackers", blurb: "Stuffed overhead bins everywhere.", bias: [.chatterbox: 1.5, .nervous: 1.5])
    static let skiTeam = Story(name: "Ski team", blurb: "Hungry athletes ordering combos.", bias: [.business: 1.5, .chatterbox: 1.5])
    static let overnight = Story(name: "Overnight crossing", blurb: "A quiet cabin, if you keep it that way.", bias: [.sleeper: 2.5])
    static let photographers = Story(name: "Photographers' tour", blurb: "Nervous flyers with heavy bags.", bias: [.nervous: 2.5])
    static let director = Story(name: "Film director on board", blurb: "A demanding guest and a full cabin.", bias: [.business: 1.5], vip: true)
    static let tourGroup = Story(name: "Tour group", blurb: "Everyone travelling together, everyone asking.", bias: [.chatterbox: 1.5, .family: 1.5])
    static let engineers = Story(name: "Engineers' convention", blurb: "They'd fix the cart themselves if you let them.", bias: [.business: 2.5])
    static let royal = Story(name: "Royal guest", blurb: "The flight everyone will talk about.", bias: [:], vip: true)
}

/// What the captain says on the PA before takeoff (GDD §8b): light-hearted, never formal.
extension Story {
    /// A cheeky welcome; which one plays depends on the flight so repeats feel fresh.
    static func captainWelcome(to destination: String, flight id: String) -> String {
        let lines = [
            "Captain here! Next stop, \(destination). Probably.",
            "Good news: we have wings! Next stop, \(destination).",
            "I've read the manual twice. \(destination), here we come!",
            "Hands, feet and snacks inside, please. Next stop, \(destination)!",
            "Hello from the pointy end! \(destination) coming up.",
            "Lovely weather in \(destination). Lovely passengers too. Mostly."
        ]
        return lines[id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % lines.count]
    }

    /// A joke about today's passenger group, ending with the cue for the crew.
    var captainQuip: String {
        switch name {
        case Story.commuters.name: return "Lots of commuters today. Crew, brace for coffee!"
        case Story.weekend.name: return "Weekend mode, folks. Don't recline into Monday."
        case Story.family.name: return "Tiny passengers today. Crew, may the toys be with you."
        case Story.business.name: return "Laptops out, Wi-Fi imaginary. Good luck, crew."
        case Story.skiTrip.name: return "Ski club aboard. No moves in the aisle, please."
        case Story.celebrity.name: return "A celebrity's on board. Act normal. Crew, you too."
        case Story.surfClub.name: return "Surf club's here. That wave in the aisle? A spilled drink."
        case Story.wedding.name: return "Congrats, wedding party! Dance on the ground, please."
        case Story.earlyBirds.name: return "Very early flight. Snoring counts as a lullaby."
        case Story.sportsTeam.name: return "The team is hungry. Crew, feed them fast."
        case Story.charter.name: return "Beach time! Sunscreen at the hotel, not in row twelve."
        case Story.conference.name: return "Conference crowd. Slide decks under a hundred pages, please."
        case Story.themePark.name: return "Theme park next! No loops on this ride. I checked."
        case Story.lateCommute.name: return "Last flight home. Pyjamas optional."
        case Story.honeymoon.name: return "Honeymooners up front. Crew, keep the romance flowing."
        case Story.finale.name: return "Full house! Your seat is the one with your name on it."
        case Story.band.name: return "The band's aboard. No drum solos on the tray tables."
        case Story.backpackers.name: return "Backpackers today. If a bin won't close, it's not the bin."
        case Story.skiTeam.name: return "Ski team aboard. Crew, warm up that oven."
        case Story.overnight.name: return "Night flight. Please whisper your complaints."
        case Story.photographers.name: return "Photographers aboard. Smile, you're in a picture."
        case Story.director.name: return "A film director's aboard. Crew, this is your audition."
        case Story.tourGroup.name: return "Big tour group! Follow the flag, not into the cockpit."
        case Story.engineers.name: return "Engineers aboard. Please don't take the plane apart."
        case Story.royal.name: return "Royalty on board! Crew, best manners and best napkins."
        default: return "Crew, the cabin is yours!"
        }
    }
}

/// One flight (level): what can happen on it and when (GDD §6, §6a, §9a).
struct FlightPlan: Identifiable, Equatable {
    let id: String                     // flight code, e.g. "TB101"
    let name: String
    let aircraft: Aircraft
    let duration: Double               // seconds, boarding to touchdown
    let kinds: [OccurrenceKind]        // what the director may roll (toilet = lavatories can clog)
    let script: [OccurrenceKind]       // teaching beats played first
    let maxCap: Int                    // most problems at once at the cruise peak
    var menu: [Item] = [.water, .juice]  // what drink/meal orders can ask for
    var combos = false                 // orders can need two items at once
    var strolls = false                // passengers walk the aisle (GDD §4)
    var dozing = false                 // passengers nod off; noise wakes them (GDD §7)
    var turbulence: [TurbulenceBump] = []
    var cart: CartMode = .none
    var twist: Twist?
    var story: Story = .commuters
    var goal: Goal = .noMisses
    let whatsNew: String               // the one new thing this flight teaches

    var landingAt: Double { duration - Tuning.landingLead }

    /// Whether this flight fits a galley station; the rest stay hidden (GDD §6a "Only what this flight uses").
    func uses(_ kind: StationKind) -> Bool {
        switch kind {
        case .drinks, .trash: return true
        case .oven: return menu.contains { Item.meals.contains($0) }
        case .bin(let item):
            switch item {
            case .snack: return menu.contains(.snack)
            case .toy: return kinds.contains(.baby)
            case .plunger: return kinds.contains(.toilet)
            case .tool: return cart == .breaks
            default: return true
            }
        }
    }

    /// A station this flight fits that the flight before it didn't: it pops in at Go.
    func introduces(_ kind: StationKind) -> Bool {
        guard uses(kind), let before = Campaign.flight(before: self) else { return false }
        return !before.uses(kind)
    }

    /// Satisfaction needed for 1, 2 and 3 stars. Busier, longer flights pay out more (GDD §2 Scoring).
    var targets: [Int] {
        if let t = Campaign.starTargets[id] { return t }
        let three = Tuning.starPace * (duration - Tuning.landingLead) * (0.6 + 0.2 * Double(maxCap))
        func round5(_ v: Double) -> Int { Int((v / 5).rounded()) * 5 }
        return [round5(three * 0.35), round5(three * 0.65), round5(three)]
    }

    func stars(for satisfaction: Double) -> Int { targets.filter { satisfaction >= Double($0) }.count }

    /// Warm-up → build → peak, as shares of the flight so any length uses the same curve.
    func cap(at t: Double) -> Int {
        let f = t / duration
        return f < 0.2 ? min(2, maxCap) : f < 0.5 ? min(3, maxCap) : maxCap
    }

    /// The all-mechanics Comet flight used by tests and `-demo`.
    static let prototype = FlightPlan(
        id: "TB100", name: "Prototype", aircraft: .comet, duration: 150,
        kinds: [.sick, .spill, .call, .drink], script: [.sick, .spill], maxCap: 3, menu: Item.drinks + [.snack] + Item.meals,
        strolls: true, dozing: true, turbulence: Tuning.turbulenceSchedule, whatsNew: "")
}

struct Route: Identifiable, Equatable {
    let id: Int
    let name: String
    let aircraftNames: String
    let cities: [String]               // one more than flights: each flight is a leg
    let flights: [FlightPlan]
    let unlockStars: Int
    var inDevelopment: Bool { flights.isEmpty }
}

/// v1.0 routes (GDD §9a, §11): Routes 1–3, 30 flights. Every flight mixes several task types (GDD §6a).
enum Campaign {
    /// Satisfaction for 1/2/3 stars, set from a greedy bot's median run over 7 seeds (0.4× · 0.85× · 1.3×):
    /// a plain run earns one or two stars, three needs clean streaks and full trays (GDD §2 Scoring).
    static let starTargets: [String: [Int]] = [
        "TB101": [80, 175, 265], "TB102": [95, 205, 315], "TB103": [180, 380, 585],
        "TB104": [60, 125, 190], "TB105": [60, 125, 190], "TB106": [65, 140, 215],
        "TB201": [60, 125, 195], "TB202": [60, 135, 205], "TB203": [55, 120, 185],
        "TB204": [30, 65, 95], "TB205": [25, 50, 80], "TB206": [20, 35, 55],
        "TB207": [30, 65, 100], "TB208": [90, 185, 285], "TB209": [45, 95, 140],
        "TB210": [35, 75, 110], "TB211": [25, 50, 80], "TB212": [25, 50, 75],
        "TB301": [30, 65, 105], "TB302": [115, 240, 365], "TB303": [40, 85, 135],
        "TB304": [40, 85, 135], "TB305": [40, 85, 125], "TB306": [40, 85, 130],
        "TB307": [115, 250, 380], "TB308": [140, 295, 450], "TB309": [175, 370, 565],
        "TB310": [95, 200, 305], "TB311": [50, 105, 160], "TB312": [40, 85, 130]
    ]

    private static func bump(_ start: Double, _ duration: Double = 7, _ intensity: Double = 0.375) -> [TurbulenceBump] {
        [TurbulenceBump(start: start, duration: duration, intensity: intensity)]
    }
    private static let service: [OccurrenceKind] = [.call, .drink, .sick]
    private static let cabin: [OccurrenceKind] = [.call, .drink, .sick, .spill]
    private static let family: [OccurrenceKind] = [.call, .drink, .sick, .spill, .baby]
    private static let full: [OccurrenceKind] = [.call, .drink, .sick, .spill, .baby, .dirtyLav, .toilet]
    // Menus (GDD §6a): drinks come from the drinks machine, chicken and pasta from the ovens.
    private static let basic: [Item] = [.water, .juice, .soda]
    private static let simple: [Item] = [.water, .juice, .soda, .snack]
    private static let cafe: [Item] = [.water, .juice, .soda, .snack, .coffee]
    private static let dining: [Item] = [.water, .juice, .soda, .snack, .coffee, .chicken, .pasta]

    // MARK: Route 1 – Regional Hops (RJ-100 Comet, 12 rows)

    static let route1 = Route(
        id: 1, name: "Regional Hops", aircraftNames: Aircraft.comet.displayName,
        cities: ["Port Wren", "Halden", "Marisol Bay", "Kestrel Falls", "Ashby Cross", "Lumen Harbour", "Vale City"],
        flights: [
            FlightPlan(id: "TB101", name: "First Service", aircraft: .comet, duration: 90,
                       kinds: [.call, .drink, .spill], script: [.drink, .call, .spill], maxCap: 3, menu: basic,
                       story: .commuters, goal: .serveAllOrders,
                       whatsNew: "The drinks machine pours one drink at a time: tap it, pick the drink, come back for it. Call buttons and spills too."),
            FlightPlan(id: "TB102", name: "Mind the Aisle", aircraft: .comet, duration: 105,
                       kinds: [.call, .drink, .spill, .dirtyLav], script: [.drink, .spill], maxCap: 3,
                       menu: [.water, .juice, .soda, .coffee], strolls: true,
                       twist: .boardingRush, story: .weekend, goal: .noMisses,
                       whatsNew: "Coffee goes cold if it waits. Lavatories get dirty: wipe them with a towel. Bags block the aisle while everyone boards."),
            FlightPlan(id: "TB103", name: "Little Ones", aircraft: .comet, duration: 120,
                       kinds: [.call, .drink, .spill, .baby, .dirtyLav], script: [.baby, .drink], maxCap: 3,
                       menu: [.water, .juice, .soda, .coffee, .chicken, .pasta], strolls: true,
                       story: .family, goal: .serveAllOrders,
                       whatsNew: "Two ovens: the passenger picks chicken or pasta and you heat the same dish. A crying baby needs a toy, fast."),
            FlightPlan(id: "TB104", name: "Bumpy Ride", aircraft: .comet, duration: 120,
                       kinds: [.call, .drink, .sick, .spill, .baby, .dirtyLav], script: [.sick, .drink], maxCap: 3,
                       menu: [.water, .juice, .soda, .coffee, .chicken, .pasta], strolls: true,
                       turbulence: [TurbulenceBump(start: 55, duration: 7, intensity: 0.375, warning: 8)],
                       story: .skiTrip, goal: .seatedEveryBump,
                       whatsNew: "Turbulence! When the seatbelt sign comes on, get to a jump seat before it hits. Sick passengers need a towel, the bin, then water."),
            FlightPlan(id: "TB105", name: "Night Flight", aircraft: .comet, duration: 135,
                       kinds: full, script: [.drink, .call], maxCap: 4, menu: dining, combos: true, strolls: true, dozing: true,
                       twist: .redEye, story: .commuters, goal: .noneWoken,
                       whatsNew: "A dim red-eye: don't wake the sleepers. Snacks and two-item combo orders. A dirty loo left too long clogs and needs the plunger."),
            FlightPlan(id: "TB106", name: "Full Service", aircraft: .comet, duration: 150,
                       kinds: full, script: [.drink, .sick], maxCap: 4, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(100), twist: .mealService, story: .celebrity, goal: .vipHappy,
                       whatsNew: "Everything at once, with a meal-service rush and a celebrity on board.")
        ],
        unlockStars: 0)

    // MARK: Route 2 – Coastal Shuttle (N737-Swift, then A320-Current)

    static let route2 = Route(
        id: 2, name: "Coastal Shuttle", aircraftNames: "N737-Swift · A320-Current",
        cities: ["Vale City", "Seabright", "Corran Point", "Gullhaven", "Tidewell", "Saltmere", "Brightcliff",
                 "Pelican Reach", "Harrow Sands", "Coralline", "Westwater", "Driftmoor", "Beacon Isle"],
        flights: [
            FlightPlan(id: "TB201", name: "Bigger Cabin", aircraft: .swift, duration: 120,
                       kinds: cabin, script: [.drink, .call], maxCap: 3, menu: simple,
                       twist: .boardingRush, story: .surfClub, goal: .serveAllOrders,
                       whatsNew: "Six across: middle and window seats take longer to reach."),
            FlightPlan(id: "TB202", name: "Behind the Curtain", aircraft: .swift, duration: 135,
                       kinds: cabin, script: [.call], maxCap: 3, menu: cafe,
                       story: .celebrity, goal: .vipHappy,
                       whatsNew: "A curtain hides premium problems until they're urgent. The VIP up front has short fuses."),
            FlightPlan(id: "TB203", name: "Two Lavatories", aircraft: .swift, duration: 135,
                       kinds: full, script: [.drink], maxCap: 3, menu: cafe, strolls: true,
                       story: .wedding, goal: .noMisses,
                       whatsNew: "Walkers head for both ends, and either lavatory can clog."),
            FlightPlan(id: "TB204", name: "Morning Nap", aircraft: .swift, duration: 150,
                       kinds: family, script: [.baby], maxCap: 3, menu: cafe, strolls: true, dozing: true,
                       twist: .redEye, story: .earlyBirds, goal: .noneWoken,
                       whatsNew: "A dim, sleepy cabin with a baby on board. Keep it quiet."),
            FlightPlan(id: "TB205", name: "Sea Breeze", aircraft: .swift, duration: 150,
                       kinds: full, script: [.drink], maxCap: 3, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(70), twist: .helper, story: .sportsTeam, goal: .maxStreak,
                       whatsNew: "Combo orders, and a trainee who handles call buttons for you."),
            FlightPlan(id: "TB206", name: "Swift Finale", aircraft: .swift, duration: 165,
                       kinds: full, script: [.drink, .sick], maxCap: 4, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(60) + bump(130), twist: .mealService, story: .finale, goal: .noMisses,
                       whatsNew: "Meal service, two bumps and up to four problems at once."),
            FlightPlan(id: "TB207", name: "Drink Service", aircraft: .current, duration: 135,
                       kinds: cabin, script: [.drink], maxCap: 3, menu: cafe, cart: .service,
                       story: .charter, goal: .serveAllOrders,
                       whatsNew: "The drink cart rolls down the aisle. Squeezing past it is slow, and service means more spills."),
            FlightPlan(id: "TB208", name: "Stuck Trolley", aircraft: .current, duration: 135,
                       kinds: cabin, script: [.call], maxCap: 3, menu: cafe, cart: .sticks,
                       twist: .boardingRush, story: .conference, goal: .quickService,
                       whatsNew: "The cart can jam in the aisle. Push it free with a free hand."),
            FlightPlan(id: "TB209", name: "Rush Hour", aircraft: .current, duration: 150,
                       kinds: family, script: [.baby], maxCap: 3, menu: cafe, strolls: true, cart: .sticks,
                       twist: .helper, story: .themePark, goal: .noMisses,
                       whatsNew: "Walkers, kids and the cart share one aisle. The trainee takes the call buttons."),
            FlightPlan(id: "TB210", name: "Late Service", aircraft: .current, duration: 150,
                       kinds: full, script: [.drink], maxCap: 3, menu: dining, strolls: true, dozing: true, cart: .sticks,
                       twist: .redEye, story: .lateCommute, goal: .noneWoken,
                       whatsNew: "Night service with the cart. Every grumble wakes someone."),
            FlightPlan(id: "TB211", name: "Crosswind", aircraft: .current, duration: 165,
                       kinds: full, script: [.sick], maxCap: 3, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(75), cart: .sticks, story: .honeymoon, goal: .vipHappy,
                       whatsNew: "Turbulence during service: the cart parks while the seatbelt sign is on."),
            FlightPlan(id: "TB212", name: "Coastal Finale", aircraft: .current, duration: 180,
                       kinds: full, script: [.drink, .spill], maxCap: 4, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(70) + bump(140), cart: .sticks, twist: .mealService, story: .finale, goal: .maxStreak,
                       whatsNew: "Everything the coast has thrown at you, on one long flight.")
        ],
        unlockStars: 12)

    // MARK: Route 3 – Transcontinental (B757-Longhaul, then A330-Voyager)

    private static let bins: [OccurrenceKind] = [.call, .drink, .sick, .spill, .binJam]
    private static let binsFull: [OccurrenceKind] = [.call, .drink, .sick, .spill, .binJam, .baby, .toilet]

    static let route3 = Route(
        id: 3, name: "Transcontinental", aircraftNames: "B757-Longhaul · A330-Voyager",
        cities: ["Beacon Isle", "Highmoor", "Estrella", "Cinder Flats", "Northgate", "Redrock", "Silvermere",
                 "Cobalt Ridge", "Amberlyn", "Frostholm", "Meridian", "Larkspur", "Aurora Bay"],
        flights: [
            FlightPlan(id: "TB301", name: "Long Body", aircraft: .longhaul, duration: 135,
                       kinds: full, script: [.drink], maxCap: 3, menu: cafe, strolls: true,
                       story: .band, goal: .serveAllOrders,
                       whatsNew: "A long cabin with lavatories front, middle and back. Pick the nearer galley."),
            FlightPlan(id: "TB302", name: "Overhead Trouble", aircraft: .longhaul, duration: 135,
                       kinds: bins, script: [.binJam, .call], maxCap: 3, menu: cafe,
                       twist: .boardingRush, story: .backpackers, goal: .noMisses,
                       whatsNew: "Overhead bins pop open and block the aisle. Shut them with a free hand."),
            FlightPlan(id: "TB303", name: "Full Bins", aircraft: .longhaul, duration: 150,
                       kinds: binsFull, script: [.drink], maxCap: 3, menu: dining, combos: true, strolls: true,
                       twist: .helper, story: .skiTeam, goal: .quickService,
                       whatsNew: "Hungry athletes order combos while the trainee handles calls."),
            FlightPlan(id: "TB304", name: "Night Crossing", aircraft: .longhaul, duration: 150,
                       kinds: binsFull, script: [.baby], maxCap: 3, menu: cafe, strolls: true, dozing: true,
                       twist: .redEye, story: .overnight, goal: .noneWoken,
                       whatsNew: "A long, dark cabin. Keep everyone asleep."),
            FlightPlan(id: "TB305", name: "Mountain Wave", aircraft: .longhaul, duration: 165,
                       kinds: binsFull, script: [.sick], maxCap: 3, menu: dining, strolls: true, dozing: true,
                       turbulence: bump(65, 9), story: .photographers, goal: .noMisses,
                       whatsNew: "A long bump over the mountains shakes bins loose and upsets nervous flyers."),
            FlightPlan(id: "TB306", name: "Longhaul Finale", aircraft: .longhaul, duration: 180,
                       kinds: binsFull, script: [.drink, .binJam], maxCap: 4, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(70) + bump(140), cart: .sticks, twist: .mealService, story: .director, goal: .vipHappy,
                       whatsNew: "Meal service with the cart, a demanding director and up to four problems."),
            FlightPlan(id: "TB307", name: "Two Aisles", aircraft: .voyager, duration: 135,
                       kinds: full, script: [.drink, .call], maxCap: 3, menu: cafe,
                       story: .tourGroup, goal: .serveAllOrders,
                       whatsNew: "Two aisles: you can only cross between them at a galley, front or middle."),
            FlightPlan(id: "TB308", name: "Twin Galleys", aircraft: .voyager, duration: 150,
                       kinds: full, script: [.drink], maxCap: 3, menu: simple, strolls: true,
                       twist: .galleyClosed, story: .weekend, goal: .quickService,
                       whatsNew: "The forward galley is closed. Work from the middle galley instead."),
            FlightPlan(id: "TB309", name: "Broken Cart", aircraft: .voyager, duration: 150,
                       kinds: cabin, script: [.call], maxCap: 3, menu: cafe, cart: .breaks,
                       twist: .boardingRush, story: .engineers, goal: .noMisses,
                       whatsNew: "The cart can break down. Grab the toolkit from a galley and fix it."),
            FlightPlan(id: "TB310", name: "Wide Awake", aircraft: .voyager, duration: 165,
                       kinds: binsFull, script: [.baby], maxCap: 3, menu: cafe, strolls: true, dozing: true, cart: .breaks,
                       twist: .redEye, story: .overnight, goal: .noneWoken,
                       whatsNew: "Eight across in the dark. Noise travels across the whole row."),
            FlightPlan(id: "TB311", name: "Ocean Chop", aircraft: .voyager, duration: 165,
                       kinds: binsFull, script: [.sick], maxCap: 4, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(60, 9) + bump(125), cart: .breaks, twist: .helper, story: .sportsTeam, goal: .maxStreak,
                       whatsNew: "Up to four problems at once over open water, with the trainee's help."),
            FlightPlan(id: "TB312", name: "Voyager Finale", aircraft: .voyager, duration: 195,
                       kinds: binsFull, script: [.drink, .sick], maxCap: 4, menu: dining, combos: true, strolls: true, dozing: true,
                       turbulence: bump(70) + bump(150, 8), cart: .breaks, twist: .mealService, story: .royal, goal: .vipHappy,
                       whatsNew: "The last flight of the crossing, with a royal guest. Three stars masters the Voyager.")
        ],
        unlockStars: 36)

    static let routes = [route1, route2, route3]

    static func route(containing id: String) -> Route? { routes.first { $0.flights.contains { $0.id == id } } }

    static func flight(before plan: FlightPlan) -> FlightPlan? {
        let all = routes.flatMap(\.flights)
        guard let i = all.firstIndex(of: plan), i > 0 else { return nil }
        return all[i - 1]
    }

    static func flight(after plan: FlightPlan) -> FlightPlan? {
        guard let r = route(containing: plan.id), let i = r.flights.firstIndex(of: plan) else { return nil }
        if i + 1 < r.flights.count { return r.flights[i + 1] }
        guard let ri = routes.firstIndex(of: r), ri + 1 < routes.count else { return nil }
        return routes[ri + 1].flights.first
    }
}
