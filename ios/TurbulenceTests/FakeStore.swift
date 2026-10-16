@testable import Turbulence

/// A stand-in App Store for the Full Game purchase, so tests never reach StoreKit.
final class FakeStore: FullGameStore {
    var owned: Bool
    var price: String? = "$3.99"
    /// What the next purchase does; a purchase that succeeds marks Full Game owned.
    var nextPurchase = PurchaseOutcome.purchased
    private(set) var purchases = 0
    private var onChange: ((Bool) -> Void)?

    init(owned: Bool = false) { self.owned = owned }

    func refresh() async -> (owned: Bool, price: String?) { (owned, price) }

    func purchase() async -> PurchaseOutcome {
        purchases += 1
        if nextPurchase == .purchased { owned = true }
        return nextPurchase
    }

    func restore() async -> Bool { owned }

    func listen(_ onChange: @escaping (Bool) -> Void) { self.onChange = onChange }

    /// A change from outside the app: an Ask to Buy approval, a refund.
    func push(_ owned: Bool) {
        self.owned = owned
        onChange?(owned)
    }
}
