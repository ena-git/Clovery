import SwiftUI

enum AuthenticationRoute: Hashable {
    case login
    case signUp
    case recovery
}

struct AuthenticationFlowView: View {
    @State private var path: [AuthenticationRoute] = []
    @StateObject private var providerViewModel: AuthenticationProviderViewModel
    private let providerPolicy = ProviderVisibilityPolicy()
    let api: AuthenticationAPIProtocol
    @ObservedObject var sessionController: ApplicationSessionController

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController
    ) {
        self.api = api
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
                }
            }
        }
        .tint(.authInk)
    }

    private var quickProviders: [AuthenticationProviderKind] {
        providerPolicy.quickProviders(for: .iOS).filter(providerViewModel.isAvailable)
    }

    private func authenticate(_ provider: AuthenticationProviderKind) {
        Task {
            await providerViewModel.authenticate(provider)
        }
    }
}
