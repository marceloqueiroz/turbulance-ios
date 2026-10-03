import SpriteKit
import SwiftUI

struct GameView: View {
    let app: AppModel
    let game: GameController
    @State private var pickerSize = CGSize(width: 260, height: 96)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.sky.ignoresSafeArea()
                // the cabin uses the whole screen; the scene keeps it clear of the cutout, home indicator and HUD
                SpriteView(scene: game.scene, preferredFramesPerSecond: 60)
                    .ignoresSafeArea()
                if let intro = game.intro3D {
                    IntroSceneView(intro: intro)
                        .ignoresSafeArea()
                        .onTapGesture { game.skipIntro() }
                        .transition(.opacity)
                }
                HUDBar(game: game)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .opacity(game.screen == .intro ? 0 : 1)
                if let n = game.countdownText {
                    Text(n)
                        .font(rounded(n == "Go!" ? 96 : 120, .heavy))
                        .foregroundStyle(n == "Go!" ? Color.calm : Color.text)
                        .shadow(color: .black.opacity(0.55), radius: 12, y: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(n)
                        .transition(.scale(scale: 1.8).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                if let p = game.picker {
                    GeometryReader { full in
                        let inset = game.scene.contentInsets
                        let hw = pickerSize.width / 2 + 10, hh = pickerSize.height / 2 + 8
                        MachinePickerView(options: p.options) { game.pick($0) }
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { pickerSize = $0 }
                            // under the machine, but never under the camera cutout or off screen
                            .position(x: min(max(p.point.x, inset.left + hw), full.size.width - inset.right - hw),
                                      y: min(max(p.point.y + 62, inset.top + hh), full.size.height - hh))
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)                    // a plain fade: no bounce
                }
                if game.twoCrew && (game.screen == .playing || game.screen == .countdown) {
                    CrewSwitchButton(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 14).padding(.bottom, 10)
                }
                overlay.ignoresSafeArea()
                if game.screen == .intro { IntroLetterbox(game: game).transition(.opacity) }
                Color.black.opacity(game.blackout).ignoresSafeArea().allowsHitTesting(false)
            }
            .onAppear { updateInsets(geo) }
            .onChange(of: geo.size) { _, _ in updateInsets(geo) }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { updateInsets(geo) }   // the cutout switches sides
            }
        }
        .animation(.easeInOut(duration: 0.4), value: game.screen)
        .animation(.easeInOut(duration: IntroScene3D.handoffLead), value: game.intro3D == nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.countdownText)
        .animation(.easeOut(duration: 0.12), value: game.picker)
    }

    /// Keeps the cabin clear of the HUD and of the camera cutout — only on the side the cutout is on, and only
    /// as deep as the cutout itself (iOS reports the full safe inset on both sides in landscape).
    private func updateInsets(_ geo: GeometryProxy) {
        let safe = geo.safeAreaInsets
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.effectiveGeometry.interfaceOrientation
        let cutout = max(0, max(safe.leading, safe.trailing) - 22)     // ≈ the cutout's depth
        let cutoutOnLeft = orientation != .landscapeLeft                // landscapeLeft: the top of the phone is on the right
        game.scene.contentInsets = UIEdgeInsets(top: safe.top + 50, left: cutoutOnLeft ? cutout : 6,
                                                bottom: 2, right: cutoutOnLeft ? 6 : cutout)
    }

    @ViewBuilder private var overlay: some View {
        switch game.screen {
        case .paused:
            Scrim {
                PauseCard(resume: { game.setPaused(false) }, restart: { app.board(game.plan) },
                          options: { app.sheet = .options }, map: { app.openMap() }, menu: { app.goToLanding() })
            }
        case .ended:
            Scrim {
                EndCard(plan: game.plan, result: game.result, newBest: app.newBest, sound: { game.playUI($0) },
                        next: app.nextFlight(after: game.plan).map { next in { app.openMap(brief: next) } },
                        retry: { app.board(game.plan) }, map: { app.openMap() })
            }
        case .idle, .intro, .countdown, .playing: EmptyView()
        }
    }
}

// MARK: - Intro letterbox (GDD §8b): flight title on top, captain's subtitles below, tap to skip

