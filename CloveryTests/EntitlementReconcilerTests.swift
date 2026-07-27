import Foundation
import XCTest
@testable import Clovery

@MainActor
final class EntitlementReconcilerTests: XCTestCase {
    private let accountUUID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLegacyTransactionIsClaimedBeforeGroupedRestoreAndServerList() async {
        let api = EntitlementAPISpy(entitlements: [.activeBoard])
        let reconciler = makeReconciler(api: api)
        let transaction = BoardTransaction.stub(
            transactionID: 42,
            environment: .production,
            appAccountToken: nil
        )

        let outcome = await reconciler.reconcile(
            accountID: accountUUID.uuidString.lowercased(),
            storeKitResult: .verified([transaction])
        )

        XCTAssertEqual(outcome, .complete([.activeBoard]))
        XCTAssertEqual(
            api.calls,
            [
                .claim("header.payload.signature", .production),
                .restore([42], .production),
                .list,
            ]
        )
    }

    func testMatchingTokensVerifyAndRestoreEveryEnvironmentGroup() async {
        let api = EntitlementAPISpy(entitlements: [.activeBoard])
        let reconciler = makeReconciler(api: api)
        let transactions = [
            BoardTransaction.stub(
                transactionID: 42,
                environment: .production,
                appAccountToken: accountUUID
            ),
            BoardTransaction.stub(
                transactionID: 84,
                environment: .sandbox,
                appAccountToken: accountUUID
            ),
        ]

        let outcome = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: .verified(transactions)
        )

        XCTAssertEqual(outcome, .complete([.activeBoard]))
        XCTAssertTrue(api.calls.contains(.verify(42, .production)))
        XCTAssertTrue(api.calls.contains(.verify(84, .sandbox)))
        XCTAssertTrue(api.calls.contains(.restore([42], .production)))
        XCTAssertTrue(api.calls.contains(.restore([84], .sandbox)))
        XCTAssertEqual(api.calls.last, .list)
    }

    func testEmptyInventoryStillCompletesRestore() async {
        let api = EntitlementAPISpy(entitlements: [])
        let reconciler = makeReconciler(api: api)

        let outcome = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: .verified([])
        )

        XCTAssertEqual(outcome, .complete([]))
        XCTAssertEqual(api.calls, [.restore([], .production), .list])
    }

    func testUnverifiedStoreKitEvidenceNeverReachesBackend() async {
        let api = EntitlementAPISpy(entitlements: [.activeBoard])
        let reconciler = makeReconciler(api: api)

        let outcome = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: .verificationFailed
        )

        XCTAssertEqual(outcome, .pending(cached: []))
        XCTAssertEqual(api.calls, [])
    }

    func testCrossAccountTransactionNeedsAttentionWithoutUnlocking() async {
        let api = EntitlementAPISpy(entitlements: [.activeBoard])
        let reconciler = makeReconciler(api: api)
        let otherAccount = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let outcome = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: .verified([
                .stub(transactionID: 42, appAccountToken: otherAccount)
            ])
        )

        XCTAssertEqual(
            outcome,
            .needsAttention("apple_transaction_account_mismatch")
        )
        XCTAssertFalse(outcome.isUnlocked(productID: BoardStore.productID, at: now))
        XCTAssertEqual(api.calls, [])
    }

    func testServerStateIsAuthoritativeOverLocalStoreKitEvidence() async {
        for serverEntitlement in [
            AccountEntitlementSummary.revokedBoard,
            AccountEntitlementSummary.expiredBoard,
        ] {
            let api = EntitlementAPISpy(entitlements: [serverEntitlement])
            let reconciler = makeReconciler(api: api)
            let outcome = await reconciler.reconcile(
                accountID: accountUUID.uuidString,
                storeKitResult: .verified([
                    .stub(transactionID: 42, appAccountToken: accountUUID)
                ])
            )

            XCTAssertEqual(outcome, .complete([serverEntitlement]))
            XCTAssertFalse(outcome.isUnlocked(productID: BoardStore.productID, at: now))
        }
    }

    func testServerRejectionNeverUnlocksLocalEntitlement() async {
        let api = EntitlementAPISpy(
            entitlements: [.activeBoard],
            error: APIError.server(
                code: "apple_transaction_claimed",
                message: "Already claimed.",
                statusCode: 409
            )
        )
        let reconciler = makeReconciler(api: api)

        let outcome = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: .verified([.stub(transactionID: 42)])
        )

        XCTAssertEqual(outcome, .needsAttention("apple_transaction_claimed"))
        XCTAssertFalse(outcome.isUnlocked(productID: BoardStore.productID, at: now))
    }

    func testRetryingSameTransactionRemainsIdempotentlyComplete() async {
        let api = EntitlementAPISpy(entitlements: [.activeBoard])
        let reconciler = makeReconciler(api: api)
        let evidence = BoardEntitlementResult.verified([
            .stub(transactionID: 42, appAccountToken: accountUUID)
        ])

        let first = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: evidence
        )
        let second = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: evidence
        )

        XCTAssertEqual(first, .complete([.activeBoard]))
        XCTAssertEqual(second, first)
        XCTAssertEqual(api.calls.filter { $0 == .restore([42], .production) }.count, 2)
    }

    func testNetworkFailureUsesOnlyRecentSameAccountCacheAndStaysPending() async {
        let cache = EntitlementCacheSpy(
            snapshot: AccountEntitlementCacheSnapshot(
                accountID: accountUUID.uuidString.lowercased(),
                environment: .production,
                entitlements: [.activeBoard],
                fetchedAt: now
            )
        )
        let api = EntitlementAPISpy(
            entitlements: [],
            error: APIError.server(
                code: "apple_verification_unavailable",
                message: "Unavailable.",
                statusCode: 503
            )
        )
        let reconciler = makeReconciler(api: api, cache: cache)

        let outcome = await reconciler.reconcile(
            accountID: accountUUID.uuidString,
            storeKitResult: .verified([])
        )

        XCTAssertEqual(outcome, .pending(cached: [.activeBoard]))
        XCTAssertTrue(outcome.isUnlocked(productID: BoardStore.productID, at: now))
        XCTAssertFalse(outcome.completesBootstrap)
        XCTAssertEqual(cache.loadedAccountID, accountUUID.uuidString.lowercased())
    }

    func testPurchaseVerificationReloadsServerBeforeCompleting() async {
        let api = EntitlementAPISpy(entitlements: [.activeBoard])
        let reconciler = makeReconciler(api: api)
        let transaction = BoardTransaction.stub(
            transactionID: 42,
            appAccountToken: accountUUID
        )

        let outcome = await reconciler.reconcilePurchase(
            accountID: accountUUID.uuidString,
            transaction: transaction
        )

        XCTAssertEqual(outcome, .complete([.activeBoard]))
        XCTAssertEqual(api.calls, [.verify(42, .production), .list])
    }

    func testStoreKitEvidenceIsNotInterpolatedIntoLogs() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Clovery/BoardStoreClient.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("result.jwsRepresentation"))
        XCTAssertTrue(source.contains(".appAccountToken(accountUUID)"))
        XCTAssertFalse(source.contains("\\(transactionID"))
        XCTAssertFalse(source.contains("\\(signedTransactionInfo"))
        XCTAssertFalse(source.contains("privacy: .public)\n                            signedTransactionInfo"))
    }

    private func makeReconciler(
        api: EntitlementAPISpy,
        cache: AccountEntitlementCaching? = nil
    ) -> EntitlementReconciler {
        EntitlementReconciler(
            api: api,
            cache: cache ?? EntitlementCacheSpy(),
            defaultEnvironment: .production,
            now: { self.now }
        )
    }
}

