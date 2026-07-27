import Foundation
import XCTest
@testable import Clovery

@MainActor
final class InitialVaultPullerTests: XCTestCase {
    func testPullPaginatesFromDurableCursorAndMaterializesChangesOnce() async throws {
        let directory = temporaryDirectory()
        let namespace = VaultSyncNamespace(accountID: "account-a", vaultID: "vault-a")
        let checkpointStore = VaultSyncCheckpointStore(baseDirectory: directory.appendingPathComponent("sync"))
        var initialState = VaultSyncState.empty
        initialState.cursor = 4
        try checkpointStore.save(initialState, for: namespace)
        let localStore = VaultLocalStore(documentsDirectory: directory)
        try localStore.save(
            VaultDiarySnapshot(
                entries: [
                    ["id": .string("keep"), "text": .string("untouched")],
                    ["id": .string("delete-me"), "text": .string("old")]
                ],
                deletedIDs: [],
                name: "Clovery"
            )
        )
        let duplicateOperationID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let api = VaultSyncAPISpy(pages: [
            VaultSyncPage(
                changes: [
                    change(cursor: 6, entityID: "delete-me", operationID: UUID(), deleted: true),
                    change(cursor: 5, entityID: "server-entry", operationID: duplicateOperationID, text: "first")
                ],
                nextCursor: 6,
                hasMore: true
            ),
            VaultSyncPage(
                changes: [
                    change(cursor: 7, entityID: "server-entry", operationID: duplicateOperationID, text: "duplicate"),
                    change(cursor: 8, entityID: "server-entry", operationID: UUID(), revision: 2, text: "latest")
                ],
                nextCursor: 8,
                hasMore: false
            )
        ])
        let assets = VaultAssetRestorerSpy()
        let bootstrap = AccountBootstrapAPISpy()
        let puller = InitialVaultPuller(
            api: api,
            localStore: localStore,
            checkpointStore: checkpointStore,
            assetRestorer: assets,
            bootstrapAPI: bootstrap
        )

        let result = try await puller.pull(
            namespace: namespace,
            migrationID: nil,
            sourceKind: .legacyLocal
        )

        XCTAssertEqual(api.pullCursors, [4, 6])
        XCTAssertEqual(result.cursor, 8)
        XCTAssertFalse(result.hasMore)
        XCTAssertEqual(bootstrap.resumeCheckpoints, [VaultCheckpoint(cursor: 8, hasMore: false)])
        let snapshot = try localStore.load()
        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertEqual(snapshot.entry(id: "keep")?["text"], .string("untouched"))
        XCTAssertEqual(snapshot.entry(id: "server-entry")?["text"], .string("latest"))
        XCTAssertNil(snapshot.entry(id: "delete-me"))
        XCTAssertEqual(assets.payloads.count, 2)
        let state = try checkpointStore.load(for: namespace)
        XCTAssertEqual(state.cursor, 8)
        XCTAssertEqual(state.appliedOperationIDs.count, 3)
    }

    func testCursorDoesNotAdvanceWhenAtomicMaterializationFails() async throws {
        let namespace = VaultSyncNamespace(accountID: "account", vaultID: "vault")
        let checkpoints = VaultSyncCheckpointStoreSpy()
        var state = VaultSyncState.empty
        state.cursor = 12
        checkpoints.states[namespace] = state
        let api = VaultSyncAPISpy(pages: [
            VaultSyncPage(
                changes: [change(cursor: 13, entityID: "entry", operationID: UUID(), text: "new")],
                nextCursor: 13,
                hasMore: false
            )
        ])
        let puller = InitialVaultPuller(
            api: api,
            localStore: FailingVaultLocalStore(),
            checkpointStore: checkpoints,
            assetRestorer: VaultAssetRestorerSpy(),
            bootstrapAPI: AccountBootstrapAPISpy()
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await puller.pull(
                namespace: namespace,
                migrationID: nil,
                sourceKind: .newInstall
            )
        }

        XCTAssertEqual(checkpoints.states[namespace]?.cursor, 12)
        XCTAssertEqual(checkpoints.saveCount, 0)
    }

    private func change(
        cursor: Int64,
        entityID: String,
        operationID: UUID,
        revision: Int = 1,
        text: String = "",
        deleted: Bool = false
    ) -> VaultSyncChange {
        VaultSyncChange(
            cursor: cursor,
            entityType: "journal_entry",
            entityID: entityID,
            revision: revision,
            operationID: operationID,
            payload: .object(["id": .string("legacy-id"), "text": .string(text)]),
            deleted: deleted,
            changedAt: "2026-07-27T00:00:00Z"
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

@MainActor
private final class VaultSyncAPISpy: VaultSyncAPIProtocol {
    private var pages: [VaultSyncPage]
    private(set) var pullCursors: [Int64] = []

    init(pages: [VaultSyncPage]) {
        self.pages = pages
    }

    func push(_ operations: [VaultSyncOperation]) async throws -> [VaultSyncDecision] { [] }

    func pull(cursor: Int64, limit: Int) async throws -> VaultSyncPage {
        pullCursors.append(cursor)
        return pages.removeFirst()
    }
}

@MainActor
private final class VaultAssetRestorerSpy: VaultAssetRestoring {
    private(set) var payloads: [JSONValue] = []
    private(set) var migrationIDs: [UUID] = []

    func restoreMigrationAssets(
        migrationID: UUID,
        namespace: VaultSyncNamespace
    ) async throws {
        migrationIDs.append(migrationID)
    }

    func restoreReferencedAssets(
        in payload: JSONValue,
        namespace: VaultSyncNamespace
    ) async throws {
        payloads.append(payload)
    }
}

@MainActor
private final class AccountBootstrapAPISpy: AccountBootstrapAPIProtocol {
    private(set) var resumeCheckpoints: [VaultCheckpoint?] = []

    func status() async throws -> AccountBootstrapStatus { completedStatus }

    func resume(
        sourceKind: BootstrapSourceKind,
        vaultCheckpoint: VaultCheckpoint?
    ) async throws -> AccountBootstrapStatus {
        resumeCheckpoints.append(vaultCheckpoint)
        return completedStatus
    }

    private var completedStatus: AccountBootstrapStatus {
        AccountBootstrapStatus(
            overall: .complete,
            sourceKind: .newInstall,
            migrationID: nil,
            stages: AccountBootstrapStages(
                identity: .complete,
                migration: .complete,
                entitlement: .complete,
                vault: .complete
            ),
            lastErrorCode: nil,
            retryCount: 0,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class VaultSyncCheckpointStoreSpy: VaultSyncCheckpointStoring {
    var states: [VaultSyncNamespace: VaultSyncState] = [:]
    private(set) var saveCount = 0

    func load(for namespace: VaultSyncNamespace) throws -> VaultSyncState {
        states[namespace] ?? .empty
    }

    func save(_ state: VaultSyncState, for namespace: VaultSyncNamespace) throws {
        saveCount += 1
        states[namespace] = state
    }
}

private struct FailingVaultLocalStore: VaultLocalStoring {
    func load() throws -> VaultDiarySnapshot { .empty }
    func save(_ snapshot: VaultDiarySnapshot) throws { throw TestError.failed }
    func materialize(_ changes: [VaultSyncChange]) throws -> VaultDiarySnapshot {
        throw TestError.failed
    }
}

private enum TestError: Error {
    case failed
}

private extension VaultDiarySnapshot {
    func entry(id: String) -> [String: JSONValue]? {
        entries.first { $0["id"] == .string(id) }
    }
}