struct IntroLetterbox: View {
    let game: GameController
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.85)
                Text(game.introTitle ?? "").font(rounded(13, .heavy)).tracking(1.5).foregroundStyle(Color.text)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 20)
            }
            .frame(height: 38)
            Spacer()
            ZStack {
                Color.black.opacity(0.85)
                if let line = game.introSubtitle {
                    Text(line).font(rounded(16, .semibold)).foregroundStyle(Color.text)
                        .multilineTextAlignment(.center).padding(.horizontal, 60)
                        .transition(.opacity)
                        .id(line)
                }
                HStack {
                    Spacer()
                    Text("Tap to skip").font(rounded(11, .heavy)).foregroundStyle(Color.muted).padding(.trailing, 20)
                }
            }
            .frame(height: 56)
            .animation(.easeInOut(duration: 0.3), value: game.introSubtitle)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - HUD (timer left, hands centre, satisfaction right — GDD §8a)

struct HUDBar: View {
    let game: GameController

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.panelLine, lineWidth: 5)
                    Circle().trim(from: 0, to: game.clockFraction)
                        .stroke(game.landing ? Color.coral : Color.teal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 32, height: 32)
                Text(game.timeText).font(rounded(21, .semibold)).monospacedDigit().foregroundStyle(Color.text)
                    .fixedSize()
                if game.seatbelt { SeatbeltSign() }
            }
            Spacer(minLength: 4)
            if game.seatPrompt != .none {
                SeatPromptPill(prompt: game.seatPrompt)
            } else {
                // where the scene draws the cabin strip (GDD §8a Follow camera)
                Color.clear
                    .frame(minWidth: 110, maxWidth: 230)
                    .frame(height: 22)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { game.scene.stripSlot = $0 }
                    .onDisappear { game.scene.stripSlot = nil }
            }
            Spacer(minLength: 4)
            // the score and its multiplier, nothing else: the stars are revealed on the scorecard (GDD §8a)
            Text("\(game.satisfaction)").font(rounded(26, .heavy)).monospacedDigit().foregroundStyle(Color.text)
                .contentTransition(.numericText(value: Double(game.satisfaction)))
                .animation(.easeOut(duration: 0.25), value: game.satisfaction)
                .fixedSize()
                .accessibilityLabel("Score \(game.satisfaction)")
            StreakBadge(streak: game.streak)
            HStack(spacing: 8) {
                RoundButton(system: game.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: "Sound") { game.toggleMute() }
                RoundButton(system: "pause.fill", label: "Pause") { game.setPaused(game.screen == .playing) }
            }
        }
        .frame(height: 40)
    }
}

/// Twin-aisle planes: switches control and the camera to the other attendant. A red dot shows when the other
/// side has an urgent or critical problem (GDD §8a Two attendants).
struct CrewSwitchButton: View {
    let game: GameController
    var body: some View {
        Button { game.switchCrew() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: game.activeCrew == 0 ? "arrow.down" : "arrow.up")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.text)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.panel))
                    .overlay(Circle().stroke(Color.navy, lineWidth: 2.5))
                if game.partnerAlert {
                    Circle().fill(Color(uiColor: Palette.critical)).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(game.activeCrew == 0 ? "Switch to the bottom aisle" : "Switch to the top aisle")
    }
}

/// The ×1–×4 streak multiplier: it pops when it climbs and drops back to ×1 on a mistake (GDD §2 Scoring).
struct StreakBadge: View {
    let streak: Int
    var body: some View {
        Text("×\(streak)")
            .font(rounded(streak > 1 ? 17 : 14, .heavy)).monospacedDigit()
            .foregroundStyle(streak > 1 ? .white : Color.muted)
            .frame(minWidth: 34, minHeight: 28)
            .background(Capsule().fill(color))
            .overlay(Capsule().stroke(Color.navy.opacity(streak > 1 ? 0.9 : 0.25), lineWidth: 2))
            .scaleEffect(streak > 1 ? 1.08 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: streak)
            .accessibilityLabel("Streak times \(streak)")
    }
    private var color: Color {
        switch streak {
        case 1: return Color.panel
        case 2: return .teal
        case 3: return Color(uiColor: Palette.urgent)
        default: return .coral
        }
    }
}

/// "Take your seat" (blinking coral) until the crew is buckled into a jump seat (GDD §5b).
struct SeatPromptPill: View {
    let prompt: GameController.SeatPrompt
    @State private var on = true
    var body: some View {
        let buckled = prompt == .buckled
        HStack(spacing: 6) {
            Image(systemName: buckled ? "checkmark.circle.fill" : "chair.fill").font(.system(size: 13, weight: .bold))
            Text(buckled ? "BUCKLED IN" : "TAKE YOUR SEAT").font(rounded(12, .heavy)).tracking(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .fixedSize()
        .background(buckled ? Color.teal : Color.coral, in: Capsule())
        .opacity(buckled || on ? 1 : 0.5)
        .onAppear { withAnimation(.easeInOut(duration: 0.4).repeatForever()) { on = false } }
        .transition(.scale.combined(with: .opacity))
    }
}

/// Lit seatbelt sign shown while turbulence is coming or happening.
struct SeatbeltSign: View {
    @State private var lit = true
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "figure.seated.seatbelt").font(.system(size: 13, weight: .bold))
            Text("SEATBELT").font(rounded(10, .heavy)).tracking(1)
        }
        .foregroundStyle(Color.navy)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .fixedSize()
        .background(Color(uiColor: Palette.calm), in: Capsule())
        .opacity(lit ? 1 : 0.55)
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { lit = false } }
        .transition(.scale.combined(with: .opacity))
    }
}

