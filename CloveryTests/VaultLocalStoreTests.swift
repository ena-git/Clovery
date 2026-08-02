import Foundation
import XCTest
@testable import Clovery

final class VaultLocalStoreTests: XCTestCase {
    func testMaterializationPreservesOrderAndHandlesDuplicateLegacyIDsWithoutTrapping() throws {
        let directory = temporaryDirectory()
        let store = VaultLocalStore(documentsDirectory: directory)
        try store.save(VaultDiarySnapshot(
            entries: [
                ["id": .string("duplicate"), "text": .string("first")],
                ["id": .string("duplicate"), "text": .string("second")],
                ["id": .string("keep"), "text": .string("third")]
            ],
            deletedIDs: [],
            name: nil
        ))
        let entityID = "11111111-1111-4111-8111-111111111111"

        let result = try store.materialize([VaultSyncChange(
            cursor: 1,
            entityType: "journal_entry",
            entityID: entityID,
            revision: 1,
            operationID: UUID(),
            payload: .object(["id": .string("legacy"), "text": .string("server")]),
            deleted: false,
            changedAt: ""
        )])

        XCTAssertEqual(result.entries.compactMap { $0.stringValue(for: "id") }, [
            "duplicate", "duplicate", "keep", entityID
        ])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
