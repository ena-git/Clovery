import OSLog
import StoreKit

struct BoardTransaction: Sendable {
    let productID: String
    let revocationDate: Date?
    let finishOperation: @Sendable () async -> Void

    func finish() async {
        await finishOperation()
    }
}

enum BoardEntitlementResult: Sendable {
    case verified([BoardTransaction])
    case verificationFailed
}

enum BoardClientPurchaseResult: Sendable {
    case success(BoardTransaction)
    case cancelled
    case pending
    case failed
}

struct BoardStoreClient: Sendable {
    let currentEntitlements: @Sendable (_ productID: String) async -> BoardEntitlementResult
    let purchase: @Sendable (_ productID: String) async -> BoardClientPurchaseResult
    let displayPrice: @Sendable (_ productID: String) async -> String?
    let sync: @Sendable () async throws -> Void
    let updates: @Sendable () -> AsyncStream<BoardTransaction>
}

private let boardStoreClientLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.clovery.app",
    category: "StoreKit"
)

private extension BoardTransaction {
    init(storeKitTransaction: StoreKit.Transaction) {
        productID = storeKitTransaction.productID
        revocationDate = storeKitTransaction.revocationDate
        finishOperation = { await storeKitTransaction.finish() }
    }
}

extension BoardStoreClient {
    static var live: BoardStoreClient {
        BoardStoreClient(
            currentEntitlements: { productID in
                var transactions: [BoardTransaction] = []
                var targetVerificationFailed = false
                for await result in StoreKit.Transaction.currentEntitlements {
                    switch result {
                    case .verified(let transaction):
                        guard transaction.productID == productID else { continue }
                        transactions.append(BoardTransaction(storeKitTransaction: transaction))
                    case .unverified(let transaction, let error):
                        boardStoreClientLogger.error(
                            "Unverified entitlement: \(String(describing: error), privacy: .public)"
                        )
                        if transaction.productID == productID {
                            targetVerificationFailed = true
                        }
                    }
                }
                if targetVerificationFailed {
                    return .verificationFailed
                }
                return .verified(transactions)
            },
            purchase: { productID in
                do {
                    let products = try await Product.products(for: [productID])
                    guard let product = products.first(where: { $0.id == productID }) else {
                        boardStoreClientLogger.error(
                            "Product unavailable: \(productID, privacy: .public)"
                        )
                        return .failed
                    }

                    var options: Set<Product.PurchaseOption> = []
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-CloverySimulateAskToBuy") {
                        options.insert(.simulatesAskToBuyInSandbox(true))
                    }
                    #endif

                    switch try await product.purchase(options: options) {
                    case .success(let result):
                        switch result {
                        case .verified(let transaction):
                            return .success(BoardTransaction(storeKitTransaction: transaction))
                        case .unverified(_, let error):
                            boardStoreClientLogger.error(
                                "Purchase verification failed: \(String(describing: error), privacy: .public)"
                            )
                            return .failed
                        }
                    case .userCancelled:
                        return .cancelled
                    case .pending:
                        return .pending
                    @unknown default:
                        boardStoreClientLogger.error("Unknown StoreKit purchase result")
                        return .failed
                    }
                } catch {
                    boardStoreClientLogger.error(
                        "Purchase failed: \(error.localizedDescription, privacy: .public)"
                    )
                    return .failed
                }
            },
            displayPrice: { productID in
                do {
                    return try await Product.products(for: [productID])
                        .first(where: { $0.id == productID })?
                        .displayPrice
                } catch {
                    boardStoreClientLogger.error(
                        "Price request failed: \(error.localizedDescription, privacy: .public)"
                    )
                    return nil
                }
            },
            sync: {
                try await AppStore.sync()
            },
            updates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await result in StoreKit.Transaction.updates {
                            guard !Task.isCancelled else { break }
                            switch result {
                            case .verified(let transaction):
                                continuation.yield(
                                    BoardTransaction(storeKitTransaction: transaction)
                                )
                            case .unverified(_, let error):
                                boardStoreClientLogger.error(
                                    "Transaction update verification failed: \(String(describing: error), privacy: .public)"
                                )
                            }
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }
}