struct RoundButton: View {
    let system: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.text)
                .frame(width: 34, height: 34)
                .background(Color.panel, in: Circle())
                .overlay(Circle().stroke(Color.panelLine, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Cards

struct Scrim<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            Color(red: 9 / 255, green: 16 / 255, blue: 33 / 255).opacity(0.72)
            content.padding(8)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 540)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.navy, lineWidth: 3))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.coral, lineWidth: 4).padding(-3.5))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .foregroundStyle(Color.navy)
    }
}

struct CTA: View {
    let title: String
    var color: Color = .coral
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(rounded(17, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(color, in: Capsule())
                .overlay(Capsule().stroke(Color.navy, lineWidth: 3))
                .background(Capsule().fill(Color.navy).offset(y: 4))
        }
        .buttonStyle(.plain)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(rounded(10, .heavy)).tracking(1.4).foregroundStyle(Color.teal) }
}

struct LegendDot: View {
    let color: UIColor
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(uiColor: color)).overlay(Circle().stroke(Color.navy, lineWidth: 2)).frame(width: 13, height: 13)
            Text(label).font(rounded(11, .heavy))
        }
    }
}

struct PauseCard: View {
    let resume: () -> Void
    let restart: () -> Void
    let options: () -> Void
    let map: () -> Void
    let menu: () -> Void
    var body: some View {
        Card {
            Text("Paused").font(rounded(26, .bold))
            Text("Passengers will wait. Just this once.").font(rounded(13, .medium))
            HStack(spacing: 12) {
                CTA(title: "Resume", action: resume)
                CTA(title: "Restart", color: .teal, action: restart)
                CTA(title: "Options", color: .teal, action: options)
            }
            HStack(spacing: 12) {
                CTA(title: "Route map", color: .navy, action: map)
                CTA(title: "Main menu", color: .navy, action: menu)
            }
            .padding(.top, 4).padding(.bottom, 4)
        }
    }
}

/// The animated scorecard (GDD §2 Scoring): the score counts up event by event (each one named on its own line), stars fill as it passes each
/// target, then the title, the bonus medal (only if earned) and a NEW BEST badge land. Tap to skip the count.
struct EndCard: View {
    let plan: FlightPlan
    let result: FlightResult?
    let newBest: Bool
    let sound: (Synth.Sound) -> Void
    let next: (() -> Void)?
    let retry: () -> Void
    let map: () -> Void

    @State private var shown = 0.0
    @State private var resolved = 0
    @State private var missed = 0
    @State private var lit = 0
    @State private var delta: ScoreEvent?
    @State private var deltaID = 0
    @State private var done = false
    @State private var bounce = false

    private var r: FlightResult { result ?? FlightResult(stars: 0, resolved: 0, missed: 0, averageFix: nil, satisfaction: 0) }
    private static let titles = ["Rough flight", "Safe landing", "Smooth flight", "Perfect flight!"]

