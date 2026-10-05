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
            case .splash, .landing: TitleView(app: app)          // one view, so the title card settles into the menu without a cut
            case .map: WorldMapView(app: app)
            case .game: GameView(app: app, game: app.game)
            }
            if let sheet = app.sheet {
                Scrim { card(for: sheet) }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.25), value: app.screen)
        .animation(.easeOut(duration: 0.2), value: app.sheet)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.game.setPaused(true) }
        }
    }

    @ViewBuilder private func card(for sheet: AppModel.Sheet) -> some View {
        switch sheet {
        case .picker, .replace:
            ProfileSwitcherCard(slots: app.slots, replacing: sheet == .replace, select: app.continueAs,
                                create: app.startNewCrew, delete: app.deleteProfile, close: app.dismissSheet)
        case .newCrew:
            OnboardingCard(firstRun: app.slots.isEmpty, create: { app.createProfile(name: $0, avatar: $1) },
                           cancel: app.dismissSheet)
        case .options:
            optionsCard
        case .about:
            AboutCard(close: app.dismissSheet)
        }
    }

    private var optionsCard: OptionsCard {
        // From the landing page no one is picked yet, so only the device settings show.
        var card = OptionsCard(device: app.device, options: app.screen == .landing ? nil : app.profile.map { ($0.name, $0.options) },
                               updateDevice: app.update, updateOptions: app.update, done: app.dismissSheet)
        #if DEBUG
        card.developer = DevSection(canMakeDev: app.slots.devSlot != nil, makeDev: app.makeDevProfile)
        #endif
        return card
    }
}

// MARK: - New Game: name + avatar

struct OnboardingCard: View {
    var firstRun = true
    let create: (String, Int) -> Void
    var cancel: () -> Void = {}
    @State private var name = ""
    @State private var avatar = 0
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            HStack {
                Eyebrow(text: firstRun ? "Welcome aboard" : "New crew member")
                Spacer()
                Button(action: cancel) { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Cancel")
            }
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
            CTA(title: firstRun ? "Let's fly" : "Join the crew") { create(name, avatar) }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .padding(.bottom, 4)
        }
    }
}

// MARK: - Profiles (GDD §9a): the map's Menu button and the four-slot picker

/// The active crew member in the map's top bar; tapping it goes back to the landing page.
struct MenuChip: View {
    let profile: Profile?
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                AvatarView(index: profile?.avatar ?? 0, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(profile?.name ?? "Crew").font(rounded(15, .bold)).foregroundStyle(Color.text).lineLimit(1)
                    Text("Main menu").font(rounded(10, .heavy)).foregroundStyle(Color.muted)
                }
                Image(systemName: "house.fill").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.muted)
            }
            .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 3)
            .background(Color.panel, in: Capsule())
            .overlay(Capsule().stroke(Color.panelLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile?.name ?? "Crew"), main menu")
    }
}

/// Continue's picker. In replace mode (New Game with all four slots full) the only action is deleting one.
struct ProfileSwitcherCard: View {
    let slots: ProfileSlots
    var replacing = false
    let select: (Int) -> Void
    let create: (Int) -> Void
    let delete: (Int) -> Void
    let close: () -> Void

    var body: some View {
        Card {
            HStack {
                Eyebrow(text: replacing ? "The crew is full" : "Continue")
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            Text(replacing ? "Make room for someone new" : "Who's flying?").font(rounded(26, .bold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(0..<ProfileSlots.count, id: \.self) { i in
                    if let p = slots.slots[i] {
                        ProfileSlotView(profile: p, lastFlown: i == slots.active && !replacing, selectable: !replacing,
                                        select: { select(i) }, delete: { delete(i) })
                    } else {
                        Button { create(i) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 22, weight: .bold))
                                Text("New crew").font(rounded(15, .bold))
                            }
                            .foregroundStyle(Color.finePrint)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.navy.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Empty slot \(i + 1), add new crew member")
                    }
                }
            }
            Text(replacing ? "Hold the bin to delete a crew member and their progress. This can't be undone."
                           : "Each crew member keeps their own stars, unlocks and options. Hold the bin to delete one.")
                .font(rounded(11, .medium)).foregroundStyle(Color.finePrint)
                .padding(.bottom, 4)
        }
    }
}

