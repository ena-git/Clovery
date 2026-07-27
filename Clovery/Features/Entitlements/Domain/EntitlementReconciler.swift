import Foundation

enum EntitlementReconciliationOutcome: Equatable, Sendable {
    case complete([AccountEntitlementSummary])
    case pending(cached: [AccountEntitlementSummary])
    case needsAttention(String)

    var completesBootstrap: Bool {
        if case .complete = self { return true }
        return false
    }

    func isUnlocked(productID: String, at date: Date) -> Bool {
        switch self {
        case let .complete(entitlements), let .pending(entitlements):
            return entitlements.contains {
                $0.productID == productID && $0.isActive(at: date)
            }
        case .needsAttention:
            return false
        }
    }
}

@MainActor
protocol EntitlementReconciling: AnyObject {
    func reconcile(
        accountID: String,
        storeKitResult: BoardEntitlementResult
    ) async -> EntitlementReconciliationOutcome
    func reconcilePurchase(
        accountID: String,
        transaction: BoardTransaction
    ) async -> EntitlementReconciliationOutcome
}

@MainActor
final class EntitlementReconciler: EntitlementReconciling {
    private let api: AccountEntitlementAPIProtocol
    private let cache: AccountEntitlementCaching
    private let defaultEnvironment: AccountEntitlementEnvironment
    private let now: () -> Date

    init(
        api: AccountEntitlementAPIProtocol,
        cache: AccountEntitlementCaching,
        defaultEnvironment: AccountEntitlementEnvironment,
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.cache = cache
        self.defaultEnvironment = defaultEnvironment
        self.now = now
    }

    func reconcile(
        accountID: String,
        storeKitResult: BoardEntitlementResult
    ) async -> EntitlementReconciliationOutcome {
        guard let account = normalizedAccount(accountID) else {
            return .needsAttention("invalid_clovery_account_id")
        }
        guard case let .verified(transactions) = storeKitResult else {
            return cachedPending(accountID: account.id)
        }

        do {
            for transaction in transactions {
                guard transaction.appAccountToken == nil ||
                        transaction.appAccountToken == account.uuid else {
                    return .needsAttention("apple_transaction_account_mismatch")
                }
                try await submit(transaction)
            }

            let groups = Dictionary(grouping: transactions, by: \.environment)
            if groups.isEmpty {
                _ = try await api.restore(
                    transactionIDs: [],
                    environment: defaultEnvironment
                )
            } else {
                for environment in AccountEntitlementEnvironment.allCases {
                    guard let groupedTransactions = groups[environment] else { continue }
                    _ = try await api.restore(
                        transactionIDs: groupedTransactions.map(\.transactionID).sorted(),
                        environment: environment
                    )
                }
            }
            return try await authoritativeOutcome(accountID: account.id)
        } catch {
            return failureOutcome(error, accountID: account.id)
        }
    }

    func reconcilePurchase(
        accountID: String,
        transaction: BoardTransaction
    ) async -> EntitlementReconciliationOutcome {
        guard let account = normalizedAccount(accountID) else {
            return .needsAttention("invalid_clovery_account_id")
        }
        guard transaction.appAccountToken == nil ||
                transaction.appAccountToken == account.uuid else {
            return .needsAttention("apple_transaction_account_mismatch")
        }

        do {
            try await submit(transaction)
            return try await authoritativeOutcome(accountID: account.id)
        } catch {
            return failureOutcome(error, accountID: account.id)
        }
    }

    private func submit(_ transaction: BoardTransaction) async throws {
        if transaction.appAccountToken == nil {
            _ = try await api.claimLegacy(
                signedTransactionInfo: transaction.signedTransactionInfo,
                environment: transaction.environment
            )
        } else {
            _ = try await api.verify(
                transactionID: transaction.transactionID,
                environment: transaction.environment
            )
        }
    }

    private func authoritativeOutcome(
        accountID: String
    ) async throws -> EntitlementReconciliationOutcome {
        let entitlements = try await api.list()
        try cache.save(
            accountID: accountID,
            environment: defaultEnvironment,
            entitlements: entitlements,
            fetchedAt: now()
        )
        return .complete(entitlements)
    }

    private func failureOutcome(
        _ error: Error,
        accountID: String
    ) -> EntitlementReconciliationOutcome {
        if let apiError = error as? APIError {
            switch apiError.code {
            case "apple_transaction_claimed", "apple_transaction_account_mismatch":
                return .needsAttention(apiError.code ?? "entitlement_account_conflict")
            case "apple_verification_unavailable":
                return cachedPending(accountID: accountID)
            default:
                if apiError.statusCode.map({ $0 >= 500 }) == true {
                    return cachedPending(accountID: accountID)
                }
                if case .transport = apiError {
                    return cachedPending(accountID: accountID)
                }
                return .needsAttention(apiError.code ?? "entitlement_reconciliation_failed")
            }
        }
        if error is AuthenticatedAPIClientError {
            return .needsAttention("authentication_required")
        }
        return cachedPending(accountID: accountID)
    }

    private func cachedPending(accountID: String) -> EntitlementReconciliationOutcome {
        let cached = (try? cache.load(
            accountID: accountID,
            environment: defaultEnvironment
        ))?.entitlements ?? []
        return .pending(cached: cached)
    }

    private func normalizedAccount(_ accountID: String) -> (id: String, uuid: UUID)? {
        guard let uuid = UUID(uuidString: accountID), uuid != UUID.zero else { return nil }
        return (uuid.uuidString.lowercased(), uuid)
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
