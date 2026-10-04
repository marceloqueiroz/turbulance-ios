import SpriteKit
import SwiftUI

/// The route map (GDD §9a, Route Map Plan step 5): the SpriteKit world with a fixed top bar,
/// the briefing card for open flights and a short notice for anything locked or not built yet.
struct WorldMapView: View {
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notice: Notice?

    struct Notice: Equatable {
        let title: String
        let detail: String
        let symbol: String
    }

    private var scene: WorldMapScene { .shared }

    var body: some View {
        let profile = app.profile ?? Profile(name: "", avatar: 0)
        ZStack {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()

            VStack {
                topBar(profile)
                Spacer()
                if let notice {
                    NoticeCard(notice: notice) { self.notice = nil }
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .animation(.easeOut(duration: 0.2), value: app.briefing)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: notice)
        .onAppear {
            scene.reduceMotion = reduceMotion
            scene.onTap = handle
            scene.configure(profile: profile)
            app.markMapVisited()
            let plan = app.briefing ?? profile.nextFlight
            if let city = Campaign.destination(of: plan) { scene.focus(city: city, animated: false) }
        }
        .onChange(of: app.profile) { _, p in if let p { scene.configure(profile: p) } }
    }

    private func topBar(_ profile: Profile) -> some View {
        HStack(spacing: 10) {
            MenuChip(profile: app.profile) { app.goToLanding() }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Campaign.routes) { r in
                    let open = profile.isUnlocked(r)
                    Button { scene.focus(route: r.id) } label: {
                        HStack(spacing: 4) {
                            if !open { Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)) }
                            Text("\(r.id)").font(rounded(15, .heavy))
                        }
                        .foregroundStyle(Color.text)
                        .frame(minWidth: 40, minHeight: 32)
                        .background(Color.panel, in: Capsule())
                        .overlay(Capsule().stroke(Color.panelLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show route \(r.id), \(r.name)\(open ? "" : ", locked")")
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
            RoundButton(system: "location.fill", label: "Show the next flight") {
                if let city = Campaign.destination(of: profile.nextFlight) { scene.focus(city: city) }
            }
            RoundButton(system: "gearshape.fill", label: "Options") { app.sheet = .options }
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private func handle(_ tap: WorldMapScene.Tap) {
        notice = nil
        switch tap {
        case .flight(let plan):
            if app.profile?.isUnlocked(plan) == true {
                app.briefing = plan
            } else if let before = Campaign.flight(before: plan), let route = Campaign.route(containing: before.id),
                      let n = route.flights.firstIndex(of: before) {
                show(Notice(title: "Flight \(plan.id) is locked", detail: "Get a star on flight \(n + 1) of \(route.name) first.", symbol: "lock.fill"))
            }
        case let .lockedRoute(route, needs, have):
            show(Notice(title: "Route \(route.id) · \(route.name)",
                        detail: "Unlocks at \(needs) stars. You have \(have). About two stars a flight on the earlier routes gets you there.",
                        symbol: "lock.fill"))
        case .comingSoon(let name):
            show(Notice(title: name, detail: "Arrives in a future update.", symbol: "cloud.bolt.fill"))
        }
    }

    private func show(_ n: Notice) {
        notice = n
        Task {
            try? await Task.sleep(for: .seconds(4))
            if notice == n { notice = nil }
        }
    }
}

/// A small panel at the bottom of the map; tap to dismiss.
struct NoticeCard: View {
    let notice: WorldMapView.Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Color.calm)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(rounded(16, .bold)).foregroundStyle(Color.text)
                Text(notice.detail).font(rounded(13, .semibold)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: 440)
        .background(Color.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.panelLine, lineWidth: 1))
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .combine)
    }
}
