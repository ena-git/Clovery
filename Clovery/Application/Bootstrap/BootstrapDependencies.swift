import Foundation

@MainActor
struct BootstrapDependencies {
    let authenticationAPI: AuthenticationAPIProtocol
    let identityClaimAPI: IdentityClaimAPIProtocol
    let sessionController: ApplicationSessionController
    let coordinator: AccountBootstrapCoordinator
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
        let coordinator = AccountBootstrapCoordinator(
            sessionController: sessionController,
            noticeController: noticeController,
            api: AccountBootstrapAPI(client: authenticatedClient),
            checkpointStore: BootstrapCheckpointStore(userDefaults: userDefaults)
        )

        return BootstrapDependencies(
            authenticationAPI: authenticationAPI,
            identityClaimAPI: identityClaimAPI,
            sessionController: sessionController,
            coordinator: coordinator,
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
}
