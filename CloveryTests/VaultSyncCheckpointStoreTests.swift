import Foundation
import XCTest
@testable import Clovery

final class VaultSyncCheckpointStoreTests: XCTestCase {
    func testStateIsDurableAndSeparatedByAccountAndVault() throws {
        let directory = temporaryDirectory()
        let store = VaultSyncCheckpointStore(baseDirectory: directory)
        let first = VaultSyncNamespace(accountID: "account-a", vaultID: "vault-a")
        let second = VaultSyncNamespace(accountID: "account-b", vaultID: "vault-b")
        let operation = VaultSyncOperation(
            operationID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            entryID: "22222222-2222-4222-8222-222222222222",
            baseRevision: 0,
            payload: .object(["text": .string("draft")]),
            deleted: false
        )
        var state = VaultSyncState.empty
        state.cursor = 42
        state.pendingOperations = [operation]
        state.appliedOperationIDs = [operation.operationID]

        try store.save(state, for: first)

        XCTAssertEqual(try VaultSyncCheckpointStore(baseDirectory: directory).load(for: first), state)
        XCTAssertEqual(try store.load(for: second), .empty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("account-a").path
        ))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
