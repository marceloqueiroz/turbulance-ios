import SpriteKit
import SwiftUI

// MARK: - Root

struct RootView: View {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.sky.ignoresSafeArea()
            switch app.screen {
            case .studio: StudioSplash { app.finishStudio() }
            case .splash: SplashView { app.finishSplash() }
            case .onboarding: CabinBackdrop(game: app.game) { OnboardingCard { app.createProfile(name: $0, avatar: $1) } }
            case .menu: CabinBackdrop(game: app.game) { MenuView(app: app) }
            case .map: RouteMapView(app: app)
            case .game: GameView(app: app, game: app.game)
            }
            if app.showOptions {
                Scrim { OptionsCard(options: app.options, update: app.update) { app.showOptions = false } }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.25), value: app.screen)
        .animation(.easeOut(duration: 0.2), value: app.showOptions)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.game.setPaused(true) }
        }
    }
}

/// The idle cabin, dimmed, behind menus.
struct CabinBackdrop<Content: View>: View {
    let game: GameController
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            SpriteView(scene: game.scene, preferredFramesPerSecond: 30).ignoresSafeArea()
            Color(red: 9 / 255, green: 16 / 255, blue: 33 / 255).opacity(0.6).ignoresSafeArea()
            content.padding(16)
        }
    }
}

// MARK: - Splash (GDD §9a): a plane taxis in, the logo lands, "Tap to board"

