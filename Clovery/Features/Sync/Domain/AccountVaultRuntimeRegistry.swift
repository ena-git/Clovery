import Foundation

@MainActor
final class AccountVaultRuntimeRegistry {
    private let documentsDirectory: URL
    private let syncAPI: VaultSyncAPIProtocol
    private let assetAPI: VaultAssetAPIProtocol
    private let checkpointStore: VaultSyncCheckpointStoring
    private var contexts: [VaultSyncNamespace: AccountVaultWebContext] = [:]

    init(
        documentsDirectory: URL,
        syncAPI: VaultSyncAPIProtocol,
        assetAPI: VaultAssetAPIProtocol,
        checkpointStore: VaultSyncCheckpointStoring
    ) {
        self.documentsDirectory = documentsDirectory
        self.syncAPI = syncAPI
        self.assetAPI = assetAPI
        self.checkpointStore = checkpointStore
    }

    func context(for namespace: VaultSyncNamespace) -> AccountVaultWebContext {
        if let existing = contexts[namespace] { return existing }
        let directory = accountDirectory(for: namespace)
        let localStore = VaultLocalStore(documentsDirectory: directory)
        let assetUploader = VaultAssetUploader(
            api: assetAPI,
            documentsDirectory: directory,
            checkpointStore: checkpointStore
        )
        let coordinator = VaultSyncCoordinator(
            api: syncAPI,
            localStore: localStore,
            checkpointStore: checkpointStore,
            assetUploader: assetUploader
        )
        let context = AccountVaultWebContext(
            namespace: namespace,
            accountDirectory: directory,
            coordinator: coordinator,
            localStore: localStore
        )
        contexts[namespace] = context
        return context
    }

    func accountDidChange(to namespace: VaultSyncNamespace?) {
        let staleNamespaces = contexts.keys.filter { $0 != namespace }
        for storedNamespace in staleNamespaces {
            contexts[storedNamespace]?.coordinator.cancel()
            contexts.removeValue(forKey: storedNamespace)
        }
    }

    func accountDirectory(for namespace: VaultSyncNamespace) -> URL {
        documentsDirectory
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(namespace.storageKey, isDirectory: true)
    }
}
