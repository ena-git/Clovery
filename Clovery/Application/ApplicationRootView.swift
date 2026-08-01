import SwiftUI

struct ApplicationRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let authenticationAPI: AuthenticationAPIProtocol
    private let identityClaimAPI: IdentityClaimAPIProtocol
    private let sourceKind: BootstrapSourceKind
    private let vaultRegistry: AccountVaultRuntimeRegistry
    private let accountManagementAPI: AccountManagementAPI
    private let entitlementCache: AccountEntitlementCache
    @StateObject private var sessionController: ApplicationSessionController
    @StateObject private var bootstrapCoordinator: AccountBootstrapCoordinator
    @StateObject private var boardStore: BoardStore
    @StateObject private var fontStore: AppFontStore
    @State private var showsAccountSecurity = false

    @MainActor
    init(
        dependencies: BootstrapDependencies? = nil,
        fontStore: AppFontStore? = nil
    ) {
        let resolved = dependencies ?? BootstrapDependencies.live()
        authenticationAPI = resolved.authenticationAPI
        identityClaimAPI = resolved.identityClaimAPI
        sourceKind = resolved.sourceKind
        vaultRegistry = resolved.vaultRegistry
        accountManagementAPI = resolved.accountManagementAPI
        entitlementCache = resolved.entitlementCache
        _sessionController = StateObject(wrappedValue: resolved.sessionController)
        _bootstrapCoordinator = StateObject(wrappedValue: resolved.coordinator)
        _boardStore = StateObject(wrappedValue: resolved.boardStore)
        _fontStore = StateObject(wrappedValue: fontStore ?? AppFontStore())
    }

    var body: some View {
        routeView
            .task {
                bootstrapCoordinator.start()
                await bootstrapCoordinator.waitForIdle()
            }
            .onChange(of: authenticatedAccountKey) { _ in
                boardStore.accountDidChange()
                vaultRegistry.accountDidChange(to: authenticatedNamespace)
                bootstrapCoordinator.sessionDidChange()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await boardStore.refresh() }
                WebViewCoordinatorBridge.shared.refreshAccountVault()
            }
            .environment(\.appFontSelection, fontStore.selection)
    }

    @ViewBuilder
    private var routeView: some View {
        switch bootstrapCoordinator.route {
        case .loading:
            ApplicationLoadingView()
        case .upgradeNotice:
            ZStack {
                ApplicationLoadingView(showsTitle: false)
                    .accessibilityHidden(true)
                UpgradeNoticeView(
                    acknowledge: bootstrapCoordinator.acknowledgeNotice
                )
            }
        case .authentication:
            AuthenticationFlowView(
                api: authenticationAPI,
                identityClaimAPI: identityClaimAPI,
                sourceKind: sourceKind,
                sessionController: sessionController
            )
        case let .reconciling(state):
            AccountReconciliationView(
                state: state,
                retry: bootstrapCoordinator.retry,
                logout: bootstrapCoordinator.logout
            )
        case let .diary(accountID, vaultID):
            let namespace = VaultSyncNamespace(accountID: accountID, vaultID: vaultID)
            WebView(
                boardStore: boardStore,
                fontStore: fontStore,
                vaultContext: vaultRegistry.context(for: namespace),
                onAccountSecurity: { showsAccountSecurity = true }
            )
                .id("\(accountID):\(vaultID)")
                .ignoresSafeArea()
                .sheet(isPresented: $showsAccountSecurity) {
                    AccountSecurityView(
                        api: accountManagementAPI,
                        session: sessionController,
                        entitlementCache: entitlementCache,
                        entitlementState: boardStore
                    )
                }
        }
    }

    private var authenticatedAccountKey: String? {
        sessionController.authenticationSession().map {
            "\($0.accountID):\($0.vaultID)"
        }
    }

    private var authenticatedNamespace: VaultSyncNamespace? {
        sessionController.authenticationSession().map {
            VaultSyncNamespace(accountID: $0.accountID, vaultID: $0.vaultID)
        }
    }
}
