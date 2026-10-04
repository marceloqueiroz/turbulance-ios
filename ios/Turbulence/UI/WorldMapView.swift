import SpriteKit
import SwiftUI

/// The route map (GDD §9a, Route Map Plan step 5): the SpriteKit world with a fixed top bar,
/// the briefing card for open flights and a short notice for anything locked or not built yet.
struct WorldMapView: View {
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notice: Notice?
    /// A briefing waiting for the plane and any reveals to finish.
    @State private var heldBriefing: FlightPlan?

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
                if app.mapEditor { editorBar }
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
        .onAppear(perform: arrive)
        .onChange(of: app.profile) { _, p in if let p, heldBriefing == nil, app.pendingLeg == nil { scene.configure(profile: p) } }
    }

    /// Arriving on the map: the toy plane flies the leg just finished, newly opened routes reveal themselves one by one,
    /// and only then does a waiting briefing card open.
    private func arrive() {
        scene.reduceMotion = reduceMotion
        scene.haptics = app.device.haptics
        scene.onTap = handle
        scene.editing = app.mapEditor
        app.markMapVisited()
        guard let profile = app.profile else { return }
        let reveals = MapState(profile: profile).pendingReveals
        let leg = app.pendingLeg
        scene.configure(profile: profile, hiding: Set(reveals))
        if leg == nil && reveals.isEmpty {
            if let city = Campaign.destination(of: app.briefing ?? profile.nextFlight) { scene.focus(city: city, animated: false) }
            return
        }
        heldBriefing = app.briefing
        app.briefing = nil
        app.pendingLeg = nil
        func revealNext(_ remaining: [Int]) {
            guard let id = remaining.first else {
                app.markRevealsSeen()
                if let held = heldBriefing {
                    if let city = Campaign.destination(of: held) { scene.focus(city: city) }
                    app.briefing = held
                }
                heldBriefing = nil
                return
            }
            scene.reveal(route: id) { revealNext(Array(remaining.dropFirst())) }
        }
        if let leg {
            if let from = Campaign.route(containing: leg.id).flatMap({ r in r.flights.firstIndex(of: leg).map { r.cities[$0] } }) {
                scene.focus(city: from, animated: false)
            }
            scene.flyLeg(leg) { revealNext(reveals) }
        } else {
            revealNext(reveals)
        }
    }

    /// Debug-only toolbar for drawing city-life paths; Export copies JSON for MapLayout.json.
    private var editorBar: some View {
        HStack(spacing: 8) {
            Picker("Kind", selection: Binding(get: { scene.editorKind }, set: { scene.editorKind = $0 })) {
                ForEach(MapLayout.Life.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            Button("New") { scene.editorNewPath() }
            Button("Undo") { scene.editorUndo() }
            Button("Delete") { scene.editorDeleteLast() }
            Button("Export") {
                let json = scene.editorExport()
                UIPasteboard.general.string = json
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MapLife.json")
                try? json.write(to: url, atomically: true, encoding: .utf8)
                show(Notice(title: "Life paths exported", detail: "Copied to the clipboard and saved as Documents/MapLife.json.", symbol: "doc.on.clipboard"))
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
        .font(rounded(13, .bold))
        .padding(10)
        .background(Color.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 10)
    }

    private func topBar(_ profile: Profile) -> some View {
        HStack(spacing: 10) {
            MenuChip(profile: app.profile) { app.goToLanding() }
            Spacer()
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
        .padding(.horizontal, 24).padding(.top, 8)
        .ignoresSafeArea(edges: .horizontal)     // 24 pt from the screen edge, not from the notch inset
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
