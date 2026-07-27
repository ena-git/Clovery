import Foundation

enum VaultSyncCoordinatorError: Error {
    case invalidEntryID
    case invalidServerDecision
}

@MainActor
final class VaultSyncCoordinator {
    private let api: VaultSyncAPIProtocol
    private let localStore: VaultLocalStoring
    private let checkpointStore: VaultSyncCheckpointStoring
    private let assetUploader: VaultAssetUploading & VaultAssetRestoring
    private let metadataStore: VaultSnapshotMetadataStore
    private let conflictResolver = VaultSyncConflictResolver()
    private let operationIDGenerator: () -> UUID
    private var activeNamespace: VaultSyncNamespace?
    private var generation = UUID()

    init(
        api: VaultSyncAPIProtocol,
        localStore: VaultLocalStoring,
        checkpointStore: VaultSyncCheckpointStoring,
        assetUploader: VaultAssetUploading & VaultAssetRestoring,
        operationIDGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.api = api
        self.localStore = localStore
        self.checkpointStore = checkpointStore
        self.assetUploader = assetUploader
        self.metadataStore = VaultSnapshotMetadataStore(localStore: localStore)
        self.operationIDGenerator = operationIDGenerator
    }

    func sync(
        _ snapshot: VaultDiarySnapshot,
        for namespace: VaultSyncNamespace
    ) async throws -> VaultDiarySnapshot {
        let token = activate(namespace)
        try localStore.save(try metadataStore.preservingPrivateMetadata(in: snapshot))
        var state = try checkpointStore.load(for: namespace)
        let newOperations = try await makeOperations(
            from: snapshot,
            state: state,
            namespace: namespace
        )
        try ensureCurrent(token, namespace: namespace)
        state = try checkpointStore.load(for: namespace)
        state.pendingOperations.append(contentsOf: newOperations)
        if !newOperations.isEmpty {
            try checkpointStore.save(state, for: namespace)
        }
        try await drainPendingOperations(namespace: namespace, token: token)
        return try await pull(for: namespace, token: token)
    }

    func pull(for namespace: VaultSyncNamespace) async throws -> VaultDiarySnapshot {
        let token = activate(namespace)
        return try await pull(for: namespace, token: token)
    }

    func cancel() {
        generation = UUID()
        activeNamespace = nil
    }

    private func activate(_ namespace: VaultSyncNamespace) -> UUID {
        if activeNamespace != namespace {
            generation = UUID()
            activeNamespace = namespace
        }
        return generation
    }

    private func makeOperations(
        from snapshot: VaultDiarySnapshot,
        state: VaultSyncState,
        namespace: VaultSyncNamespace
    ) async throws -> [VaultSyncOperation] {
        let pendingEntryIDs = Set(state.pendingOperations.map(\.entryID))
        var operations: [VaultSyncOperation] = []
        for entry in snapshot.entries {
            if entry.booleanValue(for: "isWelcome") == true { continue }
            guard let entryID = entry.stringValue(for: "id"),
                  UUID(uuidString: entryID) != nil else {
                throw VaultSyncCoordinatorError.invalidEntryID
            }
            guard !pendingEntryIDs.contains(entryID) else { continue }
            let visiblePayload = JSONValue.object(entry.removingPrivateAssetReferences())
            let visibleHash = try VaultPayloadHash.make(visiblePayload)
            if state.entries[entryID]?.payloadHash == visibleHash { continue }
            let prepared = try await assetUploader.preparePayload(
                .object(entry),
                namespace: namespace
            )
            operations.append(
                VaultSyncOperation(
                    operationID: operationIDGenerator(),
                    entryID: entryID,
                    baseRevision: state.entries[entryID]?.revision ?? 0,
                    payload: prepared,
                    deleted: false
                )
            )
        }

        let localEntryIDs = Set(snapshot.entries.compactMap { $0.stringValue(for: "id") })
        for entryID in snapshot.deletedIDs where
            state.entries[entryID] != nil &&
            !localEntryIDs.contains(entryID) &&
            !pendingEntryIDs.contains(entryID) {
            operations.append(
                VaultSyncOperation(
                    operationID: operationIDGenerator(),
                    entryID: entryID,
                    baseRevision: state.entries[entryID]?.revision ?? 0,
                    payload: .object([:]),
                    deleted: true
                )
            )
        }
        return operations
    }

    private func drainPendingOperations(
        namespace: VaultSyncNamespace,
        token: UUID
    ) async throws {
        while true {
            try ensureCurrent(token, namespace: namespace)
            let state = try checkpointStore.load(for: namespace)
            let batch = Array(state.pendingOperations.prefix(100))
            guard !batch.isEmpty else { return }
            let decisions = try await api.push(batch)
            try ensureCurrent(token, namespace: namespace)
            guard decisions.count == batch.count else {
                throw VaultSyncCoordinatorError.invalidServerDecision
            }
            for operation in batch {
                guard let decision = decisions.first(where: {
                    $0.operationID == operation.operationID
                }) else {
                    throw VaultSyncCoordinatorError.invalidServerDecision
                }
                try apply(
                    decision,
                    operation: operation,
                    namespace: namespace
                )
            }
        }
    }

