import Foundation
import XCTest
@testable import Clovery

final class BootstrapCheckpointStoreTests: XCTestCase {
    func testCheckpointPersistsOnlyAccountVaultAndProgressOwnership() throws {
        let defaults = UserDefaults(suiteName: "com.clovery.tests.\(UUID().uuidString)")!
        let store = BootstrapCheckpointStore(userDefaults: defaults)
        let checkpoint = BootstrapCheckpoint(
            accountID: "account",
            vaultID: "vault",
            sourceKind: .legacyLocal,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try store.save(checkpoint)

        XCTAssertEqual(try store.load(), checkpoint)
        let rawData = try XCTUnwrap(
            defaults.data(forKey: BootstrapCheckpointStore.storageKey)
        )
        let rawText = try XCTUnwrap(String(data: rawData, encoding: .utf8))
        XCTAssertFalse(rawText.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(rawText.localizedCaseInsensitiveContains("claim"))
        XCTAssertFalse(rawText.localizedCaseInsensitiveContains("password"))
    }
}
