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
        purchaseResult: BoardClientPurchaseResult = .failed,
        displayPrice: String? = "¥6.00",
        syncError: Error? = nil,
        updates: AsyncStream<BoardTransaction>? = nil
    ) -> BoardStoreClient {
        let updateStream = updates ?? AsyncStream { continuation in
            continuation.finish()
        }
        return BoardStoreClient(
            currentEntitlements: { currentEntitlements },
            purchase: { _ in purchaseResult },
            displayPrice: { _ in displayPrice },
            sync: {
                if let syncError { throw syncError }
            },
            updates: { updateStream }
        )
    }
}