struct SplashView: View {
    let done: () -> Void
    @State private var taxied = false
    @State private var logo = false
    @State private var prompt = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.27, blue: 0.47), .sky], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                // runway: the coral livery stripe
                Rectangle().fill(Color.coral).frame(height: 6).offset(y: 44)
                HStack(spacing: 18) {
                    ForEach(0..<14, id: \.self) { _ in Capsule().fill(Color.cream.opacity(0.5)).frame(width: 22, height: 3) }
                }
                .offset(y: 44)
                Image(systemName: "airplane")
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(Color.cream)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
                    .offset(x: taxied ? 0 : -geo.size.width * 0.7, y: 10)
                VStack(spacing: 10) {
                    Logo(size: 56).scaleEffect(logo ? 1 : 0.6).opacity(logo ? 1 : 0)
                    Text("Tap to board").font(rounded(18, .semibold)).foregroundStyle(Color.text)
                        .opacity(prompt ? 1 : 0.35)
                        .opacity(logo ? 1 : 0)
                }
                .offset(y: -80)
            }
            .contentShape(Rectangle())
            .onTapGesture { done() }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { taxied = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.9)) { logo = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever().delay(1.4)) { prompt = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Turbulence. Tap to board.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - First run: name + avatar

struct OnboardingCard: View {
    let create: (String, Int) -> Void
    @State private var name = ""
    @State private var avatar = 0
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            Eyebrow(text: "Welcome aboard")
            Text("Who's working this flight?").font(rounded(26, .bold))
            TextField("Your name", text: $name)
                .font(rounded(18, .semibold))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.navy, lineWidth: 2))
            Text("Pick your look").font(rounded(12, .heavy))
            HStack(spacing: 12) {
                ForEach(Avatar.looks.indices, id: \.self) { i in
                    Button { avatar = i } label: {
                        AvatarView(index: i, size: 48)
                            .overlay(Circle().stroke(Color.coral, lineWidth: avatar == i ? 4 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Look \(i + 1)")
                    .accessibilityAddTraits(avatar == i ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            CTA(title: "Start first flight") { create(name, avatar) }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .padding(.bottom, 4)
        }
    }
}

// MARK: - Main menu

struct MenuView: View {
    let app: AppModel
    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 14) {
                Logo(size: 54)
                if let p = app.profile {
                    HStack(spacing: 10) {
                        AvatarView(index: p.avatar, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(rounded(17, .bold)).foregroundStyle(Color.text)
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").foregroundStyle(Color.calm)
                                Text("\(p.totalStars) stars").foregroundStyle(Color.muted)
                            }
                            .font(rounded(13, .semibold))
                        }
                    }
                    .padding(.leading, 4).padding(.trailing, 16).padding(.vertical, 4)
                    .background(Color.panel, in: Capsule())
                    .overlay(Capsule().stroke(Color.panelLine, lineWidth: 1))
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                CTA(title: "Fly") { app.openMap(brief: app.profile?.nextFlight) }
                CTA(title: "Options", color: .teal) { app.showOptions = true }
                HStack(spacing: 8) {
                    CTA(title: "Co-op", color: .muted) {}
                        .disabled(true)
                    Text("Coming soon").font(rounded(12, .heavy)).foregroundStyle(Color.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Co-op, coming soon")
            }
        }
    }
}

// MARK: - Route map (GDD §9a)

struct RouteMapView: View {
    let app: AppModel
    @State private var selected: Int?

    /// Cities strung left to right in a wave; labels alternate above and below so long routes stay readable.
    private func cityPoints(_ count: Int) -> [CGPoint] {
        (0..<count).map { i in
            let f = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0.5
            let wave: CGFloat = i % 2 == 0 ? 0.66 : 0.46
            return CGPoint(x: 0.07 + 0.86 * f, y: wave + 0.04 * sin(CGFloat(i) * 1.3))
        }
    }

    var body: some View {
        let profile = app.profile ?? Profile(name: "", avatar: 0)
        let routeID = selected ?? Campaign.route(containing: app.briefing?.id ?? profile.nextFlight.id)?.id ?? 1
        let route = Campaign.routes.first { $0.id == routeID } ?? Campaign.route1
        let unlocked = profile.isUnlocked(route)
        let points = cityPoints(route.cities.count)
        let dense = route.flights.count > 8
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pt = { (p: CGPoint) in CGPoint(x: p.x * w, y: p.y * h) }
            ZStack {
                MapBackground()
                Canvas { ctx, _ in
                    for i in 0..<route.flights.count {
                        let a = pt(points[i]), b = pt(points[i + 1])
                        let open = unlocked && profile.isUnlocked(route.flights[i])
                        var path = Path()
                        path.move(to: a)
                        path.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 30))
                        ctx.stroke(path, with: .color(open ? .coral : .muted.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: open ? [] : [6, 8]))
                    }
                }
                CityLabel(name: route.cities[0], home: true).position(pt(points[0]))
                ForEach(Array(route.flights.enumerated()), id: \.element.id) { i, plan in
                    let open = unlocked && profile.isUnlocked(plan)
                    FlightPin(number: i + 1, stars: profile.stars[plan.id] ?? 0, medal: profile.medals.contains(plan.id), unlocked: open,
                              isNext: plan == profile.nextFlight, city: route.cities[i + 1],
                              compact: dense, labelAbove: dense && i % 2 == 1)
                        .position(pt(points[i + 1]))
                        .onTapGesture { if open { app.briefing = plan } }
                        .accessibilityAddTraits(.isButton)
                }
                if !unlocked {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 22, weight: .bold))
                        Text("Route \(route.id) unlocks at \(route.unlockStars) stars").font(rounded(17, .bold))
                        Text("You have \(profile.totalStars). About two stars a flight on the earlier routes gets you there.")
                            .font(rounded(13, .semibold)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.text)
                    .padding(18)
                    .background(Color.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.panelLine, lineWidth: 1))
                    .frame(maxWidth: 380)
                }

                // top bar
                VStack {
                    HStack(spacing: 12) {
                        RoundButton(system: "chevron.left", label: "Main menu") { app.openMenu() }
                        VStack(alignment: .leading, spacing: 0) {
                            Eyebrow(text: "Route \(route.id) · \(route.aircraftNames)")
                            Text(route.name).font(rounded(22, .bold)).foregroundStyle(Color.text)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(Campaign.routes) { r in
                                let isOn = r.id == route.id
                                Button { selected = r.id } label: {
                                    HStack(spacing: 4) {
                                        if !profile.isUnlocked(r) { Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)) }
                                        Text("\(r.id)").font(rounded(15, .heavy))
                                    }
                                    .foregroundStyle(isOn ? Color.navy : Color.text)
                                    .frame(minWidth: 40, minHeight: 32)
                                    .background(isOn ? Color.calm : Color.panel, in: Capsule())
                                    .overlay(Capsule().stroke(Color.panelLine, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Route \(r.id), \(r.name)\(profile.isUnlocked(r) ? "" : ", locked")")
                            }
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").foregroundStyle(Color.calm)
                            Text("\(profile.totalStars)").monospacedDigit().foregroundStyle(Color.text)
                        }
                        .font(rounded(17, .bold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.panel, in: Capsule())
                        .overlay(Capsule().stroke(Color.panelLine, lineWidth: 1))
                        RoundButton(system: "gearshape.fill", label: "Options") { app.showOptions = true }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                    Spacer()
                }

                if let plan = app.briefing, let r = Campaign.route(containing: plan.id) {
                    Scrim {
                        BriefingCard(plan: plan, route: r, profile: profile,
                                     board: { app.board(plan) }, close: { app.briefing = nil })
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.briefing)
        .animation(.easeInOut(duration: 0.25), value: selected)
    }
}

/// Stylised top-down world in the cabin palette: navy ocean, cream land.
struct MapBackground: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.09, green: 0.15, blue: 0.29)))
            for x in stride(from: 0.0, to: size.width, by: 48) {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(.white.opacity(0.04)), lineWidth: 1)
            }
            for y in stride(from: 0.0, to: size.height, by: 48) {
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(.white.opacity(0.04)), lineWidth: 1)
            }
            let land: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.02, 0.38, 0.36, 0.52), (0.28, 0.30, 0.30, 0.46), (0.52, 0.24, 0.34, 0.50), (0.78, 0.14, 0.24, 0.30), (0.80, 0.66, 0.22, 0.28)
            ]
            for (x, y, w, h) in land {
                let r = CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
                ctx.fill(Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.45), with: .color(Color.cream.opacity(0.16)))
            }
        }
        .ignoresSafeArea()
    }
}

