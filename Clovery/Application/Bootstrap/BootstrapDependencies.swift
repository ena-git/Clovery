import Foundation

@MainActor
struct BootstrapDependencies {
    let authenticationAPI: AuthenticationAPIProtocol
    let identityClaimAPI: IdentityClaimAPIProtocol
    let sessionController: ApplicationSessionController
    let coordinator: AccountBootstrapCoordinator
    let boardStore: BoardStore
    let vaultRegistry: AccountVaultRuntimeRegistry
    let sourceKind: BootstrapSourceKind

    static func live(
        userDefaults: UserDefaults = .standard,
        currentVersion: String? = nil
    ) -> BootstrapDependencies {
        let baseClient = APIClient(configuration: apiConfiguration())
        let authenticationAPI = AuthenticationAPI(client: baseClient)
        let identityClaimAPI = IdentityClaimAPI(client: baseClient)
        let sessionController = ApplicationSessionController(api: authenticationAPI)
        let authenticatedClient = AuthenticatedAPIClient(
            client: baseClient,
            sessionController: sessionController
        )
        let detector = LegacyDataDetector(userDefaults: userDefaults)
        let noticeController = LegacyUpgradeController(
            detector: detector,
            currentVersion: currentVersion ?? marketingVersion,
            userDefaults: userDefaults
        )
        let sourceKind: BootstrapSourceKind = detector.hasLegacyData
            ? .legacyLocal
            : .newInstall
        let bootstrapAPI = AccountBootstrapAPI(client: authenticatedClient)
        let entitlementAPI = AccountEntitlementAPI(client: authenticatedClient)
        let entitlementReconciler = EntitlementReconciler(
            api: entitlementAPI,
            cache: AccountEntitlementCache(),
            defaultEnvironment: entitlementEnvironment
        )
        let boardStore = BoardStore(
            accountIDProvider: { [weak sessionController] in
                sessionController?.authenticationSession()?.accountID
            },
            client: .live,
            reconciler: entitlementReconciler
        )
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let migrationReader = LegacySnapshotReader(
            documentsDirectory: documentsDirectory,
            webReader: LegacyWebLocalStorageReader(),
            cloudPuller: CloudKitSync.shared
        )
        let migrationCoordinator = LegacyMigrationCoordinator(
            archivePreparer: LegacyMigrationArchivePreparer(reader: migrationReader),
            api: LegacyMigrationAPI(client: authenticatedClient),
            checkpointStore: LegacyMigrationCheckpointStore(
                documentsDirectory: documentsDirectory
            )
        )
        let vaultCheckpointStore = VaultSyncCheckpointStore()
        let vaultSyncAPI = VaultSyncAPI(client: authenticatedClient)
        let vaultAssetAPI = VaultAssetAPI(client: authenticatedClient)
        let vaultRegistry = AccountVaultRuntimeRegistry(
            documentsDirectory: documentsDirectory,
            syncAPI: vaultSyncAPI,
            assetAPI: vaultAssetAPI,
            checkpointStore: vaultCheckpointStore
        )
        let initialVaultPuller = InitialVaultPuller(
            api: vaultSyncAPI,
            localStoreProvider: { namespace in
                VaultLocalStore(
                    documentsDirectory: vaultRegistry.accountDirectory(for: namespace)
                )
            },
            checkpointStore: vaultCheckpointStore,
            assetRestorerProvider: { namespace in
                VaultAssetUploader(
                    api: vaultAssetAPI,
                    documentsDirectory: vaultRegistry.accountDirectory(for: namespace),
                    checkpointStore: vaultCheckpointStore
                )
            },
            bootstrapAPI: bootstrapAPI
        )
        let pipeline = AccountBootstrapPipeline(
            api: bootstrapAPI,
            migration: migrationCoordinator,
            entitlement: boardStore,
            vaultPuller: initialVaultPuller
        )
        let coordinator = AccountBootstrapCoordinator(
            sessionController: sessionController,
            noticeController: noticeController,
            api: bootstrapAPI,
            checkpointStore: BootstrapCheckpointStore(userDefaults: userDefaults),
            pipeline: pipeline
        )

        return BootstrapDependencies(
            authenticationAPI: authenticationAPI,
            identityClaimAPI: identityClaimAPI,
            sessionController: sessionController,
            coordinator: coordinator,
            boardStore: boardStore,
            vaultRegistry: vaultRegistry,
            sourceKind: sourceKind
        )
    }

    private static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }

    private static func apiConfiguration() -> APIConfiguration {
        let buildConfiguration: BuildConfiguration
        #if DEBUG
            buildConfiguration = .debug
        #else
            buildConfiguration = .release
        #endif

        if let current = try? APIConfiguration.current(),
           (try? current.validate(for: buildConfiguration)) != nil
        {
            return current
        }
        return APIConfiguration(baseURL: URL(string: "https://invalid.clovery.local")!)
    }

    private static var entitlementEnvironment: AccountEntitlementEnvironment {
#if DEBUG
        .sandbox
#else
        .production
#endif
    }
}
