import SwiftUI

enum AuthenticationRoute: Hashable {
    case login
    case signUp
    case recovery
}

struct AuthenticationFlowView: View {
    @State private var path: [AuthenticationRoute] = []
    let api: AuthenticationAPIProtocol
    @ObservedObject var sessionController: ApplicationSessionController

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
                        recoverAccount: { path.append(.recovery) }
                    )
                case .signUp:
                    SignUpView(
                        api: api,
                        sessionController: sessionController,
                        showLogin: { path.append(.login) }
                    )
                case .recovery:
                    AccountRecoveryView(api: api)
                }
            }
        }
        .tint(.authInk)
    }
}