struct CityLabel: View {
    let name: String
    var home = false
    var body: some View {
        VStack(spacing: 4) {
            Circle().fill(home ? Color.teal : Color.cream).frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.navy, lineWidth: 2))
            Text(home ? "\(name) · Home" : name).font(rounded(11, .heavy)).foregroundStyle(Color.text)
        }
        .offset(y: 10)
    }
}

struct FlightPin: View {
    let number: Int
    let stars: Int
    var medal = false
    let unlocked: Bool
    let isNext: Bool
    let city: String
    var compact = false
    var labelAbove = false
    @State private var pulse = false

    var body: some View {
        let d: CGFloat = compact ? 32 : 40
        VStack(spacing: 3) {
            if labelAbove { label }
            ZStack {
                if isNext && unlocked {
                    Circle().stroke(Color.calm, lineWidth: 3).frame(width: d + 12, height: d + 12)
                        .scaleEffect(pulse ? 1.15 : 0.95).opacity(pulse ? 0.2 : 0.9)
                }
                Circle().fill(unlocked ? Color.coral : Color.panel).frame(width: d, height: d)
                    .overlay(Circle().stroke(Color.navy, lineWidth: 3))
                if medal {
                    Image(systemName: "medal.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.calm)
                        .offset(x: d / 2, y: -d / 2)
                }
                if unlocked {
                    Text("\(number)").font(rounded(compact ? 15 : 18, .heavy)).foregroundStyle(.white)
                } else {
                    Image(systemName: "lock.fill").font(.system(size: compact ? 12 : 14, weight: .bold)).foregroundStyle(Color.muted)
                }
            }
            if !labelAbove { label }
        }
        .offset(y: labelAbove ? -18 : 0)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked ? "Flight \(number) to \(city), \(stars) of 3 stars" : "Flight \(number) to \(city), locked")
    }

