import SwiftUI

enum AuthenticationRoute: Hashable {
    case login
    case signUp
    case recovery
    case identityClaim(IdentityClaimContext)
}

struct AuthenticationFlowView: View {
    @State private var path: [AuthenticationRoute] = []
    @StateObject private var providerViewModel: AuthenticationProviderViewModel
    private let providerPolicy = ProviderVisibilityPolicy()
    let api: AuthenticationAPIProtocol
    let identityClaimAPI: IdentityClaimAPIProtocol
    let sourceKind: BootstrapSourceKind
    @ObservedObject var sessionController: ApplicationSessionController

    init(
        api: AuthenticationAPIProtocol,
        identityClaimAPI: IdentityClaimAPIProtocol,
        sourceKind: BootstrapSourceKind,
        sessionController: ApplicationSessionController
    ) {
        self.api = api
        self.identityClaimAPI = identityClaimAPI
        self.sourceKind = sourceKind
        self.sessionController = sessionController
        _providerViewModel = StateObject(
            wrappedValue: AuthenticationProviderViewModel(
                api: api,
                sessionController: sessionController
            )
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            AuthenticationEntryView(
                showLogin: { path.append(.login) },
                showSignUp: { path.append(.signUp) }
            )
            .navigationDestination(for: AuthenticationRoute.self) { route in
                switch route {
                case .login:
                    LoginView(
                        api: api,
                        sessionController: sessionController,
                        showSignUp: { path.append(.signUp) },
                        recoverAccount: { path.append(.recovery) },
                        authenticateWithProvider: authenticate,
                        quickProviders: quickProviders,
                        providerMessage: providerViewModel.message
                    )
                case .signUp:
                    SignUpView(
                        api: api,
                        sessionController: sessionController,
                        showLogin: { path.append(.login) },
                        authenticateWithProvider: authenticate,
                        quickProviders: quickProviders,
                        providerMessage: providerViewModel.message
                    )
                case .recovery:
                    AccountRecoveryView(api: api)
                case let .identityClaim(claim):
                    IdentityClaimRegistrationView(
                        api: identityClaimAPI,
                        sessionHandler: sessionController,
                        claim: claim,
                        sourceKind: sourceKind,
                        reauthorize: reauthorize
                    )
                }
            }
        }
        .tint(.authInk)
        .onChange(of: providerViewModel.pendingIdentityClaim) { pendingClaim in
            guard let claim = providerViewModel.consumePendingIdentityClaim() else {
                return
            }
            path.append(.identityClaim(claim))
        }
    }

    private var quickProviders: [AuthenticationProviderKind] {
        providerPolicy.quickProviders(for: .iOS).filter(providerViewModel.isAvailable)
    }

    private func authenticate(_ provider: AuthenticationProviderKind) {
        Task {
            await providerViewModel.authenticate(provider)
        }
    }

    private func reauthorize(_ provider: IdentityProvider) {
        if case .identityClaim = path.last {
            path.removeLast()
        }
        switch provider {
        case .apple:
            authenticate(.apple)
        case .google:
            authenticate(.google)
        case .huawei:
            authenticate(.huawei)
        }
    }
}
