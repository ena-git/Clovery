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

    @MainActor
    private final class EntitlementRefreshSignal {
        private var result: EntitlementRefreshResult?
        private var continuations: [CheckedContinuation<EntitlementRefreshResult, Never>] = []

        func value() async -> EntitlementRefreshResult {
            if let result {
                return result
            }

            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func resolve(_ result: EntitlementRefreshResult) {
            guard self.result == nil else { return }
            self.result = result
            let continuations = continuations
            self.continuations.removeAll()
            continuations.forEach { $0.resume(returning: result) }
        }
    }

    private struct EntitlementRefreshRequest {
        let generation: UInt64
        let signal: EntitlementRefreshSignal
    }

    static let productID = "com.clovery.app.board.lifetime"
    static let shared = BoardStore()

    @Published private(set) var isUnlocked = false

    private let client: BoardStoreClient
    private var updatesTask: Task<Void, Never>?
    private var stateGeneration: UInt64 = 0
    private var latestEntitlementRefreshRequest: EntitlementRefreshRequest?
    private var entitlementRefreshWorkers: [UInt64: Task<Void, Never>] = [:]
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
        supersedeLatestEntitlementRefreshRequest()
        let generation = advanceStateGeneration()
        let signal = EntitlementRefreshSignal()
        let request = EntitlementRefreshRequest(generation: generation, signal: signal)
        latestEntitlementRefreshRequest = request
        let client = client
        let productID = Self.productID
        entitlementRefreshWorkers[generation] = Task { [weak self, client] in
            let result = await client.currentEntitlements(productID)
            let wasCancelled = Task.isCancelled
            self?.completeEntitlementRefresh(
                result,
                generation: generation,
                wasCancelled: wasCancelled
            )
        }
        return request
    }

    private func resolveEntitlementRefresh(
        startingWith initialRequest: EntitlementRefreshRequest
    ) async -> ResolvedEntitlementState {
        var request = initialRequest
        while true {
            switch await request.signal.value() {
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

    private func completeEntitlementRefresh(
        _ result: BoardEntitlementResult,
        generation: UInt64,
        wasCancelled: Bool
    ) {
        entitlementRefreshWorkers[generation] = nil
        guard !wasCancelled,
              generation == stateGeneration,
              let request = latestEntitlementRefreshRequest,
              request.generation == generation else {
            return
        }

        request.signal.resolve(applyEntitlementResult(result, generation: generation))
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
        supersedeLatestEntitlementRefreshRequest()
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
        supersedeLatestEntitlementRefreshRequest()
    }

    private func supersedeLatestEntitlementRefreshRequest() {
        guard let request = latestEntitlementRefreshRequest else { return }
        request.signal.resolve(.superseded)
        entitlementRefreshWorkers.removeValue(forKey: request.generation)?.cancel()
        latestEntitlementRefreshRequest = nil
    }

    @discardableResult
    private func advanceStateGeneration() -> UInt64 {
        stateGeneration += 1
        return stateGeneration
    }

    deinit {
        updatesTask?.cancel()
        entitlementRefreshWorkers.values.forEach { $0.cancel() }
    }
}
