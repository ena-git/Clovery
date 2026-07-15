import XCTest
@testable import Clovery

@MainActor
final class BoardStoreTests: XCTestCase {
    func testRefreshRestoresVerifiedLifetimeEntitlement() async {
        let transaction = BoardTransaction.stub(productID: BoardStore.productID)
        let store = BoardStore(
            client: .stub(currentEntitlements: [transaction]),
            observesUpdates: false,
            refreshesOnInit: false
        )

        await store.refresh()

        XCTAssertTrue(store.isUnlocked)
    }

    func testSuccessfulPurchaseUnlocksBeforeFinishingTransaction() async {
        var store: BoardStore!
        var unlockedWhenFinished = false
        let transaction = BoardTransaction(
            productID: BoardStore.productID,
            revocationDate: nil,
            finishOperation: { @MainActor in
                unlockedWhenFinished = store.isUnlocked
            }
        )
        store = BoardStore(
            client: .stub(purchaseResult: .success(transaction)),
            observesUpdates: false,
            refreshesOnInit: false
        )

        let outcome = await store.purchase()

        XCTAssertEqual(outcome, .success)
        XCTAssertTrue(store.isUnlocked)
        XCTAssertTrue(unlockedWhenFinished)
    }

    func testCancelledAndPendingPurchasesDoNotUnlock() async {
        let cases: [(BoardClientPurchaseResult, BoardPurchaseOutcome)] = [
            (.cancelled, .cancelled),
            (.pending, .pending)
        ]

        for (purchaseResult, expectedOutcome) in cases {
            let store = BoardStore(
                client: .stub(purchaseResult: purchaseResult),
                observesUpdates: false,
                refreshesOnInit: false
            )

            let outcome = await store.purchase()

            XCTAssertEqual(outcome, expectedOutcome)
            XCTAssertFalse(store.isUnlocked)
        }
    }

    func testRestoreDistinguishesRestoredNotFoundAndFailed() async {
        let restored = BoardStore(
            client: .stub(
                currentEntitlements: [.stub(productID: BoardStore.productID)]
            ),
            observesUpdates: false,
            refreshesOnInit: false
        )
        let restoredOutcome = await restored.restore()
        XCTAssertEqual(restoredOutcome, .restored)

        let missing = BoardStore(
            client: .stub(),
            observesUpdates: false,
            refreshesOnInit: false
        )
        let missingOutcome = await missing.restore()
        XCTAssertEqual(missingOutcome, .notFound)

        let failed = BoardStore(
            client: .stub(syncError: StoreClientTestError.failed),
            observesUpdates: false,
            refreshesOnInit: false
        )
        let failedOutcome = await failed.restore()
        XCTAssertEqual(failedOutcome, .failed)
    }

    func testRestoreReturnsFailedWhenTargetEntitlementVerificationFails() async {
        let store = BoardStore(
            client: .stub(entitlementResult: .verificationFailed),
            observesUpdates: false,
            refreshesOnInit: false
        )

        let outcome = await store.restore()

        XCTAssertEqual(outcome, .failed)
        XCTAssertFalse(store.isUnlocked)
    }

    func testRestoreSyncsBeforeQueryingEntitlements() async {
        let recorder = StoreClientCallRecorder()
        let transaction = BoardTransaction.stub(productID: BoardStore.productID)
        let store = BoardStore(
            client: .stub(
                currentEntitlementsOperation: { _ in
                    await recorder.record("entitlements")
                    return .verified([transaction])
                },
                syncOperation: {
                    await recorder.record("sync")
                }
            ),
            observesUpdates: false,
            refreshesOnInit: false
        )

        let outcome = await store.restore()
        let calls = await recorder.recordedCalls()

        XCTAssertEqual(outcome, .restored)
        XCTAssertEqual(calls, ["sync", "entitlements"])
    }

    func testApprovedTransactionUpdateUnlocksAndFinishes() async {
        var continuation: AsyncStream<BoardTransaction>.Continuation!
        let updates = AsyncStream<BoardTransaction> { continuation = $0 }
        let finished = expectation(description: "finished")
        let store = BoardStore(
            client: .stub(updates: updates),
            observesUpdates: true,
            refreshesOnInit: false
        )

        continuation.yield(BoardTransaction(
            productID: BoardStore.productID,
            revocationDate: nil,
            finishOperation: { finished.fulfill() }
        ))

        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(store.isUnlocked)
        continuation.finish()
    }

    func testDeinitCancelsTransactionUpdates() async {
        let terminated = expectation(description: "updates terminated")
        var continuation: AsyncStream<BoardTransaction>.Continuation!
        let updates = AsyncStream<BoardTransaction> { streamContinuation in
            continuation = streamContinuation
            streamContinuation.onTermination = { _ in terminated.fulfill() }
        }
        var store: BoardStore? = BoardStore(
            client: .stub(updates: updates),
            observesUpdates: true,
            refreshesOnInit: false
        )
        weak var weakStore = store

        for _ in 0..<3 {
            await Task.yield()
        }
        store = nil

        for _ in 0..<20 where weakStore != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(weakStore)
        await fulfillment(of: [terminated], timeout: 0.5)
        withExtendedLifetime(continuation) {}
    }

