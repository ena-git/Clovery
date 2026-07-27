import Foundation
@testable import Clovery

@MainActor
func makeTestBoardStore() -> BoardStore {
    BoardStore(
        accountID: "11111111-1111-4111-8111-111111111111",
        client: BoardStoreClient(
            currentEntitlements: { _ in .verified([]) },
            purchase: { _, _ in .failed },
            displayPrice: { _ in nil },
            sync: {},
            updates: { AsyncStream { $0.finish() } }
        ),
        reconciler: TestEntitlementReconciler(),
        observesUpdates: false,
        refreshesOnInit: false
    )
}

@MainActor
private final class TestEntitlementReconciler: EntitlementReconciling {
    func reconcile(
        accountID: String,
        storeKitResult: BoardEntitlementResult
    ) async -> EntitlementReconciliationOutcome {
        .complete([])
    }

    func reconcilePurchase(
        accountID: String,
        transaction: BoardTransaction
    ) async -> EntitlementReconciliationOutcome {
        .complete([])
    }
}
