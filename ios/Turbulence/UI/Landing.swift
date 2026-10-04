import SwiftUI

// MARK: - Title card and landing page (GDD §9a)

/// The cabin flies in through the clouds and the logo lands (the title card); about 2 s later the logo rises
/// and the landing menu fades in over the same scene.
struct TitleView: View {
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var arrived = false
    @State private var logo = false
    /// Counts the bumps on the landing page; each one plays the jolt below.
    @State private var bumps = 0

    private var menu: Bool { app.screen == .landing }

    /// Cloud layers back to front: asset, height and vertical centre (fractions of the screen),
    /// drift speed (screen widths per second), starting x (fraction), blur and opacity for depth.
    private static let clouds: [(name: String, height: CGFloat, y: CGFloat, speed: CGFloat, x: CGFloat, blur: CGFloat, opacity: Double)] = [
        ("TitleCloud5", 0.12, 0.16, 0.025, 0.08, 2, 0.45),
        ("TitleCloud4", 0.15, 0.80, 0.030, 0.40, 2, 0.45),
        ("TitleCloud3", 0.18, 0.30, 0.045, 0.62, 1, 0.65),
        ("TitleCloud2", 0.24, 0.64, 0.060, 0.02, 0.5, 0.8),
        ("TitleCloud1", 0.34, 0.95, 0.090, 0.70, 3, 0.9),   // foreground, cropped by the bottom edge
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shake = reduceMotion ? 0 : app.options.shake.scale     // follows the last crew member's Screen shake option
            ZStack {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    ZStack {
                        ForEach(Self.clouds.indices.dropLast(), id: \.self) { cloud(Self.clouds[$0], t: t, in: size) }
                        // the cabin rides the bumps: a slow bob and a gentle roll, slightly out of step
                        Image("TitleCabin")
                            .resizable().scaledToFit()
                            .frame(height: size.height * 0.74)
                            .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 1.3) * 1.6 + sin(t * 3.1) * 0.4))
                            .offset(y: reduceMotion ? 0 : sin(t * 2.0) * 6 + sin(t * 4.7) * 1.5)
                            .position(x: size.width * 0.73, y: size.height * 0.53)
                            .offset(x: arrived ? 0 : size.width * 0.6)
                        cloud(Self.clouds[Self.clouds.count - 1], t: t, in: size)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { app.finishSplash() }       // a tap skips the title card; does nothing on the landing page
                .accessibilityHidden(true)

                // the crew-wings badge (branding/gemini/logo/round2/W1): big on the title card, tucked above the menu on the landing page
                // the logo and menu are one block, centred on the left and scaled with the screen (iPhone 1×, iPad up to 1.8×)
                let s = min(1.8, max(1, size.height / 402))
                let logoW = 260 * s, logoH = logoW * 558 / 1025, menuH = 198 * s, gap = 18 * s
                let top = (size.height - logoH - gap - menuH) / 2
                Image("LogoMenu")
                    .resizable().scaledToFit()
                    .frame(width: menu ? logoW : min(size.width * 0.4, 360 * s))
                    .scaleEffect(logo ? 1 : 0.6).opacity(logo ? 1 : 0)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 5)
                    .position(x: size.width * 0.29, y: menu ? top + logoH / 2 : size.height * 0.47)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Turbulence")

                LandingMenu(app: app)
                    .frame(width: 240)
                    .scaleEffect(s)
                    .position(x: size.width * 0.29, y: top + logoH + gap + menuH / 2)
                    .opacity(menu ? 1 : 0)
                    .offset(y: menu ? 0 : 16)
                    .allowsHitTesting(menu)
                    .accessibilityHidden(!menu)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: menu)
            .keyframeAnimator(initialValue: Jolt(), trigger: bumps) { content, j in
                content.offset(x: j.x * shake, y: j.y * shake).rotationEffect(.degrees(j.angle * shake))
            } keyframes: { _ in Jolt.keyframes }
        }
        // the sky stays put while everything in front of it jolts, so the screen edges never show a gap
        .background(LinearGradient(colors: [Color(red: 0.16, green: 0.27, blue: 0.47), .sky], startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea()                             // measure the whole screen, not just the safe area
        .onAppear {
            start = .now
            if menu {                                  // launched straight onto the landing page: no fly-in
                arrived = true
                logo = true
                return
            }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.75)) { arrived = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.7)) { logo = true }
        }
        .task {
            guard !menu else { return }
            try? await Task.sleep(for: .seconds(2.2))
            app.finishSplash()
        }
        .task(id: menu) {
            // a patch of rough air every few seconds while the menu is up
            guard menu else { return }
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 5...9)))
                guard !Task.isCancelled, app.sheet == nil else { continue }    // no bumps under an open card
                bumps += 1
                if app.device.haptics { haptic.impactOccurred(intensity: 0.7) }
            }
        }
    }

    /// A cloud drifting right to left, wrapping round once it leaves the screen.
    private func cloud(_ c: (name: String, height: CGFloat, y: CGFloat, speed: CGFloat, x: CGFloat, blur: CGFloat, opacity: Double),
                       t: TimeInterval, in size: CGSize) -> some View {
        let h = size.height * c.height
        let w = h * 1.75
        let span = size.width + w
        let travelled = reduceMotion ? 0 : CGFloat(t) * c.speed * size.width
        let x = (c.x * span - travelled).truncatingRemainder(dividingBy: span)
        return Image(c.name)
            .resizable().scaledToFit()
            .frame(height: h)
            .blur(radius: c.blur)
            .opacity(c.opacity)
            .position(x: (x < 0 ? x + span : x) - w / 2, y: size.height * c.y)
    }
}

