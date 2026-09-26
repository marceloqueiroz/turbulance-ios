import SpriteKit
import SwiftUI

struct GameView: View {
    let app: AppModel
    let game: GameController

    var body: some View {
        ZStack {
            Color.sky.ignoresSafeArea()
            VStack(spacing: 4) {
                HUDBar(game: game)
                    .padding(.horizontal, 16)
                    .opacity(game.screen == .intro ? 0 : 1)
                // The cabin runs edge to edge, under the notch and home-indicator insets.
                ZStack {
                    SpriteView(scene: game.scene, preferredFramesPerSecond: 60)
                        .ignoresSafeArea()
                    if let toast = game.toast {
                        VStack {
                            Spacer()
                            Text(toast)
                                .font(rounded(game.largeText ? 23 : 18, .semibold))
                                .foregroundStyle(Color.text)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .padding(.horizontal, 22).padding(.vertical, 14)
                                .background(Color.navy, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(uiColor: Palette.calm), lineWidth: 3))
                                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                                .frame(maxWidth: 720)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 14)
                                .allowsHitTesting(false)
                        }
                        .transition(.opacity)
                    }
                    overlay
                }
                .ignoresSafeArea(edges: [.horizontal, .bottom])
            }
            .padding(.top, 6)
            if game.screen == .intro { IntroLetterbox(game: game).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: game.toast)
        .animation(.easeInOut(duration: 0.4), value: game.screen)
    }

    @ViewBuilder private var overlay: some View {
        switch game.screen {
        case .paused:
            Scrim {
                PauseCard(resume: { game.setPaused(false) }, restart: { app.board(game.plan) },
                          options: { app.showOptions = true }, map: { app.openMap() })
            }
        case .ended:
            Scrim {
                EndCard(plan: game.plan, result: game.result, newBest: app.newBest,
                        next: app.nextFlight(after: game.plan).map { next in { app.openMap(brief: next) } },
                        retry: { app.board(game.plan) }, map: { app.openMap() })
            }
        case .idle, .intro, .playing: EmptyView()
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
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.panelLine, lineWidth: 5)
                    Circle().trim(from: 0, to: game.clockFraction)
                        .stroke(game.landing ? Color.coral : Color.teal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.timeText).font(rounded(21, .semibold)).monospacedDigit().foregroundStyle(Color.text)
                    (Text(game.phaseText).bold().foregroundColor(.text) + Text(" · \(game.flightLabel)"))
                        .font(rounded(10, .semibold)).foregroundStyle(Color.muted).lineLimit(1)
                }
                if game.seatbelt { SeatbeltSign() }
            }
            Spacer(minLength: 8)
            if game.seatPrompt != .none { SeatPromptPill(prompt: game.seatPrompt) }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("SATISFACTION").font(rounded(9, .heavy)).tracking(1).foregroundStyle(Color.muted)
                    Spacer()
                    Text("\(game.satisfaction)").font(rounded(11, .heavy)).monospacedDigit().foregroundStyle(Color.text)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.panel).overlay(Capsule().stroke(Color.panelLine, lineWidth: 1))
                        Capsule().fill(satColor).frame(width: geo.size.width * CGFloat(game.satisfaction) / 100)
                        ForEach(Tuning.starThresholds, id: \.self) { t in
                            Rectangle().fill(Color.sky.opacity(0.7)).frame(width: 2).offset(x: geo.size.width * t / 100)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: game.satisfaction)
                }
                .frame(height: 10)
            }
            .frame(width: 170)
            HStack(spacing: 8) {
                RoundButton(system: game.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: "Sound") { game.toggleMute() }
                RoundButton(system: "pause.fill", label: "Pause") { game.setPaused(game.screen == .playing) }
            }
        }
        .frame(height: 40)
    }

    private var satColor: Color {
        game.satisfaction >= 65 ? .teal : game.satisfaction >= 40 ? Color(uiColor: Palette.calm) : Color(uiColor: Palette.critical)
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
    var body: some View {
        Card {
            Text("Paused").font(rounded(26, .bold))
            Text("Passengers will wait. Just this once.").font(rounded(13, .medium))
            HStack(spacing: 12) {
                CTA(title: "Resume", action: resume)
                CTA(title: "Restart", color: .teal, action: restart)
                CTA(title: "Options", color: .teal, action: options)
                CTA(title: "Route map", color: .navy, action: map)
            }
            .padding(.bottom, 4)
        }
    }
}

struct EndCard: View {
    let plan: FlightPlan
    let result: FlightResult?
    let newBest: Bool
    let next: (() -> Void)?
    let retry: () -> Void
    let map: () -> Void
    var body: some View {
        let r = result ?? FlightResult(stars: 0, resolved: 0, missed: 0, averageFix: nil, satisfaction: 0)
        Card {
            Eyebrow(text: "Landed · \(plan.id) \(plan.name)")
            HStack(spacing: 14) {
                Text(["Rough landing", "Bumpy but done", "Smooth landing", "Five-star crew"][r.stars]).font(rounded(26, .bold))
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < r.stars ? "star.fill" : "star")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(i < r.stars ? Color.coral : Color.navy)
                    }
                }
                .accessibilityLabel("\(r.stars) of 3 stars")
                if newBest {
                    Text("NEW BEST").font(rounded(11, .heavy)).tracking(1).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.teal, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Stat(label: "Resolved", value: "\(r.resolved)")
                Stat(label: "Missed", value: "\(r.missed)")
                Stat(label: "Avg fix", value: r.averageFix.map { String(format: "%.1fs", $0) } ?? "–")
                Stat(label: "Satisfaction", value: "\(r.satisfaction)")
            }
            HStack(spacing: 8) {
                Image(systemName: r.goalMet ? "medal.fill" : "medal")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(r.goalMet ? Color.calm : Color.finePrint)
                Text("Bonus goal: \(r.goal.title) \(r.goalMet ? "· medal earned" : "· not this time")")
                    .font(rounded(13, .bold))
            }
            Text(r.stars == 0 ? "Earn at least one star (40 satisfaction) to open the next flight."
                              : "Stars: 40 · 65 · 85 satisfaction (the ticks on the HUD bar).")
                .font(rounded(11, .medium)).foregroundStyle(Color.finePrint)
            HStack(spacing: 12) {
                if let next { CTA(title: "Next flight", action: next) }
                CTA(title: "Retry", color: next == nil ? .coral : .teal, action: retry)
                CTA(title: "Route map", color: .navy, action: map)
            }
            .padding(.bottom, 4)
        }
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
