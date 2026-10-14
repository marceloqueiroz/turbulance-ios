import SwiftUI

/// Unlock the full game (GDD §9): what Full Game opens, its price, Restore and Not now.
/// Opened from a padlocked route on the map and from the scorecard at the end of Route 1.
struct PaywallCard: View {
    let price: String?
    let status: AppModel.StoreStatus
    let buy: () -> Void
    let restore: () -> Void
    let close: () -> Void

    private var working: Bool { status == .working }

    var body: some View {
        Card {
            HStack {
                Eyebrow(text: "Full game")
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Not now")
            }
            Image("LogoCrew")
                .resizable().scaledToFit()
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text("Unlock the full game").font(rounded(26, .bold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Campaign.routes.filter { $0.requiresFullGame && !$0.inDevelopment }) { route in
                    included(title: "Route \(route.id) · \(route.name)", detail: "\(route.flights.count) flights · \(route.aircraftNames)")
                }
                included(title: "Every future route", detail: "New routes and aircraft as they arrive")
            }
            .padding(.vertical, 2)
            Text("One purchase for every crew member on this device. Routes still open as you earn stars.")
                .font(rounded(12, .medium)).foregroundStyle(Color.finePrint)
            if case .message(let text) = status {
                Text(text).font(rounded(13, .semibold)).foregroundStyle(Color.coral)
            }
            HStack(spacing: 12) {
                CTA(title: working ? "One moment…" : price.map { "Unlock for \($0)" } ?? "Unlock", action: buy)
                    .disabled(working || price == nil)
                    .opacity(working || price == nil ? 0.6 : 1)
                CTA(title: "Restore", color: .teal, action: restore)
                    .disabled(working).opacity(working ? 0.6 : 1)
                CTA(title: "Not now", color: .navy, action: close)
            }
            .padding(.bottom, 4)
            if price == nil && !working {
                Text("The App Store isn't reachable right now.")
                    .font(rounded(11, .medium)).foregroundStyle(Color.finePrint)
            }
        }
    }

    private func included(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "airplane.circle.fill").font(.system(size: 20)).foregroundStyle(Color.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(rounded(15, .bold))
                Text(detail).font(rounded(12, .medium)).foregroundStyle(Color.finePrint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
