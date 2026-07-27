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
            accountID: "11111111-1111-4111-8111-111111111111",
            client: .live,
            reconciler: StoreKitAuthoritativeReconciler(),
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
            accountID: "11111111-1111-4111-8111-111111111111",
            client: .live,
            reconciler: StoreKitAuthoritativeReconciler(),
            observesUpdates: false,
            refreshesOnInit: false
        )
        await relaunchedStore.refresh()
        XCTAssertTrue(relaunchedStore.isUnlocked)
    }
}

@MainActor
private final class StoreKitAuthoritativeReconciler: EntitlementReconciling {
    func reconcile(
        accountID: String,
        storeKitResult: BoardEntitlementResult
    ) async -> EntitlementReconciliationOutcome {
        guard case let .verified(transactions) = storeKitResult,
              !transactions.isEmpty else {
            return .complete([])
        }
        return .complete([Self.activeEntitlement])
    }

    func reconcilePurchase(
        accountID: String,
        transaction: BoardTransaction
    ) async -> EntitlementReconciliationOutcome {
        .complete([Self.activeEntitlement])
    }

    private static let activeEntitlement = AccountEntitlementSummary(
        productID: "com.clovery.app.board.lifetime",
        state: .active,
        expiresAt: nil,
        revokedAt: nil,
        sourceStorefront: "XCODE",
        updatedAt: Date()
    )
}
