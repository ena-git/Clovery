import StoreKit

/// Manages the "Today's Board" lifetime in-app purchase.
@MainActor
class BoardStore: ObservableObject {

    static let shared = BoardStore()

    private let productID = "com.clovery.app.board.lifetime"

    @Published var isUnlocked = false

    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    init() {
        Task { await refresh() }
    }

    /// Re-checks current entitlements (call on every app launch or foreground).
    /// TestFlight builds automatically unlock all paid features.
    func refresh() async {
        if isTestFlight {
            isUnlocked = true
            return
        }
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == productID {
                isUnlocked = true
                return
            }
        }
    }

    /// Initiates the StoreKit purchase flow.
    /// Returns `true` if the transaction was completed and verified.
    func purchase() async -> Bool {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else { return false }
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let tx) = verification {
                await tx.finish()
                isUnlocked = true
                return true
            }
        } catch {
            // Purchase was cancelled or failed — not an error worth surfacing.
        }
        return false
    }

    /// Returns the localized price string for the board lifetime IAP (e.g. "$4.99").
    func fetchDisplayPrice() async -> String? {
        guard let product = try? await Product.products(for: [productID]).first else { return nil }
        return product.displayPrice
    }

    /// Restores previous purchases by syncing with the App Store.
    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