    func testStaleRefreshCannotRelockSuccessfulPurchase() async {
        let entitlementGate = EntitlementGate()
        let transaction = BoardTransaction.stub(productID: BoardStore.productID)
        let store = BoardStore(
            client: .stub(
                currentEntitlementsOperation: { productID in
                    await entitlementGate.currentEntitlements(for: productID)
                },
                purchaseResult: .success(transaction)
            ),
            observesUpdates: false,
            refreshesOnInit: false
        )
        let refreshTask = Task { await store.refresh() }

        await entitlementGate.waitUntilStarted()

        let purchaseOutcome = await store.purchase()
        XCTAssertEqual(purchaseOutcome, .success)
        XCTAssertTrue(store.isUnlocked)

        await entitlementGate.resume(returning: .verified([]))
        await refreshTask.value

        XCTAssertTrue(store.isUnlocked)
    }

    func testRestoreUsesSupersedingRefreshResult() async {
        let entitlementGate = SequencedEntitlementGate()
        let transaction = BoardTransaction.stub(productID: BoardStore.productID)
        let store = BoardStore(
            client: .stub(
                currentEntitlementsOperation: { productID in
                    await entitlementGate.currentEntitlements(for: productID)
                },
                purchaseResult: .success(transaction)
            ),
            observesUpdates: false,
            refreshesOnInit: false
        )

        let purchaseOutcome = await store.purchase()
        XCTAssertEqual(purchaseOutcome, .success)
        XCTAssertTrue(store.isUnlocked)

        let restoreTask = Task { await store.restore() }
        await entitlementGate.waitForRequestCount(1)

        let refreshTask = Task { await store.refresh() }
        await entitlementGate.waitForRequestCount(2)

        await entitlementGate.resumeRequest(1, returning: .verified([transaction]))
        for _ in 0..<3 {
            await Task.yield()
        }

        await entitlementGate.resumeRequest(2, returning: .verified([]))
        await refreshTask.value
        let restoreOutcome = await restoreTask.value
        let requestCount = await entitlementGate.totalRequestCount()

        XCTAssertEqual(restoreOutcome, .notFound)
        XCTAssertFalse(store.isUnlocked)
        XCTAssertEqual(requestCount, 2)
    }
}

private actor EntitlementGate {
    private var started = false
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<BoardEntitlementResult, Never>?

    func currentEntitlements(for _: String) async -> BoardEntitlementResult {
        started = true
        let continuations = startedContinuations
        startedContinuations.removeAll()
        continuations.forEach { $0.resume() }

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func resume(returning result: BoardEntitlementResult) {
        guard let continuation = resultContinuation else {
            preconditionFailure("Entitlement request has not started")
        }
        resultContinuation = nil
        continuation.resume(returning: result)
    }
}

private actor SequencedEntitlementGate {
    private struct RequestWaiter {
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var requestCount = 0
    private var requestWaiters: [RequestWaiter] = []
    private var resultContinuations: [
        Int: CheckedContinuation<BoardEntitlementResult, Never>
    ] = [:]

    func currentEntitlements(for _: String) async -> BoardEntitlementResult {
        requestCount += 1
        let requestID = requestCount

        var pendingWaiters: [RequestWaiter] = []
        for waiter in requestWaiters {
            if requestCount >= waiter.minimumCount {
                waiter.continuation.resume()
            } else {
                pendingWaiters.append(waiter)
            }
        }
        requestWaiters = pendingWaiters

        return await withCheckedContinuation { continuation in
            resultContinuations[requestID] = continuation
        }
    }

    func waitForRequestCount(_ minimumCount: Int) async {
        guard requestCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(RequestWaiter(
                minimumCount: minimumCount,
                continuation: continuation
            ))
        }
    }

    func resumeRequest(_ requestID: Int, returning result: BoardEntitlementResult) {
        guard let continuation = resultContinuations.removeValue(forKey: requestID) else {
            preconditionFailure("Entitlement request \(requestID) has not started")
        }
        continuation.resume(returning: result)
    }

    func totalRequestCount() -> Int {
        requestCount
    }
}

private actor StoreClientCallRecorder {
    private var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }

    func recordedCalls() -> [String] {
        calls
    }
}

private enum StoreClientTestError: Error {
    case failed
}

private extension BoardTransaction {
    static func stub(productID: String) -> BoardTransaction {
        BoardTransaction(
            productID: productID,
            revocationDate: nil,
            finishOperation: {}
        )
    }
}

private extension BoardStoreClient {
    static func stub(
        currentEntitlements: [BoardTransaction] = [],
        entitlementResult: BoardEntitlementResult? = nil,
        currentEntitlementsOperation: (@Sendable (_ productID: String) async -> BoardEntitlementResult)? = nil,
        purchaseResult: BoardClientPurchaseResult = .failed,
        displayPrice: String? = "¥6.00",
        syncError: Error? = nil,
        syncOperation: (@Sendable () async throws -> Void)? = nil,
        updates: AsyncStream<BoardTransaction>? = nil
    ) -> BoardStoreClient {
        let resolvedEntitlementResult = entitlementResult ?? .verified(currentEntitlements)
        let resolvedEntitlementOperation = currentEntitlementsOperation ?? {
            _ in resolvedEntitlementResult
        }
        let resolvedSyncOperation = syncOperation ?? {
            if let syncError { throw syncError }
        }
        let updateStream = updates ?? AsyncStream { continuation in
            continuation.finish()
        }
        return BoardStoreClient(
            currentEntitlements: resolvedEntitlementOperation,
            purchase: { _ in purchaseResult },
            displayPrice: { _ in displayPrice },
            sync: resolvedSyncOperation,
            updates: { updateStream }
        )
    }
}
