import SwiftUI

// MARK: - Title card and landing page (GDD §9a)

/// The cabin flies in through the clouds and the logo lands (the title card); about 2 s later the galley wall
/// fades in over the same sky, which now shows through its window (the galley main menu, specs/galley-main-menu).
struct TitleView: View {
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var arrived = false
    @State private var logo = false
    /// Counts the bumps on the landing page; each one plays the jolt below.
    @State private var bumps = 0
    /// The same bumps as the galley feels them (recent ones only).
    @State private var kicks: [GalleyKick] = []

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
            let motion = reduceMotion ? 0 : app.options.shake.scale    // follows the last crew member's Screen shake option
            let shake = motion * 0.3                                   // the room holds still; the loose things in the galley move
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
                            .opacity(menu ? 0 : 1)
                        cloud(Self.clouds[Self.clouds.count - 1], t: t, in: size)
                            .opacity(menu ? 0 : 1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { app.finishSplash() }       // a tap skips the title card; does nothing on the landing page
                .accessibilityHidden(true)

                // the crew-wings badge (branding/gemini/logo/round2/W1) lands on the title card; the galley wall has its own
                Image("LogoMenu")
                    .resizable().scaledToFit()
                    .frame(width: min(size.width * 0.4, 360 * min(1.8, max(1, size.height / 402))))
                    .scaleEffect(logo ? 1 : 0.6).opacity(logo && !menu ? 1 : 0)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 5)
                    .position(x: size.width * 0.29, y: size.height * 0.47)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Turbulence")
                    .accessibilityHidden(menu)

                galley
                    .opacity(menu ? 1 : 0)
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
                var wait = Double.random(in: 5...9)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-galleyShake") { wait = 1.2 }   // tuning the galley: a bump every 1.2 s
                #endif
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, app.sheet == nil else { continue }    // no bumps under an open card
                bump()
                if app.device.haptics { haptic.impactOccurred(intensity: 0.7) }
            }
        }
    }

    private var galley: some View {
        #if DEBUG
        GalleyMenu(app: app, kicks: kicks, start: start, motion: reduceMotion ? 0 : app.options.shake.scale, bump: bump)
        #else
        GalleyMenu(app: app, kicks: kicks, start: start, motion: reduceMotion ? 0 : app.options.shake.scale)
        #endif
    }

    /// One patch of rough air: the screen jolts a little and every loose thing in the galley gets a kick.
    private func bump() {
        let now = Date.now.timeIntervalSince(start)
        kicks = kicks.filter { now - $0.time < GalleyMotion.memory } + [GalleyKick.random(at: now)]
        bumps += 1
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

