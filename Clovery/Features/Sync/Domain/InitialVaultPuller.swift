import Foundation

@MainActor
protocol VaultAssetRestoring: AnyObject {
    func restoreMigrationAssets(
        migrationID: UUID,
        namespace: VaultSyncNamespace
    ) async throws
    func restoreReferencedAssets(
        in payload: JSONValue,
        namespace: VaultSyncNamespace
    ) async throws
}

@MainActor
final class InitialVaultPuller {
    private let api: VaultSyncAPIProtocol
    private let localStore: VaultLocalStoring
    private let checkpointStore: VaultSyncCheckpointStoring
    private let assetRestorer: VaultAssetRestoring
    private let bootstrapAPI: AccountBootstrapAPIProtocol
    private let pageLimit: Int

    init(
        api: VaultSyncAPIProtocol,
        localStore: VaultLocalStoring,
        checkpointStore: VaultSyncCheckpointStoring,
        assetRestorer: VaultAssetRestoring,
        bootstrapAPI: AccountBootstrapAPIProtocol,
        pageLimit: Int = 100
    ) {
        self.api = api
        self.localStore = localStore
        self.checkpointStore = checkpointStore
        self.assetRestorer = assetRestorer
        self.bootstrapAPI = bootstrapAPI
        self.pageLimit = pageLimit
    }

    func pull(
        namespace: VaultSyncNamespace,
        migrationID: UUID?,
        sourceKind: BootstrapSourceKind
    ) async throws -> VaultCheckpoint {
        var state = try checkpointStore.load(for: namespace)
        if let migrationID, state.restoredMigrationID != migrationID {
            try await assetRestorer.restoreMigrationAssets(
                migrationID: migrationID,
                namespace: namespace
            )
            state = try checkpointStore.load(for: namespace)
            state.restoredMigrationID = migrationID
            try checkpointStore.save(state, for: namespace)
        }

        var hasMore = true
        while hasMore {
            try Task.checkCancellation()
            let page = try await api.pull(cursor: state.cursor, limit: pageLimit)
            let changes = uniqueChanges(page.changes, excluding: state.appliedOperationIDs)
            for change in changes where !change.deleted {
                try await assetRestorer.restoreReferencedAssets(
                    in: change.payload,
                    namespace: namespace
                )
            }
            state = try checkpointStore.load(for: namespace)
            if !changes.isEmpty {
                _ = try localStore.materialize(changes)
            }
            apply(changes, to: &state)
            state.cursor = page.nextCursor
            try checkpointStore.save(state, for: namespace)
            hasMore = page.hasMore
        }

        let checkpoint = VaultCheckpoint(cursor: state.cursor, hasMore: false)
        _ = try await bootstrapAPI.resume(
            sourceKind: sourceKind,
            vaultCheckpoint: checkpoint
        )
        return checkpoint
    }

    private func uniqueChanges(
        _ changes: [VaultSyncChange],
        excluding applied: Set<UUID>
    ) -> [VaultSyncChange] {
        var operationIDs = applied
        return changes.sorted(by: { $0.cursor < $1.cursor }).filter { change in
            operationIDs.insert(change.operationID).inserted
        }
    }

    private func apply(_ changes: [VaultSyncChange], to state: inout VaultSyncState) {
        for change in changes {
            state.appliedOperationIDs.insert(change.operationID)
            if change.deleted {
                state.entries.removeValue(forKey: change.entityID)
            } else {
                var materialized = change.payload
                if case var .object(payload) = materialized {
                    payload["id"] = .string(change.entityID)
                    materialized = .object(payload)
                }
                state.entries[change.entityID] = VaultEntryMirror(
                    revision: change.revision,
                    payloadHash: (try? VaultPayloadHash.make(materialized)) ?? "",
                    payload: materialized
                )
            }
        }
    }
}