    private func apply(
        _ decision: VaultSyncDecision,
        operation: VaultSyncOperation,
        namespace: VaultSyncNamespace
    ) throws {
        var state = try checkpointStore.load(for: namespace)
        switch decision.status {
        case .applied:
            guard let entry = decision.entry else {
                throw VaultSyncCoordinatorError.invalidServerDecision
            }
            let change = VaultSyncChange(
                cursor: decision.cursor ?? state.cursor,
                entityType: "journal_entry",
                entityID: entry.entryID,
                revision: entry.revision,
                operationID: operation.operationID,
                payload: entry.payload,
                deleted: operation.deleted || entry.deletedAt != nil,
                changedAt: ""
            )
            _ = try localStore.materialize([change])
            updateMirror(with: change, state: &state)
            state.pendingOperations.removeAll { $0.operationID == operation.operationID }
        case .conflict:
            guard let server = decision.serverSnapshot else {
                throw VaultSyncCoordinatorError.invalidServerDecision
            }
            let serverChange = VaultSyncChange(
                cursor: decision.cursor ?? state.cursor,
                entityType: "journal_entry",
                entityID: server.entryID,
                revision: server.revision,
                operationID: operation.operationID,
                payload: server.payload,
                deleted: server.deletedAt != nil,
                changedAt: ""
            )
            _ = try localStore.materialize([serverChange])
            updateMirror(with: serverChange, state: &state)
            state.pendingOperations.removeAll { $0.operationID == operation.operationID }
            if !operation.deleted {
                let copy = try conflictResolver.makeConflictCopy(
                    operation: operation,
                    namespace: namespace
                )
                try metadataStore.preserveConflictCopy(copy)
                state.pendingOperations.append(copy)
            }
        }
        state.appliedOperationIDs.insert(operation.operationID)
        if let cursor = decision.cursor {
            state.cursor = max(state.cursor, cursor)
        }
        try checkpointStore.save(state, for: namespace)
    }

    private func pull(
        for namespace: VaultSyncNamespace,
        token: UUID
    ) async throws -> VaultDiarySnapshot {
        var state = try checkpointStore.load(for: namespace)
        var hasMore = true
        while hasMore {
            let page = try await api.pull(cursor: state.cursor, limit: 100)
            try ensureCurrent(token, namespace: namespace)
            let changes = uniqueChanges(page.changes, excluding: state.appliedOperationIDs)
            for change in changes where !change.deleted {
                try await assetUploader.restoreReferencedAssets(
                    in: change.payload,
                    namespace: namespace
                )
            }
            state = try checkpointStore.load(for: namespace)
            if !changes.isEmpty {
                _ = try localStore.materialize(changes)
            }
            changes.forEach { updateMirror(with: $0, state: &state) }
            state.cursor = page.nextCursor
            try checkpointStore.save(state, for: namespace)
            hasMore = page.hasMore
        }
        return try localStore.load()
    }

    private func updateMirror(with change: VaultSyncChange, state: inout VaultSyncState) {
        state.appliedOperationIDs.insert(change.operationID)
        if change.deleted {
            state.entries.removeValue(forKey: change.entityID)
            return
        }
        var payload = change.payload
        if case var .object(entry) = payload {
            entry["id"] = .string(change.entityID)
            payload = .object(entry)
        }
        let visiblePayload: JSONValue
        if case let .object(entry) = payload {
            visiblePayload = .object(entry.removingPrivateAssetReferences())
        } else {
            visiblePayload = payload
        }
        state.entries[change.entityID] = VaultEntryMirror(
            revision: change.revision,
            payloadHash: (try? VaultPayloadHash.make(visiblePayload)) ?? "",
            payload: payload
        )
    }

    private func uniqueChanges(
        _ changes: [VaultSyncChange],
        excluding applied: Set<UUID>
    ) -> [VaultSyncChange] {
        var operationIDs = applied
        return changes.sorted(by: { $0.cursor < $1.cursor }).filter {
            operationIDs.insert($0.operationID).inserted
        }
    }

    private func ensureCurrent(_ token: UUID, namespace: VaultSyncNamespace) throws {
        guard token == generation, activeNamespace == namespace, !Task.isCancelled else {
            throw CancellationError()
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func removingPrivateAssetReferences() -> [String: JSONValue] {
        var copy = self
        copy.removeValue(forKey: "clovery_asset_refs")
        return copy
    }

    func booleanValue(for key: String) -> Bool? {
        guard case let .boolean(value) = self[key] else { return nil }
        return value
    }
}
