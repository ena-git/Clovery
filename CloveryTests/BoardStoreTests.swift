import Foundation
import XCTest
@testable import Clovery

@MainActor
final class BoardStoreTests: XCTestCase {
    private let accountID = "11111111-1111-4111-8111-111111111111"

    func testRefreshUsesServerOutcomeInsteadOfLocalStoreKitUnlock() async {
        let transaction = BoardTransaction.stub()
        let rejected = BoardStore(
            accountID: accountID,
            client: .stub(currentEntitlements: [transaction]),
            reconciler: EntitlementReconcilerSpy(
                reconcileOutcomes: [.needsAttention("apple_transaction_claimed")]
            ),
            observesUpdates: false,
            refreshesOnInit: false
        )

        await rejected.refresh()

        XCTAssertFalse(rejected.isUnlocked)

        let accepted = BoardStore(
            accountID: accountID,
            client: .stub(currentEntitlements: [transaction]),
            reconciler: EntitlementReconcilerSpy(
                reconcileOutcomes: [.complete([.activeBoard])]
            ),
            observesUpdates: false,
            refreshesOnInit: false
        )
        await accepted.refresh()
        XCTAssertTrue(accepted.isUnlocked)
    }

    func testInvalidAccountFailsBeforePresentingStoreKit() async {
        let recorder = BoardClientRecorder()
        let store = BoardStore(
            accountID: "not-a-uuid",
            client: .stub(recorder: recorder),
            reconciler: EntitlementReconcilerSpy(),
            observesUpdates: false,
            refreshesOnInit: false
        )

        let outcome = await store.purchase()

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(recorder.purchaseAccounts, [])
        XCTAssertFalse(store.isUnlocked)
    }

    func testPurchaseUnlocksAndFinishesOnlyAfterServerConfirmation() async {
        var store: BoardStore!
        var unlockedWhenFinished = false
        let transaction = BoardTransaction.stub(
            appAccountToken: UUID(uuidString: accountID),
            finishOperation: { @MainActor in
                unlockedWhenFinished = store.isUnlocked
            }
        )
        let reconciler = EntitlementReconcilerSpy(
            purchaseOutcomes: [.complete([.activeBoard])]
        )
        store = BoardStore(
            accountID: accountID,
            client: .stub(purchaseResult: .success(transaction)),
            reconciler: reconciler,
            observesUpdates: false,
            refreshesOnInit: false
        )

        let outcome = await store.purchase()

        XCTAssertEqual(outcome, .success)
        XCTAssertTrue(store.isUnlocked)
        XCTAssertTrue(unlockedWhenFinished)
        XCTAssertEqual(reconciler.purchaseTransactions.map(\.transactionID), [42])
    }

    func testPendingServerVerificationDoesNotUnlockOrFinish() async {
        let finishRecorder = FinishRecorder()
        let transaction = BoardTransaction.stub(
            appAccountToken: UUID(uuidString: accountID),
            finishOperation: { await finishRecorder.markFinished() }
        )
        let store = BoardStore(
            accountID: accountID,
            client: .stub(purchaseResult: .success(transaction)),
            reconciler: EntitlementReconcilerSpy(
                purchaseOutcomes: [.pending(cached: [.activeBoard])]
            ),
            observesUpdates: false,
            refreshesOnInit: false
        )

        let outcome = await store.purchase()
        let didFinish = await finishRecorder.isFinished()

        XCTAssertEqual(outcome, .pending)
        XCTAssertTrue(store.isUnlocked, "recent same-account cache can preserve display access")
        XCTAssertFalse(
            didFinish,
            "StoreKit must redeliver until the server confirms"
        )
    }

    func testRestoreSyncsThenMapsAuthoritativeOutcome() async {
        let recorder = BoardClientRecorder()
        let reconciler = EntitlementReconcilerSpy(
            reconcileOutcomes: [.complete([.activeBoard])]
        )
        let store = BoardStore(
            accountID: accountID,
            client: .stub(recorder: recorder),
            reconciler: reconciler,
            observesUpdates: false,
            refreshesOnInit: false
        )

        let outcome = await store.restore()

        XCTAssertEqual(outcome, .restored)
        XCTAssertEqual(recorder.calls.first, "sync")
        XCTAssertTrue(store.isUnlocked)
    }

    func testTransactionUpdateWaitsForServerBeforeFinishing() async {
        var continuation: AsyncStream<BoardTransaction>.Continuation!
        let updates = AsyncStream<BoardTransaction> { continuation = $0 }
        let finished = expectation(description: "finished after server")
        let reconciler = EntitlementReconcilerSpy(
            purchaseOutcomes: [.complete([.activeBoard])]
        )
        let store = BoardStore(
            accountID: accountID,
            client: .stub(updates: updates),
            reconciler: reconciler,
            observesUpdates: true,
            refreshesOnInit: false
        )

        continuation.yield(.stub(
            appAccountToken: UUID(uuidString: accountID),
            finishOperation: { finished.fulfill() }
        ))

        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(store.isUnlocked)
        XCTAssertEqual(reconciler.purchaseTransactions.count, 1)
        continuation.finish()
    }

