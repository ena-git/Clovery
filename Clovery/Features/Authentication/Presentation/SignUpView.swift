import SwiftUI

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SignUpViewModel
    let showLogin: () -> Void
    var authenticateWithProvider: (AuthenticationProviderKind) -> Void = { _ in }
    var providerAvailability: (AuthenticationProviderKind) -> Bool = { _ in true }
    var providerMessage: String?

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController,
        showLogin: @escaping () -> Void,
        authenticateWithProvider: @escaping (AuthenticationProviderKind) -> Void = { _ in },
        providerAvailability: @escaping (AuthenticationProviderKind) -> Bool = { _ in true },
        providerMessage: String? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: SignUpViewModel(api: api, sessionController: sessionController)
        )
        self.showLogin = showLogin
        self.authenticateWithProvider = authenticateWithProvider
        self.providerAvailability = providerAvailability
        self.providerMessage = providerMessage
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 35)

                    AuthDashedCard(height: 360) {
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
                                contentType: .newPassword
                            )
                            AuthTextField(
                                placeholder: "Confirm Password...",
                                text: $viewModel.confirmPassword,
                                isSecure: true,
                                contentType: .newPassword,
                                submitLabel: .join,
                                onSubmit: submit
                            )
                        }
                    }
                    .frame(maxWidth: 347)
                    .padding(.top, 34)

                    formMessage
                        .padding(.top, 8)

                    Button(action: submit) {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .tint(.authInk)
                            } else {
                                Text("SIGN UP")
                                    .font(.authAction)
                            }
                        }
                        .foregroundColor(.authInk)
                        .frame(minWidth: 140, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting)
                    .padding(.top, 10)

                    AuthDivider()
                        .padding(.top, 12)

                    providerRow
                        .padding(.top, 36)

                    Spacer(minLength: 26)

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundColor(.authPlaceholder)
                        Button("Log In", action: showLogin)
                            .foregroundColor(.authInk)
                            .buttonStyle(.plain)
                    }
                    .font(.authCaption)
                    .padding(.bottom, 28)
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
        .sheet(
            isPresented: Binding(
                get: { viewModel.recoveryCodes != nil },
                set: { if !$0 { viewModel.acknowledgeRecoveryCodes() } }
            )
        ) {
            if let recoveryCodes = viewModel.recoveryCodes {
                RecoveryCodesView(
                    codes: recoveryCodes,
                    acknowledge: viewModel.acknowledgeRecoveryCodes
                )
                .interactiveDismissDisabled()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text("SIGN UP")
                .font(.authTitle)
                .foregroundColor(.authInk)
            Text("Welcome to join us!")
                .font(.authAction)
                .foregroundColor(.authInk)
        }
    }

    @ViewBuilder
    private var formMessage: some View {
        if let message = validationMessage ?? viewModel.errorMessage ?? providerMessage {
            Text(message)
                .font(.authCaption)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityLabel(message)
        }
    }

    private var validationMessage: String? {
        switch viewModel.validationError {
        case .invalidCloveryID:
            return "Clovery ID 需以字母开头，使用 4–24 位小写字母、数字或下划线"
        case .invalidPassword:
            return "密码至少需要 8 位"
        case .passwordsDoNotMatch:
            return "两次输入的密码不一致"
        case nil:
            return nil
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
