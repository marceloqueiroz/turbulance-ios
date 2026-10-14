import Foundation
import StoreKit

/// What happened when the player tried to buy Full Game.
enum PurchaseOutcome: Equatable {
    case purchased
    case pending            // Ask to Buy: a parent has to approve; the updates listener picks it up later
    case cancelled
    case failed(String)
}

/// The one in-app purchase (GDD §9): a non-consumable that opens Route 2 and every later route.
/// `AppModel` talks to it through this protocol, so tests can stand in a fake store.
protocol FullGameStore: AnyObject {
    /// Ownership and the localised price; nil price when the product can't be loaded (offline, not set up).
    func refresh() async -> (owned: Bool, price: String?)
    func purchase() async -> PurchaseOutcome
    /// Syncs with the App Store and reports whether Full Game is owned afterwards.
    func restore() async -> Bool
    /// Called on every later change: Ask to Buy approvals, refunds, Family Sharing, purchases on another device.
    func listen(_ onChange: @escaping (Bool) -> Void)
}

/// StoreKit 2. Ownership comes from `Transaction.currentEntitlements`, which StoreKit caches, so it works offline.
final class AppStoreFullGame: FullGameStore {
    static let productID = "com.marceloqueiroz.turbulence.fullgame"

    private var product: Product?
    private var updates: Task<Void, Never>?

    deinit { updates?.cancel() }

    func refresh() async -> (owned: Bool, price: String?) {
        if product == nil { product = try? await Product.products(for: [Self.productID]).first }
        return (await owned(), product?.displayPrice)
    }

    func purchase() async -> PurchaseOutcome {
        if product == nil { product = try? await Product.products(for: [Self.productID]).first }
        guard let product else { return .failed("The App Store isn't available right now. Try again later.") }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                return transaction.revocationDate == nil ? .purchased : .failed("This purchase was refunded.")
            case .success(.unverified):
                return .failed("The App Store couldn't confirm this purchase.")
            case .pending: return .pending
            case .userCancelled: return .cancelled
            @unknown default: return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> Bool {
        try? await AppStore.sync()
        return await owned()
    }

    func listen(_ onChange: @escaping (Bool) -> Void) {
        updates?.cancel()
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result, transaction.productID == Self.productID {
                    await transaction.finish()
                }
                guard let self else { return }
                onChange(await self.owned())
            }
        }
    }

    private func owned() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { return true }
        }
        return false
    }
}