    func testStaleRefreshCannotOverrideNewerPurchaseConfirmation() async {
        let gate = ReconciliationGate()
        let reconciler = EntitlementReconcilerSpy(
            purchaseOutcomes: [.complete([.activeBoard])],
            reconcileOperation: { await gate.wait() }
        )
        let store = BoardStore(
            accountID: accountID,
            client: .stub(
                currentEntitlements: [.stub()],
                purchaseResult: .success(.stub(appAccountToken: UUID(uuidString: accountID)))
            ),
            reconciler: reconciler,
            observesUpdates: false,
            refreshesOnInit: false
        )
        let refreshTask = Task { await store.refresh() }
        await gate.waitUntilStarted()

        let purchaseOutcome = await store.purchase()
        XCTAssertEqual(purchaseOutcome, .success)
        XCTAssertTrue(store.isUnlocked)

        await gate.resume(.complete([]))
        await refreshTask.value
        XCTAssertTrue(store.isUnlocked)
    }
}

@MainActor
private final class EntitlementReconcilerSpy: EntitlementReconciling {
    private var reconcileOutcomes: [EntitlementReconciliationOutcome]
    private var purchaseOutcomes: [EntitlementReconciliationOutcome]
    private let reconcileOperation: (() async -> EntitlementReconciliationOutcome)?
    private(set) var purchaseTransactions: [BoardTransaction] = []

    init(
        reconcileOutcomes: [EntitlementReconciliationOutcome] = [.complete([])],
        purchaseOutcomes: [EntitlementReconciliationOutcome] = [.needsAttention("failed")],
        reconcileOperation: (() async -> EntitlementReconciliationOutcome)? = nil
    ) {
        self.reconcileOutcomes = reconcileOutcomes
        self.purchaseOutcomes = purchaseOutcomes
        self.reconcileOperation = reconcileOperation
    }

    func reconcile(
        accountID: String,
        storeKitResult: BoardEntitlementResult
    ) async -> EntitlementReconciliationOutcome {
        if let reconcileOperation { return await reconcileOperation() }
        return reconcileOutcomes.removeFirst()
    }

    func reconcilePurchase(
        accountID: String,
        transaction: BoardTransaction
    ) async -> EntitlementReconciliationOutcome {
        purchaseTransactions.append(transaction)
        return purchaseOutcomes.removeFirst()
    }
}

private actor ReconciliationGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<EntitlementReconciliationOutcome, Never>?

    func wait() async -> EntitlementReconciliationOutcome {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { resultContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume(_ outcome: EntitlementReconciliationOutcome) {
        resultContinuation?.resume(returning: outcome)
        resultContinuation = nil
    }
}

private actor FinishRecorder {
    private var finished = false

    func markFinished() {
        finished = true
    }

    func isFinished() -> Bool {
        finished
    }
}

@MainActor
private final class BoardClientRecorder {
    var calls: [String] = []
    var purchaseAccounts: [UUID] = []
}

private extension BoardStoreClient {
    @MainActor
    static func stub(
        currentEntitlements: [BoardTransaction] = [],
        purchaseResult: BoardClientPurchaseResult = .failed,
        recorder: BoardClientRecorder? = nil,
        updates: AsyncStream<BoardTransaction>? = nil
    ) -> BoardStoreClient {
        let recorder = recorder ?? BoardClientRecorder()
        let stream = updates ?? AsyncStream { $0.finish() }
        return BoardStoreClient(
            currentEntitlements: { _ in
                recorder.calls.append("entitlements")
                return .verified(currentEntitlements)
            },
            purchase: { _, accountUUID in
                recorder.calls.append("purchase")
                recorder.purchaseAccounts.append(accountUUID)
                return purchaseResult
            },
            displayPrice: { _ in "¥6.00" },
            sync: { recorder.calls.append("sync") },
            updates: { stream }
        )
    }
}

private extension BoardTransaction {
    static func stub(
        appAccountToken: UUID? = nil,
        finishOperation: @escaping @Sendable () async -> Void = {}
    ) -> BoardTransaction {
        BoardTransaction(
            transactionID: 42,
            productID: "com.clovery.app.board.lifetime",
            environment: .production,
            signedTransactionInfo: "header.payload.signature",
            appAccountToken: appAccountToken,
            revocationDate: nil,
            finishOperation: finishOperation
        )
    }
}

private extension AccountEntitlementSummary {
    static let activeBoard = AccountEntitlementSummary(
        productID: "com.clovery.app.board.lifetime",
        state: .active,
        expiresAt: nil,
        revokedAt: nil,
        sourceStorefront: "CN",
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}