/// A filled slot: tap to fly as them; hold the bin for 1.2 s to delete (it can't be undone).
struct ProfileSlotView: View {
    let profile: Profile
    let lastFlown: Bool
    var selectable = true
    let select: () -> Void
    let delete: () -> Void
    @State private var hold: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 10) {
                    AvatarView(index: profile.avatar, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name).font(rounded(15, .bold)).lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").foregroundStyle(Color.calm)
                            Text("\(profile.totalStars)").monospacedDigit()
                            Text("· next \(profile.nextFlight.id)").foregroundStyle(Color.teal)
                        }
                        .font(rounded(12, .heavy))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!selectable)
            .accessibilityLabel("\(profile.name), \(profile.totalStars) stars, next flight \(profile.nextFlight.id)\(lastFlown ? ", flown last" : "")")
            ZStack {
                Circle().fill(Color.white)
                Circle().trim(from: 0, to: hold).stroke(Color.critical, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "trash.fill").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hold > 0 ? Color.critical : Color.finePrint)
            }
            .frame(width: 34, height: 34)
            .onLongPressGesture(minimumDuration: 1.2) {
                hold = 0
                delete()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: 1.2) : .easeOut(duration: 0.2)) { hold = pressing ? 1 : 0 }
            }
            .accessibilityLabel("Delete \(profile.name)")
            .accessibilityHint("Hold to delete. This can't be undone.")
            .accessibilityAction(named: "Delete") { delete() }
        }
        .padding(.horizontal, 10).frame(minHeight: 58)
        .background(lastFlown ? Color(red: 1, green: 0.97, blue: 0.93) : Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(lastFlown ? Color.coral : Color.navy.opacity(0.3), lineWidth: lastFlown ? 3 : 1.5))
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
                Label { Text("**Stars:** \(plan.targets.map(String.init).joined(separator: " · ")) satisfaction") } icon: {
                    Image(systemName: "star.fill").foregroundStyle(Color.calm)
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

/// Device settings always; the profile's own settings only once someone is flying (GDD §9a).
struct OptionsCard: View {
    @State var device: DeviceSettings
    @State var options: GameOptions
    let profileName: String?
    let updateDevice: (DeviceSettings) -> Void
    let updateOptions: (GameOptions) -> Void
    let done: () -> Void
    #if DEBUG
    var developer: DevSection?
    #endif

    init(device: DeviceSettings, options: (name: String, options: GameOptions)?, updateDevice: @escaping (DeviceSettings) -> Void,
         updateOptions: @escaping (GameOptions) -> Void, done: @escaping () -> Void) {
        _device = State(initialValue: device)
        _options = State(initialValue: options?.options ?? GameOptions())
        profileName = options?.name
        self.updateDevice = updateDevice
        self.updateOptions = updateOptions
        self.done = done
    }

    var body: some View {
        Card {
            Text("Options").font(rounded(26, .bold))
            if profileName != nil { Eyebrow(text: "This device") }
            row("Sound") {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                    Slider(value: $device.volume, in: 0...1).tint(.teal).frame(maxWidth: 220)
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
            row("Haptics") { Toggle("Haptics", isOn: $device.haptics).labelsHidden().tint(.teal) }
            if let name = profileName {
                Eyebrow(text: "\(name)'s settings").padding(.top, 6)
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
            } else {
                Text("Screen shake and text size are set per crew member, from the route map once you're flying.")
                    .font(rounded(11, .medium)).foregroundStyle(Color.finePrint)
            }
            #if DEBUG
            developer
            #endif
            CTA(title: "Done", action: done).padding(.bottom, 4)
        }
        .onChange(of: device) { _, new in updateDevice(new) }
        .onChange(of: options) { _, new in updateOptions(new) }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(label).font(rounded(15, .bold))
            Spacer()
            control()
        }
    }
}

#if DEBUG
/// Debug builds only: the Options card's Developer section.
struct DevSection: View {
    let canMakeDev: Bool
    let makeDev: () -> Void
    @State private var skipIntro = DevSettings.skipFlightIntro

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Developer").padding(.top, 6)
            HStack {
                Text("Skip flight intro").font(rounded(15, .bold))
                Spacer()
                Toggle("Skip flight intro", isOn: $skipIntro).labelsHidden().tint(.teal)
            }
            HStack {
                Text("Dev crew, 2★ everywhere").font(rounded(15, .bold))
                Spacer()
                Button(canMakeDev ? "Create" : "Crew is full", action: makeDev)
                    .font(rounded(15, .bold)).disabled(!canMakeDev)
            }
        }
        .onChange(of: skipIntro) { _, new in DevSettings.skipFlightIntro = new }
    }
}
#endif
