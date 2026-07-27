import OSLog
import StoreKit

struct BoardTransaction: Sendable {
    let transactionID: UInt64
    let productID: String
    let environment: AccountEntitlementEnvironment
    let signedTransactionInfo: String
    let appAccountToken: UUID?
    let revocationDate: Date?
    let finishOperation: @Sendable () async -> Void

    init(
        transactionID: UInt64 = 0,
        productID: String,
        environment: AccountEntitlementEnvironment = .production,
        signedTransactionInfo: String = "",
        appAccountToken: UUID? = nil,
        revocationDate: Date?,
        finishOperation: @escaping @Sendable () async -> Void
    ) {
        self.transactionID = transactionID
        self.productID = productID
        self.environment = environment
        self.signedTransactionInfo = signedTransactionInfo
        self.appAccountToken = appAccountToken
        self.revocationDate = revocationDate
        self.finishOperation = finishOperation
    }

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
    let currentEntitlements: @MainActor @Sendable (_ productID: String) async -> BoardEntitlementResult
    let purchase: @MainActor @Sendable (
        _ productID: String,
        _ accountUUID: UUID
    ) async -> BoardClientPurchaseResult
    let displayPrice: @MainActor @Sendable (_ productID: String) async -> String?
    let sync: @MainActor @Sendable () async throws -> Void
    let updates: @MainActor @Sendable () -> AsyncStream<BoardTransaction>
}

private let boardStoreClientLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.clovery.app",
    category: "StoreKit"
)

private extension BoardTransaction {
    init(
        storeKitTransaction: StoreKit.Transaction,
        signedTransactionInfo: String
    ) {
        transactionID = storeKitTransaction.id
        productID = storeKitTransaction.productID
        environment = AccountEntitlementEnvironment(storeKitTransaction.environment)
        self.signedTransactionInfo = signedTransactionInfo
        appAccountToken = storeKitTransaction.appAccountToken
        revocationDate = storeKitTransaction.revocationDate
        finishOperation = { await storeKitTransaction.finish() }
    }
}

private extension AccountEntitlementEnvironment {
    init(_ environment: StoreKit.AppStore.Environment) {
        self = environment == .production ? .production : .sandbox
    }
}

extension BoardStoreClient {
    @MainActor
    static var live: BoardStoreClient {
        BoardStoreClient(
            currentEntitlements: { productID in
                var transactions: [BoardTransaction] = []
                var targetVerificationFailed = false
                for await result in StoreKit.Transaction.currentEntitlements {
                    switch result {
                    case .verified(let transaction):
                        guard transaction.productID == productID else { continue }
                        transactions.append(BoardTransaction(
                            storeKitTransaction: transaction,
                            signedTransactionInfo: result.jwsRepresentation
                        ))
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
            purchase: { productID, accountUUID in
                do {
                    let products = try await Product.products(for: [productID])
                    guard let product = products.first(where: { $0.id == productID }) else {
                        boardStoreClientLogger.error(
                            "Product unavailable: \(productID, privacy: .public)"
                        )
                        return .failed
                    }

                    var options: Set<Product.PurchaseOption> = [
                        .appAccountToken(accountUUID)
                    ]
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-CloverySimulateAskToBuy") {
                        options.insert(.simulatesAskToBuyInSandbox(true))
                    }
                    #endif

                    switch try await product.purchase(options: options) {
                    case .success(let result):
                        switch result {
                        case .verified(let transaction):
                            return .success(BoardTransaction(
                                storeKitTransaction: transaction,
                                signedTransactionInfo: result.jwsRepresentation
                            ))
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
                                    BoardTransaction(
                                        storeKitTransaction: transaction,
                                        signedTransactionInfo: result.jwsRepresentation
                                    )
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