    var body: some View {
        Card {
          VStack(spacing: 10) {
            Text(done ? Self.titles[r.stars] : "Touchdown!")
                .font(rounded(30, .heavy))
                .id(done)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < lit ? "star.fill" : "star")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(i < lit ? Color.calm : Color.navy.opacity(0.35))
                        .scaleEffect(i < lit ? 1.15 : 0.9)
                        .animation(.spring(response: 0.35, dampingFraction: 0.45), value: lit)
                }
            }
            .accessibilityLabel("\(lit) of 3 stars")
            Text("\(Int(shown.rounded()))")
                .font(rounded(52, .heavy)).monospacedDigit()
                .contentTransition(.numericText(value: shown))
                .frame(minWidth: 160)
            // what just happened, one line per event, sliding in as the score counts to it
            ZStack {
                if let d = delta {
                    HStack(spacing: 8) {
                        Image(systemName: d.kind == .fixed ? "checkmark.circle.fill" : d.kind == .missed ? "xmark.circle.fill" : "minus.circle.fill")
                            .foregroundStyle(d.kind == .fixed ? Color.teal : Color(uiColor: Palette.critical))
                        Text(d.kind == .missed ? "Missed: \(d.label.lowercased())" : d.label).font(rounded(16, .bold))
                        if d.kind != .missed {
                            Text(d.delta >= 0 ? "+\(Int(d.delta.rounded()))" : "\(Int(d.delta.rounded()))")
                                .font(rounded(16, .heavy)).monospacedDigit()
                                .foregroundStyle(d.kind == .fixed ? Color.teal : Color(uiColor: Palette.critical))
                        }
                    }
                    .id(deltaID)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                } else if !done {
                    Text("Tap to skip").font(rounded(12, .medium)).foregroundStyle(Color.finePrint)
                }
            }
            .frame(height: 24)
            .clipped()
            HStack(spacing: 10) {
                Stat(label: "Resolved", value: "\(resolved)")
                Stat(label: "Missed", value: "\(missed)")
            }
            .frame(maxWidth: 320)
            if done && r.goalMet {
                HStack(spacing: 8) {
                    Image(systemName: "medal.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.calm)
                    Text("Bonus goal: \(r.goal.title)").font(rounded(14, .bold))
                }
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if done && r.stars == 0 {
                Text("Earn a star (\(r.targets[0])) to open the next flight.")
                    .font(rounded(12, .medium)).foregroundStyle(Color.finePrint)
            }
            HStack(spacing: 12) {
                if let next { CTA(title: "Next flight", action: next) }
                CTA(title: "Retry", color: next == nil ? .coral : .teal, action: retry)
                CTA(title: "Route map", color: .navy, action: map)
            }
            .padding(.bottom, 4)
          }
          .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            if done && newBest {
                Text("NEW BEST").font(rounded(15, .heavy)).tracking(1.2).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.coral, in: Capsule())
                    .overlay(Capsule().stroke(Color.navy, lineWidth: 2.5))
                    .rotationEffect(.degrees(bounce ? 8 : -4))
                    .scaleEffect(bounce ? 1.08 : 0.96)
                    .offset(x: 18, y: -16)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                    .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { bounce = true } }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task(id: result) { await countUp() }
    }

    /// Replays the flight's score events, one beat each (0.3–0.6 s).
    private func countUp() async {
        shown = 0; resolved = 0; missed = 0; lit = 0; done = false; delta = nil
        let log = r.log
        guard !log.isEmpty else { finish(); return }
        try? await Task.sleep(for: .milliseconds(450))
        // each event gets its own beat (about half a second), a bit quicker on very busy flights
        let step = min(0.6, max(0.3, 24 / Double(log.count)))
        var total = 0.0
        for e in log {
            if Task.isCancelled || done { return }
            total += e.delta
            withAnimation(.easeOut(duration: 0.25)) { delta = e; deltaID += 1 }
            withAnimation(.easeOut(duration: step * 0.8)) {
                shown = total
                if e.kind == .fixed { resolved += 1 }
                if e.kind == .missed { missed += 1 }
            }
            let nowLit = r.targets.filter { total >= Double($0) }.count
            if nowLit != lit {
                if nowLit > lit { sound(.streakUp) }
                lit = nowLit
            } else {
                sound(e.kind == .fixed ? .pick : .nope)
            }
            try? await Task.sleep(for: .seconds(step))
        }
        try? await Task.sleep(for: .milliseconds(250))
        finish()
    }

    private func finish() {
        guard !done else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            shown = Double(r.satisfaction)
            resolved = r.resolved
            missed = r.missed
            lit = r.stars
            delta = nil
            done = true
        }
        sound(r.stars == 3 ? .streakUp : .ding)
    }
}

struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(rounded(9, .heavy)).tracking(0.8).foregroundStyle(Color.finePrint)
            Text(value).font(rounded(20, .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1, green: 0.97, blue: 0.93), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.navy, lineWidth: 2))
    }
}

/// The drinks machine / oven menu: tap one to walk over and start it (GDD §6a).
struct MachinePickerView: View {
    let options: [Item]
    let pick: (Item) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { item in
                Button { pick(item) } label: {
                    VStack(spacing: 1) {
                        Image(uiImage: Art.itemImage(item, size: 34))
                        Text(item.displayName).font(rounded(9, .heavy)).foregroundStyle(Color.navy).lineLimit(1)
                    }
                    .frame(width: 52, height: 54)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.navy, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.displayName)
            }
        }
        .padding(6)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.coral, lineWidth: 3))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}