/// One bump of turbulence: two hard jolts, then a wobble that settles (about 1 s).
struct Jolt {
    var x = 0.0, y = 0.0, angle = 0.0

    @KeyframesBuilder<Jolt> static var keyframes: some Keyframes<Jolt> {
        KeyframeTrack(\Jolt.y) {
            LinearKeyframe(-9, duration: 0.06)
            SpringKeyframe(6, duration: 0.12)
            LinearKeyframe(-5, duration: 0.08)
            SpringKeyframe(3, duration: 0.14)
            SpringKeyframe(-1.5, duration: 0.2)
            SpringKeyframe(0, duration: 0.4)
        }
        KeyframeTrack(\Jolt.x) {
            LinearKeyframe(4, duration: 0.07)
            LinearKeyframe(-5, duration: 0.1)
            LinearKeyframe(3, duration: 0.1)
            LinearKeyframe(-1.5, duration: 0.15)
            SpringKeyframe(0, duration: 0.5)
        }
        KeyframeTrack(\Jolt.angle) {
            LinearKeyframe(-0.8, duration: 0.08)
            SpringKeyframe(0.6, duration: 0.15)
            SpringKeyframe(-0.3, duration: 0.2)
            SpringKeyframe(0, duration: 0.5)
        }
    }
}

/// Continue (hidden with no profiles), New Game, Options, About. The main action is coral.
struct LandingMenu: View {
    let app: AppModel

    var body: some View {
        let hasCrew = !app.slots.isEmpty
        VStack(spacing: 10) {
            if hasCrew {
                MenuButton(title: "Continue", detail: app.profile.map { "Last flown: \($0.name)" }, color: .coral, action: app.continueGame)
            }
            MenuButton(title: "New Game", color: hasCrew ? .teal : .coral, action: app.newGame)
            MenuButton(title: "Options", color: .cream, ink: .navy) { app.sheet = .options }
            MenuButton(title: "About", color: .cream, ink: .navy) { app.sheet = .about }
        }
    }
}

/// A full-width CTA in the same pressed-capsule style, with an optional second line.
struct MenuButton: View {
    let title: String
    var detail: String?
    var color: Color = .coral
    var ink: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title).font(rounded(19, .bold))
                if let detail { Text(detail).font(rounded(11, .semibold)).opacity(0.85).lineLimit(1) }
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: detail == nil ? 40 : 48)
            .background(color, in: Capsule())
            .overlay(Capsule().stroke(Color.navy, lineWidth: 3))
            .background(Capsule().fill(Color.navy).offset(y: 4))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - About

struct AboutCard: View {
    let close: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        Card {
            HStack {
                Eyebrow(text: "About")
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            // the full crew-wings logo with the attendant (branding/gemini/logo/L5); the main menu uses the character-free one
            Image("LogoCrew")
                .resizable().scaledToFit()
                .frame(height: 88)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Turbulence")
            HStack(spacing: 8) {
                ZeldaLabsMark().frame(width: 26, height: 26).accessibilityHidden(true)
                Text(version).font(rounded(13, .semibold)).foregroundStyle(Color.finePrint)
            }
            .frame(maxWidth: .infinity)
            section("Credits", "Designed and built by Zelda Labs. Sound effects are synthesised in the game.")
            section("Privacy", "Your crew and progress are saved on this device only. No account, no ads, no tracking.")
            section("Made with", "Swift, SwiftUI and SpriteKit.")
            CTA(title: "Done", action: close).padding(.bottom, 4)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(rounded(10, .heavy)).tracking(1.2).foregroundStyle(Color.coral)
            Text(body).font(rounded(14, .medium))
        }
    }
}
