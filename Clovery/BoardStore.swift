import Combine

@MainActor
final class BoardStore: ObservableObject {
    private enum ResolvedEntitlementState {
        case active
        case notFound
        case verificationFailed
    }

    private enum EntitlementRefreshResult {
        case resolved(ResolvedEntitlementState)
        case superseded
    }

    private struct EntitlementRefreshRequest {
        let generation: UInt64
        let task: Task<EntitlementRefreshResult, Never>
    }

    static let productID = "com.clovery.app.board.lifetime"
    static let shared = BoardStore()

    @Published private(set) var isUnlocked = false

    private let client: BoardStoreClient
    private var updatesTask: Task<Void, Never>?
    private var stateGeneration: UInt64 = 0
    private var latestEntitlementRefreshRequest: EntitlementRefreshRequest?
    private var lastResolvedEntitlementState: ResolvedEntitlementState = .notFound

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
            _ = startEntitlementRefresh()
        }
    }

    func refresh() async {
        let request = startEntitlementRefresh()
        _ = await resolveEntitlementRefresh(startingWith: request)
    }

    func purchase() async -> BoardPurchaseOutcome {
        switch await client.purchase(Self.productID) {
        case .success(let transaction)
            where transaction.productID == Self.productID && transaction.revocationDate == nil:
            recordResolvedEntitlementEvent(.active)
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
            let request = startEntitlementRefresh()
            switch await resolveEntitlementRefresh(startingWith: request) {
            case .active:
                return .restored
            case .notFound:
                return .notFound
            case .verificationFailed:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    private func handleTransactionUpdate(_ transaction: BoardTransaction) async {
        if transaction.productID == Self.productID && transaction.revocationDate == nil {
            recordResolvedEntitlementEvent(.active)
            await transaction.finish()
        } else {
            supersedeEntitlementRefreshRequests()
            let request = startEntitlementRefresh()
            _ = await resolveEntitlementRefresh(startingWith: request)
        }
    }

    private func startEntitlementRefresh() -> EntitlementRefreshRequest {
        let generation = advanceStateGeneration()
        latestEntitlementRefreshRequest?.task.cancel()
        let client = client
        let productID = Self.productID
        let task = Task<EntitlementRefreshResult, Never> { [weak self, client] in
            let result = await client.currentEntitlements(productID)
            guard !Task.isCancelled else { return .superseded }
            guard let self else { return .superseded }
            return self.applyEntitlementResult(result, generation: generation)
        }
        let request = EntitlementRefreshRequest(generation: generation, task: task)
        latestEntitlementRefreshRequest = request
        return request
    }

    private func resolveEntitlementRefresh(
        startingWith initialRequest: EntitlementRefreshRequest
    ) async -> ResolvedEntitlementState {
        var request = initialRequest
        while true {
            switch await request.task.value {
            case .resolved(let state):
                return state
            case .superseded:
                guard let latestRequest = latestEntitlementRefreshRequest,
                      latestRequest.generation > request.generation else {
                    return lastResolvedEntitlementState
                }
                request = latestRequest
            }
        }
    }

    private func applyEntitlementResult(
        _ result: BoardEntitlementResult,
        generation: UInt64
    ) -> EntitlementRefreshResult {
        guard generation == stateGeneration else { return .superseded }

        switch result {
        case .verified(let transactions):
            let hasActiveEntitlement = transactions.contains {
                $0.productID == Self.productID && $0.revocationDate == nil
            }
            let state: ResolvedEntitlementState = hasActiveEntitlement ? .active : .notFound
            isUnlocked = hasActiveEntitlement
            lastResolvedEntitlementState = state
            return .resolved(state)
        case .verificationFailed:
            lastResolvedEntitlementState = .verificationFailed
            return .resolved(.verificationFailed)
        }
    }

    private func recordResolvedEntitlementEvent(_ state: ResolvedEntitlementState) {
        advanceStateGeneration()
        latestEntitlementRefreshRequest?.task.cancel()
        latestEntitlementRefreshRequest = nil
        lastResolvedEntitlementState = state
        switch state {
        case .active:
            isUnlocked = true
        case .notFound:
            isUnlocked = false
        case .verificationFailed:
            break
        }
    }

    private func supersedeEntitlementRefreshRequests() {
        advanceStateGeneration()
        latestEntitlementRefreshRequest?.task.cancel()
        latestEntitlementRefreshRequest = nil
    }

    @discardableResult
    private func advanceStateGeneration() -> UInt64 {
        stateGeneration += 1
        return stateGeneration
    }

    deinit {
        updatesTask?.cancel()
        latestEntitlementRefreshRequest?.task.cancel()
    }
}
