import StoreKitTest
import XCTest
@testable import Clovery

@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "Clovery")
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = false
    }

    override func tearDown() {
        session.clearTransactions()
        session.resetToDefaultState()
        session = nil
    }

    func testAskToBuyApprovalUnlocksThroughTransactionUpdates() async throws {
        session.askToBuyEnabled = true
        let store = BoardStore(
            client: .live,
            observesUpdates: true,
            refreshesOnInit: false
        )

        let purchaseOutcome = await store.purchase()
        XCTAssertEqual(purchaseOutcome, .pending)
        XCTAssertFalse(store.isUnlocked)

        let pending = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == BoardStore.productID && $0.pendingAskToBuyConfirmation
        })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        for _ in 0..<40 where !store.isUnlocked {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(store.isUnlocked)

        let relaunchedStore = BoardStore(
            client: .live,
            observesUpdates: false,
            refreshesOnInit: false
        )
        await relaunchedStore.refresh()
        XCTAssertTrue(relaunchedStore.isUnlocked)
    }
}