    private var label: some View {
        VStack(spacing: 1) {
            StarRow(stars: stars, size: compact ? 9 : 11)
            Text(city).font(rounded(compact ? 9 : 11, .heavy)).foregroundStyle(unlocked ? Color.text : Color.muted)
                .lineLimit(1).fixedSize()
        }
    }
}

// MARK: - Flight briefing

struct BriefingCard: View {
    let plan: FlightPlan
    let route: Route
    let profile: Profile
    let board: () -> Void
    let close: () -> Void

    var body: some View {
        let i = route.flights.firstIndex(of: plan) ?? 0
        let secs = Int(plan.duration)
        Card {
            HStack {
                Eyebrow(text: "Flight \(plan.id) · \(plan.aircraft.displayName) · \(secs / 60) min\(secs % 60 > 0 ? " \(secs % 60) s" : "")")
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            Text(plan.name).font(rounded(28, .bold))
            Text("\(route.cities[i]) → \(route.cities[i + 1])").font(rounded(14, .semibold)).foregroundStyle(Color.finePrint)
            VStack(alignment: .leading, spacing: 4) {
                Text("WHAT'S NEW").font(rounded(10, .heavy)).tracking(1.2).foregroundStyle(Color.coral)
                Text(plan.whatsNew).font(rounded(15, .semibold))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1, green: 0.97, blue: 0.93), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.navy, lineWidth: 2))
            VStack(alignment: .leading, spacing: 5) {
                Label { Text("**\(plan.story.name)**. \(plan.story.blurb)") } icon: { Image(systemName: plan.story.vip ? "crown.fill" : "person.3.fill") }
                if let twist = plan.twist {
                    Label { Text("**\(twist.title)**. \(twist.detail)") } icon: { Image(systemName: "sparkles") }
                }
                Label { Text("**Bonus goal:** \(plan.goal.title)") } icon: {
                    Image(systemName: profile.medals.contains(plan.id) ? "medal.fill" : "medal")
                        .foregroundStyle(profile.medals.contains(plan.id) ? Color.calm : Color.navy)
                }
            }
            .font(rounded(13, .medium))
            if i == 0 {
                Text("Tap the aisle to walk, tap a galley bin to grab an item, then tap a passenger or spill to use it.")
                    .font(rounded(13, .medium))
            }
            HStack(spacing: 14) {
                CTA(title: "Board", action: board)
                if let best = profile.best[plan.id] {
                    HStack(spacing: 6) {
                        StarRow(stars: profile.stars[plan.id] ?? 0, size: 16)
                        Text("Best \(best)").font(rounded(13, .heavy)).foregroundStyle(Color.finePrint)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Options (GDD §9a)

struct OptionsCard: View {
    @State var options: GameOptions
    let update: (GameOptions) -> Void
    let done: () -> Void

    init(options: GameOptions, update: @escaping (GameOptions) -> Void, done: @escaping () -> Void) {
        _options = State(initialValue: options)
        self.update = update
        self.done = done
    }

    var body: some View {
        Card {
            Text("Options").font(rounded(26, .bold))
            row("Sound") {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                    Slider(value: $options.volume, in: 0...1).tint(.teal).frame(maxWidth: 220)
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
            row("Haptics") { Toggle("Haptics", isOn: $options.haptics).labelsHidden().tint(.teal) }
            row("Screen shake") {
                Picker("Screen shake", selection: $options.shake) {
                    ForEach(ShakeLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 260)
            }
            row("Notification text") {
                Picker("Notification text", selection: $options.largeText) {
                    Text("Standard").tag(false)
                    Text("Large").tag(true)
                }
                .pickerStyle(.segmented).frame(maxWidth: 260)
            }
            CTA(title: "Done", action: done).padding(.bottom, 4)
        }
        .onChange(of: options) { _, new in update(new) }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(label).font(rounded(15, .bold))
            Spacer()
            control()
        }
    }
}
