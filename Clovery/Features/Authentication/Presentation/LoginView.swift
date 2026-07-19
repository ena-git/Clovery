import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LoginViewModel
    let showSignUp: () -> Void
    var recoverAccount: () -> Void = {}
    var authenticateWithProvider: (AuthenticationProviderKind) -> Void = { _ in }
    var providerAvailability: (AuthenticationProviderKind) -> Bool = { _ in true }
    var providerMessage: String?

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController,
        showSignUp: @escaping () -> Void,
        recoverAccount: @escaping () -> Void = {},
        authenticateWithProvider: @escaping (AuthenticationProviderKind) -> Void = { _ in },
        providerAvailability: @escaping (AuthenticationProviderKind) -> Bool = { _ in true },
        providerMessage: String? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: LoginViewModel(api: api, sessionController: sessionController)
        )
        self.showSignUp = showSignUp
        self.recoverAccount = recoverAccount
        self.authenticateWithProvider = authenticateWithProvider
        self.providerAvailability = providerAvailability
        self.providerMessage = providerMessage
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 36)

                    AuthDashedCard(height: 254) {
                        VStack(spacing: 26) {
                            AuthTextField(
                                placeholder: "Clovery ID...",
                                text: $viewModel.loginID,
                                contentType: .username
                            )
                            AuthTextField(
                                placeholder: "Password...",
                                text: $viewModel.password,
                                isSecure: true,
                                contentType: .password,
                                submitLabel: .go,
                                onSubmit: submit
                            )
                        }
                    }
                    .frame(maxWidth: 347)
                    .padding(.top, 34)

                    errorMessage
                        .padding(.top, 10)

                    Button(action: submit) {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .tint(.authInk)
                            } else {
                                Text("LOG IN")
                                    .font(.authAction)
                            }
                        }
                        .foregroundColor(.authInk)
                        .frame(minWidth: 140, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting)
                    .padding(.top, 12)

                    Button("Recover account", action: recoverAccount)
                        .font(.authCaption)
                        .foregroundColor(.authInk)
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                    AuthDivider()
                        .padding(.top, 16)

                    providerRow
                        .padding(.top, 36)

                    Spacer(minLength: 54)

                    HStack(spacing: 4) {
                        Text("New here?")
                            .foregroundColor(.authPlaceholder)
                        Button("Sign Up", action: showSignUp)
                            .foregroundColor(.authInk)
                            .buttonStyle(.plain)
                    }
                    .font(.authCaption)
                    .padding(.bottom, 34)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.authBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(AuthenticationAsset.backArrow.rawValue)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 22)
                }
                .accessibilityLabel("返回")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text("LOG IN")
                .font(.authTitle)
                .foregroundColor(.authInk)
            Text("Welcome back to us!")
                .font(.authAction)
                .foregroundColor(.authInk)
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let errorMessage = viewModel.errorMessage ?? providerMessage {
            Text(errorMessage)
                .font(.authCaption)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityLabel(errorMessage)
        }
    }

    private var providerRow: some View {
        HStack(spacing: 10) {
            ForEach(AuthenticationProviderKind.allCases, id: \.self) { provider in
                AuthProviderButton(
                    provider: provider,
                    isEnabled: providerAvailability(provider),
                    action: { authenticateWithProvider(provider) }
                )
            }
        }
    }

    private func submit() {
        Task {
            await viewModel.submit()
        }
    }
}
