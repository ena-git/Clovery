import Foundation
import XCTest
@testable import Clovery

@MainActor
final class VaultSyncCoordinatorTests: XCTestCase {
    func testDiffUsesServerRevisionPersistsDeletesAndDoesNotRepushSameSnapshot() async throws {
        let fixture = try makeFixture()
        let editedID = "11111111-1111-4111-8111-111111111111"
        let deletedID = "22222222-2222-4222-8222-222222222222"
        let newID = "33333333-3333-4333-8333-333333333333"
        var state = VaultSyncState.empty
        state.entries[editedID] = mirror(id: editedID, revision: 4, text: "old")
        state.entries[deletedID] = mirror(id: deletedID, revision: 2, text: "remove")
        try fixture.checkpoints.save(state, for: fixture.namespace)
        fixture.api.decisionProvider = { operations in
            operations.enumerated().map { offset, operation in
                VaultSyncDecision(
                    operationID: operation.operationID,
                    status: .applied,
                    entry: VaultSyncEntry(
                        entryID: operation.entryID,
                        revision: operation.baseRevision + 1,
                        payload: operation.payload,
                        deletedAt: operation.deleted ? "2026-07-27T00:00:00Z" : nil
                    ),
                    serverSnapshot: nil,
                    cursor: Int64(offset + 1)
                )
            }
        }
        let snapshot = VaultDiarySnapshot(
            entries: [entry(id: editedID, text: "edited"), entry(id: newID, text: "new")],
            deletedIDs: [deletedID],
            name: nil
        )

        _ = try await fixture.coordinator.sync(snapshot, for: fixture.namespace)
        _ = try await fixture.coordinator.sync(snapshot, for: fixture.namespace)

        XCTAssertEqual(fixture.api.pushes.count, 1)
        let operations = try XCTUnwrap(fixture.api.pushes.first)
        XCTAssertEqual(operations.map(\.entryID), [editedID, newID, deletedID])
        XCTAssertEqual(operations.map(\.baseRevision), [4, 0, 2])
        XCTAssertEqual(operations.map(\.deleted), [false, false, true])
        XCTAssertTrue(try fixture.checkpoints.load(for: fixture.namespace).pendingOperations.isEmpty)
    }

    func testPendingOperationIDSurvivesNetworkFailureAndIsReused() async throws {
        let fixture = try makeFixture()
        let entryID = "11111111-1111-4111-8111-111111111111"
        let snapshot = VaultDiarySnapshot(
            entries: [entry(id: entryID, text: "draft")],
            deletedIDs: [],
            name: nil
        )
        fixture.api.pushError = CoordinatorTestError.offline

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.coordinator.sync(snapshot, for: fixture.namespace)
        }
        let durableID = try XCTUnwrap(
            fixture.checkpoints.load(for: fixture.namespace).pendingOperations.first?.operationID
        )
        fixture.api.pushError = nil
        fixture.api.decisionProvider = appliedDecisions

        _ = try await fixture.coordinator.sync(snapshot, for: fixture.namespace)

