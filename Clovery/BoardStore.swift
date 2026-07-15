import Combine

@MainActor
final class BoardStore: ObservableObject {
    static let productID = "com.clovery.app.board.lifetime"
    static let shared = BoardStore()

    @Published private(set) var isUnlocked = false

    private let client: BoardStoreClient
    private var updatesTask: Task<Void, Never>?

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
        let transactions = await client.currentEntitlements()
        isUnlocked = transactions.contains {
            $0.productID == Self.productID && $0.revocationDate == nil
        }
    }

    func purchase() async -> BoardPurchaseOutcome {
        switch await client.purchase(Self.productID) {
        case .success(let transaction)
            where transaction.productID == Self.productID && transaction.revocationDate == nil:
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
            await refresh()
            return isUnlocked ? .restored : .notFound
        } catch {
            return .failed
        }
    }

    private func handleTransactionUpdate(_ transaction: BoardTransaction) async {
        if transaction.productID == Self.productID && transaction.revocationDate == nil {
            isUnlocked = true
            await transaction.finish()
        } else {
            await refresh()
        }
    }

    deinit {
        updatesTask?.cancel()
    }
}
