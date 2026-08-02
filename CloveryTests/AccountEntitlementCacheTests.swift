import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountEntitlementCacheTests: XCTestCase {
    private let accountID = "11111111-1111-4111-8111-111111111111"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecentCacheLoadsOnlyForSameAccountAndEnvironment() throws {
        let fileURL = temporaryURL()
        let cache = AccountEntitlementCache(
            fileURL: fileURL,
            now: { self.now }
        )
        try cache.save(
            accountID: accountID,
            environment: .production,
            entitlements: [.activeBoard(updatedAt: now)],
            fetchedAt: now.addingTimeInterval(-71 * 60 * 60)
        )

        let loaded = try cache.load(
            accountID: accountID,
            environment: .production
        )

        XCTAssertEqual(loaded?.accountID, accountID)
        XCTAssertEqual(loaded?.entitlements, [.activeBoard(updatedAt: now)])
        XCTAssertNil(try cache.load(accountID: "another-account", environment: .production))
        XCTAssertNil(try cache.load(accountID: accountID, environment: .sandbox))
    }

    func testStaleOrFutureCacheCannotBeUsed() throws {
        let fileURL = temporaryURL()
        let cache = AccountEntitlementCache(fileURL: fileURL, now: { self.now })

        try cache.save(
            accountID: accountID,
            environment: .production,
            entitlements: [.activeBoard(updatedAt: now)],
            fetchedAt: now.addingTimeInterval(-72 * 60 * 60 - 1)
        )
        XCTAssertNil(try cache.load(accountID: accountID, environment: .production))

        try cache.save(
            accountID: accountID,
            environment: .production,
            entitlements: [.activeBoard(updatedAt: now)],
            fetchedAt: now.addingTimeInterval(1)
        )
        XCTAssertNil(try cache.load(accountID: accountID, environment: .production))
    }

    func testCacheContainsOnlyServerSummaryAndUsesFileProtection() throws {
        let fileURL = temporaryURL()
        let cache = AccountEntitlementCache(fileURL: fileURL, now: { self.now })
        try cache.save(
            accountID: accountID,
            environment: .sandbox,
            entitlements: [.activeBoard(updatedAt: now)],
            fetchedAt: now
        )

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(accountID))
        XCTAssertTrue(contents.contains(BoardStore.productID))
        XCTAssertFalse(contents.contains("signed_transaction_info"))
        XCTAssertFalse(contents.contains("source_transaction_id"))
        XCTAssertFalse(contents.contains("header.payload.signature"))

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
        XCTAssertTrue(
            protection == nil || protection == .completeUntilFirstUserAuthentication
        )
#else
        XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
#endif
    }

    private func temporaryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("entitlements.json")
    }
}

private extension AccountEntitlementSummary {
    static func activeBoard(updatedAt: Date) -> AccountEntitlementSummary {
        AccountEntitlementSummary(
            productID: "com.clovery.app.board.lifetime",
            state: .active,
            expiresAt: nil,
            revokedAt: nil,
            sourceStorefront: "CN",
            updatedAt: updatedAt
        )
    }
}