        XCTAssertEqual(fixture.api.pushes.count, 2)
        XCTAssertEqual(fixture.api.pushes[0].first?.operationID, durableID)
        XCTAssertEqual(fixture.api.pushes[1].first?.operationID, durableID)
    }

    func testPushesInOrderedBatchesOfOneHundred() async throws {
        let fixture = try makeFixture()
        fixture.api.decisionProvider = appliedDecisions
        let entries = (0..<205).map { index in
            entry(id: uuidString(index), text: "entry-\(index)")
        }

        _ = try await fixture.coordinator.sync(
            VaultDiarySnapshot(entries: entries, deletedIDs: [], name: nil),
            for: fixture.namespace
        )

        XCTAssertEqual(fixture.api.pushes.map(\.count), [100, 100, 5])
        XCTAssertEqual(
            fixture.api.pushes.flatMap { $0 }.map(\.entryID),
            entries.compactMap { $0.stringValue(for: "id") }
        )
    }

    func testConflictPreservesServerEntryAndPushesDeterministicLocalCopy() async throws {
        let fixture = try makeFixture()
        let entryID = "11111111-1111-4111-8111-111111111111"
        var state = VaultSyncState.empty
        state.entries[entryID] = mirror(id: entryID, revision: 1, text: "old")
        try fixture.checkpoints.save(state, for: fixture.namespace)
        var responseCount = 0
        fixture.api.decisionProvider = { operations in
            responseCount += 1
            let operation = operations[0]
            if responseCount == 1 {
                return [VaultSyncDecision(
                    operationID: operation.operationID,
                    status: .conflict,
                    entry: nil,
                    serverSnapshot: VaultSyncEntry(
                        entryID: entryID,
                        revision: 2,
                        payload: .object(self.entry(id: entryID, text: "server")),
                        deletedAt: nil
                    ),
                    cursor: 9
                )]
            }
            return self.appliedDecisions(operations)
        }

        let result = try await fixture.coordinator.sync(
            VaultDiarySnapshot(
                entries: [entry(id: entryID, text: "local")],
                deletedIDs: [],
                name: nil
            ),
            for: fixture.namespace
        )

        XCTAssertEqual(fixture.api.pushes.count, 2)
        let conflictCopy = try XCTUnwrap(fixture.api.pushes[1].first)
        XCTAssertNotEqual(conflictCopy.entryID, entryID)
        XCTAssertEqual(result.entry(id: entryID)?["text"], .string("server"))
        XCTAssertEqual(result.entry(id: conflictCopy.entryID)?["text"], .string("local"))
        XCTAssertEqual(conflictCopy.entryID, fixture.api.pushes[1].first?.entryID)
    }

    private func makeFixture() throws -> CoordinatorFixture {
        let directory = temporaryDirectory()
        let namespace = VaultSyncNamespace(accountID: "account", vaultID: "vault")
        let api = CoordinatorVaultSyncAPISpy()
        let checkpoints = VaultSyncCheckpointStore(baseDirectory: directory.appendingPathComponent("sync"))
        let localStore = VaultLocalStore(documentsDirectory: directory)
        let coordinator = VaultSyncCoordinator(
            api: api,
            localStore: localStore,
            checkpointStore: checkpoints,
            assetUploader: CoordinatorAssetUploaderSpy()
        )
        return CoordinatorFixture(
            namespace: namespace,
            api: api,
            checkpoints: checkpoints,
            coordinator: coordinator
        )
    }

    private func entry(id: String, text: String) -> [String: JSONValue] {
        ["id": .string(id), "text": .string(text), "photos": .array([])]
    }

    private func mirror(id: String, revision: Int, text: String) -> VaultEntryMirror {
        let payload = JSONValue.object(entry(id: id, text: text))
        return VaultEntryMirror(
            revision: revision,
            payloadHash: try! VaultPayloadHash.make(payload),
            payload: payload
        )
    }

    private func uuidString(_ index: Int) -> String {
        String(format: "00000000-0000-4000-8000-%012d", index)
    }

    private func appliedDecisions(_ operations: [VaultSyncOperation]) -> [VaultSyncDecision] {
        operations.enumerated().map { offset, operation in
            VaultSyncDecision(
                operationID: operation.operationID,
                status: .applied,
                entry: VaultSyncEntry(
                    entryID: operation.entryID,
                    revision: operation.baseRevision + 1,
                    payload: operation.payload,
                    deletedAt: operation.deleted ? "2026-07-27T00:00:00Z" : nil
                ),
                serverSnapshot: nil,
                cursor: Int64(offset + 1)
            )
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct CoordinatorFixture {
    let namespace: VaultSyncNamespace
    let api: CoordinatorVaultSyncAPISpy
    let checkpoints: VaultSyncCheckpointStore
    let coordinator: VaultSyncCoordinator
}

@MainActor
private final class CoordinatorVaultSyncAPISpy: VaultSyncAPIProtocol {
    var pushError: Error?
    var decisionProvider: (([VaultSyncOperation]) -> [VaultSyncDecision])?
    var pullPages: [VaultSyncPage] = []
    private(set) var pushes: [[VaultSyncOperation]] = []

    func push(_ operations: [VaultSyncOperation]) async throws -> [VaultSyncDecision] {
        pushes.append(operations)
        if let pushError { throw pushError }
        return decisionProvider?(operations) ?? []
    }

    func pull(cursor: Int64, limit: Int) async throws -> VaultSyncPage {
        guard !pullPages.isEmpty else {
            return VaultSyncPage(changes: [], nextCursor: cursor, hasMore: false)
        }
        return pullPages.removeFirst()
    }
}

@MainActor
private final class CoordinatorAssetUploaderSpy: VaultAssetUploading, VaultAssetRestoring {
    func preparePayload(
        _ payload: JSONValue,
        namespace: VaultSyncNamespace
    ) async throws -> JSONValue { payload }

    func restoreMigrationAssets(
        migrationID: UUID,
        namespace: VaultSyncNamespace
    ) async throws {}

    func restoreReferencedAssets(
        in payload: JSONValue,
        namespace: VaultSyncNamespace
    ) async throws {}
}

private enum CoordinatorTestError: Error {
    case offline
}

private extension VaultDiarySnapshot {
    func entry(id: String) -> [String: JSONValue]? {
        entries.first { $0.stringValue(for: "id") == id }
    }
}
