import SwiftUI

enum AuthenticationRoute: Hashable {
    case login
    case signUp
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
                        showSignUp: { path.append(.signUp) }
                    )
                case .signUp:
                    SignUpView(
                        api: api,
                        sessionController: sessionController,
                        showLogin: { path.append(.login) }
                    )
                }
            }
        }
        .tint(.authInk)
    }
}
