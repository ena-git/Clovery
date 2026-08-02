import Foundation

struct VaultSnapshotMetadataStore {
    private let localStore: VaultLocalStoring

    init(localStore: VaultLocalStoring) {
        self.localStore = localStore
    }

    func preservingPrivateMetadata(
        in snapshot: VaultDiarySnapshot
    ) throws -> VaultDiarySnapshot {
        var storedEntries: [String: [String: JSONValue]] = [:]
        for entry in try localStore.load().entries {
            if let entryID = entry.stringValue(for: "id") {
                storedEntries[entryID] = entry
            }
        }
        var result = snapshot
        result.entries = snapshot.entries.map { entry in
            guard let entryID = entry.stringValue(for: "id"),
                  let assetReferences = storedEntries[entryID]?["clovery_asset_refs"] else {
                return entry
            }
            var merged = entry
            merged["clovery_asset_refs"] = assetReferences
            return merged
        }
        return result
    }

    func preserveConflictCopy(_ operation: VaultSyncOperation) throws {
        guard case let .object(payload) = operation.payload else { return }
        var snapshot = try localStore.load()
        snapshot.entries.removeAll { $0.stringValue(for: "id") == operation.entryID }
        snapshot.entries.append(payload)
        try localStore.save(snapshot)
    }
}
