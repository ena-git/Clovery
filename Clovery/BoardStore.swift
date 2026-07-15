import StoreKit
import OSLog

/// Manages the "Today's Board" lifetime in-app purchase.
@MainActor
class BoardStore: ObservableObject {

    static let shared = BoardStore()

    private let productID = "com.clovery.app.board.lifetime"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.clovery.app",
        category: "StoreKit"
    )

    @Published var isUnlocked = false

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { await refresh() }
    }

    /// Re-checks current entitlements (call on every app launch or foreground).
    func refresh() async {
        var hasActiveEntitlement = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == productID,
                      transaction.revocationDate == nil else { continue }
                hasActiveEntitlement = true
            case .unverified(_, let error):
                logger.error(
                    "Unverified current entitlement: \(String(describing: error), privacy: .public)"
                )
            }
        }
        isUnlocked = hasActiveEntitlement
    }

    /// Initiates the StoreKit purchase flow.
    func purchase() async -> BoardPurchaseOutcome {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                logger.error("Product unavailable: \(self.productID, privacy: .public)")
                return .failed
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard transaction.productID == productID else {
                        logger.error(
                            "Unexpected purchased product: \(transaction.productID, privacy: .public)"
                        )
                        return .failed
                    }
                    await transaction.finish()
                    isUnlocked = true
                    return .success
                case .unverified(_, let error):
                    logger.error(
                        "Purchase verification failed: \(String(describing: error), privacy: .public)"
                    )
                    return .failed
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                logger.error("Unknown StoreKit purchase result")
                return .failed
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Returns the localized price string for the board lifetime IAP (e.g. "$4.99").
    func fetchDisplayPrice() async -> String? {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                logger.error("Price unavailable for product: \(self.productID, privacy: .public)")
                return nil
            }
            return product.displayPrice
        } catch {
            logger.error("Price request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Restores previous purchases by syncing with the App Store.
    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }

            switch result {
            case .verified(let transaction):
                guard transaction.productID == productID else { continue }
                await transaction.finish()
                await refresh()
            case .unverified(_, let error):
                logger.error(
                    "Unverified transaction update: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
