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
                                placeholder: "密码…",
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
                                Text("登录")
                                    .cloveryFont(.action)
                            }
                        }
                        .foregroundColor(.authInk)
                        .frame(minWidth: 140, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting)
                    .padding(.top, 12)

                    Button("找回账户", action: recoverAccount)
                        .cloveryFont(.caption)
                        .foregroundColor(.authInk)
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                    AuthDivider()
                        .padding(.top, 16)

                    providerRow
                        .padding(.top, 36)

                    Spacer(minLength: 54)

                    HStack(spacing: 4) {
                        Text("新用户？")
                            .foregroundColor(.authPlaceholder)
                        Button("注册", action: showSignUp)
                            .foregroundColor(.authInk)
                            .buttonStyle(.plain)
                    }
                    .cloveryFont(.caption)
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
            Text("登录")
                .cloveryFont(.title)
                .foregroundColor(.authInk)
            Text("欢迎回来！")
                .cloveryFont(.action)
                .foregroundColor(.authInk)
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let errorMessage = viewModel.errorMessage ?? providerMessage {
            Text(errorMessage)
                .cloveryFont(.caption)
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
