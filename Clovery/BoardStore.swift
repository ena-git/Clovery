import Combine
import Foundation

@MainActor
final class BoardStore: ObservableObject {
    nonisolated static let productID = "com.clovery.app.board.lifetime"

    @Published private(set) var isUnlocked = false

    private let accountIDProvider: () -> String?
    private let client: BoardStoreClient
    private let reconciler: EntitlementReconciling
    private let now: () -> Date
    private var updatesTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var lastOutcome: EntitlementReconciliationOutcome = .pending(cached: [])

    init(
        accountID: String,
        client: BoardStoreClient,
        reconciler: EntitlementReconciling,
        observesUpdates: Bool = true,
        refreshesOnInit: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.accountIDProvider = { accountID }
        self.client = client
        self.reconciler = reconciler
        self.now = now
        start(observesUpdates: observesUpdates, refreshesOnInit: refreshesOnInit)
    }

    init(
        accountIDProvider: @escaping () -> String?,
        client: BoardStoreClient,
        reconciler: EntitlementReconciling,
        observesUpdates: Bool = true,
        refreshesOnInit: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.accountIDProvider = accountIDProvider
        self.client = client
        self.reconciler = reconciler
        self.now = now
        start(observesUpdates: observesUpdates, refreshesOnInit: refreshesOnInit)
    }

    func refresh() async {
        _ = await refreshOutcome()
    }

    func reconcileForBootstrap(
        accountID: String
    ) async -> EntitlementReconciliationOutcome {
        guard currentAccount()?.id == UUID(uuidString: accountID)?.uuidString.lowercased() else {
            return .needsAttention("bootstrap_account_mismatch")
        }
        return await refreshOutcome()
    }

    func purchase() async -> BoardPurchaseOutcome {
        guard let account = currentAccount() else { return .failed }
        let token = beginOperation()
        switch await client.purchase(Self.productID, account.uuid) {
        case let .success(transaction):
            let outcome = await reconciler.reconcilePurchase(
                accountID: account.id,
                transaction: transaction
            )
            guard apply(outcome, token: token) else { return .failed }
            switch outcome {
            case .complete:
                await transaction.finish()
                return isUnlocked ? .success : .failed
            case .pending:
                return .pending
            case .needsAttention:
                return .failed
            }
        case .cancelled:
            return .cancelled
        case .pending:
            return .pending
        case .failed:
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
        } catch {
            return .failed
        }

        switch await refreshOutcome() {
        case .complete:
            return isUnlocked ? .restored : .notFound
        case .pending, .needsAttention:
            return .failed
        }
    }

    func accountDidChange() {
        generation += 1
        lastOutcome = .pending(cached: [])
        isUnlocked = false
    }

    private func start(observesUpdates: Bool, refreshesOnInit: Bool) {
        if observesUpdates {
            let stream = client.updates()
            updatesTask = Task { [weak self] in
                for await transaction in stream {
                    guard !Task.isCancelled, let self else { return }
                    await self.handleTransactionUpdate(transaction)
                }
            }
        }
        if refreshesOnInit {
            Task { [weak self] in await self?.refresh() }
        }
    }

    private func refreshOutcome() async -> EntitlementReconciliationOutcome {
        guard let account = currentAccount() else {
            accountDidChange()
            return lastOutcome
        }
        let token = beginOperation()
        let storeKitResult = await client.currentEntitlements(Self.productID)
        let outcome = await reconciler.reconcile(
            accountID: account.id,
            storeKitResult: storeKitResult
        )
        return apply(outcome, token: token) ? outcome : lastOutcome
    }

    private func handleTransactionUpdate(_ transaction: BoardTransaction) async {
        guard let account = currentAccount() else {
            accountDidChange()
            return
        }
        let token = beginOperation()
        let outcome = await reconciler.reconcilePurchase(
            accountID: account.id,
            transaction: transaction
        )
        guard apply(outcome, token: token) else { return }
        if case .complete = outcome {
            await transaction.finish()
        }
    }

    @discardableResult
    private func apply(
        _ outcome: EntitlementReconciliationOutcome,
        token: UInt64
    ) -> Bool {
        guard token == generation else { return false }
        lastOutcome = outcome
        isUnlocked = outcome.isUnlocked(productID: Self.productID, at: now())
        return true
    }

    private func beginOperation() -> UInt64 {
        generation += 1
        return generation
    }

    private func currentAccount() -> (id: String, uuid: UUID)? {
        guard let value = accountIDProvider(),
              let uuid = UUID(uuidString: value),
              uuid.uuidString != "00000000-0000-0000-0000-000000000000"
        else {
            return nil
        }
        return (uuid.uuidString.lowercased(), uuid)
    }

    deinit {
        updatesTask?.cancel()
    }
}
