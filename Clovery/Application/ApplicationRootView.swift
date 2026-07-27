import SwiftUI

struct ApplicationRootView: View {
    private let authenticationAPI: AuthenticationAPIProtocol
    private let identityClaimAPI: IdentityClaimAPIProtocol
    private let sourceKind: BootstrapSourceKind
    @StateObject private var sessionController: ApplicationSessionController
    @StateObject private var bootstrapCoordinator: AccountBootstrapCoordinator
    @StateObject private var fontStore: AppFontStore

    @MainActor
    init(
        dependencies: BootstrapDependencies? = nil,
        fontStore: AppFontStore? = nil
    ) {
        let resolved = dependencies ?? BootstrapDependencies.live()
        authenticationAPI = resolved.authenticationAPI
        identityClaimAPI = resolved.identityClaimAPI
        sourceKind = resolved.sourceKind
        _sessionController = StateObject(wrappedValue: resolved.sessionController)
        _bootstrapCoordinator = StateObject(wrappedValue: resolved.coordinator)
        _fontStore = StateObject(wrappedValue: fontStore ?? AppFontStore())
    }

    var body: some View {
        routeView
            .task {
                bootstrapCoordinator.start()
                await bootstrapCoordinator.waitForIdle()
            }
            .onChange(of: authenticatedAccountKey) { _ in
                bootstrapCoordinator.sessionDidChange()
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
                ApplicationLoadingView()
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
            BootstrapHoldingView(
                state: state,
                retry: bootstrapCoordinator.retry,
                logout: bootstrapCoordinator.logout
            )
        case .diary:
            WebView(fontStore: fontStore)
                .ignoresSafeArea()
        }
    }

    private var authenticatedAccountKey: String? {
        sessionController.authenticationSession().map {
            "\($0.accountID):\($0.vaultID)"
        }
    }
}
