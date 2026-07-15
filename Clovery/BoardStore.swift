import Combine

@MainActor
final class BoardStore: ObservableObject {
    private enum EntitlementRefreshResult {
        case active
        case notFound
        case verificationFailed
        case superseded
    }

    static let productID = "com.clovery.app.board.lifetime"
    static let shared = BoardStore()

    @Published private(set) var isUnlocked = false

    private let client: BoardStoreClient
    private var updatesTask: Task<Void, Never>?
    private var stateGeneration: UInt64 = 0

    init(
        client: BoardStoreClient = .live,
        observesUpdates: Bool = true,
        refreshesOnInit: Bool = true
    ) {
        self.client = client
        if observesUpdates {
            updatesTask = Task { [weak self, client] in
                for await transaction in client.updates() {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    await self.handleTransactionUpdate(transaction)
                }
            }
        }
        if refreshesOnInit {
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        _ = await refreshEntitlementState()
    }

    private func refreshEntitlementState() async -> EntitlementRefreshResult {
        let refreshGeneration = advanceStateGeneration()
        let result = await client.currentEntitlements(Self.productID)
        guard refreshGeneration == stateGeneration else { return .superseded }

        switch result {
        case .verified(let transactions):
            let hasActiveEntitlement = transactions.contains {
                $0.productID == Self.productID && $0.revocationDate == nil
            }
            isUnlocked = hasActiveEntitlement
            return hasActiveEntitlement ? .active : .notFound
        case .verificationFailed:
            return .verificationFailed
        }
    }

    func purchase() async -> BoardPurchaseOutcome {
        switch await client.purchase(Self.productID) {
        case .success(let transaction)
            where transaction.productID == Self.productID && transaction.revocationDate == nil:
            advanceStateGeneration()
            isUnlocked = true
            await transaction.finish()
            return .success
        case .cancelled:
            return .cancelled
        case .pending:
            return .pending
        case .success, .failed:
            return .failed
        }
    }

    func fetchDisplayPrice() async -> String? {
        await client.displayPrice(Self.productID)
    }

    @discardableResult
    func restore() async -> BoardRestoreOutcome {
        do {
            try await client.sync()
            switch await refreshEntitlementState() {
            case .active:
                return .restored
            case .notFound:
                return .notFound
            case .verificationFailed:
                return .failed
            case .superseded:
                return isUnlocked ? .restored : .failed
            }
        } catch {
            return .failed
        }
    }

    private func handleTransactionUpdate(_ transaction: BoardTransaction) async {
        advanceStateGeneration()
        if transaction.productID == Self.productID && transaction.revocationDate == nil {
            isUnlocked = true
            await transaction.finish()
        } else {
            await refresh()
        }
    }

    @discardableResult
    private func advanceStateGeneration() -> UInt64 {
        stateGeneration += 1
        return stateGeneration
    }

    deinit {
        updatesTask?.cancel()
    }
}
