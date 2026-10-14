import SwiftUI

/// Unlock the full game (GDD §9): what Full Game opens, its price, Restore and Not now. Full screen in the cards'
/// cream, navy and coral, without their rim: the logo and pitch on the left, what's included and the buttons on the right.
/// Opened from a padlocked route on the map and from the scorecard at the end of Route 1.
struct PaywallScreen: View {
    let price: String?
    let status: AppModel.StoreStatus
    let buy: () -> Void
    let restore: () -> Void
    let close: () -> Void

    private var working: Bool { status == .working }

    var body: some View {
        GeometryReader { outer in
            // the same margin on both sides, from the larger inset: landscape puts the island on one side only
            let inset = outer.safeAreaInsets
            let side = max(inset.leading, inset.trailing, 16) + 4
            frame(wide: outer.size.width > outer.size.height)
                .padding(.horizontal, side)
                .padding(.top, max(inset.top, 10))
                .padding(.bottom, max(inset.bottom, 10))
        }
        .ignoresSafeArea()
        .foregroundStyle(Color.navy)
        .background(Color.cream.ignoresSafeArea())
    }

    /// The page: full-bleed cream, no card rim (a frame round the whole screen reads as a card on a border).
    private func frame(wide: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if wide {
                    HStack(alignment: .center, spacing: 40) {
                        pitch.frame(maxWidth: .infinity)
                        details.frame(maxWidth: 440)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 28) { pitch; details }.padding(.vertical, 40)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 1000, maxHeight: .infinity)
            .frame(maxWidth: .infinity)

            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
            .padding(.trailing, 8).padding(.top, 8)
        }
    }

    /// The logo and what the purchase is.
    private var pitch: some View {
        VStack(spacing: 14) {
            Image("LogoCrew")
                .resizable().scaledToFit()
                .frame(maxHeight: 120)
                .accessibilityHidden(true)
            Eyebrow(text: "Full game")
            Text("Unlock the full game")
                .font(rounded(32, .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("One purchase for every crew member on this device. Routes still open as you earn stars.")
                .font(rounded(14, .medium)).foregroundStyle(Color.finePrint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }

    /// What's included, the buttons and how the purchase went.
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Campaign.routes.filter { $0.requiresFullGame && !$0.inDevelopment }) { route in
                included(title: "Route \(route.id) · \(route.name)", detail: "\(route.flights.count) flights · \(route.aircraftNames)")
            }
            included(title: "Every future route", detail: "New routes and aircraft as they arrive")
            if case .message(let text) = status {
                Text(text).font(rounded(13, .semibold)).foregroundStyle(Color.coral)
            }
            if price == nil && !working {
                Text("The App Store isn't reachable right now.")
                    .font(rounded(12, .medium)).foregroundStyle(Color.finePrint)
            }
            HStack(spacing: 12) {
                CTA(title: working ? "One moment…" : price.map { "Unlock for \($0)" } ?? "Unlock", action: buy)
                    .disabled(working || price == nil)
                    .opacity(working || price == nil ? 0.6 : 1)
                CTA(title: "Restore", color: .teal, action: restore)
                    .disabled(working).opacity(working ? 0.6 : 1)
            }
            .padding(.top, 6)
            Button("Not now", action: close)
                .font(rounded(15, .bold)).foregroundStyle(Color.navy.opacity(0.7))
                .buttonStyle(.plain)
        }
    }

    private func included(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "airplane.circle.fill").font(.system(size: 24)).foregroundStyle(Color.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(rounded(17, .bold))
                Text(detail).font(rounded(13, .medium)).foregroundStyle(Color.finePrint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