@MainActor
private final class EntitlementAPISpy: AccountEntitlementAPIProtocol {
    enum Call: Equatable {
        case claim(String, AccountEntitlementEnvironment)
        case verify(UInt64, AccountEntitlementEnvironment)
        case restore([UInt64], AccountEntitlementEnvironment)
        case list
    }

    private let entitlements: [AccountEntitlementSummary]
    private let error: Error?
    private(set) var calls: [Call] = []

    init(entitlements: [AccountEntitlementSummary], error: Error? = nil) {
        self.entitlements = entitlements
        self.error = error
    }

    func claimLegacy(
        signedTransactionInfo: String,
        environment: AccountEntitlementEnvironment
    ) async throws -> AccountEntitlementSummary {
        calls.append(.claim(signedTransactionInfo, environment))
        if let error { throw error }
        return entitlements.first ?? .activeBoard
    }

    func verify(
        transactionID: UInt64,
        environment: AccountEntitlementEnvironment
    ) async throws -> AccountEntitlementSummary {
        calls.append(.verify(transactionID, environment))
        if let error { throw error }
        return entitlements.first ?? .activeBoard
    }

    func restore(
        transactionIDs: [UInt64],
        environment: AccountEntitlementEnvironment
    ) async throws -> [AccountEntitlementSummary] {
        calls.append(.restore(transactionIDs, environment))
        if let error { throw error }
        return entitlements
    }

    func list() async throws -> [AccountEntitlementSummary] {
        calls.append(.list)
        if let error { throw error }
        return entitlements
    }
}

@MainActor
private final class EntitlementCacheSpy: AccountEntitlementCaching {
    private let snapshot: AccountEntitlementCacheSnapshot?
    private(set) var loadedAccountID: String?

    init(snapshot: AccountEntitlementCacheSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func save(
        accountID: String,
        environment: AccountEntitlementEnvironment,
        entitlements: [AccountEntitlementSummary],
        fetchedAt: Date
    ) throws {}

    func load(
        accountID: String,
        environment: AccountEntitlementEnvironment
    ) throws -> AccountEntitlementCacheSnapshot? {
        loadedAccountID = accountID
        guard snapshot?.accountID == accountID,
              snapshot?.environment == environment
        else {
            return nil
        }
        return snapshot
    }

    func clear() throws {}
}

private extension BoardTransaction {
    static func stub(
        transactionID: UInt64,
        environment: AccountEntitlementEnvironment = .production,
        appAccountToken: UUID? = nil
    ) -> BoardTransaction {
        BoardTransaction(
            transactionID: transactionID,
            productID: "com.clovery.app.board.lifetime",
            environment: environment,
            signedTransactionInfo: "header.payload.signature",
            appAccountToken: appAccountToken,
            revocationDate: nil,
            finishOperation: {}
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

    static let revokedBoard = AccountEntitlementSummary(
        productID: "com.clovery.app.board.lifetime",
        state: .revoked,
        expiresAt: nil,
        revokedAt: Date(timeIntervalSince1970: 1_799_999_000),
        sourceStorefront: "CN",
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    static let expiredBoard = AccountEntitlementSummary(
        productID: "com.clovery.app.board.lifetime",
        state: .expired,
        expiresAt: Date(timeIntervalSince1970: 1_799_999_000),
        revokedAt: nil,
        sourceStorefront: "CN",
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}
